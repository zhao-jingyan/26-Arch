// ----------------------------------------------------------------------------
// File        : MemStage.sv
// Description : MEM + WB stage, ALU-only writeback, MEM/WB pipeline reg at end
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

import common::*;
import pipeline_pkg::*;

module MemStage (
    input  logic    clk,
    input  logic    rst_n,
    input  logic    stall_i,

    input  ex_mem_t ex_mem_i,

    output wb_reg_t wb_o
);

    wb_reg_t mem_wb_d;

    assign mem_wb_d.wen     = (ex_mem_i.rd_addr != 5'b0);
    assign mem_wb_d.rd_addr = ex_mem_i.rd_addr;
    assign mem_wb_d.rd_data = ex_mem_i.alu_res;
    assign mem_wb_d.pc      = ex_mem_i.pc;
    assign mem_wb_d.inst    = ex_mem_i.inst;

    // MEM/WB pipeline reg
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_o <= '0;
        end else if (!stall_i) begin
            wb_o <= mem_wb_d;
        end
    end

endmodule
