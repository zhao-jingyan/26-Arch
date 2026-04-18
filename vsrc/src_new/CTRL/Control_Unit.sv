// ----------------------------------------------------------------------------
// File        : Control_Unit.sv
// Description : v2 控制层：聚合 stall / 跳转反馈 / load-use 冒险检测
//               pipeline_stall = !is_inst_ready || !is_mem_ready，对全流水均匀施加
//               load_use_hazard 精确匹配 EX 位 load.rd 与 ID 位消费者 rs1/rs2
//               命中则冻结 IF/ID、在 ID/EX 寄存器注入 bubble；EX/MEM/WB 正常前进
// ----------------------------------------------------------------------------

`include "src_new/top_pkg.sv"

import common::*;
import top_pkg::*;

module Control_Unit (
    input  IF_2_CTRL if_2_ctrl,
    input  ID_2_CTRL id_2_ctrl,
    input  EX_2_CTRL ex_2_ctrl,
    input  logic     is_mem_ready,

    input  logic     ex_pc_should_jump,
    input  u64       ex_pc_jump_address,

    output logic     stall_if,
    output logic     stall_id,
    output logic     stall_ex,
    output logic     stall_mem,
    output logic     insert_bubble,

    output logic     pc_should_jump,
    output u64       pc_jump_address
);

    logic pipeline_stall;
    assign pipeline_stall = !if_2_ctrl.is_inst_ready || !is_mem_ready;

    // load-use 冒险：EX 位是 load，且其 rd 与 ID 位消费者 rs1/rs2 匹配（rd != 0）
    logic load_use_hazard;
    assign load_use_hazard = ex_2_ctrl.is_ex_load
                          && (ex_2_ctrl.rd_addr != 5'b0)
                          && (  (ex_2_ctrl.rd_addr == id_2_ctrl.rs1_addr)
                             || (ex_2_ctrl.rd_addr == id_2_ctrl.rs2_addr));

    // IF / ID 冻结；EX / MEM / WB 正常推进让 load 自己走到 MEM/WB
    assign stall_if  = pipeline_stall || load_use_hazard;
    assign stall_id  = pipeline_stall || load_use_hazard;
    assign stall_ex  = pipeline_stall;
    assign stall_mem = pipeline_stall;

    // 仅当 pipeline 本拍会推进时才注入 bubble；pipeline_stall 时所有级已冻结，不应覆盖
    assign insert_bubble = load_use_hazard && !pipeline_stall;

    // EX 当拍的跳转反馈直接转给 IF
    assign pc_should_jump  = ex_pc_should_jump;
    assign pc_jump_address = ex_pc_jump_address;

endmodule
