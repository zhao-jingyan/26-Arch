// ----------------------------------------------------------------------------
// File        : Inst_Fetch.sv
// Description : 取指单元；缓存当前 PC 对应的指令，驱动 InstructionMemory 请求 ibus
// ----------------------------------------------------------------------------

`include "src_new/IF/InstructionMemory.sv"

import common::*;

module Inst_Fetch (
    input  logic       clk,
    input  logic       rst_n,

    input  u64         pc_inst_address,

    output u32         inst,
    output logic       is_inst_ready,

    output ibus_req_t  ibus_request,
    input  ibus_resp_t ibus_response
);

    u64   latched_addr;
    u32   latched_inst;
    logic latched_valid;

    u32   response_data;
    logic is_response_valid;
    logic request_valid;

    // 命中：已缓存地址与当前 PC 匹配
    assign is_inst_ready = latched_valid && (latched_addr == pc_inst_address);
    assign inst          = latched_inst;
    assign request_valid = !is_inst_ready;

    InstructionMemory u_instruction_memory (
        .clk               ( clk ),
        .rst_n             ( rst_n ),

        .request_addr      ( pc_inst_address ),
        .request_valid     ( request_valid ),

        .response_data     ( response_data ),
        .is_response_valid ( is_response_valid ),

        .ibus_request      ( ibus_request ),
        .ibus_response     ( ibus_response )
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
            latched_inst  <= response_data;
            latched_valid <= 1'b1;
        end
    end

endmodule
