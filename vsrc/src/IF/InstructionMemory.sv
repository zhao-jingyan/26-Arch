// ----------------------------------------------------------------------------
// File        : InstructionMemory.sv
// Description : ibus 握手适配器；组合传递请求与响应
// ----------------------------------------------------------------------------

import common::*;

module InstructionMemory (
    input  logic       clk,
    input  logic       rst_n,

    input  u64         request_addr,
    input  logic       request_valid,

    output u32         response_data,
    output logic       is_response_valid,

    output ibus_req_t  ibus_request,
    input  ibus_resp_t ibus_response
);

    assign ibus_request.valid = request_valid;
    assign ibus_request.addr  = request_addr;

    assign response_data      = ibus_response.data;
    assign is_response_valid  = ibus_response.data_ok;

endmodule
