// ----------------------------------------------------------------------------
// File        : ALU_Core.sv
// Description : 64-bit ALU：算术 / 逻辑 / 移位 / 比较
//               NORM = 全 64-bit；WORD = 低 32-bit 运算结果 sext 回 64
// ----------------------------------------------------------------------------

`include "src/EX/EX_PKG.sv"

import common::*;
import EX_PKG::*;

module ALU_Core (
    input  ALU_OP_CODE op_code,
    input  ALU_INST    inst_type,

    input  u64         alu_input_1,
    input  u64         alu_input_2,

    output u64         alu_core_res
);

    // RV64 移位量：NORM 取低 6 位，WORD 取低 5 位
    logic [5:0] shamt64;
    logic [4:0] shamt32;
    assign shamt64 = alu_input_2[5:0];
    assign shamt32 = alu_input_2[4:0];

    u32 res32;
    u64 res64;

    always_comb begin
        alu_core_res = 64'b0;
        res32        = 32'b0;
        res64        = 64'b0;

        unique case (inst_type)
            NORM: begin
                unique case (op_code)
                    ADD:  alu_core_res = alu_input_1 + alu_input_2;
                    SUB:  alu_core_res = alu_input_1 - alu_input_2;
                    AND:  alu_core_res = alu_input_1 & alu_input_2;
                    OR :  alu_core_res = alu_input_1 | alu_input_2;
                    XOR:  alu_core_res = alu_input_1 ^ alu_input_2;
                    SLL:  alu_core_res = alu_input_1 << shamt64;
                    SRL:  alu_core_res = alu_input_1 >> shamt64;
                    SRA:  alu_core_res = u64'($signed(alu_input_1) >>> shamt64);
                    SLT:  alu_core_res = {63'b0, ($signed(alu_input_1) < $signed(alu_input_2))};
                    SLTU: alu_core_res = {63'b0, (alu_input_1 < alu_input_2)};
                    default: alu_core_res = 64'b0;
                endcase
            end

            WORD: begin
                unique case (op_code)
                    ADD: begin
                        res32        = alu_input_1[31:0] + alu_input_2[31:0];
                        alu_core_res = {{32{res32[31]}}, res32};
                    end
                    SUB: begin
                        res32        = alu_input_1[31:0] - alu_input_2[31:0];
                        alu_core_res = {{32{res32[31]}}, res32};
                    end
                    SLL: begin
                        res32        = alu_input_1[31:0] << shamt32;
                        alu_core_res = {{32{res32[31]}}, res32};
                    end
                    SRL: begin
                        res32        = alu_input_1[31:0] >> shamt32;
                        alu_core_res = {{32{res32[31]}}, res32};
                    end
                    SRA: begin
                        res32        = u32'($signed(alu_input_1[31:0]) >>> shamt32);
                        alu_core_res = {{32{res32[31]}}, res32};
                    end
                    default: alu_core_res = 64'b0;
                endcase
            end

            default: alu_core_res = 64'b0;
        endcase
    end

endmodule
