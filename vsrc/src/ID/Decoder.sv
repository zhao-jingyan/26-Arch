// ----------------------------------------------------------------------------
// File        : Decoder.sv
// Description : RISC-V 指令字译码；纯组合。输出 ALU 控制 + 分支/跳转/rd 源 flag
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/ID/ID_PKG.sv"
`include "src/ID/CSR_PKG.sv"
`include "src/EX/EX_PKG.sv"
`endif

import common::*;
import ID_PKG::*;
import CSR_PKG::*;
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
    output RD_SRC      rd_src,

    // CSR 相关（Zicsr）
    output logic       is_csr,        // 当前是否 CSR 指令
    output logic       is_csr_imm,    // CSRRWI/CSRRSI/CSRRCI（rs1 字段是立即数）
    output CSR_OP      csr_op,        // CSR 操作类型
    output u12         csr_addr,      // CSR 地址 = inst[31:20]
    output u5          csr_uimm,      // 5-bit zero-extended uimm = inst[19:15]

    output logic       is_ecall,
    output logic       is_mret,
    output logic       is_illegal
);

    u3  funct3;
    u7  funct7;
    u7  opcode_w;
    logic is_decoded;

    assign opcode_w = inst[6:0];
    assign funct3   = inst[14:12];
    assign funct7   = inst[31:25];

    assign opcode   = opcode_w;
    // S/B-type 与 ECALL/MRET 无架构 rd/rs 副作用，Decoder 内部清零
    assign rd_addr  = (opcode_w == OP_STORE || opcode_w == OP_BRANCH || is_ecall || is_mret) ? 5'b0 : inst[11:7];
    assign rs1_addr = (is_ecall || is_mret) ? 5'b0 : inst[19:15];
    assign rs2_addr = (is_ecall || is_mret) ? 5'b0 : inst[24:20];

    // CSR 字段：地址固定取 inst[31:20]，uimm 取 inst[19:15]
    assign csr_addr = inst[31:20];
    assign csr_uimm = inst[19:15];

    always_comb begin
        alu_op_code   = ADD;
        alu_inst_type = NORM;
        is_op1_zero   = 1'b0;
        is_op1_pc     = 1'b0;
        is_op2_imm    = 1'b0;
        branch_op     = BR_NONE;
        jump_type     = JT_NONE;
        rd_src        = RD_FROM_ALU;
        is_csr        = 1'b0;
        is_csr_imm    = 1'b0;
        csr_op        = CSR_NONE;
        is_ecall      = 1'b0;
        is_mret       = 1'b0;
        is_decoded    = 1'b0;

        unique case (opcode_w)
            OP_IMM: begin
                alu_inst_type = NORM;
                is_op2_imm    = 1'b1;
                unique case (funct3)
                    3'b000: begin alu_op_code = ADD; is_decoded = 1'b1; end
                    3'b100: begin alu_op_code = XOR; is_decoded = 1'b1; end
                    3'b110: begin alu_op_code = OR;  is_decoded = 1'b1; end
                    3'b111: begin alu_op_code = AND; is_decoded = 1'b1; end
                    3'b010: begin alu_op_code = SLT; is_decoded = 1'b1; end
                    3'b011: begin alu_op_code = SLTU; is_decoded = 1'b1; end
                    3'b001: begin alu_op_code = SLL; is_decoded = 1'b1; end
                    3'b101: begin alu_op_code = funct7[5] ? SRA : SRL; is_decoded = 1'b1; end
                    default: ;
                endcase
            end

            OP: begin
                alu_inst_type = NORM;
                if (funct7 == FUNCT7_M) begin
                    // RV64M：MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
                    unique case (funct3)
                        3'b000: begin alu_op_code = MUL;  is_decoded = 1'b1; end
                        3'b100: begin alu_op_code = DIV;  is_decoded = 1'b1; end
                        3'b101: begin alu_op_code = DIVU; is_decoded = 1'b1; end
                        3'b110: begin alu_op_code = REM;  is_decoded = 1'b1; end
                        3'b111: begin alu_op_code = REMU; is_decoded = 1'b1; end
                        default: ;
                    endcase
                end
                else begin
                    unique case (funct3)
                        3'b000: begin alu_op_code = funct7[5] ? SUB : ADD; is_decoded = 1'b1; end
                        3'b100: begin alu_op_code = XOR; is_decoded = 1'b1; end
                        3'b110: begin alu_op_code = OR;  is_decoded = 1'b1; end
                        3'b111: begin alu_op_code = AND; is_decoded = 1'b1; end
                        3'b010: begin alu_op_code = SLT; is_decoded = 1'b1; end
                        3'b011: begin alu_op_code = SLTU; is_decoded = 1'b1; end
                        3'b001: begin alu_op_code = SLL; is_decoded = 1'b1; end
                        3'b101: begin alu_op_code = funct7[5] ? SRA : SRL; is_decoded = 1'b1; end
                        default: ;
                    endcase
                end
            end

            OP_IMM32: begin
                alu_inst_type = WORD;
                is_op2_imm    = 1'b1;
                unique case (funct3)
                    3'b000: begin alu_op_code = ADD; is_decoded = 1'b1; end
                    3'b001: begin alu_op_code = SLL; is_decoded = 1'b1; end
                    3'b101: begin alu_op_code = funct7[5] ? SRA : SRL; is_decoded = 1'b1; end
                    default: ;
                endcase
            end

            OP_32: begin
                alu_inst_type = WORD;
                if (funct7 == FUNCT7_M) begin
                    // RV64M 字版本：MULW/DIVW/DIVUW/REMW/REMUW
                    unique case (funct3)
                        3'b000: begin alu_op_code = MUL;  is_decoded = 1'b1; end
                        3'b100: begin alu_op_code = DIV;  is_decoded = 1'b1; end
                        3'b101: begin alu_op_code = DIVU; is_decoded = 1'b1; end
                        3'b110: begin alu_op_code = REM;  is_decoded = 1'b1; end
                        3'b111: begin alu_op_code = REMU; is_decoded = 1'b1; end
                        default: ;
                    endcase
                end
                else begin
                    unique case (funct3)
                        3'b000: begin alu_op_code = funct7[5] ? SUB : ADD; is_decoded = 1'b1; end
                        3'b001: begin alu_op_code = SLL; is_decoded = 1'b1; end
                        3'b101: begin alu_op_code = funct7[5] ? SRA : SRL; is_decoded = 1'b1; end
                        default: ;
                    endcase
                end
            end

            OP_LOAD: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;
                is_op2_imm    = 1'b1;
                is_decoded    = 1'b1;
            end

            OP_STORE: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;
                is_op2_imm    = 1'b1;
                is_decoded    = 1'b1;
            end

            OP_LUI: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;
                is_op1_zero   = 1'b1;
                is_op2_imm    = 1'b1;
                is_decoded    = 1'b1;
            end

            OP_AUIPC: begin
                alu_inst_type = NORM;
                alu_op_code   = ADD;
                is_op1_pc     = 1'b1;
                is_op2_imm    = 1'b1;
                is_decoded    = 1'b1;
            end

            OP_BRANCH: begin
                jump_type = JT_BR;
                unique case (funct3)
                    3'b000: begin branch_op = BR_EQ;  is_decoded = 1'b1; end
                    3'b001: begin branch_op = BR_NE;  is_decoded = 1'b1; end
                    3'b100: begin branch_op = BR_LT;  is_decoded = 1'b1; end
                    3'b101: begin branch_op = BR_GE;  is_decoded = 1'b1; end
                    3'b110: begin branch_op = BR_LTU; is_decoded = 1'b1; end
                    3'b111: begin branch_op = BR_GEU; is_decoded = 1'b1; end
                    default: branch_op = BR_NONE;
                endcase
            end

            OP_JAL: begin
                jump_type  = JT_JAL;
                rd_src     = RD_FROM_PC_PLUS_4;
                is_decoded = 1'b1;
            end

            OP_JALR: begin
                jump_type  = JT_JALR;
                rd_src     = RD_FROM_PC_PLUS_4;
                is_op2_imm = 1'b1;
                is_decoded = 1'b1;
            end

            OP_SYSTEM: begin
                // Zicsr：CSRRW/RS/RC/RWI/RSI/RCI；rd 写回 = CSR 旧值
                // ECALL/MRET 不走 EX 段 jump，由 Privilege_Unit 在 WB 段统一接管
                // 把 CSR 指令统一标记为 JT_CSR（永远预测失败的 pc+4 跳转），
                // 借 EX 段 jump flush 路径在写 CSR 后强制刷新流水线，避免后续指令读到旧 CSR 状态
                unique case (funct3)
                    3'b000: begin
                        unique case (inst[31:20])
                            FUNCT12_ECALL: begin is_ecall = 1'b1; is_decoded = 1'b1; end
                            FUNCT12_MRET:  begin is_mret  = 1'b1; is_decoded = 1'b1; end
                            // sfence/fence/wfi 等：未实现但合法，当 NOP
                            default: begin
                                rd_src     = RD_FROM_ALU;
                                is_decoded = 1'b1;
                            end
                        endcase
                    end
                    FUNCT3_CSRRW:  begin rd_src = RD_FROM_CSR; is_csr = 1'b1; csr_op = CSR_RW;  jump_type = JT_CSR; is_decoded = 1'b1; end
                    FUNCT3_CSRRS:  begin rd_src = RD_FROM_CSR; is_csr = 1'b1; csr_op = CSR_RS;  jump_type = JT_CSR; is_decoded = 1'b1; end
                    FUNCT3_CSRRC:  begin rd_src = RD_FROM_CSR; is_csr = 1'b1; csr_op = CSR_RC;  jump_type = JT_CSR; is_decoded = 1'b1; end
                    FUNCT3_CSRRWI: begin rd_src = RD_FROM_CSR; is_csr = 1'b1; csr_op = CSR_RWI; is_csr_imm = 1'b1; jump_type = JT_CSR; is_decoded = 1'b1; end
                    FUNCT3_CSRRSI: begin rd_src = RD_FROM_CSR; is_csr = 1'b1; csr_op = CSR_RSI; is_csr_imm = 1'b1; jump_type = JT_CSR; is_decoded = 1'b1; end
                    FUNCT3_CSRRCI: begin rd_src = RD_FROM_CSR; is_csr = 1'b1; csr_op = CSR_RCI; is_csr_imm = 1'b1; jump_type = JT_CSR; is_decoded = 1'b1; end
                    // 非 Zicsr 的 SYSTEM 变体：当 NOP
                    default: begin
                        rd_src     = RD_FROM_ALU;
                        is_decoded = 1'b1;
                    end
                endcase
            end

            default: ;
        endcase
    end

    assign is_illegal = !is_decoded;

endmodule
