// ----------------------------------------------------------------------------
// File        : BypassOperandMux.sv
// Description : Operand data plane: pick bypass pool vs decoder_out register read
// Author      : zhao-jingyan | Date: 2026-04-13
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"
`include "src/DECODE/DECODE_PKG.sv"

import common::*;
import pipeline_pkg::*;
import DECODE_PKG::*;

module BypassOperandMux (
    input  decoder_out_t decoder_out_i,
    input  u64           fwd_data_ex_stage_i,
    input  u64           fwd_data_mem_stage_i,
    input  u64           fwd_data_wb_stage_i,
    input  logic [1:0] op1_src_sel_i,
    input  logic [1:0] op2_src_sel_i,
    input  logic [1:0] store_val_src_sel_i,

    output u64           op1_val_o,
    output u64           op2_val_o,
    output u64           store_ex_data_o
);

    u64 rs1_pool;
    u64 rs2_pool;
    u64 store_pool;

    always_comb begin
        case (op1_src_sel_i)
            2'b01: rs1_pool = fwd_data_ex_stage_i;
            2'b10: rs1_pool = fwd_data_wb_stage_i;
            2'b11: rs1_pool = fwd_data_mem_stage_i;
            default: rs1_pool = decoder_out_i.rs1_data;
        endcase
    end

    always_comb begin
        case (op2_src_sel_i)
            2'b01: rs2_pool = fwd_data_ex_stage_i;
            2'b10: rs2_pool = fwd_data_wb_stage_i;
            2'b11: rs2_pool = fwd_data_mem_stage_i;
            default: rs2_pool = decoder_out_i.rs2_data;
        endcase
    end

    always_comb begin
        case (store_val_src_sel_i)
            2'b01: store_pool = fwd_data_ex_stage_i;
            2'b10: store_pool = fwd_data_wb_stage_i;
            2'b11: store_pool = fwd_data_mem_stage_i;
            default: store_pool = decoder_out_i.store_data;
        endcase
    end

    assign op1_val_o = rs1_pool;
    assign op2_val_o = (decoder_out_i.opcode == OP_IMM || decoder_out_i.opcode == OP_IMM32)
        ? decoder_out_i.imm : rs2_pool;
    assign store_ex_data_o = (decoder_out_i.opcode == OP_STORE) ? store_pool : decoder_out_i.store_data;

endmodule
