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
    input  logic       flush,

    input  u64         pc_inst_address,

    output u32         inst,
    output logic       is_inst_ready,
    output logic       fetch_exc_valid,
    output u64         fetch_exc_cause,
    output u64         fetch_exc_tval,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    u64   latched_addr;
    u32   latched_inst;
    logic latched_valid;
    logic latched_exc_valid;
    u64   latched_exc_cause;
    u64   latched_exc_tval;

    u64   response_data;
    u32   inst_word;
    logic is_response_valid;
    logic request_valid;
    u64   request_addr;
    u64   pending_addr;
    logic pending_valid;
    logic pending_kill;
    logic response_matches_pc;

    // 命中：已缓存地址与当前 PC 匹配
    assign is_inst_ready = latched_valid && (latched_addr == pc_inst_address);
    assign inst          = latched_inst;
    assign fetch_exc_valid = is_inst_ready && latched_exc_valid;
    assign fetch_exc_cause = latched_exc_cause;
    assign fetch_exc_tval  = latched_exc_tval;
    // 仅在已寄存的 pending 下向总线发起请求：消除未被追踪的“发起拍”，
    // 保证每一笔进总线的事务都在 pending_kill 追踪内，flush 时可正确丢弃，
    // 避免仲裁器中残留的旧请求响应被错配为新 PC 的指令。
    assign request_valid = pending_valid;
    assign request_addr  = pending_addr;
    assign response_matches_pc = pending_valid && (pending_addr == pc_inst_address);

    assign inst_word = pending_addr[2] ? response_data[63:32] : response_data[31:0];

    DataMemory u_data_memory (
        .clk                ( clk ),
        .rst_n              ( rst_n ),

        .request_addr       ( request_addr ),
        .request_valid      ( request_valid ),
        .request_size       ( MSIZE4 ),
        .request_strobe     ( 8'b0 ),
        .request_write_data ( 64'b0 ),

        .response_data      ( response_data ),
        .is_response_valid  ( is_response_valid ),

        .dbus_request       ( dbus_request ),
        .dbus_response      ( dbus_response )
    );

    // 指令到达时 latch；若跳转已改变 PC，则丢弃旧请求的响应
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr  <= '0;
            latched_inst  <= '0;
            latched_valid <= 1'b0;
            latched_exc_valid <= 1'b0;
            latched_exc_cause <= 64'b0;
            latched_exc_tval  <= 64'b0;
            pending_addr  <= '0;
            pending_valid <= 1'b0;
            pending_kill  <= 1'b0;
        end
        else begin
            if (flush) begin
                latched_valid <= 1'b0;
                if (pending_valid)
                    pending_kill <= 1'b1;
            end

            if (!flush && !pending_valid && !is_inst_ready) begin
                pending_addr  <= pc_inst_address;
                pending_valid <= 1'b1;
                pending_kill  <= 1'b0;
            end

            if (is_response_valid && pending_valid) begin
                pending_valid <= 1'b0;
                pending_kill  <= 1'b0;
                if (response_matches_pc && !pending_kill && !flush) begin
                    latched_addr  <= pending_addr;
                    latched_inst  <= inst_word;
                    latched_valid <= 1'b1;
                    latched_exc_valid <= dbus_response.exc_valid;
                    latched_exc_cause <= dbus_response.exc_cause;
                    latched_exc_tval  <= dbus_response.exc_tval;
                end
            end
        end
    end

endmodule
