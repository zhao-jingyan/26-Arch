// --------------------------------------------------
// File        : ALU_Core.sv
// Description : ALU Core conducts add, sub, etc.
// Author      : zhao-jingyan | Date: 2026-03-06
// --------------------------------------------------

import ALU_PKG::*;
import common::*;

module ALU_Core (
    input ALU_OP_CODE op_code_i,
    input ALU_INST inst_type_i,

    input u64 op1_i,
    input u64 op2_i,
    output u64 alu_core_res_o
);
    always_comb begin
        alu_core_res_o = 64'b0;
        
        case( inst_type_i )
            NORM: begin
                case( op_code_i )
                    ADD: alu_core_res_o = op1_i + op2_i;
                    SUB: alu_core_res_o = op1_i - op2_i;
                    AND: alu_core_res_o = op1_i & op2_i;
                    OR : alu_core_res_o = op1_i | op2_i;
                    XOR: alu_core_res_o = op1_i ^ op2_i;
                    default: alu_core_res_o = 64'b0;
                endcase
            end

            WORD: begin
                case( op_code_i )
                    ADD: begin
                        automatic u32 res32 = op1_i[31:0] + op2_i[31:0];
                        alu_core_res_o = {{32{res32[31]}}, res32};
                    end
                    SUB: begin
                        automatic u32 res32 = op1_i[31:0] - op2_i[31:0];
                        alu_core_res_o = {{32{res32[31]}}, res32};
                    end
                    default: alu_core_res_o = 64'b0;
                endcase
            end

            default: alu_core_res_o = 64'b0;
        endcase
    end
endmodule