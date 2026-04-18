// ----------------------------------------------------------------------------
// File        : Top.sv
// Description : Five-stage pipeline: IF, ID, EX, MEM, WB
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"

`include "src/IF/FetchStage.sv"
`include "src/DECODE/DecodeStage.sv"
`include "src/ALU/BypassOperandMux.sv"
`include "src/ALU/ALUStage.sv"
`include "src/MEM/MemStage.sv"

import common::*;
import DECODE_PKG::*;
import pipeline_pkg::*;

module Top (
    input  logic       clk,
    input  logic       rst_n,

    output ibus_req_t  ibus_req_o,
    input  ibus_resp_t ibus_resp_i,
    output dbus_req_t  dbus_req_o,
    input  dbus_resp_t dbus_resp_i,

    output logic       commit_valid_o,
    output u64         commit_pc_o,
    output logic [31:0] commit_instr_o,
    output logic       commit_wen_o,
    output u8          commit_wdest_o,
    output u64         commit_wdata_o,
    output u64         gpr_o [0:31]
);

    if_id_t       if_id;
    decoder_out_t decoder_out;
    alu_input_t   alu_input;
    alu_out_t     alu_out;
    wb_reg_t wb;
    wb_reg_t wb_prev_q;

    logic       stall_front;
    logic       stall_back;
    logic       stall_if_issue_block;
    logic       stall_if_issue_block_q;
    logic       im_busy;
    logic       dm_busy;
    logic       load_bypass_valid;
    u64         load_bypass_data;

    logic       rs1_used;
    logic       rs2_used;
    logic       store_src_used;
    logic       load_use_stall;

    u64         alu_op1_val;
    u64         alu_op2_val;
    u64         alu_store_val;

    assign rs1_used       = (decoder_out.rs1_addr != 5'b0);
    assign rs2_used       = (decoder_out.rs2_addr != 5'b0);
    assign store_src_used = (decoder_out.opcode == OP_STORE) && (decoder_out.inst[24:20] != 5'b0);
    assign load_use_stall  = (alu_out.ctx.opcode == OP_LOAD)
                           && (alu_out.ctx.rd_addr != 5'b0)
                           && (
                                  (rs1_used && (alu_out.ctx.rd_addr == decoder_out.rs1_addr))
                               || (rs2_used && (alu_out.ctx.rd_addr == decoder_out.rs2_addr))
                               || (store_src_used && (alu_out.ctx.rd_addr == decoder_out.inst[24:20]))
                              )
                           && !load_bypass_valid;

    assign stall_front = im_busy || dm_busy || load_use_stall;
    assign stall_back  = dm_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stall_if_issue_block_q <= 1'b0;
        else
            stall_if_issue_block_q <= dm_busy || load_use_stall;
    end
    assign stall_if_issue_block = stall_if_issue_block_q;

    assign alu_input.ctx.pc      = decoder_out.pc;
    assign alu_input.ctx.inst    = decoder_out.inst;
    assign alu_input.ctx.rd_addr = decoder_out.rd_addr;
    assign alu_input.ctx.opcode  = decoder_out.opcode;
    assign alu_input.ctrl.alu_op_code   = decoder_out.alu_op_code;
    assign alu_input.ctrl.alu_inst_type = decoder_out.alu_inst_type;

    // No forwarding: operand mux uses ID/EX register file read only (sel = RF).
    BypassOperandMux u_bypass_mux (
        .decoder_out_i        ( decoder_out ),
        .fwd_data_ex_stage_i  ( alu_out.alu_res ),
        .fwd_data_mem_stage_i ( load_bypass_data ),
        .fwd_data_wb_stage_i  ( wb.rd_data ),
        .op1_src_sel_i        ( 2'b00 ),
        .op2_src_sel_i        ( 2'b00 ),
        .store_val_src_sel_i  ( 2'b00 ),
        .op1_val_o            ( alu_op1_val ),
        .op2_val_o            ( alu_op2_val ),
        .store_ex_data_o      ( alu_store_val )
    );

    assign alu_input.op1_val   = alu_op1_val;
    assign alu_input.op2_val   = alu_op2_val;
    assign alu_input.store_val = alu_store_val;

    FetchStage u_fetch (
        .clk          ( clk ),
        .rst_n        ( rst_n ),
        .stall_front_i( stall_front ),
        .stall_if_issue_block_i ( stall_if_issue_block ),
        .if_id_o      ( if_id ),
        .im_busy_o    ( im_busy ),
        .ibus_req_o   ( ibus_req_o ),
        .ibus_resp_i  ( ibus_resp_i )
    );

    DecodeStage u_decode (
        .clk      ( clk ),
        .rst_n    ( rst_n ),
        .stall_front_i( stall_front ),
        .if_id_i  ( if_id ),
        .wb_i     ( wb ),
        .decoder_out_o ( decoder_out ),
        .gpr_o    ( gpr_o )
    );

    ALUStage u_alu (
        .clk         ( clk ),
        .rst_n       ( rst_n ),
        .stall_i     ( stall_front ),
        .flush_i     ( 1'b0 ),
        .alu_input_i ( alu_input ),
        .alu_out_o   ( alu_out )
    );

    MemStage u_mem (
        .clk       ( clk ),
        .rst_n     ( rst_n ),
        .stall_front_i( stall_front ),
        .stall_back_i( stall_back ),
        .mem_input_i ( alu_out ),
        .dbus_req_o( dbus_req_o ),
        .dbus_resp_i( dbus_resp_i ),
        .dm_busy_o ( dm_busy ),
        .load_bypass_valid_o ( load_bypass_valid ),
        .load_bypass_data_o  ( load_bypass_data ),
        .wb_o      ( wb )
    );

    // Retire previous WB slot when wb advances; aligns difftest with RegFile seeing retiring insn.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_prev_q <= '0;
        else
            wb_prev_q <= wb;
    end

    assign commit_valid_o  = (wb_prev_q.inst != 32'b0)
        && ((wb.pc != wb_prev_q.pc) || (wb.inst != wb_prev_q.inst));
    assign commit_pc_o     = wb_prev_q.pc;
    assign commit_instr_o  = wb_prev_q.inst;
    assign commit_wen_o    = wb_prev_q.wen;
    assign commit_wdest_o  = {3'b0, wb_prev_q.rd_addr};
    assign commit_wdata_o  = wb_prev_q.rd_data;

endmodule
