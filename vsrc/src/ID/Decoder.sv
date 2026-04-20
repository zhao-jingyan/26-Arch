// ----------------------------------------------------------------------------
// File        : Decoder.sv
// Description : RISC-V 指令字译码；纯组合。输出 ALU 控制 + 分支/跳转/rd 源 flag
// ----------------------------------------------------------------------------

`include "src/ID/ID_PKG.sv"
`include "src/EX/EX_PKG.sv"

import common::*;
import ID_PKG::*;
import EX_PKG::*;

module Decoder (
    input  u32         inst,

    output u7          opcode,
    output u5          rd_addr,
    output u5          rs1_addr,
    output u5          rs2_addr,

    output ALU_OP_CODE alu_op_code,
    output ALU_INST    alu_inst_type,
    output logic       is_op1_zero,
    output logic       is_op1_pc,
    output logic       is_op2_imm,

    output BRANCH_OP   branch_op,
    output JUMP_TYPE   jump_type,
    output RD_SRC      rd_src
);

    u3  funct3;
    u7  funct7;
    u7  opcode_w;

    assign opcode_w = inst[6:0];
    assign funct3   = inst[14:12];
    assign funct7   = inst[31:25];

    assign opcode   = opcode_w;
    // S/B-type 无架构 rd，Decoder 内部清零
    assign rd_addr  = (opcode_w == OP_STORE || opcode_w == OP_BRANCH) ? 5'b0 : inst[11:7];
    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];

    always_comb begin
        alu_op_code   = ADD;
        alu_inst_type = NORM;
        is_op1_zero   = 1'b0;
        is_op1_pc     = 1'b0;
        is_op2_imm    = 1'b0;
        branch_op     = BR_NONE;
        jump_type     = JT_NONE;
        rd_src        = RD_FROM_ALU;

        unique case (opcode_w)
            OP_IMM: begin
                alu_inst_type = NORM;
                is_op2_imm    = 1'b1;
                unique case (funct3)
                    3'b000: alu_op_code = ADD;                          // addi
                    3'b100: alu_op_code = XOR;                          // xori
                    3'b110: alu_op_code = OR;                           // ori
                    3'b111: alu_op_code = AND;                          // andi
                    3'b010: alu_op_code = SLT;                          // slti
                    3'b011: alu_op_code = SLTU;                         // sltiu
                    3'b001: alu_op_code = SLL;                          // slli
                    3'b101: alu_op_code = funct7[5] ? SRA : SRL;        // srai / srli
                    default: ;
                endcase
            end

            OP: begin
                alu_inst_type = NORM;
                if (funct7 == FUNCT7_M) begin
                    // RV64M：MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
                    unique case (funct3)
                        3'b000: alu_op_code = MUL;                      // mul
                        3'b100: alu_op_code = DIV;                      // div
                        3'b101: alu_op_code = DIVU;                     // divu
                        3'b110: alu_op_code = REM;                      // rem
                        3'b111: alu_op_code = REMU;                     // remu
                        default: ;
                    endcase
                end
                else begin
                    unique case (funct3)
                        3'b000: alu_op_code = funct7[5] ? SUB : ADD;    // sub / add
                        3'b100: alu_op_code = XOR;                      // xor
                        3'b110: alu_op_code = OR;                       // or
                        3'b111: alu_op_code = AND;                      // and
                        3'b010: alu_op_code = SLT;                      // slt
                        3'b011: alu_op_code = SLTU;                     // sltu
                        3'b001: alu_op_code = SLL;                      // sll
                        3'b101: alu_op_code = funct7[5] ? SRA : SRL;    // sra / srl
                        default: ;
                    endcase
                end
            end

            OP_IMM32: begin
                alu_inst_type = WORD;
                is_op2_imm    = 1'b1;
                unique case (funct3)
                    3'b000: alu_op_code = ADD;                          // addiw
                    3'b001: alu_op_code = SLL;                          // slliw
                    3'b101: alu_op_code = funct7[5] ? SRA : SRL;        // sraiw / srliw
                    default: ;
                endcase
            end

            OP_32: begin
                alu_inst_type = WORD;
                if (funct7 == FUNCT7_M) begin
                    // RV64M 字版本：MULW/DIVW/DIVUW/REMW/REMUW
                    unique case (funct3)
                        3'b000: alu_op_code = MUL;                      // mulw
                        3'b100: alu_op_code = DIV;                      // divw
                        3'b101: alu_op_code = DIVU;                     // divuw
                        3'b110: alu_op_code = REM;                      // remw
                        3'b111: alu_op_code = REMU;                     // remuw
                        default: ;
                    endcase
                end
                else begin
                    unique case (funct3)
                        3'b000: alu_op_code = funct7[5] ? SUB : ADD;    // subw / addw
                        3'b001: alu_op_code = SLL;                      // sllw
                        3'b101: alu_op_code = funct7[5] ? SRA : SRL;    // sraw / srlw
                        default: ;
                    endcase
                end
            end

            OP_LOAD: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;    // 地址 = rs1 + imm
                is_op2_imm    = 1'b1;
            end

            OP_STORE: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;    // 地址 = rs1 + imm
                is_op2_imm    = 1'b1;
            end

            OP_LUI: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;    // rd = 0 + imm
                is_op1_zero   = 1'b1;
                is_op2_imm    = 1'b1;
            end

            OP_AUIPC: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;    // rd = PC + imm
                is_op1_pc     = 1'b1;
                is_op2_imm    = 1'b1;
            end

            OP_BRANCH: begin
                jump_type = JT_BR;
                unique case (funct3)
                    3'b000: branch_op = BR_EQ;
                    3'b001: branch_op = BR_NE;
                    3'b100: branch_op = BR_LT;
                    3'b101: branch_op = BR_GE;
                    3'b110: branch_op = BR_LTU;
                    3'b111: branch_op = BR_GEU;
                    default: branch_op = BR_NONE;
                endcase
            end

            OP_JAL: begin
                jump_type = JT_JAL;
                rd_src    = RD_FROM_PC_PLUS_4;
            end

            OP_JALR: begin
                jump_type  = JT_JALR;
                rd_src     = RD_FROM_PC_PLUS_4;
                is_op2_imm = 1'b1;  // PC_Target 用 rs1+imm，与 ALU 无关
            end

            default: ;
        endcase
    end

endmodule
