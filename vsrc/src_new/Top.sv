// ----------------------------------------------------------------------------
// File        : Top.sv
// Description : v2 五段流水线顶层：IF → ID → EX → MEM → WB + Control_Unit
//               对外接口保持与 v1 Top 一致（ibus/dbus/commit/gpr），供 core.sv 使用
//               commit 信号按 v1 做法：MEM/WB 寄存器 + 1-cycle prev 比较，检测"推进"沿
// ----------------------------------------------------------------------------

`include "src_new/top_pkg.sv"
`include "src_new/ID/ID_PKG.sv"
`include "src_new/IF/IF_Stage.sv"
`include "src_new/ID/ID_Stage.sv"
`include "src_new/EX/EX_Stage.sv"
`include "src_new/MEM/MEM_Stage.sv"
`include "src_new/WB/WB_Stage.sv"
`include "src_new/CTRL/Control_Unit.sv"
`include "src_new/CTRL/Forward_Unit.sv"

import common::*;
import top_pkg::*;
import ID_PKG::*;

module Top (
    input  logic       clk,
    input  logic       rst_n,

    output ibus_req_t  ibus_req_o,
    input  ibus_resp_t ibus_resp_i,
    output dbus_req_t  dbus_req_o,
    input  dbus_resp_t dbus_resp_i,

    output logic       commit_valid_o,
    output u64         commit_pc_o,
    output u32         commit_instr_o,
    output logic       commit_wen_o,
    output u8          commit_wdest_o,
    output u64         commit_wdata_o,
    output logic       commit_skip_o,   // 外设 MMIO 访存跳过 Difftest 对账
    output u64         gpr_o [0:31]
);

    // ------------------------------------------------------------------------
    // Stage-to-stage bundles
    // ------------------------------------------------------------------------
    IF_2_ID   if_2_id;
    IF_2_CTRL if_2_ctrl;

    INST_CTX  id_inst_ctx;
    ID_2_EX   id_2_ex;
    ID_2_FWD  id_2_fwd;
    ID_2_CTRL id_2_ctrl;

    INST_CTX  ex_inst_ctx;
    EX_2_MEM  ex_2_mem;
    EX_2_FWD  ex_2_fwd;
    EX_2_CTRL ex_2_ctrl;

    INST_CTX  mem_inst_ctx;
    MEM_2_WB  mem_2_wb;
    MEM_2_FWD mem_2_fwd;

    FWD_2_EX  fwd_2_ex;

    WB_2_ID   wb_2_id;

    // EX / MEM 对控制层的裸端口反馈
    logic ex_pc_should_jump;
    u64   ex_pc_jump_address;
    logic is_mem_ready;

    // 控制层输出
    logic stall_if, stall_id, stall_ex, stall_mem;
    logic insert_bubble;
    logic pc_should_jump;
    u64   pc_jump_address;

    Forward_Unit u_fwd (
        .id_2_fwd  ( id_2_fwd ),
        .ex_2_fwd  ( ex_2_fwd ),
        .mem_2_fwd ( mem_2_fwd ),

        .fwd_2_ex  ( fwd_2_ex )
    );

    Control_Unit u_ctrl (
        .if_2_ctrl          ( if_2_ctrl ),
        .id_2_ctrl          ( id_2_ctrl ),
        .ex_2_ctrl          ( ex_2_ctrl ),
        .is_mem_ready       ( is_mem_ready ),

        .ex_pc_should_jump  ( ex_pc_should_jump ),
        .ex_pc_jump_address ( ex_pc_jump_address ),

        .stall_if           ( stall_if ),
        .stall_id           ( stall_id ),
        .stall_ex           ( stall_ex ),
        .stall_mem          ( stall_mem ),
        .insert_bubble      ( insert_bubble ),

        .pc_should_jump     ( pc_should_jump ),
        .pc_jump_address    ( pc_jump_address )
    );

    IF_Stage u_if (
        .clk             ( clk ),
        .rst_n           ( rst_n ),

        .stall           ( stall_if ),
        .pc_should_jump  ( pc_should_jump ),
        .pc_jump_address ( pc_jump_address ),

        .if_2_id         ( if_2_id ),
        .if_2_ctrl       ( if_2_ctrl ),

        .ibus_request    ( ibus_req_o ),
        .ibus_response   ( ibus_resp_i )
    );

    ID_Stage u_id (
        .clk           ( clk ),
        .rst_n         ( rst_n ),

        .stall         ( stall_id ),
        .insert_bubble ( insert_bubble ),
        .if_2_id       ( if_2_id ),
        .wb_2_id       ( wb_2_id ),

        .inst_ctx      ( id_inst_ctx ),
        .id_2_ex       ( id_2_ex ),
        .id_2_fwd      ( id_2_fwd ),
        .gpr           ( gpr_o ),
        .id_2_ctrl     ( id_2_ctrl )
    );

    EX_Stage u_ex (
        .clk             ( clk ),
        .rst_n           ( rst_n ),

        .stall           ( stall_ex ),

        .inst_ctx_in     ( id_inst_ctx ),
        .id_2_ex         ( id_2_ex ),
        .fwd_2_ex        ( fwd_2_ex ),

        .inst_ctx_out    ( ex_inst_ctx ),
        .ex_2_mem        ( ex_2_mem ),
        .ex_2_fwd        ( ex_2_fwd ),
        .ex_2_ctrl       ( ex_2_ctrl ),

        .pc_should_jump  ( ex_pc_should_jump ),
        .pc_jump_address ( ex_pc_jump_address )
    );

    MEM_Stage u_mem (
        .clk           ( clk ),
        .rst_n         ( rst_n ),

        .stall         ( stall_mem ),

        .inst_ctx_in   ( ex_inst_ctx ),
        .ex_2_mem      ( ex_2_mem ),

        .inst_ctx_out  ( mem_inst_ctx ),
        .mem_2_wb      ( mem_2_wb ),
        .mem_2_fwd     ( mem_2_fwd ),

        .is_mem_ready  ( is_mem_ready ),

        .dbus_request  ( dbus_req_o ),
        .dbus_response ( dbus_resp_i )
    );

    WB_Stage u_wb (
        .inst_ctx ( mem_inst_ctx ),
        .mem_2_wb ( mem_2_wb ),

        .wb_2_id  ( wb_2_id )
    );

    // ------------------------------------------------------------------------
    // Commit / Difftest：MEM/WB 寄存器出口 + 1-cycle prev 比较
    //   prev_* 同步 MEM/WB 输出；commit_valid 当且仅当 MEM/WB 发生推进时拉高
    //   commit_pc/_instr/_wen/_wdest/_wdata 报告"上一拍已经进入 RF 的指令"
    // ------------------------------------------------------------------------
    INST_CTX prev_inst_ctx;
    MEM_2_WB prev_mem_2_wb;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_inst_ctx <= '0;
            prev_mem_2_wb <= '0;
        end
        else begin
            prev_inst_ctx <= mem_inst_ctx;
            prev_mem_2_wb <= mem_2_wb;
        end
    end

    assign commit_valid_o = (prev_inst_ctx.inst != 32'b0)
                          && ((mem_inst_ctx.pc_inst_address != prev_inst_ctx.pc_inst_address)
                              || (mem_inst_ctx.inst            != prev_inst_ctx.inst));
    assign commit_pc_o    = prev_inst_ctx.pc_inst_address;
    assign commit_instr_o = prev_inst_ctx.inst;
    assign commit_wen_o   = (prev_inst_ctx.rd_addr != 5'b0);
    assign commit_wdest_o = {3'b0, prev_inst_ctx.rd_addr};
    assign commit_wdata_o = prev_mem_2_wb.rd_data;

    // Difftest skip：提交指令为 load/store 且访存地址 bit31 == 0（外设 MMIO 区）
    logic commit_is_mem;
    assign commit_is_mem = (prev_inst_ctx.opcode == OP_LOAD)
                        || (prev_inst_ctx.opcode == OP_STORE);
    assign commit_skip_o = commit_is_mem && (prev_mem_2_wb.mem_addr[31] == 1'b0);

endmodule
