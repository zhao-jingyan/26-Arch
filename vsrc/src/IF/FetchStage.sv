// ----------------------------------------------------------------------------
// File        : FetchStage.sv
// Description : IF stage: PC counter + InstructionMemory
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"
`include "src/IF/InstructionMemory.sv"

import common::*;
import pipeline_pkg::*;

module FetchStage (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       stall_i,

    output if_id_t     if_id_o,
    output logic       im_busy_o,
    output ibus_req_t  ibus_req_o,
    input  ibus_resp_t ibus_resp_i
);

    u64 pc_q;

    im_req_t im_req;
    im_rsp_t im_rsp;

    // PC counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_q <= PCINIT;
        else if (im_rsp.valid && !stall_i)
            pc_q <= pc_q + 64'd4;
    end

    assign im_req.valid = 1'b1;
    assign im_busy_o    = im_req.valid && !im_rsp.valid;

    assign im_req.addr  = pc_q;

    InstructionMemory u_im (
        .clk          ( clk ),
        .rst_n        ( rst_n ),
        .req_i        ( im_req ),
        .rsp_o        ( im_rsp ),
        .ibus_req_o   ( ibus_req_o ),
        .ibus_resp_i  ( ibus_resp_i )
    );

    // IF/ID pipeline reg
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_o <= '0;
        end else if (im_rsp.valid && !stall_i) begin
            if_id_o.inst <= im_rsp.data;
            if_id_o.pc   <= pc_q;
        end
    end

endmodule
