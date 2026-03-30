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
    input  logic       stall_front_i,
    input  logic       stall_if_issue_block_i,

    output if_id_t     if_id_o,
    output logic       im_busy_o,
    output ibus_req_t  ibus_req_o,
    input  ibus_resp_t ibus_resp_i
);

    u64 pc_q;
    im_req_t im_req;
    im_rsp_t im_rsp;
    logic if_pending_q;

    // PC counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_q <= PCINIT;
        // If response is valid and not stalled, increment PC
        else if (im_rsp.valid && !stall_front_i)
            pc_q <= pc_q + 64'd4;
    end

    // No new issue under DMEM/load-use stall; hold valid until rsp if already in flight.
    assign im_req.valid = !stall_if_issue_block_i || if_pending_q;
    assign im_busy_o      = im_req.valid && !im_rsp.valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            if_pending_q <= 1'b0;
        else begin
            if (im_rsp.valid)
                if_pending_q <= 1'b0;
            else if (im_req.valid)
                if_pending_q <= 1'b1;
        end
    end

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
        end else if (im_rsp.valid && !stall_front_i) begin
            if_id_o.inst <= im_rsp.data;
            if_id_o.pc   <= pc_q;
        end
    end

endmodule
