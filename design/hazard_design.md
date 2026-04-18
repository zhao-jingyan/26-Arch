# Hazard 模块设计文档

> **[v1 过时文档]** 本文描述的是 v1 流水线的 Hazard 设计。v2 架构已将其拆解，stall/forwarding 产生机制待定，详见 [arch_v2.md](arch_v2.md)。本文保留作历史参考。

本文档说明 Hazard 模块的 stall 与 forwarding 设计，用于管理流水线数据冒险。

---

## 1. 为什么需要 Hazard 控制

流水线中，后序指令可能依赖前序指令尚未写回 RegFile 的结果，产生**数据冒险（RAW）**。若直接读 RegFile，会得到旧值。

**两种解决方式**：
- **Forwarding（前递）**：把后面级中已算出的结果直接送给前面的级，无需等待写回。
- **Stall（停顿）**：前递无法解决时（如 load-use），暂停流水线 1～N 拍。

---

## 2. 哪些值"将会被更新"

需要跟踪的是：**哪些 rd 会被更新，以及对应的值在哪个流水级**。

| 流水级 | 信号来源 | rd 地址 | 数据 | 说明 |
|--------|----------|---------|------|------|
| EX     | EX/MEM 输入（组合） | `id_ex.rd_addr` | `alu_res` | 本拍在 EX 算出，下一拍进入 EX/MEM |
| MEM    | EX/MEM 寄存器      | `ex_mem.rd_addr` | `ex_mem.alu_res` | 已在 EX/MEM，下一拍进入 MEM/WB |
| WB     | MEM/WB 寄存器      | `wb.rd_addr` | `wb.rd_data` | 本拍写入 RegFile |

要点：
- 不额外建表，直接用现有流水级寄存器。
- 用 `wen`（或 `rd_addr != 0`）表示该级确实有写回。

---

## 3. 前递（Forwarding）设计

### 3.1 数据流

ID 级通过 RegFile 读出 `rs1_data`、`rs2_data`，但 EX 需要的可能是：
- EX 级刚算出的 `alu_res`
- MEM 级 `ex_mem.alu_res`
- WB 级 `wb.rd_data`

因此需要在 ALU 的 op1/op2 入口做多路选择，而不是只用 RegFile 输出。

### 3.2 前递来源与优先级

ID 在某一拍读 rs1/rs2，可能有多级同时写同一 rd。优先用**离 ID 最近**（最新）的写：

1. **EX → ID**：最高优先级，`ex_mem.rd_addr == rs1` 且 `ex_mem.rd_addr != 0`
2. **MEM → ID**：次之，`wb.rd_addr == rs1` 且 `wb.wen`（MEM/WB 寄存器内容）
3. **RegFile**：默认，无匹配时用 RegFile 读出的值

> 说明：EX 级结果在 EX 拍结束时锁存进 EX/MEM，下一拍（MEM 拍）EX/MEM 中的值可用。ID 读的是上一拍锁存后的内容，时序上对齐。

### 3.3 前递判断逻辑（伪代码）

```
// rs1 前递
if      (ex_mem.rd_addr == id_ex.rs1_addr && ex_mem.rd_addr != 0)
    rs1_fwd = ex_mem.alu_res;
else if (wb.rd_addr == id_ex.rs1_addr && wb.wen)
    rs1_fwd = wb.rd_data;
else
    rs1_fwd = rs1_data;  // RegFile 读出

// rs2 同理
```

### 3.4 实现位置

前递在 **ALU 级**完成：op1/op2 来自 DecodeStage 的输出，经 Hazard 模块选择后再送入 ALU。  
因此 Hazard 需要输入 `id_ex`、`ex_mem`、`wb`，输出 `rs1_fwd`、`rs2_fwd`，在 ALU 之前插入 MUX。

---

## 4. Stall 设计

### 4.1 需要 Stall 的情况

| 来源 | 条件 | 说明 |
|------|------|------|
| IF 等 IM | `im_req.valid && !im_rsp.valid` | 取指未返回，整条流水线停 |
| Load-use | 前条是 load，下条用其 rd | load 数据在 MEM 才返回，无法在 EX 前递，需 stall 1 拍 |
| MEM 等 DM | （将来）load/store 等 `dm_rsp` | 数据访存未完成时 stall |

### 4.2 Load-use 的 Stall 逻辑

```
load_in_ex_mem = (ex_mem.opcode == OP_LOAD);
use_rd_as_rs1  = (ex_mem.rd_addr == id_ex.rs1_addr && id_ex.rs1_addr != 0);
use_rd_as_rs2  = (ex_mem.rd_addr == id_ex.rs2_addr && id_ex.rs2_addr != 0);

load_use_stall = load_in_ex_mem && (use_rd_as_rs1 || use_rd_as_rs2);
```

Stall 一拍后，load 结果进入 MEM/WB，可用 `wb.rd_data` 前递。

### 4.3 Stall 的级联

`stall = 1` 时：
- 所有流水线寄存器不更新（保持当前值）
- PC 不递增
- IF 不发新取指请求（或保持同一 PC，视实现而定）

---

## 5. Hazard 模块接口

### 5.1 输入

| 信号 | 类型 | 说明 |
|------|------|------|
| `id_ex_i` | id_ex_t | ID/EX  pipeline 寄存器 |
| `ex_mem_i` | ex_mem_t | EX/MEM pipeline 寄存器 |
| `wb_i` | wb_reg_t | MEM/WB 写回信息 |
| `im_req_valid_i` | logic | IM 请求有效 |
| `im_rsp_valid_i` | logic | IM 响应有效 |

### 5.2 输出

| 信号 | 类型 | 说明 |
|------|------|------|
| `stall_o` | logic | 流水线 stall |
| `rs1_fwd_sel_o` | [1:0] | rs1 前递选择（RegFile / EX / MEM） |
| `rs2_fwd_sel_o` | [1:0] | rs2 前递选择 |
| `rs1_fwd_data_o` | u64 | 前递后的 rs1（或由 Top 用 sel 做 MUX） |
| `rs2_fwd_data_o` | u64 | 前递后的 rs2 |

也可以只输出 `rs1_fwd`、`rs2_fwd` 两个 64 位数据，由 Hazard 内部完成 MUX。

---

## 6. 数据流示意

```
                    ┌─────────────┐
    id_ex ──────────┤             │
    ex_mem ─────────┤   Hazard    ├─── stall ────► 各 stage.stall_i
    wb ─────────────┤             ├─── rs1_fwd ──► ALU op1 选择
    im_req/resp ────┤             ├─── rs2_fwd ──► ALU op2 选择
                    └─────────────┘
```

---

## 7. 实现顺序建议

1. 实现 forwarding，使 EX→ID、MEM→ID 前递生效。
2. 在 Top 中插入 Hazard 模块，将 `rs1_fwd`、`rs2_fwd` 接到 ALU 的 op1/op2。
3. 实现 `if_stall`（IM 未返回时 stall）。
4. 有 load/store 后，实现 load-use stall。
