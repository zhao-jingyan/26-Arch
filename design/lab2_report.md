# lab2 实验报告

## 实验目标

在 lab1 五级流水线与算术指令的基础上，扩展对 **RV64I 访存与 upper-immediate** 的支持。

典型指令范围包括：`lb` / `lh` / `lw` / `ld` / `lbu` / `lhu` / `lwu`，`sb` / `sh` / `sw` / `sd`，以及 `lui`。

---

## 实现流程（分步）

### 1. Data Memory 抽象

**目标**：把 LSU 与外部总线之间的握手从具体实现里抽出来，便于以后替换缓冲、cache 或不同 DBus 适配层。

- 在 `pipeline_pkg.sv` 中定义 **`dm_req_t` / `dm_rsp_t`**：请求侧包含 `valid`、`is_write`、`addr`、`size`、`strobe`、`wdata`；响应侧包含 `valid` 与 `rdata`，与 `common.sv` 中的 `dbus_req_t` / `dbus_resp_t` 语义对齐、层次上更贴近“抽象数据口”。
- **`DataMemory.sv`**：作为一层薄封装，将 `dm_req_t` 映射到 `dbus_req_o`，在 `dbus_resp_i.data_ok` 且事务忙时打一拍产生 `rsp_o.valid` 与读数据，便于单独仿真 LSU 行为。

当前顶层 **`Top.sv`** 仍由 **`MemStage`** 直接驱动 **DBus** 完成 load/store，与**`FetchStage`**的s设计一致。

**MEM 级实际行为**：

参考wiki的内存总线介绍实现，通过MemDataAlign模块实现对齐和扩展，MemStage模块实现总线事务和load写回。

---

### 2. Decode环节

**Decoder**（`Decoder.sv`）在 lab1 基础上增加对 **`OP_LOAD`、`OP_STORE`、`OP_LUI`** 的译码：load/store 统一走 **`rs1 + imm`** 的 ALU `ADD` 路径，`LUI` 使用 `op1_is_zero` + 立即数实现 **`0 + imm`**。

**立即数** 由 **`Sign_Extend.sv`** 按 opcode 区分 I-type（load）、S-type（store）、U-type（`lui`）。

**逐级传递** 上，在流水线结构体中显式增加访存所需字段，避免在 MEM 级再拼数据：

---

### 3. Forwarding（前递）

lab2 在 lab1 前递思路上补全 **load 数据** 的前递。

 **`ALUStage`** 对 **`rs1` / `rs2` / `store_data`** 做 MUX
 
 优先级为：**load 旁路**（MEM 上 `data_ok` 当拍）→ **`ex_mem.alu_res`** → **`wb.rd_data`** → **RegFile / `id_ex`**。 
 
 **`Hazard`** 不把 **load** 的 `alu_res`（仅是地址）当作数据前递，只有 **`alu_res` 即写回值** 的指令才允许从 **`ex_mem` 前递**。 **Store** 因立即数指令把 **`id_ex.rs2_addr` 清 0**，另用 **`store_data_fwd_sel_o`** 按 **`inst[24:20]`** 做依赖判断。

---

### 4. Hazard Control（冒险与停顿）

**停顿来源** 在 lab2 中合并为：

| 来源 | 作用 |
|------|------|
| **指令存储器忙** `im_busy` | 与 lab1 类似，取指未返回时冻结流水前端 |
| **数据存储器忙** `dm_busy` | **`MemStage`** 在访存请求未 **`data_ok`** 前拉高，阻止 **EX/MEM** 被错误刷新 |
| **Load-use** | 当 **EX/MEM 级** 为 **load** 且 **`rd` 被下一条在 EX 的指令用作 `rs1` / `rs2`（或 store 的 `rs2`）**，且 **同周期无法由 load bypass 消解** 时，**`load_use_stall`** 冻结前端一拍 |

**级联行为**（可概括为：前端停 = 全量冻结；后端停 = 主要卡住写回口；后端对取指的牵制单独走 **issue block**）：

- **`stall_front_o`（前端停，效果上接近全量 stall）**：`im_busy || dm_busy || load_use_stall`。为真时 **PC 不推、IF/ID 不采新指、`id_ex` 与 EX 输出的 `ex_mem` 不前进**（与 **`DecodeStage` / `ALUStage` / `FetchStage`** 中对 `stall_front_i` 的用法一致），整条流水在“指令推移”意义上一起停住。
- **`stall_back_o`（后端停，语义上是部分 stall）**：仅与 **`dm_busy`** 绑定，意图是 **卡住 MEM→WB 一侧**：**`MemStage`** 里 **`wb_o` 仅在 `!stall_back && !stall_front` 时更新**，避免访存未完成时把 load 写回冲掉。本设计中 **`dm_busy` 同时会拉高 `stall_front`**，故后端忙时前端也会跟着冻住，以保证 **EX/MEM 里仍是当前访存那条**，不仅是 WB 寄存器单独等一拍。
- **`stall_if_issue_block_o`（后端 / load-use 对 IF 的“发卡”）**：对 **`dm_busy` 与 `load_use_stall` 打一拍寄存**，专给 **`FetchStage`**： **`im_req.valid = !stall_if_issue_block || if_pending_q`**，在阻塞时不再发**新的**取指请求（已在飞的事务仍可依 `if_pending_q` 维持），用于 **打断 DBus/旁路与 IF 请求之间的组合路径**，并与纯 `stall_front` 分工——**“back 类原因要拽住取指”**时由这一路体现。

**Load bypass**：**`MemStage`** 输出 **`load_bypass_valid_o` / `load_bypass_data_o`**（扩展后的 load 数据），**`Hazard`** 在判断 **`load_use_stall`** 时若 bypass 有效则 **不再停顿**，并在前递优先级中把 **load 旁路** 放在 **EX/MEM / WB** 之前。

hazard control的逻辑在lab3中需要重写。

---

## AI 使用情况

由于实验室的个人工作紧张，第三四周能用来打磨lab的时间有限，在拆分任务后，AI负责完成大部分工作。通过了测试，但显然stall的可扩展性和可维护性都不佳。

AI生成代码最大的问题是，命名抽象，代码可读性极差，未经人思考的抽象非常糟糕。

因此，计划在lab3过程中对代码做大量重构，同时优化部分性能，将stall & flush的逻辑做的更好
