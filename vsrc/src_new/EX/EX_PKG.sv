// ----------------------------------------------------------------------------
// File        : EX_PKG.sv
// Description : v2 EX Stage 公共枚举：ALU 操作、分支条件、rd 写回源、跳转类型
// ----------------------------------------------------------------------------

`ifndef EX_PKG
`define EX_PKG

package EX_PKG;
    // ALU 操作码；位宽 4 位，未来乘除法回归时填空闲槽位
    typedef enum logic [3:0] {
        ADD  = 4'd0,
        SUB  = 4'd1,
        AND  = 4'd2,
        OR   = 4'd3,
        XOR  = 4'd4,
        SLL  = 4'd5,
        SRL  = 4'd6,
        SRA  = 4'd7,
        SLT  = 4'd8,
        SLTU = 4'd9
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
