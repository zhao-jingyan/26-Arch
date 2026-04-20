// ----------------------------------------------------------------------------
// File        : Control_Unit.sv
// Description : v2 控制层：聚合 stall / 跳转 flush / load-use 冒险检测
//               pipeline_stall = !is_inst_ready || !is_mem_ready，对全流水均匀施加
//               load_use_hazard：EX 位 load.rd 与 ID 位消费者 rs1/rs2 匹配
//                 → 冻结 IF/ID、在 ID/EX 寄存器注入 bubble；EX/MEM/WB 正常推进
//               ex_pc_should_jump（branch/jalr/jal 在 EX 段决出）：
//                 → 清空 IF/ID（已 speculative 取的下一拍指令）
//                 → 在 ID/EX 注入 bubble（已 decode 的 wrong-path 指令）
//                 → PC 重定向到 ex_pc_jump_address
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`endif

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
    output logic     flush_if_id,

    output logic     pc_should_jump,
    output u64       pc_jump_address
);

    // 全局阻塞：取指未就绪 / 访存未就绪 / ALU 多周期单元（乘除法）忙
    logic pipeline_stall;
    assign pipeline_stall = !if_2_ctrl.is_inst_ready
                          || !is_mem_ready
                          || ex_2_ctrl.is_alu_busy;

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

    // ID/EX bubble：load-use 冲突，或 EX 决出跳转需要把 wrong-path 的 ID 指令清掉
    // pipeline_stall 时所有级已冻结，不应覆盖
    assign insert_bubble = (load_use_hazard || ex_pc_should_jump) && !pipeline_stall;

    // IF/ID flush：仅在跳转命中时清掉 speculative 取的下一拍指令
    // load-use 不能 flush（IF/ID 里那条正是要保留、下拍重走的消费者）
    assign flush_if_id = ex_pc_should_jump && !pipeline_stall;

    // EX 当拍的跳转反馈直接转给 IF
    assign pc_should_jump  = ex_pc_should_jump;
    assign pc_jump_address = ex_pc_jump_address;

endmodule
