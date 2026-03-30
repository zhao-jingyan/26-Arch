// ----------------------------------------------------------------------------
// File        : MemStage.sv
// Description : MEM + WB stage, ALU-only writeback, MEM/WB pipeline reg at end
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"
`include "src/DECODE/DECODE_PKG.sv"
`include "src/MEM/MemDataAlign.sv"

import common::*;
import DECODE_PKG::*;
import pipeline_pkg::*;

module MemStage (
    input  logic    clk,
    input  logic    rst_n,
    input  logic    stall_front_i,
    input  logic    stall_back_i,

    input  ex_mem_t ex_mem_i,
    output dbus_req_t dbus_req_o,
    input  dbus_resp_t dbus_resp_i,
    output logic    dm_busy_o,
    // MEM-stage bypass when load data is valid (same cycle as data_ok)
    output logic    load_bypass_valid_o,
    output u64      load_bypass_data_o,

    output wb_reg_t wb_o
);

    wb_reg_t mem_wb_d;
    logic is_load;
    logic is_store;
    logic [2:0] funct3;
    logic [63:0] store_wdata;
    logic [7:0] store_strobe;
    logic [63:0] load_data_ext;
    msize_t req_size;
    logic is_mem;
    logic mem_req_pending_q;
    logic mem_req_done_q;
    logic mem_inst_same;
    u64   load_data_q;
    u64   mem_pc_q;
    logic [31:0] mem_inst_q;
    u7    mem_opcode_q;

    assign is_load  = (ex_mem_i.opcode == OP_LOAD);
    assign is_store = (ex_mem_i.opcode == OP_STORE);
    assign is_mem   = is_load || is_store;
    assign funct3   = ex_mem_i.inst[14:12];
    assign mem_inst_same = (ex_mem_i.pc == mem_pc_q)
                        && (ex_mem_i.inst == mem_inst_q)
                        && (ex_mem_i.opcode == mem_opcode_q);
    
    MemDataAlign u_mem_data_align (
        .funct3_i     ( funct3 ),
        .addr_i       ( ex_mem_i.alu_res ),
        .store_data_i ( ex_mem_i.store_data ),
        .load_rdata_i ( dbus_resp_i.data ),
        .req_size_o   ( req_size ),
        .req_strobe_o ( store_strobe ),
        .req_wdata_o  ( store_wdata ),
        .load_data_o  ( load_data_ext )
    );

    assign dbus_req_o.valid  = is_mem && mem_req_pending_q;
    assign dbus_req_o.addr   = ex_mem_i.alu_res;
    assign dbus_req_o.size   = req_size;
    assign dbus_req_o.strobe = is_store ? store_strobe : 8'b0;
    assign dbus_req_o.data   = is_store ? store_wdata : 64'b0;

    assign dm_busy_o = is_mem && !(mem_req_done_q || (mem_req_pending_q && dbus_resp_i.data_ok));
    assign load_bypass_valid_o = is_load && mem_req_pending_q && dbus_resp_i.data_ok && (ex_mem_i.rd_addr != 5'b0);
    assign load_bypass_data_o  = load_data_ext;

    // Keep one in-flight memory request for current EX/MEM instruction.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_req_pending_q <= 1'b0;
            mem_req_done_q    <= 1'b0;
            load_data_q       <= '0;
            mem_pc_q          <= '0;
            mem_inst_q        <= '0;
            mem_opcode_q      <= '0;
        end
        else begin
            mem_pc_q     <= ex_mem_i.pc;
            mem_inst_q   <= ex_mem_i.inst;
            mem_opcode_q <= ex_mem_i.opcode;

            if (!is_mem) begin
                mem_req_pending_q <= 1'b0;
                mem_req_done_q    <= 1'b0;
            end else if (!mem_inst_same) begin
                mem_req_pending_q <= 1'b1;
                mem_req_done_q    <= 1'b0;
            end else if (mem_req_pending_q && dbus_resp_i.data_ok) begin
                mem_req_pending_q <= 1'b0;
                mem_req_done_q    <= 1'b1;
                load_data_q       <= load_data_ext;
            end
        end
    end

    // Load: data_ok is comb; mem_req_done_q updates next edge. Same edge ex_mem may advance once
    // dm_busy drops, so capture wb using pending&&data_ok here (else load writeback is lost).
    assign mem_wb_d.wen     = is_load
        ? ((ex_mem_i.rd_addr != 5'b0)
            && (mem_req_done_q || (mem_req_pending_q && dbus_resp_i.data_ok)))
        : ((ex_mem_i.rd_addr != 5'b0) && !is_store);
    assign mem_wb_d.rd_addr = ex_mem_i.rd_addr;
    assign mem_wb_d.rd_data = is_load
        ? ((mem_req_pending_q && dbus_resp_i.data_ok) ? load_data_ext : load_data_q)
        : ex_mem_i.alu_res;
    assign mem_wb_d.pc      = ex_mem_i.pc;
    assign mem_wb_d.inst    = ex_mem_i.inst;

    // MEM/WB pipeline reg
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_o <= '0;
        end else if (!stall_back_i && !stall_front_i) begin
            wb_o <= mem_wb_d;
        end
    end

endmodule
