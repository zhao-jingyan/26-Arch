// ----------------------------------------------------------------------------
// File        : Inst_Fetch.sv
// Description : 取指单元；缓存当前 PC 对应的指令，驱动 DataMemory 请求 dbus
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/MEM/DataMemory.sv"
`endif

import common::*;

module Inst_Fetch (
    input  logic       clk,
    input  logic       rst_n,

    input  u64         pc_inst_address,

    output u32         inst,
    output logic       is_inst_ready,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    u64   latched_addr;
    u32   latched_inst;
    logic latched_valid;

    u64   response_data;
    u32   inst_word;
    logic is_response_valid;
    logic request_valid;

    // 命中：已缓存地址与当前 PC 匹配
    assign is_inst_ready = latched_valid && (latched_addr == pc_inst_address);
    assign inst          = latched_inst;
    assign request_valid = !is_inst_ready;

    assign inst_word = pc_inst_address[2] ? response_data[63:32] : response_data[31:0];

    DataMemory u_data_memory (
        .clk                ( clk ),
        .rst_n              ( rst_n ),

        .request_addr       ( pc_inst_address ),
        .request_valid      ( request_valid ),
        .request_size       ( MSIZE4 ),
        .request_strobe     ( 8'b0 ),
        .request_write_data ( 64'b0 ),

        .response_data      ( response_data ),
        .is_response_valid  ( is_response_valid ),

        .dbus_request       ( dbus_request ),
        .dbus_response      ( dbus_response )
    );

    // 指令到达时 latch；addr 在等待期间由外部 pc_stall 保证稳定
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr  <= '0;
            latched_inst  <= '0;
            latched_valid <= 1'b0;
        end
        else if (is_response_valid && !is_inst_ready) begin
            latched_addr  <= pc_inst_address;
            latched_inst  <= inst_word;
            latched_valid <= 1'b1;
        end
    end

endmodule
