// ----------------------------------------------------------------------------
// File        : InstructionMemory.sv
// Description : IF fetch, buffer impl, talks to IBus
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

import common::*;
import pipeline_pkg::*;

module InstructionMemory (
    input  logic       clk,
    input  logic       rst_n,

    input  im_req_t    req_i,
    output im_rsp_t    rsp_o,

    output ibus_req_t  ibus_req_o,
    input  ibus_resp_t ibus_resp_i
);

    logic busy;

    assign busy = req_i.valid && !rsp_o.valid;

    assign ibus_req_o.valid = busy;
    assign ibus_req_o.addr  = req_i.addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_o <= '0;
        end else begin
            rsp_o.valid <= 1'b0;
            if (ibus_resp_i.data_ok && busy) begin
                rsp_o.data  <= ibus_resp_i.data;
                rsp_o.valid <= 1'b1;
            end
        end
    end

endmodule
