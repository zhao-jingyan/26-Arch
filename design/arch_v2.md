# 架构 v2 设计总纲

本文档是项目重构（v2）的总纲，记录目录布局、全局命名与接口约定、各 stage 的模块边界**规约**，以及尚未敲定的遗留问题。

> 已落地的 stage 当前**实际**接口快照见 [implemented_stages.md](implemented_stages.md)。本文偏"应当如何"，那份偏"当前是什么"。

---

## 1. 总则

### 1.1 重构策略

采用**并行全重写**：

- 旧代码 `vsrc/src/` 整体保留为 **v1 参考实现**，只读，不再维护。
- 新代码写入 `vsrc/src_new/`，从第一行起严格遵守本文档约定。
- 逐 stage 迁移：每个 stage 先在本文档登记边界，再落地代码，然后接入 v2 Top。
- 迁移期间 `core.sv` 仍 include v1 Top，Difftest 正常运行；等 v2 Top 能端到端跑通后再切 include。

### 1.2 不动的外部边界

以下接口在整个 v2 迁移过程中**不变**：

- `core.sv` 与 Difftest 的对接（`commit_*`、`gpr`）
- 总线接口类型 `ibus_req_t / ibus_resp_t / dbus_req_t / dbus_resp_t`（见 `vsrc/include/common.sv`）
- `clk` / `reset`（高有效）由 `core.sv` 转成 `rst_n`（低有效）传入 Top

### 1.3 目录布局

```text
vsrc/
├── include/           # 基础类型、总线定义，v1/v2 共用
├── src/               # v1 参考实现，只读
├── src_new/           # v2 新代码，所有新开发在此
└── util/              # 总线桥、仲裁器等，v1/v2 共用
```

---

## 2. 全局命名与接口约定

### 2.1 system_input 约定

每个模块默认都有 `clk` 和 `rst_n`（低有效复位）两个输入。在文档与注释中将这两个信号统一称为 **system_input**；**代码里不打包**，端口仍展开为 `clk, rst_n` 两根独立线。

```systemverilog
module Example (
    input  logic clk,
    input  logic rst_n,

    // 其它端口...
);
```

### 2.2 端口与信号命名

原则：**软件化、语义优先，不靠后缀标方向或时序**。

| 类别 | v1 风格（废弃） | v2 风格 |
| --- | --- | --- |
| 输入端口 | `op_code_i`、`alu_input_i` | `op_code`、`alu_input` |
| 输出端口 | `alu_core_res_o`、`if_id_o` | `alu_core_res`、`if_id` |
| 寄存器 | `product_q`、`pc_q` | `product`、`pc_inst_address` |
| 中间信号 | `op1_abs` | `op1_abs`（不变，本来就语义化） |

补充规则：

- 端口名直接用其**业务语义**（例：`pc_inst_address`、`is_inst_ready`、`pc_jump_address`、`pc_should_jump`）。
- 布尔信号建议 `is_*` / `has_*` / `should_*` 等软件风格前缀。
- 当同名信号既做端口又做内部连线时，以模块内不冲突为准，不再用后缀区分。

### 2.3 模块端口的 bundle 描述

每个模块的端口在**设计文档**里按功能分组（bundle）呈现，代码里用**空行**分隔对应组。bundle 不是 SV 类型，只是书写约定。

典型 bundle 命名：

- `system_input`：clk + rst_n
- `{module}_input` / `{module}_output`：该模块的主业务输入 / 输出
- `{module}_2_{peer}` / `{peer}_2_{module}`：与具体对端（总线、其它模块）通信的信号组

文档里用表格展开 bundle 内各端口：

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `pc_inst_address` | output | 当前取指 PC |
| ... | ... | ... |

### 2.4 保留的旧规则

以下 v1 约定继续有效：

- **位宽类型**：`uN`（如 `u64`、`u32`、`u5`）表示无符号 N 位
- **枚举 / 包名**：SCREAMING_SNAKE_CASE（如 `ALU_OP_CODE`、`ALU_INST`）
- **模块名**：PascalCase（如 `ALU_Core`、`IF_Stage`）
- **复位**：`rst_n` 低有效
- **代码注释**：中文优先，单行简短

**v2 typedef 不加 `_t` 后缀**（如 `IF_2_ID`、`ID_2_EX`）；v1 `common.sv` 中的 `addr_t / word_t / cbus_req_t / ibus_req_t` 等类型保留 `_t`，不在本轮重命名范围。

### 2.5 流水线寄存器放置

v2 的统一做法是**流水线寄存器放在上游 stage 内部**。每个 stage 的输出端口即该 stage 末尾流水线寄存器的输出，下一 stage 从组合层开始，不再有 inline 的 stage-to-stage 寄存器模块。

### 2.6 stage 间类型登记

所有 stage-to-stage 传递的包类型（`IF_2_ID`、`ID_2_EX`、`EX_2_MEM`、`MEM_2_WB` 等）以及 stage 对控制层的反馈包（如 `IF_2_CTRL`、`ID_2_CTRL`）统一在 `vsrc/src_new/top_pkg.sv` 中以 `struct packed` 声明；结构体字段名沿用端口语义名（例：`IF_2_ID` 含 `inst`、`pc_inst_address`）。

EX Stage 子单元相关枚举（`ALU_OP_CODE` / `ALU_INST` / `BRANCH_OP` / `RD_SRC` / `JUMP_TYPE`）在 [vsrc/src_new/EX/EX_PKG.sv](../vsrc/src_new/EX/EX_PKG.sv) 单独声明，由 `top_pkg.sv` include 并 `import EX_PKG::*;` 后 re-export，下游 stage 只需 `import top_pkg::*;` 即可使用。

ID 内部用的 RISC-V opcode / funct 常量（`OP_IMM / OP / OP_LOAD / ...`）在 [vsrc/src_new/ID/ID_PKG.sv](../vsrc/src_new/ID/ID_PKG.sv) 单独声明，仅 ID Stage 内部 import，不经 `top_pkg` 透出。

**按字段生命周期拆 bundle**：

- **贯穿型 bundle**：从某 stage 起顺着流水线一路透传到终点的字段，抽成独立类型（如 `INST_CTX` = `pc_inst_address / inst / rd_addr / opcode`），**不**塞进相邻两 stage 的 `{A}_2_{B}` 里。每个 stage 顶层各开一路同名端口（`inst_ctx` 输入 / `inst_ctx` 输出）原样透传，rd_addr 等"出生在 ID、死在 WB"的字段顺这条链走。
- **相邻型 bundle**：只在相邻两 stage 间传、下一 stage 消费完就丢的字段，才用 `{A}_2_{B}` 命名（如 `ID_2_EX` 只含 `rs1_data / rs2_data / imm / is_op1_zero / is_op2_imm / alu_op_code / alu_inst_type`，EX 吃完即止）。
- **控制层反馈 bundle**：stage 给控制层看的信号（如 `IF_2_CTRL`、`ID_2_CTRL`），与流水线主干分开走，不进 `{A}_2_{B}`。

---

## 3. 模块边界

### 3.1 IF Stage

IF Stage 内部有两个子模块：

- **PC**：程序计数器
- **INST_FETCH**：取指单元，直接对接 `ibus`

IF Stage 自身直接与 `ibus` 连接。

#### 3.1.1 PC 子模块

#### pc_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `stall` | input | 为高时 PC 保持不变 |
| `pc_should_jump` | input | 为高时下周期 PC 跳转到 `pc_jump_address` |
| `pc_jump_address` | input | 跳转目标地址 |

#### pc_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `pc_inst_address` | output | 当前指令 PC |

#### 3.1.2 INST_FETCH 子模块

#### if_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `pc_inst_address` | input | 要取指的地址 |

#### if_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst` | output | 取到的指令 |
| `is_inst_ready` | output | 指令是否已就绪 |

#### if_2_ibus

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `ibus_request` | output | 对 ibus 的请求 |

#### ibus_2_if

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `ibus_response` | input | 来自 ibus 的响应 |

INST_FETCH 内部实例化 `InstructionMemory` 子模块处理 ibus 握手。

#### 3.1.3 InstructionMemory 子模块

纯薄 ibus 握手适配器，隶属于 INST_FETCH 内部。

#### im_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `request_addr` | input | 请求地址 |
| `request_valid` | input | 是否发出请求 |

#### im_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `response_data` | output | ibus 返回的指令字 |
| `is_response_valid` | output | 本周期 `response_data` 是否有效 |

#### im_2_ibus

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `ibus_request` | output | 组合传递给 ibus 的请求 |

#### ibus_2_im

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `ibus_response` | input | 来自 ibus 的响应 |

`request_*` 直接映射到 `ibus_request`，`ibus_response.data / data_ok` 同周期透出到 `response_*`；ibus 合约"`valid` 拉高到 `data_ok` 期间 `addr` 稳定"由调用方（Inst_Fetch + PC 的 `pc_stall`）保证。

#### 3.1.4 IF Stage 顶层接口

#### IF_stage_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `stall` | input | 流水线暂停 |
| `pc_should_jump` | input | 跳转使能 |
| `pc_jump_address` | input | 跳转目标 |

#### IF_stage_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `if_2_id` | output | IF/ID 流水线寄存器输出，类型 `IF_2_ID`（含 `inst`、`pc_inst_address`） |

#### if_2_ctrl

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `if_2_ctrl` | output | IF 对控制层的反馈，类型 `IF_2_CTRL`，当前仅含 `is_inst_ready` |

（IF Stage 另有 `if_2_ibus` / `ibus_2_if` 两个直通到 ibus 的 bundle。）

#### 3.1.5 IF Stage 内部时序

- **PC 内部优先级**：`rst_n > pc_should_jump > stall > 自增`
- **IF_Stage 对 PC 的 stall**：`pc_stall = stall || !is_inst_ready`，由 IF_Stage 组合产生并喂给 `PC.stall`；PC 自身端口不感知 `is_inst_ready`
- **IF 对控制层反馈**：`if_2_ctrl.is_inst_ready = is_inst_ready`，未来控制层可据此生成全局 `stall`
- **IF/ID 寄存器更新条件**：`is_inst_ready && !stall` 时 latch 新数据，否则保持
- **跳转时 IF/ID**：当前实现为**保持上一拍**，不清零；flush 语义由未来控制层定义

#### 3.1.6 数据流示意

```mermaid
flowchart LR
    Ext[外部控制] -->|stall, pc_should_jump, pc_jump_address| PC
    PC -->|pc_inst_address| INST_FETCH
    INST_FETCH --> IM[InstructionMemory]
    IM <-->|ibus_request / ibus_response| IBus
    INST_FETCH -->|inst, is_inst_ready| IF_ID["IF/ID Pipeline Reg (IF_2_ID)"]
    INST_FETCH -->|if_2_ctrl.is_inst_ready| Ctrl[ControlLayer]
    PC -->|pc_inst_address| IF_ID
    IF_ID -->|if_2_id| Downstream[ID Stage]
```

### 3.2 ID Stage

ID Stage 内部有三个子模块：

- **Decoder**：纯组合，从 32bit 指令字解出各字段 + ALU 控制 + 两个操作数选择 flag
- **RegFile**：32×64 寄存器堆，一写两读，x0 硬连 0，附 32 根 `gpr` 快照出口
- **Sign_Extend**：按 opcode 把立即数扩展到 64 位

ID Stage 顶层把三者装配起来，并在末尾放 **ID/EX 流水线寄存器**。该寄存器的输出在 ID Stage 顶层拆成**两个语义不同的端口**：

- `inst_ctx`（`INST_CTX` 类型）：贯穿 pipeline 的指令上下文
- `id_2_ex`（`ID_2_EX` 类型）：仅供 EX 消费的操作数与 ALU 控制

#### 3.2.1 Decoder 子模块

纯组合，无 system_input。

#### decoder_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst` | input | 指令字 |

#### decoder_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `opcode` | output | RISC-V 7 位 opcode |
| `rd_addr` | output | 目的寄存器号，S/B-type 已清零 |
| `rs1_addr` | output | 源寄存器 1 号 |
| `rs2_addr` | output | 源寄存器 2 号（原始 `inst[24:20]`） |
| `alu_op_code` | output | ALU 操作码 `ALU_OP_CODE` |
| `alu_inst_type` | output | ALU 操作宽度 `ALU_INST`（NORM / WORD） |
| `is_op1_zero` | output | 为高时 EX 把 op1 当 0（LUI 场景） |
| `is_op2_imm` | output | 为高时 EX 用 imm 代替 rs2 作为 op2（OP-IMM / Load / Store / LUI / AUIPC） |

#### 3.2.2 RegFile 子模块

#### regfile_write

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `write_en` | input | 写使能 |
| `write_addr` | input | 写地址；x0 写入被屏蔽 |
| `write_data` | input | 写数据 |

#### regfile_read

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `read_addr_1` | input | 读端口 1 地址 |
| `read_addr_2` | input | 读端口 2 地址 |
| `read_data_1` | output | 读端口 1 数据；x0 恒 0 |
| `read_data_2` | output | 读端口 2 数据；x0 恒 0 |

#### regfile_snapshot

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `gpr` | output | `u64 [0:31]`，供 Difftest 比对 |

#### 3.2.3 Sign_Extend 子模块

纯组合，无 system_input。按 opcode 区分 I / S / B / U / J 五种格式拼出立即数并 sext 到 64 位。

#### sign_extend_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst` | input | 指令字 |
| `opcode` | input | 决定立即数格式 |

#### sign_extend_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `imm` | output | 64 位 sign-extended 立即数 |

#### 3.2.4 ID Stage 顶层接口

#### ID_stage_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `stall` | input | 为高时 ID/EX 流水线寄存器保持 |
| `if_2_id` | input | 来自 IF stage，类型 `IF_2_ID` |
| `wb_2_id` | input | 来自 WB 的写回，类型 `WB_2_ID` |

#### ID_stage_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst_ctx` | output | ID/EX 寄存器后的指令上下文，类型 `INST_CTX`，贯穿 pipeline |
| `id_2_ex` | output | ID/EX 寄存器后的 EX 操作数 + ALU 控制，类型 `ID_2_EX` |
| `gpr` | output | `u64 [0:31]` 快照，透出供 Difftest |

#### id_2_ctrl

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `id_2_ctrl` | output | ID 对控制层反馈，类型 `ID_2_CTRL`；当前仅 `placeholder` 占位 |

#### 3.2.5 数据流示意

```mermaid
flowchart LR
    IF[IF Stage] -->|if_2_id.inst| Decoder
    IF -->|if_2_id.inst| SignExt[Sign_Extend]
    IF -->|pc_inst_address, inst| PipeReg["ID/EX Pipeline Reg"]
    Decoder -->|rs1_addr, rs2_addr| RegFile
    WB[WB Stage] -->|wb_2_id| RegFile
    Decoder -->|rd_addr, opcode| PipeReg
    Decoder -->|alu_op_code, alu_inst_type, flags| PipeReg
    Decoder -->|opcode| SignExt
    RegFile -->|rs1_data, rs2_data| PipeReg
    SignExt -->|imm| PipeReg
    PipeReg -->|inst_ctx| CtxStream[INST_CTX downstream: EX -> MEM -> WB]
    PipeReg -->|id_2_ex| EX[EX Stage]
    RegFile -->|gpr| TopOut[core / Difftest]
    PipeReg -->|id_2_ctrl| Ctrl[Control Layer]
```

#### 3.2.6 关键设计点

- **操作数 split 形态**：`id_2_ex.rs1_data / rs2_data` 是 RegFile 的原始读值，**不**做 v1 的 LUI/imm 融合；是否把 op1 当 0、是否用 imm 代替 op2，由 EX 阶段根据 `is_op1_zero / is_op2_imm` 做 mux。store 时下游直接用 `rs2_data`，不再单独维护 `store_data` 字段。
- **rd_addr 清零点**：S/B-type 无架构 rd，Decoder 内部就把 `rd_addr` 清零；EX/MEM/WB 无需再判 opcode。
- **INST_CTX 贯穿**：`inst_ctx` 从 ID 出发顺着每个 stage 原样透传，WB 据 `inst_ctx.rd_addr` 写回、commit 据 `inst_ctx.pc_inst_address / inst` 对账；MEM 据 `inst_ctx.opcode` 识别 load/store。
- **ID/EX 寄存器更新条件**：`!stall` 时 latch 新数据；复位同步清零。`inst_ctx` 与 `id_2_ex` 物理上为同一组寄存器，只是按语义拆成两个端口。
- **flush 语义**：跳转时 ID/EX 暂按"保持"处理，与 IF/ID 的处理一致；未来控制层若要求显式清零再校准。
- **WB 写回**：`wb_2_id.write_en / write_addr / write_data` 直接接到 `RegFile.regfile_write`，零转接；x0 写入由 RegFile 内部屏蔽。
- **id_2_ctrl**：本轮仅 `placeholder`；未来放 `rs1_addr / rs2_addr / is_rs*_used` 等 hazard 判定信号，随控制层形态一起定。

### 3.3 EX Stage

EX Stage 内部有三个子模块：

- **ALU_Core**：64-bit 算术 / 逻辑 / 移位 / 比较，NORM 与 WORD 两种位宽
- **Branch_Unit**：条件分支判定（6 种）
- **PC_Target**：产 `pc_plus_4`（JAL/JALR 的 rd 源）与 `jump_target`

EX Stage 顶层把三者装配起来，在组合层做 op1/op2 mux、rd mux、跳转判定；末尾放 **EX/MEM 流水线寄存器**，输出 `inst_ctx_out` 与 `ex_2_mem`。分支/跳转信号 `pc_should_jump` / `pc_jump_address` 为**组合直出**，本拍反馈给 IF Stage，不经寄存器（IF 当拍可转向）。

#### 3.3.1 ALU_Core 子模块

纯组合，无 system_input。

#### alu_core_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `op_code` | input | `ALU_OP_CODE`，决定运算种类 |
| `inst_type` | input | `ALU_INST`，NORM 全 64-bit / WORD 低 32-bit 运算再 sext |
| `alu_input_1 / alu_input_2` | input | 两个 64-bit 操作数（已由 EX_Stage 顶层 mux 过） |

#### alu_core_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `alu_core_res` | output | 64-bit 运算结果 |

支持 `ADD / SUB / AND / OR / XOR / SLL / SRL / SRA / SLT / SLTU`。WORD 下 `SLL/SRL/SRA` 用低 5 位移位量，NORM 用低 6 位；`SLT/SLTU` 仅 NORM（RISC-V 无字版本）。

#### 3.3.2 Branch_Unit 子模块

纯组合，按 `branch_op` 对 `rs1_data / rs2_data` 做比较，输出 `is_branch_taken`。吃的是**原始** rs1/rs2，不走 EX 顶层的 op1/op2 mux。

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `branch_op` | input | `BRANCH_OP`：`BR_EQ/NE/LT/GE/LTU/GEU` |
| `rs1_data / rs2_data` | input | 原始寄存器读值 |
| `is_branch_taken` | output | 分支是否成立 |

#### 3.3.3 PC_Target 子模块

纯组合，同时产 `pc_plus_4` 与 `jump_target`。

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `jump_type` | input | `JUMP_TYPE` |
| `pc_inst_address` | input | 当前指令 PC |
| `rs1_data` | input | JALR 的基址 |
| `imm` | input | J/B/I 类立即数 |
| `pc_plus_4` | output | `pc_inst_address + 4`，供 JAL/JALR 的 rd |
| `jump_target` | output | `JT_JALR` → `(rs1+imm) & ~1`，`JT_JAL/JT_BR` → `pc_inst_address + imm`，`JT_NONE` → 0 |

#### 3.3.4 EX Stage 顶层接口

#### EX_stage_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `stall` | input | EX/MEM 流水寄存器暂停 |
| `inst_ctx_in` | input | 来自 ID，类型 `INST_CTX` |
| `id_2_ex` | input | 来自 ID，类型 `ID_2_EX` |

#### EX_stage_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst_ctx_out` | output | 透传，类型 `INST_CTX` |
| `ex_2_mem` | output | EX/MEM 流水寄存器输出，类型 `EX_2_MEM`，含 `ex_result` 与 `rs2_data` |

#### ex_2_pc_feedback

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `pc_should_jump` | output | 组合直出，本拍反馈 IF |
| `pc_jump_address` | output | 组合直出，本拍反馈 IF |

未来控制层落地后，这两根端口应改名为 `ex_2_ctrl` bundle，由控制层统一派发。

#### 3.3.5 数据流示意

```mermaid
flowchart LR
    IDPipe[ID Pipeline Reg] -->|inst_ctx_in| EXStage
    IDPipe -->|id_2_ex| EXStage

    subgraph EXStage [EX_Stage]
        OpMux["op1/op2 mux"] --> ALU[ALU_Core]
        BRU[Branch_Unit]
        PCTgt[PC_Target]
        RdMux["rd mux: ALU vs PC+4"]
        JumpComb["jump comb"]
        ALU --> RdMux
        PCTgt --> RdMux
        BRU --> JumpComb
        PCTgt --> JumpComb
        RdMux --> EXPipe["EX/MEM Pipeline Reg"]
    end

    EXStage -->|"pc_should_jump, pc_jump_address"| IF[IF Stage]
    EXStage -->|inst_ctx_out| MEM[MEM Stage]
    EXStage -->|ex_2_mem| MEM
```

#### 3.3.6 关键设计点

- **op1 mux 优先级**：`is_op1_zero > is_op1_pc > rs1_data`。`LUI` 用 `is_op1_zero`，`AUIPC` 用 `is_op1_pc`。
- **op2 mux**：`is_op2_imm ? imm : rs2_data`。
- **rd 写回候选**：`rd_src == RD_FROM_PC_PLUS_4` 时选 `pc_plus_4`（JAL/JALR），否则选 `alu_core_res`。AUIPC 走 ALU（op1=PC, op2=imm, ADD），不走 PC+4。
- **分支判定吃原 rs1/rs2**：Branch_Unit 不经 mux，因此条件分支时 `rs1_data / rs2_data` 必须是 RegFile 原始读值（而 OP_BRANCH 类 Decoder 默认不置 `is_op2_imm`，保证 `id_2_ex.rs2_data` 就是寄存器原值）。
- **跳转组合直出**：`pc_should_jump` / `pc_jump_address` 由 EX 组合层直接输出到 IF。`JT_JAL / JT_JALR` 无条件跳；`JT_BR` 由 `is_branch_taken` 决定。
- **store_data 走 ex_2_mem.rs2_data**：store 时 EX 不消费 rs2，透过 `ex_2_mem.rs2_data` 传给 MEM（与 v1 `store_data` 字段对应）。
- **EX/MEM 寄存器更新条件**：`!stall` 时 latch `inst_ctx` 与 `ex_2_mem`；复位清零。
- **乘除法暂缺**：`MUL / DIV / REM` 与 `ALU_STATE` 本轮未迁移；`Decoder` 对 `funct7 == FUNCT7_M` 的路径当前走默认值（产出 ADD），等乘除法回归再接回 ALU_OP_CODE 新槽位。

### 3.4 MEM Stage

MEM Stage 内部有两个子模块：

- **Fetch_Data**：访存单元，做 funct3 字节对齐 + 单槽 latch，直接对接 `dbus`
- **DataMemory**：纯 dbus 握手适配器，隶属于 Fetch_Data 内部

MEM Stage 自身直接与 `dbus` 连接。EX/MEM 流水线寄存器在 EX 内部；MEM 末尾放 **MEM/WB 流水线寄存器**，输出 `inst_ctx_out` 与 `mem_2_wb`。

#### 3.4.1 DataMemory 子模块

纯薄 dbus 握手适配器，隶属于 Fetch_Data 内部。

#### dm_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `request_addr` | input | 请求地址（保留低 3 位，dbus 内部对齐到 8B） |
| `request_valid` | input | 是否发出请求 |
| `request_size` | input | `msize_t`，访存字节数 |
| `request_strobe` | input | 写字节使能，读请求请全 0 |
| `request_write_data` | input | 写数据（需左移到对应 lane） |

#### dm_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `response_data` | output | dbus 返回的原始 64 位数据（未做 lane 对齐） |
| `is_response_valid` | output | 本周期 `response_data` 是否有效（= `dbus_response.data_ok`） |

#### dm_2_dbus

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `dbus_request` | output | 组合传递给 dbus 的请求 |

#### dbus_2_dm

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `dbus_response` | input | 来自 dbus 的响应 |

`request_*` 直接映射到 `dbus_request`，`dbus_response.data / data_ok` 同周期透出到 `response_*`；dbus 合约"`valid` 拉高到 `data_ok` 期间 `addr/size/strobe/data` 稳定"由调用方（`Fetch_Data` + 上游 stall）保证。

#### 3.4.2 Fetch_Data 子模块

#### fd_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `pc_inst_address` | input | 当前指令 PC（latch 命中判定的 key 之一） |
| `inst` | input | 当前指令字（latch 命中判定的 key 之一） |
| `mem_addr` | input | 访存地址（= `ex_2_mem.ex_result`） |
| `funct3` | input | `inst[14:12]`，决定 size/strobe/扩展方式 |
| `is_load` | input | 本指令是否 load |
| `is_store` | input | 本指令是否 store |
| `store_data` | input | store 写入数据（= `ex_2_mem.rs2_data`） |

#### fd_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `load_data` | output | funct3 对齐 + sext/zext 后的 64 位结果；非 load 时值无意义 |
| `is_mem_ready` | output | 本指令访存是否已完成（非 mem 指令恒 1） |

#### fd_2_dbus / dbus_2_fd

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `dbus_request` | output | 透传给 dbus |
| `dbus_response` | input | 透传自 dbus |

对齐规则（与 RISC-V 要求一致）：

| funct3 | size | strobe（store） | 扩展（load） |
| --- | --- | --- | --- |
| `000` | MSIZE1 | `1 << byte_idx`（sb） | sext8（lb） |
| `001` | MSIZE2 | `3 << byte_idx`（sh） | sext16（lh） |
| `010` | MSIZE4 | `0xF << byte_idx`（sw） | sext32（lw） |
| `011` | MSIZE8 | `0xFF`（sd） | 原值（ld） |
| `100` | MSIZE8 | - | zext8（lbu） |
| `101` | MSIZE8 | - | zext16（lhu） |
| `110` | MSIZE8 | - | zext32（lwu） |

其中 `byte_idx = mem_addr[2:0]`；store 的 `req_wdata = store_data << (byte_idx*8)`；load 的 `load_data_shifted = response_data >> (byte_idx*8)`。load 请求 `request_strobe` 固定为 0。

#### 3.4.3 MEM Stage 顶层接口

#### MEM_stage_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `stall` | input | 为高时 MEM/WB 流水寄存器保持 |
| `inst_ctx_in` | input | 来自 EX，类型 `INST_CTX` |
| `ex_2_mem` | input | 来自 EX，类型 `EX_2_MEM` |

#### MEM_stage_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst_ctx_out` | output | 透传，类型 `INST_CTX` |
| `mem_2_wb` | output | MEM/WB 流水寄存器输出，类型 `MEM_2_WB`，含 `rd_data` |

#### mem_2_ctrl_feedback（本轮裸端口，未来收进控制层）

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `is_mem_ready` | output | 本指令访存是否完成；非 mem 指令恒 1 |

#### mem_2_dbus / dbus_2_mem

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `dbus_request` | output | 对 dbus 的请求 |
| `dbus_response` | input | 来自 dbus 的响应 |

#### 3.4.4 数据流示意

```mermaid
flowchart LR
    EXPipe["EX/MEM Pipeline Reg"] -->|inst_ctx_in| MEMStage
    EXPipe -->|ex_2_mem| MEMStage

    subgraph MEMStage [MEM_Stage]
        FD["Fetch_Data (align + latch)"]
        DM[DataMemory]
        RdMux["rd mux: load_data vs ex_result"]
        MEMPipe["MEM/WB Pipeline Reg"]
        FD --> DM
        FD --> RdMux
        RdMux --> MEMPipe
    end

    MEMStage <-->|"dbus_request / dbus_response"| DBus
    MEMStage -->|is_mem_ready| Ctrl[ControlLayer]
    MEMStage -->|inst_ctx_out| WB[WB Stage]
    MEMStage -->|mem_2_wb| WB
```

#### 3.4.5 关键设计点

- **`is_mem_ready` 语义**：非 mem 指令（opcode 既非 `OP_LOAD` 也非 `OP_STORE`）时恒为 1，MEM/WB 寄存器当拍即可前进；mem 指令等单槽 latch 命中当前 `(pc, inst)` 才为 1
- **dbus 合约保证**：`valid` 拉到 `data_ok` 之间 `addr/size/strobe/data` 必须稳定——由 MEM 向上游传 `is_mem_ready=0` 让 EX/MEM 寄存器保持、`ex_2_mem.ex_result / rs2_data` 不变来天然保证
- **rd mux**：`is_load ? load_data : ex_2_mem.ex_result`；store 无 rd 写回（Decoder 已清零 `rd_addr`），`rd_data` 值无意义
- **单槽 latch**：`{latched_pc, latched_inst, latched_data, latched_valid}` 记录"本指令访存已完成"；在 `is_response_valid && !is_mem_ready` 的周期写入；store 的 `latched_data` 无意义，仅用 `latched_valid` 表 done
- **MEM/WB 寄存器更新条件**：`!stall && is_mem_ready` 时 latch `inst_ctx_in` → `inst_ctx_out`、`rd_data` → `mem_2_wb.rd_data`；复位清零
- **opcode 判别**：MEM_Stage 内 `import ID_PKG::*;` 以复用 `OP_LOAD` / `OP_STORE` 常量；`ID_PKG` 不经 `top_pkg` 透出，仅 ID 与 MEM 两个 stage 内部使用

### 3.5 WB Stage

WB Stage 是**纯组合**的薄层，没有子模块，没有流水线寄存器。职责仅是把 MEM 输出的 `rd_data` 与 `inst_ctx.rd_addr` 打包成 `wb_2_id` 送回 ID Stage 写回 RegFile。

#### WB_stage_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `inst_ctx` | input | 来自 MEM，类型 `INST_CTX` |
| `mem_2_wb` | input | 来自 MEM，类型 `MEM_2_WB` |

#### WB_stage_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `wb_2_id` | output | 写回三元组，类型 `WB_2_ID`，直连 ID 的 RegFile 写口 |

#### 3.5.1 关键设计点

- **纯组合，无 system_input**：与 `Decoder / Sign_Extend / ALU_Core` 等组合模块一致，不挂 `clk / rst_n`
- **write_en 由 rd_addr 判定**：`wb_2_id.write_en = (inst_ctx.rd_addr != 0)`；S/B-type 在 Decoder 已把 `rd_addr` 清零，x0 写入 RegFile 内部也会屏蔽，此处预先置 `write_en=0` 语义更清晰
- **write_addr / write_data 直通**：`wb_2_id.write_addr = inst_ctx.rd_addr`，`wb_2_id.write_data = mem_2_wb.rd_data`
- **rd_data 选择已在 MEM 做**：load 走对齐后的 `load_data`，其他走 `ex_result`，WB 不再 mux

### 3.6 Control_Unit

独立控制层模块，聚合 IF / ID / MEM 对控制层的反馈信号，产生每个 stage 的 `stall`，并把 EX 的跳转反馈转发给 IF。**纯组合**，无 system_input。

本轮采用**最小实现**：不做 hazard 检测，不做 forwarding；pipeline_stall 只吃两个"忙"信号（IF 取指没就绪、MEM 访存没就绪），然后向所有 stage 均匀施加。

#### ctrl_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `if_2_ctrl` | input | IF 反馈，类型 `IF_2_CTRL`，含 `is_inst_ready` |
| `id_2_ctrl` | input | ID 反馈，类型 `ID_2_CTRL`，当前仅 `placeholder` |
| `is_mem_ready` | input | MEM 反馈（裸端口；未来收进 `MEM_2_CTRL`） |
| `ex_pc_should_jump` | input | EX 当拍跳转使能（裸端口；未来收进 `EX_2_CTRL`） |
| `ex_pc_jump_address` | input | EX 当拍跳转目标（裸端口） |

#### ctrl_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `stall_if` | output | 供 `IF_Stage.stall` |
| `stall_id` | output | 供 `ID_Stage.stall` |
| `stall_ex` | output | 供 `EX_Stage.stall` |
| `stall_mem` | output | 供 `MEM_Stage.stall` |
| `pc_should_jump` | output | 透传给 `IF_Stage.pc_should_jump` |
| `pc_jump_address` | output | 透传给 `IF_Stage.pc_jump_address` |

#### 3.6.1 关键设计点

- **最小 stall 策略**：`pipeline_stall = !if_2_ctrl.is_inst_ready || !is_mem_ready`，`stall_if = stall_id = stall_ex = stall_mem = pipeline_stall`。任一忙信号即冻结整个流水线。
- **跳转透传**：`pc_should_jump / pc_jump_address` 为 EX 组合直出，Control_Unit 当拍转给 IF，不加寄存器。
- **没有 hazard 检测**：相邻 RAW 读到 ID/EX 旁写入同名 rd 的场景当前会读旧值；依赖后续按需引入 forwarding 或 load-use stall。
- **bubble 注入留白**：当前 `!is_inst_ready` 时整流水线一起冻结，不往 ID/EX 注入 NOP bubble；性能损失可接受。未来若需要让下游继续排空可改写此策略。

### 3.7 Top 顶层

v2 五段流水线的装配层。对外保持与 v1 `Top` 一致的接口（`ibus / dbus / commit / gpr`），由 `core.sv` 实例化；内部以 bundle 方式连线 IF → ID → EX → MEM → WB + Control_Unit。

#### top_input

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| system_input | input | `clk` + `rst_n` |
| `ibus_resp_i` | input | ibus 响应 |
| `dbus_resp_i` | input | dbus 响应 |

#### top_output

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `ibus_req_o` | output | ibus 请求（IF 透传） |
| `dbus_req_o` | output | dbus 请求（MEM 透传） |
| `commit_valid_o / commit_pc_o / commit_instr_o` | output | Difftest 提交信息 |
| `commit_wen_o / commit_wdest_o / commit_wdata_o` | output | Difftest 写回三元组 |
| `gpr_o` | output | `u64 [0:31]` RegFile 快照 |

#### 3.7.1 关键设计点

- **五段装配**：`IF_Stage → ID_Stage → EX_Stage → MEM_Stage → WB_Stage`；所有 stage 间流水寄存器都放在上游 stage 内部（符合 §2.5 约定）。
- **回路**：`WB → ID`（`wb_2_id` 组合送回 RegFile 写口）；`EX → IF`（`pc_should_jump / pc_jump_address` 经 Control_Unit 透传，同拍生效）。
- **commit / Difftest 桥接**：取 `mem_inst_ctx + mem_2_wb`（即 MEM/WB 寄存器出口）为"已进入 WB 的指令"；另维护一拍 prev 寄存器 `prev_inst_ctx / prev_mem_2_wb`。当 `mem_inst_ctx` 与 prev 不等时，对外报告 prev 为本拍 commit（对齐 v1 的 `wb_prev_q` 套路）。
  - `commit_valid = (prev.inst != 0) && (mem != prev)`：MEM/WB 寄存器发生推进时拉高；reset 后 prev=0 自然屏蔽，pipeline 冻结时 `mem == prev` 也自然屏蔽，不会重复提交
  - `commit_wen = (prev.rd_addr != 0)`：S/B-type 在 Decoder 已清零 `rd_addr`，x0 写入 RegFile 内部亦屏蔽
  - `commit_wdest = {3'b0, prev.rd_addr}` 扩展到 `u8` 以匹配 Difftest 接口
- **core.sv 接线切换**：v1 `vsrc/src/Top.sv` 不再编译；`vsrc/src/core.sv` 把 `` `include `` 从 `src/Top.sv` 改为 `src_new/Top.sv`（此处是 v1 目录唯一允许的修改点，参见 §1.1）。

#### 3.7.2 装配示意

```mermaid
flowchart LR
    IFStage[IF_Stage] -->|if_2_id| IDStage[ID_Stage]
    IFStage -->|if_2_ctrl| Ctrl[Control_Unit]

    IDStage -->|inst_ctx + id_2_ex| EXStage[EX_Stage]
    IDStage -->|id_2_ctrl| Ctrl
    IDStage -->|gpr| CoreOut[core / Difftest]

    EXStage -->|inst_ctx + ex_2_mem| MEMStage[MEM_Stage]
    EXStage -->|pc_should_jump, pc_jump_address| Ctrl

    MEMStage -->|inst_ctx + mem_2_wb| WBStage[WB_Stage]
    MEMStage -->|is_mem_ready| Ctrl
    MEMStage -->|inst_ctx + mem_2_wb| Commit["commit / prev flops"]

    WBStage -->|wb_2_id| IDStage

    Ctrl -->|stall_if| IFStage
    Ctrl -->|stall_id| IDStage
    Ctrl -->|stall_ex| EXStage
    Ctrl -->|stall_mem| MEMStage
    Ctrl -->|pc_should_jump, pc_jump_address| IFStage

    IFStage <-->|ibus_req / ibus_resp| IBus
    MEMStage <-->|dbus_req / dbus_resp| DBus

    Commit -->|commit_valid, pc, instr, wen, wdest, wdata| CoreOut
```

---

## 4. 遗留问题 / 待定

- **hazard / forwarding**：当前 `Control_Unit` 不做任何 hazard 检测，相邻 RAW 指令在 ID 读 RegFile 会读到旧值。lab2 测试正向可能暴露此问题；下一步需要在 Control_Unit 中加入：
  - **load-use stall**：EX/MEM 反馈中含 load 且 rd 匹配当前 ID 的 rs1/rs2（或 store 的 rs2）时注入一拍 bubble；
  - **EX→EX / MEM→EX / WB→EX forwarding**：纯 ALU 型 RAW 的旁路；
  - 相关 `ID_2_CTRL` 字段（`rs1_addr / rs2_addr / is_rs1_used / is_rs2_used / is_store_src_used`）届时补齐，取代当前 `placeholder`。
- **控制反馈 bundle 化**：EX 的 `pc_should_jump / pc_jump_address` 与 MEM 的 `is_mem_ready` 当前仍是裸端口，待控制层后续形态明确后收拢为 `EX_2_CTRL` / `MEM_2_CTRL`。
- **flush 语义**：当前跳转周期 IF/ID、ID/EX 两级流水寄存器都按"保持"处理，不清零。若将来控制层要求显式清零（比如 bubble 注入形式的 flush），在 Control_Unit 增加 `flush_*` 输出并在各 stage 顶层接线。
- **commit 接口类型化**：`commit_*` 目前散端口，对齐 v1 `Top`。未来可抽成 `COMMIT` struct（含 `pc / inst / wen / rd_addr / rd_data`）统一走。
- **INST_CTX 是否细化**：目前 `INST_CTX.opcode` 原样随流，MEM 识别 load/store 用。未来若换成 `is_load / is_store / is_branch / is_jump` 等语义化 flag 并归到独立的 `MEM_CTRL` bundle，随 hazard 检测一起决定。
- **乘除法**：`MUL/DIV/REM` 及 FSM 状态 `ALU_STATE` 暂不迁移，`ALU_OP_CODE` 已预留 `4'd10..4'd15` 槽位，待乘除法回归时填回。
