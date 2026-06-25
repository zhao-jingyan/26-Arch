// ----------------------------------------------------------------------------
// File        : IF_Stage.sv
// Description : IF Stage 顶层：装配 PC + Inst_Fetch + IF/ID 流水线寄存器
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/ID_PKG.sv"
`include "src/IF/PC.sv"
`include "src/IF/Inst_Fetch.sv"
`endif

import common::*;
import top_pkg::*;
import ID_PKG::*;

module IF_Stage (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       stall,
    input  logic       flush,            // 错预测 / trap 重定向时清空 IF/ID 寄存器
    input  logic       pc_should_jump,
    input  u64         pc_jump_address,

    output IF_2_ID     if_2_id,
    output IF_2_CTRL   if_2_ctrl,
    output u64         if_pc,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    u64   pc_inst_address_cur;
    u32   inst_fetched;
    logic is_inst_ready;
    logic fetch_exc_valid;
    u64   fetch_exc_cause;
    u64   fetch_exc_tval;
    logic pc_stall;
    logic predict_taken;
    u64   predict_target;
    logic predict_redirect;
    logic next_pc_should_jump;
    u64   next_pc_jump_address;

    u7 opcode_fetched;
    u64 branch_imm;
    u64 jal_imm;

    // 未取到指令时也要冻结 PC
    assign pc_stall = stall || !is_inst_ready;
    assign if_2_ctrl.is_inst_ready = is_inst_ready;
    assign if_pc    = pc_inst_address_cur;
    assign opcode_fetched = inst_fetched[6:0];

    // 静态分支预测：BTFNT（向后条件分支预测 taken，向前预测 not taken），JAL 直接预测 taken。
    // JALR 目标依赖寄存器，仍在 EX 段决出，避免引入 BTB。
    assign branch_imm = {{51{inst_fetched[31]}}, inst_fetched[31], inst_fetched[7],
                         inst_fetched[30:25], inst_fetched[11:8], 1'b0};
    assign jal_imm    = {{43{inst_fetched[31]}}, inst_fetched[31], inst_fetched[19:12],
                         inst_fetched[20], inst_fetched[30:21], 1'b0};

    always_comb begin
        predict_taken  = 1'b0;
        predict_target = pc_inst_address_cur + 64'd4;

        unique case (opcode_fetched)
            OP_BRANCH: begin
                predict_taken  = inst_fetched[31];
                predict_target = pc_inst_address_cur + branch_imm;
            end
            OP_JAL: begin
                predict_taken  = 1'b1;
                predict_target = pc_inst_address_cur + jal_imm;
            end
            default: begin
                predict_taken  = 1'b0;
                predict_target = pc_inst_address_cur + 64'd4;
            end
        endcase
    end

    assign predict_redirect = is_inst_ready && !stall && predict_taken;

    always_comb begin
        if (pc_should_jump) begin
            next_pc_should_jump  = 1'b1;
            next_pc_jump_address = pc_jump_address;
        end
        else begin
            next_pc_should_jump  = predict_redirect;
            next_pc_jump_address = predict_target;
        end
    end

    PC u_pc (
        .clk              ( clk ),
        .rst_n            ( rst_n ),

        .stall            ( pc_stall ),
        .pc_should_jump   ( next_pc_should_jump ),
        .pc_jump_address  ( next_pc_jump_address ),

        .pc_inst_address  ( pc_inst_address_cur )
    );

    Inst_Fetch u_inst_fetch (
        .clk              ( clk ),
        .rst_n            ( rst_n ),
        .flush            ( flush || next_pc_should_jump ),

        .pc_inst_address  ( pc_inst_address_cur ),

        .inst             ( inst_fetched ),
        .is_inst_ready    ( is_inst_ready ),
        .fetch_exc_valid  ( fetch_exc_valid ),
        .fetch_exc_cause  ( fetch_exc_cause ),
        .fetch_exc_tval   ( fetch_exc_tval ),

        .dbus_request     ( dbus_request ),
        .dbus_response    ( dbus_response )
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
            if_2_id.inst             <= inst_fetched;
            if_2_id.pc_inst_address  <= pc_inst_address_cur;
            if_2_id.predicted_taken  <= predict_taken;
            if_2_id.predicted_target <= predict_target;
            if_2_id.fetch_exc_valid  <= fetch_exc_valid;
            if_2_id.fetch_exc_cause  <= fetch_exc_cause;
            if_2_id.fetch_exc_tval   <= fetch_exc_tval;
        end
    end

endmodule
