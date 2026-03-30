// ----------------------------------------------------------------------------
// File        : Hazard.sv
// Description : Hazard unit: forwarding control
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

import common::*;
import DECODE_PKG::*;
import pipeline_pkg::*;

// fwd_sel: 2'b00 = RegFile, 2'b01 = ex_mem, 2'b10 = wb
module Hazard (
    input  logic     clk,
    input  logic     rst_n,
    input  id_ex_t   id_ex_i,
    input  ex_mem_t  ex_mem_i,
    input  wb_reg_t  wb_i,
    input  logic     im_busy_i,
    input  logic     dm_busy_i,
    input  logic     load_bypass_valid_i,

    output logic [1:0] rs1_fwd_sel_o,
    output logic [1:0] rs2_fwd_sel_o,
    // STORE src is inst[24:20]; id_ex.rs2_addr is forced 0 for imm into ALU op2
    output logic [1:0] store_data_fwd_sel_o,
    output logic       stall_front_o,
    output logic       stall_back_o,
    // Drop new IF issue while DMEM or load-use stalls front (in-flight IF kept in FetchStage).
    output logic       stall_if_issue_block_o
);

    logic ex_mem_fwd_ok;
    logic ex_mem_fwd_src_ok;  // no ex->ex alias while same instr held in id_ex and ex_mem (front stall)
    logic wb_fwd_ok;
    logic rs1_used;
    logic rs2_used;
    logic store_src_used;
    logic load_use_stall;
    logic stall_if_issue_block_q;

    // EX/MEM alu_res is forwardable for ALU-like ops only in phase-1.
    assign ex_mem_fwd_ok = (ex_mem_i.rd_addr != 5'b0) && (
                              (ex_mem_i.opcode == OP)
                           || (ex_mem_i.opcode == OP_32)
                           || (ex_mem_i.opcode == OP_IMM)
                           || (ex_mem_i.opcode == OP_IMM32)
                           || (ex_mem_i.opcode == OP_LUI)
                         );
    assign ex_mem_fwd_src_ok = ex_mem_fwd_ok
        && !((ex_mem_i.pc == id_ex_i.pc) && (ex_mem_i.inst == id_ex_i.inst));
    assign wb_fwd_ok = wb_i.wen && (wb_i.rd_addr != 5'b0);
    assign rs1_used = (id_ex_i.rs1_addr != 5'b0);
    assign rs2_used = (id_ex_i.rs2_addr != 5'b0);
    assign store_src_used = (id_ex_i.opcode == OP_STORE) && (id_ex_i.inst[24:20] != 5'b0);
    assign load_use_stall = (ex_mem_i.opcode == OP_LOAD)
                         && (ex_mem_i.rd_addr != 5'b0)
                         && (
                                (rs1_used && (ex_mem_i.rd_addr == id_ex_i.rs1_addr))
                             || (rs2_used && (ex_mem_i.rd_addr == id_ex_i.rs2_addr))
                             || (store_src_used && (ex_mem_i.rd_addr == id_ex_i.inst[24:20]))
                            )
                         && !load_bypass_valid_i;

    // rs1: load bypass > ex_mem > wb > rf
    always_comb begin
        rs1_fwd_sel_o = 2'b00;
        if (rs1_used && load_bypass_valid_i && (ex_mem_i.rd_addr == id_ex_i.rs1_addr))
            rs1_fwd_sel_o = 2'b11;
        else if (rs1_used && ex_mem_fwd_src_ok && (ex_mem_i.rd_addr == id_ex_i.rs1_addr))
            rs1_fwd_sel_o = 2'b01;
        else if (rs1_used && wb_fwd_ok && (wb_i.rd_addr == id_ex_i.rs1_addr))
            rs1_fwd_sel_o = 2'b10;
    end

    // rs2: load bypass > ex_mem > wb > rf
    always_comb begin
        rs2_fwd_sel_o = 2'b00;
        if (rs2_used && load_bypass_valid_i && (ex_mem_i.rd_addr == id_ex_i.rs2_addr))
            rs2_fwd_sel_o = 2'b11;
        else if (rs2_used && ex_mem_fwd_src_ok && (ex_mem_i.rd_addr == id_ex_i.rs2_addr))
            rs2_fwd_sel_o = 2'b01;
        else if (rs2_used && wb_fwd_ok && (wb_i.rd_addr == id_ex_i.rs2_addr))
            rs2_fwd_sel_o = 2'b10;
    end

    // store_data: same priority as rs2, compare architectural rs2 field
    always_comb begin
        store_data_fwd_sel_o = 2'b00;
        if (store_src_used) begin
            if (load_bypass_valid_i && (ex_mem_i.rd_addr == id_ex_i.inst[24:20]))
                store_data_fwd_sel_o = 2'b11;
            else if (ex_mem_fwd_src_ok && (ex_mem_i.rd_addr == id_ex_i.inst[24:20]))
                store_data_fwd_sel_o = 2'b01;
            else if (wb_fwd_ok && (wb_i.rd_addr == id_ex_i.inst[24:20]))
                store_data_fwd_sel_o = 2'b10;
        end
    end

    // Keep ex_mem stable during dmem wait with front freeze.
    assign stall_front_o = im_busy_i || dm_busy_i || load_use_stall;
    assign stall_back_o  = dm_busy_i;

    // Registered to break combo loop (dbus path -> load_bypass -> load_use -> im_req).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stall_if_issue_block_q <= 1'b0;
        else
            stall_if_issue_block_q <= dm_busy_i || load_use_stall;
    end

    assign stall_if_issue_block_o = stall_if_issue_block_q;

endmodule
