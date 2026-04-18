// ----------------------------------------------------------------------------
// File        : Sign_Extend.sv
// Description : 按 opcode 拼 I/S/B/U/J 五种 imm 并 sext 到 64 位，纯组合
// ----------------------------------------------------------------------------

`include "src_new/ID/ID_PKG.sv"

import common::*;
import ID_PKG::*;

module Sign_Extend (
    input  u32 inst,
    input  u7  opcode,

    output u64 imm
);

    always_comb begin
        unique case (opcode)
            // I-type：inst[31:20] sext
            OP_IMM, OP_IMM32, OP_LOAD, OP_JALR: begin
                imm = {{52{inst[31]}}, inst[31:20]};
            end
            // S-type：{inst[31:25], inst[11:7]} sext
            OP_STORE: begin
                imm = {{52{inst[31]}}, inst[31:25], inst[11:7]};
            end
            // B-type：{inst[31], inst[7], inst[30:25], inst[11:8], 1'b0} sext
            OP_BRANCH: begin
                imm = {{51{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            end
            // U-type：inst[31:12] 左移 12，低 12 位清零
            OP_LUI, OP_AUIPC: begin
                imm = {{32{inst[31]}}, inst[31:12], 12'b0};
            end
            // J-type：{inst[31], inst[19:12], inst[20], inst[30:21], 1'b0} sext
            OP_JAL: begin
                imm = {{43{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            end
            default: imm = 64'b0;
        endcase
    end

endmodule
