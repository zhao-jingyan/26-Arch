// ----------------------------------------------------------------------------
// File        : DBus_Arbiter.sv
// Description : 2-input dbus 仲裁器；MEM 优先，响应按已锁存 index 回流
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "include/common.sv"
`endif

import common::*;

module DBus_Arbiter (
    input  logic       clk,
    input  logic       rst_n,

    input  dbus_req_t  mem_request,
    output dbus_resp_t mem_response,
    input  dbus_req_t  fetch_request,
    output dbus_resp_t fetch_response,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    logic busy;
    logic index;   // 0 = MEM, 1 = IF fetch
    logic select;
    dbus_req_t saved_request;

    always_comb begin
        select = 1'b0;
        if (mem_request.valid) begin
            select = 1'b0;
        end
        else if (fetch_request.valid) begin
            select = 1'b1;
        end
    end

    always_comb begin
        dbus_request = '0;
        if (busy) begin
            dbus_request = saved_request;
        end
    end

    always_comb begin
        mem_response   = '0;
        fetch_response = '0;

        if (busy) begin
            if (index) begin
                fetch_response = dbus_response;
            end
            else begin
                mem_response = dbus_response;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy          <= 1'b0;
            index         <= 1'b0;
            saved_request <= '0;
        end
        else if (busy) begin
            if (dbus_response.data_ok) begin
                busy          <= 1'b0;
                saved_request <= '0;
            end
        end
        else begin
            busy          <= mem_request.valid || fetch_request.valid;
            index         <= select;
            saved_request <= select ? fetch_request : mem_request;
        end
    end

endmodule
