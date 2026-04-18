// ----------------------------------------------------------------------------
// File        : ID_PKG.sv
// Description : RISC-V 基础 opcode / funct 常量，仅供 ID Stage 内部使用
// ----------------------------------------------------------------------------

`ifndef ID_PKG
`define ID_PKG

package ID_PKG;
    // RISC-V base opcodes
    localparam logic [6:0] OP_IMM    = 7'b0010011;  // addi/xori/ori/andi/slti/sltiu/slli/srli/srai
    localparam logic [6:0] OP        = 7'b0110011;  // add/sub/xor/or/and/sll/srl/sra/slt/sltu
    localparam logic [6:0] OP_IMM32  = 7'b0011011;  // addiw/slliw/srliw/sraiw
    localparam logic [6:0] OP_32     = 7'b0111011;  // addw/subw/sllw/srlw/sraw
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;

    // funct7 关键编码
    localparam logic [6:0] FUNCT7_M       = 7'b0000001;  // M 扩展（当前未迁移）
    localparam logic [6:0] FUNCT7_SUB_SRA = 7'b0100000;  // sub / subw / sra / srai / sraw / sraiw
endpackage

`endif
