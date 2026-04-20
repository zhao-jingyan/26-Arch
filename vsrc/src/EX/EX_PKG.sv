// ----------------------------------------------------------------------------
// File        : EX_PKG.sv
// Description : v2 EX Stage 公共枚举：ALU 操作、分支条件、rd 写回源、跳转类型
// ----------------------------------------------------------------------------

`ifndef EX_PKG
`define EX_PKG

package EX_PKG;
    // ALU 操作码；位宽 5 位
    // 0..9 是单周期算术 / 逻辑 / 移位 / 比较
    // 10..14 是多周期乘除法（MUL / DIV / DIVU / REM / REMU），WORD 版本复用 ALU_INST=WORD
    // MULH / MULHU / MULHSU 暂未支持
    typedef enum logic [4:0] {
        ADD  = 5'd0,
        SUB  = 5'd1,
        AND  = 5'd2,
        OR   = 5'd3,
        XOR  = 5'd4,
        SLL  = 5'd5,
        SRL  = 5'd6,
        SRA  = 5'd7,
        SLT  = 5'd8,
        SLTU = 5'd9,

        MUL  = 5'd10,
        DIV  = 5'd11,
        DIVU = 5'd12,
        REM  = 5'd13,
        REMU = 5'd14
    } ALU_OP_CODE;

    // ALU 操作宽度：NORM = 64-bit，WORD = 32-bit 低位运算结果 sext 回 64
    typedef enum logic {
        NORM = 1'b0,
        WORD = 1'b1
    } ALU_INST;

    // 分支条件
    typedef enum logic [2:0] {
        BR_NONE = 3'd0,
        BR_EQ   = 3'd1,
        BR_NE   = 3'd2,
        BR_LT   = 3'd3,
        BR_GE   = 3'd4,
        BR_LTU  = 3'd5,
        BR_GEU  = 3'd6
    } BRANCH_OP;

    // rd 写回数据源：ALU 结果或 PC+4（JAL / JALR）
    typedef enum logic {
        RD_FROM_ALU       = 1'b0,
        RD_FROM_PC_PLUS_4 = 1'b1
    } RD_SRC;

    // 跳转类型
    typedef enum logic [1:0] {
        JT_NONE = 2'd0,  // 顺序
        JT_BR   = 2'd1,  // 条件跳；target = PC + imm
        JT_JAL  = 2'd2,  // 无条件跳；target = PC + imm
        JT_JALR = 2'd3   // 无条件跳；target = (rs1 + imm) & ~1
    } JUMP_TYPE;
endpackage

`endif
