// ----------------------------------------------------------------------------
// File        : Commit_Unit.sv
// Description : 提交边沿与 Difftest 对账信息收敛
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`endif

import common::*;
import top_pkg::*;

module Commit_Unit (
    input  logic    clk,
    input  logic    rst_n,

    input  INST_CTX mem_inst_ctx,
    input  MEM_2_WB mem_2_wb,

    output logic    wb_commit_valid,
    output logic    commit_valid_o,
    output u64      commit_pc_o,
    output u32      commit_instr_o,
    output logic    commit_wen_o,
    output u8       commit_wdest_o,
    output u64      commit_wdata_o,
    output logic    commit_sc_failed_o,
    output logic    commit_skip_o
);

    INST_CTX prev_inst_ctx;
    MEM_2_WB prev_mem_2_wb;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_inst_ctx <= '0;
            prev_mem_2_wb  <= '0;
        end else begin
            prev_inst_ctx <= mem_inst_ctx;
            prev_mem_2_wb  <= mem_2_wb;
        end
    end

    assign wb_commit_valid = (mem_inst_ctx.inst != 32'b0)
                          && ((mem_inst_ctx.pc_inst_address != prev_inst_ctx.pc_inst_address)
                           || (mem_inst_ctx.inst            != prev_inst_ctx.inst));

    assign commit_valid_o = (prev_inst_ctx.inst != 32'b0)
                         && ((mem_inst_ctx.pc_inst_address != prev_inst_ctx.pc_inst_address)
                          || (mem_inst_ctx.inst            != prev_inst_ctx.inst));
    assign commit_pc_o    = prev_inst_ctx.pc_inst_address;
    assign commit_instr_o = prev_inst_ctx.inst;
    assign commit_wen_o   = (prev_inst_ctx.rd_addr != 5'b0);
    assign commit_wdest_o = {3'b0, prev_inst_ctx.rd_addr};
    assign commit_wdata_o = prev_mem_2_wb.rd_data;
    assign commit_sc_failed_o = prev_mem_2_wb.sc_failed;

    logic commit_is_mem;
    assign commit_is_mem = (prev_inst_ctx.opcode == OP_LOAD)
                        || (prev_inst_ctx.opcode == OP_STORE)
                        || (prev_inst_ctx.opcode == OP_AMO);
    assign commit_skip_o = commit_is_mem && (prev_mem_2_wb.mem_addr[31] == 1'b0);

endmodule
