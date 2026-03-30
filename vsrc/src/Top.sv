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

    logic [1:0] rs1_fwd_sel;
    logic [1:0] rs2_fwd_sel;
    logic       stall;
    logic       im_busy;
    logic       dm_busy;

    Hazard u_hazard (
        .id_ex_i       ( id_ex ),
        .ex_mem_i      ( ex_mem ),
        .wb_i          ( wb ),
        .im_busy_i     ( im_busy ),
        .dm_busy_i     ( dm_busy ),
        .rs1_fwd_sel_o ( rs1_fwd_sel ),
        .rs2_fwd_sel_o ( rs2_fwd_sel ),
        .stall_o       ( stall )
    );

    FetchStage u_fetch (
        .clk          ( clk ),
        .rst_n        ( rst_n ),
        .stall_i      ( stall ),
        .if_id_o      ( if_id ),
        .im_busy_o    ( im_busy ),
        .ibus_req_o   ( ibus_req_o ),
        .ibus_resp_i  ( ibus_resp_i )
    );

    DecodeStage u_decode (
        .clk      ( clk ),
        .rst_n    ( rst_n ),
        .stall_i  ( stall ),
        .if_id_i  ( if_id ),
        .wb_i     ( wb ),
        .id_ex_o  ( id_ex ),
        .gpr_o    ( gpr_o )
    );

    ALUStage u_alu (
        .clk           ( clk ),
        .rst_n         ( rst_n ),
        .stall_i       ( stall ),
        .id_ex_i       ( id_ex ),
        .ex_mem_i      ( ex_mem ),
        .wb_i          ( wb ),
        .rs1_fwd_sel_i ( rs1_fwd_sel ),
        .rs2_fwd_sel_i ( rs2_fwd_sel ),
        .ex_mem_o      ( ex_mem )
    );

    MemStage u_mem (
        .clk       ( clk ),
        .rst_n     ( rst_n ),
        .stall_i   ( stall ),
        .ex_mem_i  ( ex_mem ),
        .dbus_req_o( dbus_req_o ),
        .dbus_resp_i( dbus_resp_i ),
        .dm_busy_o ( dm_busy ),
        .wb_o      ( wb )
    );

    assign commit_valid_o  = !stall;  // commit when pipeline advances
    assign commit_pc_o     = wb.pc;
    assign commit_instr_o  = wb.inst;
    assign commit_wen_o    = wb.wen;
    assign commit_wdest_o  = {3'b0, wb.rd_addr};  // zero-extend to 8 bits for difftest
    assign commit_wdata_o  = wb.rd_data;

endmodule
