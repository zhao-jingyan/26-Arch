// ----------------------------------------------------------------------------
// File        : Top.sv
// Description : Five-stage pipeline: IF, ID, EX, MEM, WB
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"

`include "src/HAZARD/Hazard.sv"
`include "src/IF/FetchStage.sv"
`include "src/DECODE/DecodeStage.sv"
`include "src/ALU/ALUStage.sv"
`include "src/MEM/MemStage.sv"

import common::*;
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

    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    wb_reg_t wb;
    wb_reg_t wb_prev_q;

    logic [1:0] rs1_fwd_sel;
    logic [1:0] rs2_fwd_sel;
    logic [1:0] store_data_fwd_sel;

    logic       stall_front;
    logic       stall_back;
    logic       stall_if_issue_block;
    logic       im_busy;
    logic       dm_busy;
    logic       load_bypass_valid;
    u64         load_bypass_data;

    Hazard u_hazard (
        .clk           ( clk ),
        .rst_n         ( rst_n ),
        .id_ex_i       ( id_ex ),
        .ex_mem_i      ( ex_mem ),
        .wb_i          ( wb ),
        .im_busy_i     ( im_busy ),
        .dm_busy_i     ( dm_busy ),
        .load_bypass_valid_i ( load_bypass_valid ),
        .rs1_fwd_sel_o ( rs1_fwd_sel ),
        .rs2_fwd_sel_o ( rs2_fwd_sel ),
        .store_data_fwd_sel_o ( store_data_fwd_sel ),
        .stall_front_o ( stall_front ),
        .stall_back_o  ( stall_back ),
        .stall_if_issue_block_o ( stall_if_issue_block )
    );

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
        .id_ex_o  ( id_ex ),
        .gpr_o    ( gpr_o )
    );

    ALUStage u_alu (
        .clk           ( clk ),
        .rst_n         ( rst_n ),
        .stall_front_i ( stall_front ),
        .id_ex_i       ( id_ex ),
        .ex_mem_i      ( ex_mem ),
        .wb_i          ( wb ),
        .rs1_fwd_sel_i ( rs1_fwd_sel ),
        .load_bypass_data_i ( load_bypass_data ),
        .rs2_fwd_sel_i ( rs2_fwd_sel ),
        .store_data_fwd_sel_i ( store_data_fwd_sel ),
        .ex_mem_o      ( ex_mem )
    );

    MemStage u_mem (
        .clk       ( clk ),
        .rst_n     ( rst_n ),
        .stall_front_i( stall_front ),
        .stall_back_i( stall_back ),
        .ex_mem_i  ( ex_mem ),
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
