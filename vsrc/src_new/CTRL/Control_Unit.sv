// ----------------------------------------------------------------------------
// File        : Control_Unit.sv
// Description : v2 控制层：聚合 stall / 跳转反馈
//               当前策略：最小实现——pipeline_stall = !is_inst_ready || !is_mem_ready，
//               对 IF / ID / EX / MEM 全流水线均匀施加；不做 hazard 检测、不做 forwarding
// ----------------------------------------------------------------------------

`include "src_new/top_pkg.sv"

import common::*;
import top_pkg::*;

module Control_Unit (
    input  IF_2_CTRL if_2_ctrl,
    input  ID_2_CTRL id_2_ctrl,
    input  logic     is_mem_ready,

    input  logic     ex_pc_should_jump,
    input  u64       ex_pc_jump_address,

    output logic     stall_if,
    output logic     stall_id,
    output logic     stall_ex,
    output logic     stall_mem,

    output logic     pc_should_jump,
    output u64       pc_jump_address
);

    logic pipeline_stall;
    assign pipeline_stall = !if_2_ctrl.is_inst_ready || !is_mem_ready;

    assign stall_if  = pipeline_stall;
    assign stall_id  = pipeline_stall;
    assign stall_ex  = pipeline_stall;
    assign stall_mem = pipeline_stall;

    // EX 当拍的跳转反馈直接转给 IF
    assign pc_should_jump  = ex_pc_should_jump;
    assign pc_jump_address = ex_pc_jump_address;

    // id_2_ctrl 目前仅 placeholder；显式消费避免 Verilator unused warning
    logic unused_id_placeholder;
    assign unused_id_placeholder = id_2_ctrl.placeholder;

endmodule
