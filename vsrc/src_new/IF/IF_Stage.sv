// ----------------------------------------------------------------------------
// File        : IF_Stage.sv
// Description : IF Stage 顶层：装配 PC + Inst_Fetch + IF/ID 流水线寄存器
// ----------------------------------------------------------------------------

`include "src_new/top_pkg.sv"
`include "src_new/IF/PC.sv"
`include "src_new/IF/Inst_Fetch.sv"

import common::*;
import top_pkg::*;

module IF_Stage (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       stall,
    input  logic       flush,            // 跳转命中时清空 IF/ID 寄存器
    input  logic       pc_should_jump,
    input  u64         pc_jump_address,

    output IF_2_ID     if_2_id,
    output IF_2_CTRL   if_2_ctrl,

    output ibus_req_t  ibus_request,
    input  ibus_resp_t ibus_response
);

    u64   pc_inst_address_cur;
    u32   inst_fetched;
    logic is_inst_ready;
    logic pc_stall;

    // 未取到指令时也要冻结 PC
    assign pc_stall = stall || !is_inst_ready;
    assign if_2_ctrl.is_inst_ready = is_inst_ready;

    PC u_pc (
        .clk              ( clk ),
        .rst_n            ( rst_n ),

        .stall            ( pc_stall ),
        .pc_should_jump   ( pc_should_jump ),
        .pc_jump_address  ( pc_jump_address ),

        .pc_inst_address  ( pc_inst_address_cur )
    );

    Inst_Fetch u_inst_fetch (
        .clk              ( clk ),
        .rst_n            ( rst_n ),

        .pc_inst_address  ( pc_inst_address_cur ),

        .inst             ( inst_fetched ),
        .is_inst_ready    ( is_inst_ready ),

        .ibus_request     ( ibus_request ),
        .ibus_response    ( ibus_response )
    );

    // IF/ID 流水线寄存器：复位 / flush 清零；否则 is_inst_ready && !stall 时前进
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_2_id <= '0;
        end
        else if (flush) begin
            if_2_id <= '0;
        end
        else if (is_inst_ready && !stall) begin
            if_2_id.inst            <= inst_fetched;
            if_2_id.pc_inst_address <= pc_inst_address_cur;
        end
    end

endmodule
