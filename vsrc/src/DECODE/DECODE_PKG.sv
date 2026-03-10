// --------------------------------------------------------------
// File        : DECODE_PKG.sv
// Description : RISC-V opcode and funct constants for decoder
// Author      : zhao-jingyan | Date: 2026-03-10
// --------------------------------------------------------------

`ifndef DECODE_PKG
`define DECODE_PKG

package DECODE_PKG;
    // RISC-V base opcodes
    localparam logic [6:0] OP_IMM   = 7'b0010011;  // OP-IMM (addi, xori, etc.)
    localparam logic [6:0] OP       = 7'b0110011;  // OP (add, sub, mul, etc.)
    localparam logic [6:0] OP_IMM32 = 7'b0011011;  // OP-IMM-32 (addiw)
    localparam logic [6:0] OP_32    = 7'b0111011;  // OP-32 (addw, subw, mulw, etc.)
    localparam logic [6:0] OP_LOAD  = 7'b0000011;  // load
    localparam logic [6:0] OP_STORE  = 7'b0100011;  // store
    localparam logic [6:0] OP_BRANCH = 7'b1100011;  // branch
    localparam logic [6:0] OP_JAL    = 7'b1101111;  // jal
    localparam logic [6:0] OP_JALR   = 7'b1100111;  // jalr
    localparam logic [6:0] OP_LUI    = 7'b0110111;  // lui
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;  // auipc

    // funct7 encodings
    localparam logic [6:0] FUNCT7_M   = 7'b0000001;  // M extension (mul, div, rem)
    localparam logic [6:0] FUNCT7_SUB = 7'b0100000;  // sub, subw, sra
endpackage

`endif
