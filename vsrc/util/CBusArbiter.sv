`ifndef __CBUSARBITER_SV
`define __CBUSARBITER_SV

`ifdef VERILATOR
`include "include/common.sv"
`else

`endif
/**
 * this implementation is not efficient, since
 * it adds one cycle lantency to all requests.
 */

module CBusArbiter
	import common::*;#(
    parameter int NUM_INPUTS = 2,  // NOTE: NUM_INPUTS >= 1

    localparam int MAX_INDEX = NUM_INPUTS - 1
) (
    input logic clk, reset,

    input  cbus_req_t  ireqs [MAX_INDEX:0],
    output cbus_resp_t iresps [MAX_INDEX:0],
    output cbus_req_t  oreq,
    input  cbus_resp_t oresp
);
    logic busy;
    int index, select;
    cbus_req_t saved_req, selected_req;

    // 事务发起后固定使用锁存请求，避免上游流水变化污染写数据/写掩码。
    // 空闲时仍直通新选中的请求，保证第一拍可以发起。
    assign oreq = busy ? saved_req : selected_req;
    assign selected_req = ireqs[select];

    // select a preferred request
    always_comb begin
        select = 0;

        for (int i = 0; i < NUM_INPUTS; i++) begin
            if (ireqs[i].valid) begin
                select = i;
                break;
            end
        end
    end

    // feedback to selected request
    always_comb begin
        for (int i = 0; i < NUM_INPUTS; i++) begin
            iresps[i] = '0;
        end

        if (busy) begin
            for (int i = 0; i < NUM_INPUTS; i++) begin
                if (index == i)
                    iresps[i] = oresp;
            end
        end
    end

    always_ff @(posedge clk)
    if (~reset) begin
        if (busy) begin
            if (oresp.last)
                {busy, saved_req} <= '0;
        end else begin
            // if not valid, busy <= 0
            busy <= selected_req.valid;
            index <= select;
            saved_req <= selected_req;
        end
    end else begin
        {busy, index, saved_req} <= '0;
    end

    `UNUSED_OK({index});
endmodule



`endif
