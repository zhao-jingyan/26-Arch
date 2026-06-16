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
    input  IF_2_CTRL  if_2_ctrl,
    input  ID_2_CTRL  id_2_ctrl,
    input  EX_2_CTRL  ex_2_ctrl,
    input  MEM_2_CTRL mem_2_ctrl,
    input  logic      is_mem_ready,

    input  logic      ex_pc_should_jump,
    input  u64        ex_pc_jump_address,
    input  PRIV_2_CTRL priv_2_ctrl,

    output logic      stall_if,
    output logic      stall_id,
    output logic      stall_ex,
    output logic      stall_mem,
    output logic      insert_bubble,
    output logic      flush_if_id,
    output logic      flush_ex,
    output logic      flush_mem,

    output logic      pc_should_jump,
    output u64        pc_jump_address
);

    // 切面 A：全局阻塞（取指 / 访存 / ALU 多周期）
    logic req_global_stall;
    assign req_global_stall = !if_2_ctrl.is_inst_ready
                            || !is_mem_ready
                            || ex_2_ctrl.is_alu_busy;

    // load-use 冒险：EX 位是 load，且其 rd 与 ID 位消费者 rs1/rs2 匹配（rd != 0）
    logic load_use_hazard;
    assign load_use_hazard = ex_2_ctrl.is_ex_load
                          && (ex_2_ctrl.rd_addr != 5'b0)
                          && (  (ex_2_ctrl.rd_addr == id_2_ctrl.rs1_addr)
                             || (ex_2_ctrl.rd_addr == id_2_ctrl.rs2_addr));

    // CSR / vset* 在 ID 段直接读取源寄存器，不能依赖 EX forward。
    // ID 位源寄存器若命中 EX 或 MEM 槽的 in-flight 写者，需要冻结到写者进入 WB。
    // distance-3（WB 槽）由 RegFile 内部 write-during-read bypass 覆盖，无需 stall
    logic id_direct_rs_hazard;
    logic id_direct_uses_rs1;
    logic id_direct_uses_rs2;
    assign id_direct_uses_rs1 = (id_2_ctrl.is_csr && !id_2_ctrl.is_csr_imm)
                             || (id_2_ctrl.is_vset && !id_2_ctrl.is_vset_imm)
                             || id_2_ctrl.is_vector_vx;
    assign id_direct_uses_rs2 = id_2_ctrl.is_vset_rs2;
    assign id_direct_rs_hazard = (  id_direct_uses_rs1
                                 && (id_2_ctrl.rs1_addr != 5'b0)
                                 && (  (ex_2_ctrl.rd_addr  != 5'b0 && ex_2_ctrl.rd_addr  == id_2_ctrl.rs1_addr)
                                    || (mem_2_ctrl.rd_addr != 5'b0 && mem_2_ctrl.rd_addr == id_2_ctrl.rs1_addr)))
                              || (  id_direct_uses_rs2
                                 && (id_2_ctrl.rs2_addr != 5'b0)
                                 && (  (ex_2_ctrl.rd_addr  != 5'b0 && ex_2_ctrl.rd_addr  == id_2_ctrl.rs2_addr)
                                    || (mem_2_ctrl.rd_addr != 5'b0 && mem_2_ctrl.rd_addr == id_2_ctrl.rs2_addr)));

    // 向量寄存器暂不做 forward；ID 读源命中 EX/MEM 中的向量写者时冻结。
    logic vector_raw_hazard;
    assign vector_raw_hazard = id_2_ctrl.is_vector_alu
                             && (  (ex_2_ctrl.is_vwrite
                                    && (  (id_2_ctrl.v_uses_vs1 && (ex_2_ctrl.v_rd_addr == id_2_ctrl.vs1_addr))
                                       || (ex_2_ctrl.v_rd_addr == id_2_ctrl.vs2_addr)
                                       || (ex_2_ctrl.v_rd_addr == id_2_ctrl.vd_addr)
                                       || (id_2_ctrl.v_uses_mask && (ex_2_ctrl.v_rd_addr == 5'b0))))
                                || (mem_2_ctrl.is_vwrite
                                    && (  (id_2_ctrl.v_uses_vs1 && (mem_2_ctrl.v_rd_addr == id_2_ctrl.vs1_addr))
                                       || (mem_2_ctrl.v_rd_addr == id_2_ctrl.vs2_addr)
                                       || (mem_2_ctrl.v_rd_addr == id_2_ctrl.vd_addr)
                                       || (id_2_ctrl.v_uses_mask && (mem_2_ctrl.v_rd_addr == 5'b0)))));

    // IF / ID 冻结；EX / MEM / WB 正常推进让 load / 写者自己走到 MEM/WB 出口
    // 切面 B：数据冒险
    logic req_data_stall;
    assign req_data_stall = load_use_hazard || id_direct_rs_hazard || vector_raw_hazard;

    // 切面 C/D：控制冒险与特权重定向
    logic req_branch_flush;
    logic req_trap_flush;
    assign req_branch_flush = ex_pc_should_jump;
    assign req_trap_flush   = priv_2_ctrl.is_trap_fire || priv_2_ctrl.is_mret_fire;

    assign stall_if  = req_global_stall || req_data_stall;
    assign stall_id  = req_global_stall || req_data_stall;
    assign stall_ex  = req_global_stall;
    assign stall_mem = req_global_stall;

    // ID/EX bubble：trap/mret 已在 WB 提交，可优先清 younger 指令；
    // EX 段 branch/jal 只有在流水线可推进时才能清 ID/EX，避免把跳转指令自身冲掉
    assign insert_bubble = req_trap_flush
                         || ((req_data_stall || req_branch_flush) && !req_global_stall);

    // IF/ID flush：仅在跳转命中时清掉 speculative 取的下一拍指令
    // load-use / csr-rs1 不能 flush（IF/ID 里那条正是要保留、下拍重走的消费者）
    assign flush_if_id = req_trap_flush || (req_branch_flush && !req_global_stall);

    assign flush_ex  = req_trap_flush;
    assign flush_mem = req_trap_flush;

    // PC mux 优先级：trap > mret > branch > 顺序
    always_comb begin
        if (priv_2_ctrl.is_trap_fire) begin
            pc_should_jump  = 1'b1;
            pc_jump_address = priv_2_ctrl.trap_vector;
        end
        else if (priv_2_ctrl.is_mret_fire) begin
            pc_should_jump  = 1'b1;
            pc_jump_address = priv_2_ctrl.mepc_value;
        end
        else begin
            pc_should_jump  = req_branch_flush && !req_global_stall;
            pc_jump_address = ex_pc_jump_address;
        end
    end

endmodule
