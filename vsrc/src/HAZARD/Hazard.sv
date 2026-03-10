// ----------------------------------------------------------------------------
// File        : Hazard.sv
// Description : Hazard unit: forwarding control + stall
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

import common::*;
import pipeline_pkg::*;

// fwd_sel: 2'b00 = RegFile, 2'b01 = ex_mem, 2'b10 = wb
module Hazard (
    input  id_ex_t   id_ex_i,
    input  ex_mem_t  ex_mem_i,
    input  wb_reg_t  wb_i,
    input  logic     im_busy_i,

    output logic [1:0] rs1_fwd_sel_o,
    output logic [1:0] rs2_fwd_sel_o,
    output logic      stall_o
);

    logic ex_mem_wen;
    assign ex_mem_wen = (ex_mem_i.rd_addr != 5'b0);

    // rs1: ex_mem > wb > rf
    always_comb begin
        rs1_fwd_sel_o = 2'b00;
        if (ex_mem_i.rd_addr == id_ex_i.rs1_addr && ex_mem_wen)
            rs1_fwd_sel_o = 2'b01;
        else if (wb_i.rd_addr == id_ex_i.rs1_addr && wb_i.wen)
            rs1_fwd_sel_o = 2'b10;
    end

    // rs2: ex_mem > wb > rf
    always_comb begin
        rs2_fwd_sel_o = 2'b00;
        if (ex_mem_i.rd_addr == id_ex_i.rs2_addr && ex_mem_wen)
            rs2_fwd_sel_o = 2'b01;
        else if (wb_i.rd_addr == id_ex_i.rs2_addr && wb_i.wen)
            rs2_fwd_sel_o = 2'b10;
    end

    assign stall_o = im_busy_i;  // if_stall: IM not returned; TODO: load_use_stall

endmodule
