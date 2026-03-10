// --------------------------------------------------------------
// File        : ALU_PKG.sv
// Description : Defining OpCode and Instruction Type For ALU
// Author      : zhao-jingyan | Date: 2026-03-06
// --------------------------------------------------------------

`ifndef ALU_PKG
`define ALU_PKG

package ALU_PKG;
    typedef enum logic [2:0] {
        ADD = 3'b000,
        SUB = 3'b001,
        AND = 3'b010,
        OR  = 3'b011,
        XOR = 3'b100,
        MUL = 3'b101,
        DIV = 3'b110,
        REM = 3'b111
    } ALU_OP_CODE;

    typedef enum logic {
        NORM = 1'b0,
        WORD = 1'b1
    } ALU_INST;

    // One-Hot FSM State
    typedef enum logic [2:0] {
        IDLE    = 3'b001,
        COMPUTE = 3'b010,
        DONE    = 3'b100
    } ALU_STATE;
endpackage

`endif