# 已实现 Stage 接口记录

本文档追踪 `vsrc/src_new/` 下已落地的 stage 模块及其**当前对外接口**。每完成一个 stage 实现，在此追加一节；后续接口若变动，同步更新对应节。

- 设计规约、命名约定、待定 stage 的边界草案见 [arch_v2.md](arch_v2.md)
- stage-to-stage 类型声明见 [vsrc/src_new/top_pkg.sv](../vsrc/src_new/top_pkg.sv)

---

## IF Stage

- **状态**：已实现
- **文件**：
  - [vsrc/src_new/IF/IF_Stage.sv](../vsrc/src_new/IF/IF_Stage.sv)
  - [vsrc/src_new/IF/PC.sv](../vsrc/src_new/IF/PC.sv)
  - [vsrc/src_new/IF/Inst_Fetch.sv](../vsrc/src_new/IF/Inst_Fetch.sv)
  - [vsrc/src_new/IF/InstructionMemory.sv](../vsrc/src_new/IF/InstructionMemory.sv)

### 顶层接口 `IF_Stage`

#### IF_stage_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk` | input | `logic` | system_input |
| `rst_n` | input | `logic` | system_input，低有效 |
| `stall` | input | `logic` | 流水线暂停 |
| `pc_should_jump` | input | `logic` | 跳转使能 |
| `pc_jump_address` | input | `u64` | 跳转目标 |

#### IF_stage_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `if_2_id` | output | `IF_2_ID` | IF/ID 流水线寄存器输出 |

#### if_2_ctrl / ctrl_2_if

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `if_2_ctrl` | output | `IF_2_CTRL` | IF 对控制层的反馈，当前仅含 `is_inst_ready` |

#### if_2_ibus / ibus_2_if

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `ibus_request` | output | `ibus_req_t` | 对 ibus 的请求 |
| `ibus_response` | input | `ibus_resp_t` | 来自 ibus 的响应 |

### 子模块接口

#### `PC`

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk` | input | `logic` | system_input |
| `rst_n` | input | `logic` | system_input |
| `stall` | input | `logic` | 为高时 PC 保持不变（由 `IF_Stage` 合成 `pc_stall` 喂入） |
| `pc_should_jump` | input | `logic` | 跳转使能 |
| `pc_jump_address` | input | `u64` | 跳转目标 |
| `pc_inst_address` | output | `u64` | 当前 PC |

#### `Inst_Fetch`

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk` | input | `logic` | system_input |
| `rst_n` | input | `logic` | system_input |
| `pc_inst_address` | input | `u64` | 要取的指令地址 |
| `inst` | output | `u32` | 已缓存的指令 |
| `is_inst_ready` | output | `logic` | 当前 PC 的指令是否已取回 |
| `ibus_request` | output | `ibus_req_t` | 透传给 ibus |
| `ibus_response` | input | `ibus_resp_t` | 透传自 ibus |

#### `InstructionMemory`

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk` | input | `logic` | system_input（当前未使用） |
| `rst_n` | input | `logic` | system_input（当前未使用） |
| `request_addr` | input | `u64` | 取指地址 |
| `request_valid` | input | `logic` | 是否发出请求 |
| `response_data` | output | `u32` | ibus 返回的指令字（同周期直通） |
| `is_response_valid` | output | `logic` | `response_data` 本周期是否有效（= `ibus_response.data_ok`） |
| `ibus_request` | output | `ibus_req_t` | 组合映射自 request_* |
| `ibus_response` | input | `ibus_resp_t` | 来自 ibus |

### 相关 `top_pkg` 类型

```systemverilog
typedef struct packed {
    u32 inst;
    u64 pc_inst_address;
} IF_2_ID;

typedef struct packed {
    logic is_inst_ready;
} IF_2_CTRL;
```

### 关键实现点

- **PC 优先级**：`rst_n > pc_should_jump > stall > 自增（+4）`
- **IF_Stage 内部 `pc_stall`**：`pc_stall = stall || !is_inst_ready`，喂给 `PC.stall`；PC 自身端口不感知 `is_inst_ready`
- **IF 对控制层反馈**：`if_2_ctrl.is_inst_ready = is_inst_ready`，供未来控制层决定是否拉起全局 `stall`
- **IF/ID 寄存器更新条件**：`is_inst_ready && !stall`；其他情况保持（跳转时也保持，不清零，flush 语义留控制层）
- **Inst_Fetch 缓存**：`{latched_addr, latched_inst, latched_valid}`；`is_inst_ready = latched_valid && latched_addr == pc_inst_address`；未命中时 `request_valid = 1`
- **ibus 合约**：`valid` 拉高至 `data_ok` 之间 `addr` 稳定——由 PC 在 `pc_stall` 下不变化天然保证
- **InstructionMemory**：纯组合透传，无内部状态；`clk/rst_n` 仅为 system_input 一致性保留

---

## ID Stage

- **状态**：已实现
- **文件**：
  - [vsrc/src_new/ID/ID_Stage.sv](../vsrc/src_new/ID/ID_Stage.sv)
  - [vsrc/src_new/ID/Decoder.sv](../vsrc/src_new/ID/Decoder.sv)
  - [vsrc/src_new/ID/RegFile.sv](../vsrc/src_new/ID/RegFile.sv)
  - [vsrc/src_new/ID/Sign_Extend.sv](../vsrc/src_new/ID/Sign_Extend.sv)
  - [vsrc/src_new/ID/ID_PKG.sv](../vsrc/src_new/ID/ID_PKG.sv)

### 顶层接口 `ID_Stage`

#### ID_stage_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk` | input | `logic` | system_input |
| `rst_n` | input | `logic` | system_input |
| `stall` | input | `logic` | 为高时 ID/EX 流水寄存器保持 |
| `if_2_id` | input | `IF_2_ID` | 来自 IF |
| `wb_2_id` | input | `WB_2_ID` | 来自 WB 的写回三元组 |

#### ID_stage_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `inst_ctx` | output | `INST_CTX` | ID/EX 寄存器后的指令上下文，贯穿 pipeline |
| `id_2_ex` | output | `ID_2_EX` | ID/EX 寄存器后的 EX 操作数 + ALU/分支/跳转控制 |
| `gpr` | output | `u64 [0:31]` | Difftest 用 |
| `id_2_ctrl` | output | `ID_2_CTRL` | 控制层反馈（当前仅 `placeholder`） |

### 子模块接口

#### `Decoder`（纯组合）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `inst` | input | `u32` | 指令字 |
| `opcode` | output | `u7` | `inst[6:0]` |
| `rd_addr / rs1_addr / rs2_addr` | output | `u5` | S/B-type 的 `rd_addr` 已清零 |
| `alu_op_code / alu_inst_type` | output | `ALU_OP_CODE / ALU_INST` | ALU 控制 |
| `is_op1_zero / is_op1_pc / is_op2_imm` | output | `logic` | EX 的 op1/op2 mux flag |
| `branch_op` | output | `BRANCH_OP` | 分支条件（非分支时 `BR_NONE`） |
| `jump_type` | output | `JUMP_TYPE` | `JT_NONE/JT_BR/JT_JAL/JT_JALR` |
| `rd_src` | output | `RD_SRC` | `RD_FROM_ALU` / `RD_FROM_PC_PLUS_4`（JAL/JALR） |

#### `RegFile`

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk / rst_n` | input | `logic` | system_input |
| `write_en / write_addr / write_data` | input | `logic / u5 / u64` | 写口，x0 写入被内部屏蔽 |
| `read_addr_1 / read_addr_2` | input | `u5` | 读口 |
| `read_data_1 / read_data_2` | output | `u64` | 读出，x0 恒 0 |
| `gpr` | output | `u64 [0:31]` | 32 根快照 |

#### `Sign_Extend`（纯组合）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `inst / opcode` | input | `u32 / u7` | |
| `imm` | output | `u64` | 按 opcode 分 I/S/B/U/J 五种格式 sext |

### 关键实现点

- **v2 关键差异**：不在 ID 做 op1/op2 mux（v1 `DecodeStage` 里的 `rs1_data_sel / rs2_data_sel / store_data_sel` 逻辑移至 EX）
- **分支/跳转 flag 完全枚举化**：`BRANCH_OP` / `JUMP_TYPE` / `RD_SRC` 三个枚举配合 `is_op1_zero / is_op1_pc / is_op2_imm` 三个 bool 覆盖 LUI / AUIPC / JAL / JALR / BRANCH 全部场景
- **ID/EX 流水寄存器**：`!stall` 时 latch，`inst_ctx / id_2_ex` 物理上同组寄存器按语义拆两个端口
- **WB 写回**：`wb_2_id.{write_en, write_addr, write_data}` 直连 `RegFile` 写口

---

## EX Stage

- **状态**：已实现（不含乘除法）
- **文件**：
  - [vsrc/src_new/EX/EX_Stage.sv](../vsrc/src_new/EX/EX_Stage.sv)
  - [vsrc/src_new/EX/ALU_Core.sv](../vsrc/src_new/EX/ALU_Core.sv)
  - [vsrc/src_new/EX/Branch_Unit.sv](../vsrc/src_new/EX/Branch_Unit.sv)
  - [vsrc/src_new/EX/PC_Target.sv](../vsrc/src_new/EX/PC_Target.sv)
  - [vsrc/src_new/EX/EX_PKG.sv](../vsrc/src_new/EX/EX_PKG.sv)

### 顶层接口 `EX_Stage`

#### EX_stage_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk / rst_n` | input | `logic` | system_input |
| `stall` | input | `logic` | EX/MEM 流水寄存器暂停 |
| `inst_ctx_in` | input | `INST_CTX` | 来自 ID |
| `id_2_ex` | input | `ID_2_EX` | 来自 ID |

#### EX_stage_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `inst_ctx_out` | output | `INST_CTX` | 原样透传 |
| `ex_2_mem` | output | `EX_2_MEM` | 含 `ex_result`（rd 写回候选）与 `rs2_data`（store 用） |

#### ex_2_pc_feedback（本轮裸端口，未来收进控制层）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `pc_should_jump` | output | `logic` | 组合直出，本拍送回 IF |
| `pc_jump_address` | output | `u64` | 组合直出，本拍送回 IF |

### 子模块接口

#### `ALU_Core`（纯组合）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `op_code / inst_type` | input | `ALU_OP_CODE / ALU_INST` | 运算种类与位宽 |
| `alu_input_1 / alu_input_2` | input | `u64` | 已由 EX_Stage 顶层 mux |
| `alu_core_res` | output | `u64` | 运算结果 |

支持：`ADD / SUB / AND / OR / XOR / SLL / SRL / SRA / SLT / SLTU`。WORD 下 `SLT/SLTU` 无 RISC-V 对应指令。

#### `Branch_Unit`（纯组合）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `branch_op` | input | `BRANCH_OP` | 比较类型 |
| `rs1_data / rs2_data` | input | `u64` | 原始寄存器读值，不走 mux |
| `is_branch_taken` | output | `logic` | 分支是否成立 |

#### `PC_Target`（纯组合）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `jump_type` | input | `JUMP_TYPE` | 决定 `jump_target` 怎么算 |
| `pc_inst_address / rs1_data / imm` | input | `u64` | |
| `pc_plus_4` | output | `u64` | `pc_inst_address + 4` |
| `jump_target` | output | `u64` | `JT_JALR` → `(rs1+imm)&~1`；`JT_JAL/JT_BR` → `pc_inst_address+imm`；`JT_NONE` → 0 |

### 相关 `top_pkg` 类型

```systemverilog
typedef struct packed {
    u64         rs1_data;
    u64         rs2_data;
    u64         imm;
    logic       is_op1_zero;
    logic       is_op1_pc;
    logic       is_op2_imm;
    ALU_OP_CODE alu_op_code;
    ALU_INST    alu_inst_type;
    BRANCH_OP   branch_op;
    JUMP_TYPE   jump_type;
    RD_SRC      rd_src;
} ID_2_EX;

typedef struct packed {
    u64 ex_result;
    u64 rs2_data;
} EX_2_MEM;
```

### 相关 `EX_PKG` 枚举

```systemverilog
typedef enum logic [3:0] {
    ADD=4'd0, SUB=4'd1, AND=4'd2, OR=4'd3, XOR=4'd4,
    SLL=4'd5, SRL=4'd6, SRA=4'd7, SLT=4'd8, SLTU=4'd9
} ALU_OP_CODE;

typedef enum logic { NORM, WORD } ALU_INST;

typedef enum logic [2:0] {
    BR_NONE, BR_EQ, BR_NE, BR_LT, BR_GE, BR_LTU, BR_GEU
} BRANCH_OP;

typedef enum logic { RD_FROM_ALU, RD_FROM_PC_PLUS_4 } RD_SRC;

typedef enum logic [1:0] { JT_NONE, JT_BR, JT_JAL, JT_JALR } JUMP_TYPE;
```

### 关键实现点

- **op1 mux 优先级**：`is_op1_zero > is_op1_pc > rs1_data`
- **op2 mux**：`is_op2_imm ? imm : rs2_data`
- **rd mux**：`rd_src == RD_FROM_PC_PLUS_4`（JAL/JALR） → `pc_plus_4`；其余 → `alu_core_res`。AUIPC 走 ALU（op1=PC, op2=imm, ADD）
- **分支判定吃原 rs1/rs2**：`Branch_Unit` 不经 op1/op2 mux
- **跳转组合直出**：`pc_should_jump` / `pc_jump_address` 不进流水寄存器，IF 当拍就能转向；未来控制层接入后应改名 `ex_2_ctrl`
- **store_data 走 `ex_2_mem.rs2_data`**：EX 对 rs2 不消费，原样透给 MEM
- **EX/MEM 寄存器更新条件**：`!stall` 时 latch，复位清零
- **支持指令**：
  - 比较：`slt / sltu / slti / sltiu`
  - 移位：`sll / srl / sra / slli / srli / srai` + 字版本 `sllw / srlw / sraw / slliw / srliw / sraiw`
  - 分支：`beq / bne / blt / bge / bltu / bgeu`
  - 跳转/PC：`jal / jalr / auipc`
  - 原有：`add/sub/and/or/xor/addi/xori/ori/andi/addw/subw/addiw/lui/load/store`
- **乘除法**：本轮未迁，`Decoder` 遇 `funct7 == FUNCT7_M` 走默认 ADD；`ALU_OP_CODE` 槽位 `4'd10..4'd15` 保留

---

## MEM Stage

- **状态**：已实现
- **文件**：
  - [vsrc/src_new/MEM/MEM_Stage.sv](../vsrc/src_new/MEM/MEM_Stage.sv)
  - [vsrc/src_new/MEM/Fetch_Data.sv](../vsrc/src_new/MEM/Fetch_Data.sv)
  - [vsrc/src_new/MEM/DataMemory.sv](../vsrc/src_new/MEM/DataMemory.sv)

### 顶层接口 `MEM_Stage`

#### MEM_stage_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk / rst_n` | input | `logic` | system_input |
| `stall` | input | `logic` | 为高时 MEM/WB 流水寄存器保持 |
| `inst_ctx_in` | input | `INST_CTX` | 来自 EX |
| `ex_2_mem` | input | `EX_2_MEM` | 来自 EX |

#### MEM_stage_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `inst_ctx_out` | output | `INST_CTX` | 原样透传 |
| `mem_2_wb` | output | `MEM_2_WB` | 含 `rd_data`（load 走 `load_data`，其他走 `ex_result`） |

#### mem_2_ctrl_feedback（本轮裸端口，未来收进控制层）

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `is_mem_ready` | output | `logic` | 本指令访存是否完成；非 mem 指令恒 1 |

#### mem_2_dbus / dbus_2_mem

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `dbus_request` | output | `dbus_req_t` | 对 dbus 的请求 |
| `dbus_response` | input | `dbus_resp_t` | 来自 dbus 的响应 |

### 子模块接口

#### `Fetch_Data`

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk / rst_n` | input | `logic` | system_input |
| `pc_inst_address / inst` | input | `u64 / u32` | latch 命中判定的 key |
| `mem_addr` | input | `u64` | 访存地址（来自 `ex_2_mem.ex_result`） |
| `funct3` | input | `u3` | `inst[14:12]`，决定 size/strobe/扩展方式 |
| `is_load / is_store` | input | `logic` | 指令类型 flag（由 MEM_Stage 从 opcode 判定） |
| `store_data` | input | `u64` | store 写入数据（来自 `ex_2_mem.rs2_data`） |
| `load_data` | output | `u64` | funct3 对齐 + sext/zext 后的 64 位结果 |
| `is_mem_ready` | output | `logic` | 本指令访存是否完成 |
| `dbus_request` | output | `dbus_req_t` | 透传给 dbus |
| `dbus_response` | input | `dbus_resp_t` | 透传自 dbus |

#### `DataMemory`

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk / rst_n` | input | `logic` | system_input（当前未使用） |
| `request_addr` | input | `u64` | 请求地址 |
| `request_valid` | input | `logic` | 是否发出请求 |
| `request_size` | input | `msize_t` | 访存字节数 |
| `request_strobe` | input | `strobe_t` | 写字节使能，读请求全 0 |
| `request_write_data` | input | `u64` | 写数据（已左移到对应 lane） |
| `response_data` | output | `u64` | dbus 原始 64 位数据（未 lane 对齐） |
| `is_response_valid` | output | `logic` | `response_data` 本周期是否有效 |
| `dbus_request` | output | `dbus_req_t` | 组合映射自 request_* |
| `dbus_response` | input | `dbus_resp_t` | 来自 dbus |

### 相关 `top_pkg` 类型

```systemverilog
typedef struct packed {
    u64 rd_data;
} MEM_2_WB;
```

### 关键实现点

- **`is_mem_ready` 语义**：非 mem 指令恒 1；mem 指令等单槽 latch 命中当前 `(pc, inst)` 才置 1
- **单槽 latch**：`{latched_pc, latched_inst, latched_data, latched_valid}`；在 `is_response_valid && !is_mem_ready` 的周期写入；store 的 `latched_data` 无意义，仅用 `latched_valid` 表 done
- **dbus 合约**：`valid` 拉高到 `data_ok` 期间 `addr/size/strobe/data` 必须稳定——由 MEM 向上游传 `is_mem_ready=0` 让 EX/MEM 寄存器保持来保证
- **funct3 对齐**：`byte_idx = mem_addr[2:0]`；store 左移 `store_data << (byte_idx*8)`，strobe 按宽度左移；load 右移 `response_data >> (byte_idx*8)` 再按 lb/lh/lw/ld/lbu/lhu/lwu sext/zext
- **rd mux**：`is_load ? load_data : ex_2_mem.ex_result`
- **MEM/WB 寄存器更新条件**：`!stall && is_mem_ready` 时 latch；复位清零
- **opcode 判别**：`import ID_PKG::*;` 复用 `OP_LOAD / OP_STORE` 常量
- **支持指令**：`lb / lh / lw / ld / lbu / lhu / lwu / sb / sh / sw / sd`

---

## WB Stage

- **状态**：已实现
- **文件**：
  - [vsrc/src_new/WB/WB_Stage.sv](../vsrc/src_new/WB/WB_Stage.sv)

### 顶层接口 `WB_Stage`

纯组合薄层，无子模块、无流水寄存器、不挂 `clk / rst_n`。

#### WB_stage_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `inst_ctx` | input | `INST_CTX` | 来自 MEM |
| `mem_2_wb` | input | `MEM_2_WB` | 来自 MEM |

#### WB_stage_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `wb_2_id` | output | `WB_2_ID` | 写回三元组，直连 ID 的 RegFile 写口 |

### 相关 `top_pkg` 类型

```systemverilog
typedef struct packed {
    logic write_en;
    u5    write_addr;
    u64   write_data;
} WB_2_ID;
```

### 关键实现点

- **纯组合**：`assign` 三行即完成打包，无时序元件
- **write_en = (rd_addr != 0)**：S/B-type 在 Decoder 已清零 `rd_addr`，store/branch 自然不写回；x0 写入 RegFile 内部也会屏蔽
- **write_addr / write_data 直通**：`wb_2_id.write_addr = inst_ctx.rd_addr`，`wb_2_id.write_data = mem_2_wb.rd_data`
- **rd_data 选择已在 MEM 做**：load → 对齐后的 `load_data`；其他 → `ex_result`

---

## Control_Unit

- **状态**：已实现（最小策略）
- **文件**：
  - [vsrc/src_new/CTRL/Control_Unit.sv](../vsrc/src_new/CTRL/Control_Unit.sv)

### 顶层接口 `Control_Unit`

纯组合，无 system_input。

#### ctrl_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `if_2_ctrl` | input | `IF_2_CTRL` | 含 `is_inst_ready` |
| `id_2_ctrl` | input | `ID_2_CTRL` | 当前仅 `placeholder` |
| `is_mem_ready` | input | `logic` | MEM 裸端口反馈 |
| `ex_pc_should_jump` | input | `logic` | EX 跳转使能（裸端口） |
| `ex_pc_jump_address` | input | `u64` | EX 跳转目标（裸端口） |

#### ctrl_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `stall_if / stall_id / stall_ex / stall_mem` | output | `logic` | 各 stage 的 stall |
| `pc_should_jump / pc_jump_address` | output | `logic / u64` | 透传给 IF |

### 关键实现点

- **最小 stall 策略**：`pipeline_stall = !is_inst_ready || !is_mem_ready`，四个 `stall_*` 同值
- **跳转组合透传**：EX → Control_Unit → IF，同拍生效，不加寄存器
- **无 hazard / forwarding**：相邻 RAW 会读旧值；lab2 正向若暴露需补 load-use stall 与 forwarding
- **id_2_ctrl**：当前仅 `placeholder`，显式消费避免 Verilator unused warning

---

## Top 顶层

- **状态**：已实现
- **文件**：
  - [vsrc/src_new/Top.sv](../vsrc/src_new/Top.sv)
- **外部入口**：`vsrc/src/core.sv` 已将 `` `include `` 从 `src/Top.sv` 切换到 `src_new/Top.sv`，v1 `Top` 不再编译

### 顶层接口 `Top`

保持与 v1 `Top` 一致的对外签名，供 `core.sv` 与 Difftest 直接接入。

#### top_input

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `clk / rst_n` | input | `logic` | system_input |
| `ibus_resp_i` | input | `ibus_resp_t` | ibus 响应 |
| `dbus_resp_i` | input | `dbus_resp_t` | dbus 响应 |

#### top_output

| 端口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| `ibus_req_o` | output | `ibus_req_t` | ibus 请求 |
| `dbus_req_o` | output | `dbus_req_t` | dbus 请求 |
| `commit_valid_o` | output | `logic` | Difftest 提交使能（仅 MEM/WB 推进时拉高） |
| `commit_pc_o` | output | `u64` | 本拍提交指令的 PC（= prev） |
| `commit_instr_o` | output | `u32` | 本拍提交指令的指令字 |
| `commit_wen_o` | output | `logic` | 是否写 RF（= `prev.rd_addr != 0`） |
| `commit_wdest_o` | output | `u8` | 写回 GPR 号（`{3'b0, prev.rd_addr}`） |
| `commit_wdata_o` | output | `u64` | 写回数据（= `prev.rd_data`） |
| `gpr_o` | output | `u64 [0:31]` | RegFile 快照 |

### 关键实现点

- **五段装配**：`IF_Stage → ID_Stage → EX_Stage → MEM_Stage → WB_Stage`，外加 `Control_Unit`
- **反馈回路**：
  - `WB → ID`：`wb_2_id` 组合直送 RegFile 写口
  - `EX → IF`：`pc_should_jump / pc_jump_address` 经 Control_Unit 透传，同拍生效
- **commit 桥接**：用 1-cycle prev 寄存器跟踪 MEM/WB 推进沿，mimic v1 `wb_prev_q` 做法
  - `commit_valid = (prev.inst != 0) && (mem_inst_ctx != prev_inst_ctx)`
  - `commit_wdest = {3'b0, prev_inst_ctx.rd_addr}`
  - `commit_wdata = prev_mem_2_wb.rd_data`
  - 复位时 prev 清零，首拍不会误提交；pipeline 冻结时 mem 与 prev 相等，不会重复提交
- **v1 目录唯一修改点**：`vsrc/src/core.sv` 的 include 切换；v1 Top 及其子模块整体停编

---

## 未实现 Stage

下列项尚未实现，规约见 [arch_v2.md §3](arch_v2.md#3-模块边界) 或等用户给出：

- **hazard / forwarding**（load-use stall、EX/MEM/WB → EX forwarding；对应 `ID_2_CTRL` 字段补齐）
- **控制反馈 bundle 化**（`EX_2_CTRL` / `MEM_2_CTRL` 收拢目前的裸端口）
- **flush 语义**（跳转拍显式清零 IF/ID、ID/EX，若控制层形态要求）
- **乘除法**（`MUL/DIV/REM` 及 FSM）
