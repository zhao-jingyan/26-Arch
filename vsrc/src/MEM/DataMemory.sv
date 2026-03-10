// ----------------------------------------------------------------------------
// File        : DataMemory.sv
// Description : Abstract DM for LSU, buffer implementation, talks to DBus
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

import common::*;
import pipeline_pkg::*;

module DataMemory (
    input  logic       clk,
    input  logic       rst_n,

    input  dm_req_t    req_i,
    output dm_rsp_t    rsp_o,

    output dbus_req_t  dbus_req_o,
    input  dbus_resp_t dbus_resp_i
);

    logic busy;

    assign busy = req_i.valid && !rsp_o.valid;

    assign dbus_req_o.valid = busy;
    assign dbus_req_o.addr  = req_i.addr;
    assign dbus_req_o.size  = req_i.size;
    assign dbus_req_o.strobe = req_i.is_write ? req_i.strobe : 8'b0;
    assign dbus_req_o.data  = req_i.wdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_o <= '0;
        end else begin
            rsp_o.valid <= 1'b0;
            if (dbus_resp_i.data_ok && busy) begin
                rsp_o.rdata <= dbus_resp_i.data;
                rsp_o.valid <= 1'b1;
            end
        end
    end

endmodule
