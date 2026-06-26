// ----------------------------------------------------------------------------
// File        : Interrupt_Unit.sv
// Description : M/S 模式中断聚合与精确投递
//               关键修复：中断改为「组合触发 + 锚定 MEM 段指令」的精确异步 trap。
//                 - epc = MEM 段指令（ex_inst_ctx）的 PC：它是下一条将提交的指令，
//                   比 WB 段更年轻、比 EX/ID/IF 更老。
//                 - 触发当拍复用既有异常 flush 掩码 {IF/ID, EX, MEM}：
//                   砍掉 MEM 段（=epc，随后重放）及更年轻指令，放行更老的 WB 段提交；
//                   kill_new_req 同拍抑制 MEM 段 store 发起，保证重放不二次写存储。
//               旧实现把 int_fire 寄存一拍、用固定 flush 掩码命中错位指令，会静默丢一条
//               比 epc 更老的指令（用户态 a0 损坏 / push_off 清 SIE 失效），此处一并消除。
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import CSR_PKG::*;

module Interrupt_Unit (
    input  logic     trint,
    input  logic     swint,
    input  logic     exint,

    input  u64       mstatus,
    input  u64       mip_sw,
    input  u64       mie,
    input  u64       sie,
    input  u64       mideleg,
    input  PRIV_MODE priv_mode,

    // MEM 段指令上下文（EX/MEM 寄存器输出）：作为中断锚定点
    input  INST_CTX  ex_inst_ctx,
    input  MEM_2_CTRL mem_2_ctrl,

    // WB 段事件 / 提交信息：用于优先级与写口冲突屏蔽（均来自寄存器，不含 int_fire，避免组合环）
    input  logic     wb_event_active,   // WB 段正在 exc/ecall/mret/sret（来自 Privilege_Unit）
    input  CSR_WRITE wb_csr_write,
    input  logic     wb_commit_valid,

    output u64       mip_hw,
    output logic     int_fire,
    output u64       int_mcause,
    output u64       int_epc
);

    u64   mip_full;
    logic meip_pending;
    logic msip_pending;
    logic mtip_pending;
    logic seip_pending;
    logic ssip_pending;
    logic stip_pending;
    logic global_en;
    logic s_global_en;
    logic m_int_pending;
    logic s_int_pending;
    logic meip_to_m;
    logic msip_to_m;
    logic mtip_to_m;
    logic m_int_pending_to_m;
    logic anchor_valid;
    logic block_fire;
    logic fire_cond;

    assign mip_hw  = (64'(exint) << 11) | (64'(trint) << 7) | (64'(swint) << 3);
    assign mip_full = mip_sw | mip_hw;

    // 各中断源 pending（已按使能位/委托位过滤）
    assign meip_pending = mip_full[11] && mie[11];
    assign msip_pending = mip_full[3]  && mie[3];
    assign mtip_pending = mip_full[7]  && mie[7];
    // 硬件 exint 接在 mip[11](MEIP)；当委托到 S 时按 SEIP 投递（仿照 MTIP→STIP）
    assign seip_pending = (mip_full[9] || (mideleg[9] && mip_full[11])) && sie[9] && mideleg[9];
    assign ssip_pending = mip_full[1]  && sie[1] && mideleg[1];
    assign stip_pending = (mip_full[5] || (mideleg[5] && mip_full[7])) && sie[5] && mideleg[5];

    // 全局使能：M 目标中断在 priv<M 时恒开、priv==M 看 MIE；S 目标中断 priv==U 恒开、priv==S 看 SIE
    assign global_en   = (priv_mode != PRIV_M) || mstatus_get_mie(mstatus);
    assign s_global_en = (priv_mode == PRIV_U) || ((priv_mode == PRIV_S) && mstatus_get_sie(mstatus));

    assign m_int_pending = meip_pending || msip_pending || mtip_pending;
    assign s_int_pending = seip_pending || ssip_pending || stip_pending;

    // U/S 态下未委托的 M 目标中断仍 trap 到 M（lab6 用户态 wait 依赖 MTI/MSI）
    assign meip_to_m = meip_pending && !mideleg[11];
    assign msip_to_m = msip_pending && !mideleg[3];
    assign mtip_to_m = mtip_pending && !mideleg[7];
    assign m_int_pending_to_m = meip_to_m || msip_to_m || mtip_to_m;

    // 锚定点必须是一条「干净可重放」的有效 MEM 段指令：
    //   - inst != 0：非气泡
    //   - 非原子/向量访存多拍执行中：避免打断在途访存事务
    assign anchor_valid = (ex_inst_ctx.inst != 32'b0)
                       && !mem_2_ctrl.is_atomic_busy
                       && !mem_2_ctrl.is_vmem_busy;

    // 屏蔽当拍触发的两种情形：
    //   1. WB 段本拍已在做异常/ecall/mret/sret（更老、优先级更高，让它先走）
    //   2. WB 段本拍提交一条 CSR 写：trap 写口与软件 CSR 写会争用 CSRFile，trap 优先会吞掉软件写
    assign block_fire = wb_event_active
                     || (wb_commit_valid && wb_csr_write.write_en);

    // 触发条件：M 态投递 M 目标；U/S 态投递委托到 S 的 + 未委托仍进 M 的
    assign fire_cond = (priv_mode == PRIV_M) ? (global_en && m_int_pending)
                                             : ((s_global_en && s_int_pending)
                                             || (global_en && m_int_pending_to_m));

    assign int_fire = anchor_valid && !block_fire && fire_cond;

    // epc 锚定 MEM 段指令：trap 返回后从该指令重新执行
    assign int_epc  = ex_inst_ctx.pc_inst_address;

    // mcause 优先级编码：外部 > 软件 > 定时；M 目标优先于 S 目标
    always_comb begin
        if (priv_mode == PRIV_M) begin
            if (meip_pending)      int_mcause = MCAUSE_MEI;
            else if (msip_pending) int_mcause = MCAUSE_MSI;
            else                   int_mcause = MCAUSE_MTI;
        end else begin
            if (meip_to_m)         int_mcause = MCAUSE_MEI;
            else if (msip_to_m)    int_mcause = MCAUSE_MSI;
            else if (mtip_to_m)    int_mcause = MCAUSE_MTI;
            else if (seip_pending) int_mcause = MCAUSE_SEI;
            else if (ssip_pending) int_mcause = MCAUSE_SSI;
            else                   int_mcause = MCAUSE_STI;
        end
    end

endmodule
