# lab1 实验报告

## 实验目标

要求 CPU 支持 64 位算术运算。

构建五级流水线 CPU 架构，CPU 需要支持以下指令并通过测试：

算术运算与逻辑运算：

addi, xori, ori, andi

add, sub, and, or, xor

addiw, addw, subw

## 结构设计

### 1. 流水线结构

我们将流水线拆分为五个阶段：

- IF（Instruction Fetch）：负责从内存中获取指令。
- ID（Instruction Decode）：负责解码指令，并准备操作数。
- EX（Execution）：负责执行指令，并计算结果。
- MEM（Memory）：负责访问内存，并读取数据。
- WB（Write Back）：负责将结果写回寄存器。

这样的设计带来了四个级间寄存器：

- IF -> ID 寄存器
- ID -> EX 寄存器
- EX -> MEM 寄存器
- MEM -> WB 寄存器 （ WB连线到RegFile 用于写回，之间不再有寄存器）

### 2. 架构设计

围绕四个级间寄存器，我们设计了四个Stage，每个Stage的末尾都有一个寄存器，用于存储该Stage的输出，并作为下一个Stage的输入。

#### FetchStage

FetchStage内部实例化一个pc计数器，与InstructionMemory进行异步的通信，取指请求与响应通过IBus进行。

输出到ID Stage的类型：

```verilog
// IF/ID: input to DecodeStage
    typedef struct packed {
        logic [31:0] inst; // 指令
        u64          pc;   // 程序计数器
    } if_id_t;
```

#### DecodeStage

DecodeStage内部实例化一个Decoder，一个RegFile，一个Sign_Extend，用于解码指令，读取寄存器，以及扩展立即数。

输出到EX Stage的类型：

```verilog
    // ID/EX: output from DecodeStage, input to ALU stage
    typedef struct packed {
        u64          pc;        // 程序计数器
        logic [31:0] inst;      // 指令
        u5           rd_addr;   // 目的寄存器地址，向前传递，用于写回
        u5           rs1_addr;  // 源寄存器1地址，用于hazard判断
        u5           rs2_addr;  // 源寄存器2地址，用于hazard判断
        u64          rs1_data;  // 源寄存器1数据
        u64          rs2_data;  // 源寄存器2数据
        u64          imm;       // 立即数
        ALU_OP_CODE  alu_op_code; // ALU操作码
        ALU_INST     alu_inst_type; // ALU操作类型
        u7           opcode;      // 指令类型
    } id_ex_t;
```

#### ALUStage

ALUStage内部实例化一个ALU_Core，用于执行组合逻辑计算。

输出到MEM Stage的类型：

```verilog
    // EX/MEM: output from ALU stage
    typedef struct packed {
        u64         pc;
        logic [31:0] inst;
        u5          rd_addr;    // 目的寄存器地址，向前传递，用于写回
        u64         alu_res;    // ALU计算结果
        u7          opcode;     // 指令类型，供load/store预备使用
    } ex_mem_t;
```

#### MEMStage

MEMStage内部实例化一个DataMemory，进行异步的存储器访问，请求与响应通过DBus进行。
由于lab1不要求支持load/store指令，所以MEMStage的实现没有详细验证正确性。

输出到WB Stage的类型：

```verilog
    // EX/MEM: output from ALU stage
    typedef struct packed {
        u64         pc;
        logic [31:0] inst;
        u5          rd_addr;    // 目的寄存器地址，用于写回
        u64         alu_res;    // ALU计算结果
        u7          opcode;
    } ex_mem_t;
```

WB Stage的输出连线到RegFile，用于写回寄存器。

自此，五级流水线的数据流向大致清楚了。围绕ALU的异步取指，解码，计算，（无储存器访问），写回的结构的数据流向比较清晰。

### 3. 细粒度模块分析

一个模块的组成规范为：

- 顶层Stage模块，实例化子模块，对外有清晰接口，维护寄存器。
- 子模块，实现具体功能，多为复杂的组合逻辑/抽象功能模块。
- PKG文件定义类型，常量等。

通过这种方法维护代码的结构，可读性和可维护性。

### 4. Hazard模块设计

Hazard模块用于处理流水线中的数据冒险，包括前递和停顿。

通过比较ID Stage的rs1_addr和rs2_addr与EX Stage的rd_addr，判断是否存在数据冒险。

如果存在数据冒险，现阶段的主要处理方法是前递。

前递取用数据的优先级为：EX -> WB -> RegFile，因为越靠近IF Stage的指令越晚执行，越晚写回RegFile，会发生覆盖关系。

当前只有IF的异步读写会带来stall，所以Hazard模块的stall_o信号直接连到IF Stage的stall_i信号。

### 5. 顶层连线设计

通过pipeline_pkg.sv文件定义了五个Stage的输入输出类型，以及Hazard模块的输入输出类型。
只要按照这些类型进行连线，清晰明了，易于维护。

### 6. AI使用情况

AI被给予以下指令：
```text
# 26-Arch 项目规则

## 角色定位

你是将自然语言设计转化为SystemVerilog代码实现的工具。你的主要任务是：

1. **代码实现**：根据用户的设计描述，生成对应的 SystemVerilog 代码
2. **设计文档**：根据讨论内容编写或更新设计文档

## 项目结构

- **源代码**：`vsrc/`
- **设计文档**：`design/`

## SystemVerilog 支持

- 提供最小化的语法支持，协助正确书写代码
- 不主动展开冗长的语法讲解，仅在必要时做简要说明

## 架构与设计决策

当涉及架构、设计取舍、实现策略等需要做判断的问题时：

- **不要**替用户做任何设计决定
- 可以和用户探讨设计决策，但最终决策权在用户
- 仅根据用户已明确的设计意图进行实现

## 变量命名规范

参考 `vsrc/src/ALU/` 已实现代码的风格：

### 端口声明格式

- **分组空行**：模块端口较多时，用空行分隔逻辑分组（如：时钟/复位 | 控制信号 | 操作码/类型 | 数据端口），便于快速浏览与维护

### 端口

- **输入**：`*_i` 后缀（如 `op_code_i`、`op1_i`、`mul_start_i`）
- **输出**：`*_o` 后缀（如 `alu_core_res_o`、`mul_res_o`、`div_done_o`）
- 同一单元的多信号可用前缀区分（如 `mul_*_i`、`mul_*_o`）

### 内部信号

- **寄存器（时序逻辑）**：`*_q` 后缀（如 `product_q`、`quotient_q`、`count_q`、`is_word_q`）
- **组合逻辑 / 中间变量**：snake_case，无后缀，语义清晰即可（如 `op1_abs`、`next_rem`、`sub_res`）

### 类型与常量

- **位宽类型**：`uN` 表示无符号 N 位（如 `u64`、`u32`、`u128`）
- **typedef**：`*_t` 后缀（如 `addr_t`、`word_t`、`cbus_req_t`）
- **枚举 / 包名**：SCREAMING_SNAKE_CASE（如 `ALU_OP_CODE`、`ALU_INST`）

### 其他

- **复位**：`rst_n` 表示低有效；`reset` 表示高有效（按既有模块保持一致）
- **模块名**：PascalCase，可与子单元前缀结合（如 `ALU_Core`、`ALU_Multiplier`）

---

## 代码注释

- **语言**：仅使用英文
- **风格**：极简，单行简短说明即可，避免冗长解释
- **示例**：`// word/dual select`、`// MSB of quotient`

---

## 工作流程

- 实现代码 → 写入 `vsrc/` 下相应模块
- 设计文档 → 写入 `design/` 目录
- 文档格式建议使用 Markdown，便于维护与版本控制

## 设计文档书写规范

参考 `design/alu_design.md` 的风格，设计文档应遵循：

### 结构

- **标题**：`# 模块名 设计文档`
- **开头**：一句话说明文档内容，并注明源代码路径
- **章节分隔**：用 `---` 分隔主要章节

### 模块描述模板

每个模块按以下子节组织：

1. **X.1 模块用途**：一两句话概括功能、对应指令或场景
2. **X.2 接口**：表格列出端口，列为「端口 | 方向 | 说明」
3. **X.3 实现细节**：用无序列表，每条以**加粗关键词**开头，简明描述算法、状态机、特殊处理等

### 书写风格

- 语言简洁，偏技术说明，避免冗长
- 端口名、信号名、类型名使用反引号包裹
- 数值、常量用十六进制时可用 `0x` 或 `64'h` 等形式
- 可视需要增加「其他相关模块」「模块关系示意」等节，用 Mermaid 框图示意数据流
```

lab1实现期间，我的注意力主要集中在模块化，结构化，如何划分功能，如何设计流水线。SystemVerilog的语法和RISC-V指令集的拆分（如decoder具体的连线方式，Sign-Extend的细节）交给AI处理。AI表现出了非常不错的局部能力。还有一些令人欣喜的，为未来考量的设计。人设计高级架构，AI实现底层细节的生产方式可以继续摸索实践。
