// --------------------------------------------------------------
// File        : Sign_Extend.sv
// Description : Sign-extend RISC-V immediate to 64-bit by format
// Author      : zhao-jingyan | Date: 2026-03-10
// --------------------------------------------------------------

import common::*;
import DECODE_PKG::*;

module Sign_Extend (
    input  logic [31:0] inst_i,
    input  logic [6:0]  opcode_i,

    output u64          imm_o
);

    always_comb begin
        imm_o = 64'b0;
        case (opcode_i)
            OP_IMM, OP_IMM32, OP_LOAD, OP_JALR: begin
                // I-type: [31:20] -> sext to 64
                imm_o = {{52{inst_i[31]}}, inst_i[31:20]};
            end
            OP_STORE: begin
                // S-type: {[31:25], [11:7]} -> sext to 64
                imm_o = {{52{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
            end
            OP_BRANCH: begin
                // B-type: {[31],[7],[30:25],[11:8], 1'b0} -> sext to 64
                imm_o = {{51{inst_i[31]}}, inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
            end
            OP_LUI, OP_AUIPC: begin
                // U-type: [31:12] in upper, lower 12 zero
                imm_o = {{32{inst_i[31]}}, inst_i[31:12], 12'b0};
            end
            OP_JAL: begin
                // J-type: {[31],[19:12],[20],[30:21], 1'b0} -> sext to 64
                imm_o = {{43{inst_i[31]}}, inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
            end
            default: imm_o = 64'b0;
        endcase
    end

endmodule
