// ----------------------------------------------------------
// File        : Decoder.sv
// Description : Pure combinational logic, extracts RISC-V instruction fields
//               and decodes to ALU_OP_CODE / ALU_INST
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------
//
// RISC-V 32-bit instruction layout (fixed positions):
//   [6:0]   opcode
//   [11:7]  rd      (or imm[4:0] in S-type, imm[4:1]|0 in B-type)
//   [14:12] funct3
//   [19:15] rs1
//   [24:20] rs2     (or imm[11:5] high part in S-type)
//   [31:25] funct7  (or imm in I-type, imm in S/B-type)
//

`include "src/DECODE/DECODE_PKG.sv"

import common::*;
import ALU_PKG::*;
import DECODE_PKG::*;

module Decoder (
    input  logic [31:0] inst_i,

    output logic [6:0]  opcode_o,
    output logic [4:0]  rd_addr_o,
    output logic [4:0]  rs1_addr_o,
    output logic [4:0]  rs2_addr_o,
    output ALU_OP_CODE  alu_op_code_o,
    output ALU_INST     alu_inst_type_o
);

    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    assign opcode    = inst_i[6:0];
    assign funct3    = inst_i[14:12];
    assign funct7    = inst_i[31:25];

    assign opcode_o    = opcode;
    assign rd_addr_o   = inst_i[11:7];
    assign rs1_addr_o  = inst_i[19:15];
    assign rs2_addr_o  = inst_i[24:20];

    always_comb begin
        alu_op_code_o  = ADD;
        alu_inst_type_o = NORM;

        if (opcode == OP_IMM) begin
            alu_inst_type_o = NORM;
            case (funct3)
                3'b000: alu_op_code_o = ADD;   // addi
                3'b100: alu_op_code_o = XOR;   // xori
                3'b110: alu_op_code_o = OR;    // ori
                3'b111: alu_op_code_o = AND;   // andi
                default: ;
            endcase
        end
        else if (opcode == OP) begin
            if (funct7 == FUNCT7_M) begin
                alu_inst_type_o = NORM;
                case (funct3)
                    3'b000: alu_op_code_o = MUL;   // mul
                    3'b100: alu_op_code_o = DIV;   // div
                    3'b101: alu_op_code_o = DIV;   // divu
                    3'b110: alu_op_code_o = REM;   // rem
                    3'b111: alu_op_code_o = REM;   // remu
                    default: ;
                endcase
            end else begin
                alu_inst_type_o = NORM;
                case (funct3)
                    3'b000: alu_op_code_o = funct7[5] ? SUB : ADD;  // sub / add
                    3'b100: alu_op_code_o = XOR;
                    3'b110: alu_op_code_o = OR;
                    3'b111: alu_op_code_o = AND;
                    default: ;
                endcase
            end
        end
        else if (opcode == OP_IMM32 && funct3 == 3'b000) begin
            alu_inst_type_o = WORD;
            alu_op_code_o   = ADD;   // addiw
        end
        else if (opcode == OP_32) begin
            if (funct7 == FUNCT7_M) begin
                alu_inst_type_o = WORD;
                case (funct3)
                    3'b000: alu_op_code_o = MUL;   // mulw
                    3'b100: alu_op_code_o = DIV;   // divw
                    3'b101: alu_op_code_o = DIV;   // divuw
                    3'b110: alu_op_code_o = REM;   // remw
                    3'b111: alu_op_code_o = REM;   // remuw
                    default: ;
                endcase
            end else if (funct3 == 3'b000) begin
                alu_inst_type_o = WORD;
                alu_op_code_o   = funct7[5] ? SUB : ADD;  // subw / addw
            end
        end
    end

endmodule
