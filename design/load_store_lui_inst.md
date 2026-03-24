# Load / Store / LUI 指令分析文档

本文档整理 RV64I 中待实现的访存与 `lui` 指令的编码、语义及与五级流水线的对应关系，便于逐步实现。解码相关代码见 `vsrc/src/DECODE/`，总线类型见 `vsrc/include/common.sv`（`msize_t`、`strobe_t`、`dbus_req_t` 等）。

---

## 1. 指令总览

| 助记符 | 类别 | 作用简述 |
|--------|------|----------|
| `lb` | load | 读 1 字节，符号扩展至 64 位 |
| `lh` | load | 读 2 字节（半字），符号扩展至 64 位 |
| `lw` | load | 读 4 字节（字），符号扩展至 64 位 |
| `ld` | load | 读 8 字节（双字），写入 `rd` |
| `lbu` | load | 读 1 字节，零扩展至 64 位 |
| `lhu` | load | 读 2 字节，零扩展至 64 位 |
| `lwu` | load | 读 4 字节，零扩展至 64 位（RV64） |
| `sb` | store | 写 1 字节到 `rs1+imm` |
| `sh` | store | 写 2 字节 |
| `sw` | store | 写 4 字节 |
| `sd` | store | 写 8 字节 |
| `lui` | upper-immediate | 将指令高 20 位置于 `rd` 的 bit[31:12]，低 12 位为 0；位 31 符号扩展填充 `rd[63:32]`（RV64） |

**未在表中的前提**：本项目为 **RV64**（`common` 中 `XLEN=64`），地址与寄存器宽度假定为 64 位。

---

## 2. 编码（与 `DECODE_PKG` 一致）

### 2.1 Load

- **opcode**：`OP_LOAD` = `7'b0000011`
- **I-type**：`imm[11:0]` 在 `inst[31:20]`，`rs1` = `inst[19:15]`，`rd` = `inst[11:7]`
- **funct3**：

| funct3 | 指令 |
|--------|------|
| `3'b000` | `lb` |
| `3'b001` | `lh` |
| `3'b010` | `lw` |
| `3'b011` | `ld` |
| `3'b100` | `lbu` |
| `3'b101` | `lhu` |
| `3'b110` | `lwu` |

### 2.2 Store

- **opcode**：`OP_STORE` = `7'b0100011`
- **S-type**：立即数为 `{inst[31:25], inst[11:7]}`，`rs1` / `rs2` 为基址与源数据寄存器
- **funct3**：

| funct3 | 指令 |
|--------|------|
| `3'b000` | `sb` |
| `3'b001` | `sh` |
| `3'b010` | `sw` |
| `3'b011` | `sd` |

### 2.3 LUI

- **opcode**：`OP_LUI` = `7'b0110111`
- **U-type**：`rd` = `inst[11:7]`，无 `rs1`/`rs2`；立即数字段为 `inst[31:12]`，拼装与扩展方式与 `Sign_Extend` 中 `OP_LUI` 分支一致（见 `vsrc/src/DECODE/Sign_Extend.sv`）。

---

## 3. 语义公式

- **Load**：`addr = x[rs1] + sext(imm)`；从 `addr` 读 `width` 字节，再按指令做符号或零扩展写入 `x[rd]`（`x[0]` 恒为 0，若 `rd=0` 则不写或写无效）。
- **Store**：`addr = x[rs1] + sext(imm)`；将 `x[rs2]` 的低 `width` 字节写入存储器（具体位对齐与总线见第 5 节）。
- **LUI**：`x[rd] = sext(imm_U)`，其中 `imm_U` 为将 `inst[31:12]` 置于 bit[31:12]、低 12 位为 0 的 32 位模式，再按 RV64 规则符号扩展。

---

## 4. 与五级流水线的对应（目标行为）

以下为“经典”划分，便于逐步实现；可与当前 `ALUStage` / `MemStage` 现状对齐演进。

| 阶段 | Load | Store | LUI |
|------|------|-------|-----|
| **IF** | 取指 | 同左 | 同左 |
| **ID** | `Decoder`/`Sign_Extend` 产出 `opcode`、`funct3`、`imm`、`rs1/rs2/rd`；读 `rs1`（及 store 读 `rs2`） | 同左 | 仅 `rd`/`imm`；可不读 `rs1/rs2` |
| **EX** | 典型：`addr = rs1 + imm`（可用 ALU `ADD` 或专用加法）；携带 `width`、符号性、是否 load | 典型：计算 `addr`；携带 `wdata`（来自 `rs2` 或前递）、`width`、`strobe` | 可不进 ALU：直接将扩展后的立即数作为写回数据，或仍经 ALU `ADD` 与 0 相加统一路径 |
| **MEM** | 发 `dbus` 读请求，等待 `dbus_resp`；取回 `rdata` 后做 **对齐裁剪 + 扩展** 得到最终 `rd_data` | 发 `dbus` 写请求（`valid`、`addr`、`size`、`strobe`、`data`）；**store 一般不写 `rd`**（`wen=0`） | 无访存：可在此级旁路或已在 EX 形成结果，按设计固定到 WB 寄存器 |
| **WB** | `rd_data` 写 `RegFile`（若 `rd≠0`） | 通常无寄存器写 | `lui` 结果写 `rd` |

**与 Hazard**：`load` 后紧跟使用该 `rd` 的非前递可解依赖时，需 **load-use stall**（见 `design/hazard_design.md`）；`store` 与 `lui` 不按 load-use 处理。

---

## 5. 与 `dbus_req_t` 的映射（`common.sv`）

### 5.1 `msize_t`

工程中枚举：`MSIZE1`、`MSIZE2`、`MSIZE4`、`MSIZE8` 对应 1/2/4/8 字节传输，可与 `lb/lh/lw/ld` 及 `sb/sh/sw/sd` 一一对应。

### 5.2 地址对齐

规范要求：`lh/lw/ld` 等需自然对齐，否则触发 **地址未对齐异常**；实现初期若仿真环境保证对齐，可暂不做异常，但接口上应保留以后接 trap 的余地。

### 5.3 `strobe` 与 `data` 布局

`common.sv` 注释约定：**数据按 4 字节对齐方式摆放在 `word_t` 中**，字节使能用 `strobe` 指出有效字节。例如 1 字节写在地址 `0x...f2` 时，`addr` 仍为 `0x...f2`，但 `data` 与 `strobe` 需按项目约定放到对应 lane（与现有 `DBusToCBus` 等桥接一致时再统一）。

Store 需在 EX/MEM 根据 `funct3` 与 `addr` 低位，从 `x[rs2]` 中抽出/store 宽度对应的片段，并组织 `wdata`/`strobe`。

### 5.4 Load 返回数据处理

从 `dbus_resp.rdata` 中取回的是一笔 `word_t`（宽度与总线一致）。需在 MEM（或紧接其后的组合逻辑）根据 `addr` 低位与 `funct3`：

- 取出 1/2/4/8 字节；
- `lb/lh/lw`：**符号扩展**至 64 位；
- `lbu/lhu/lwu`：**零扩展**至 64 位；
- `ld`：通常直接使用 8 字节结果（仍需与总线对齐约定一致）。

---

## 6. 实现顺序建议

1. **解码与控制字段**：在 `Decoder`（及 `id_ex`/`ex_mem` 等流水线载体）中区分 `OP_LOAD`/`OP_STORE`/`OP_LUI`，带出 `is_load`/`is_store`（或等价）、`funct3`、访存宽度/符号性。
2. **LUI**：不访存，优先单独打通 WB（验证 `Sign_Extend` + 写回路径）。
3. **按宽度扩展访存**：先 `lw`/`sw`（4 字节），再 `ld`/`sd`，再半字与字节（命令行与对齐处理更繁琐）。
4. **Hazard**：在 load 接入 MEM 后接入 `load_use_stall`；若有 `dm_busy`，与现有 `im_busy` 一样并入总 `stall`。

---

## 7. 相关模块

| 模块/文件 | 关系 |
|-----------|------|
| `DECODE_PKG.sv` | `OP_LOAD`、`OP_STORE`、`OP_LUI` 常量 |
| `Decoder.sv` | 扩展译码输出 load/store/lui 控制 |
| `Sign_Extend.sv` | `OP_LOAD`（I-type）、`OP_STORE`（S-type）、`OP_LUI`（U-type）立即数 |
| `ALUStage.sv` | 计算访存地址或旁路 `lui` 数据 |
| `MemStage.sv` | 发起/完成 `dbus` 事务，load 扩展写回 |
| `Top.sv` | 连接 `dbus_req_o`/`dbus_resp_i`（当前可能为占位） |
| `Hazard.sv` | load-use、访存忙等 stall |

---

以上编码与语义与 RISC-V RV64I 用户级规范一致；异常、非对齐、虚实地址细节可在后续章节单独开文档。
