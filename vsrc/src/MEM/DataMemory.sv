// ----------------------------------------------------------------------------
// File        : DataMemory.sv
// Description : dbus 握手适配器；组合传递请求与响应
// ----------------------------------------------------------------------------

import common::*;

module DataMemory (
    input  logic       clk,
    input  logic       rst_n,

    input  u64         request_addr,
    input  logic       request_valid,
    input  msize_t     request_size,
    input  strobe_t    request_strobe,
    input  u64         request_write_data,

    output u64         response_data,
    output logic       is_response_valid,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    assign dbus_request.valid  = request_valid;
    assign dbus_request.addr   = request_addr;
    assign dbus_request.size   = request_size;
    assign dbus_request.strobe = request_strobe;
    assign dbus_request.data   = request_write_data;

    assign response_data       = dbus_response.data;
    assign is_response_valid   = dbus_response.data_ok;

endmodule
