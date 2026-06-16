// ----------------------------------------------------------------------------
// File        : Interrupt_Unit.sv
// Description : 三类 M 模式中断聚合：硬件 mip 位 + 信号变化 / 延迟投递 evaluate
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import CSR_PKG::*;

module Interrupt_Unit (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     trint,
    input  logic     swint,
    input  logic     exint,

    input  u64       mstatus,
    input  u64       mip_sw,
    input  u64       mie,
    input  PRIV_MODE priv_mode,
    input  u64       if_pc,
    input  IF_2_ID   if_2_id,
    input  INST_CTX  ex_inst_ctx,
    input  INST_CTX  mem_inst_ctx,
    input  MEM_2_CTRL mem_2_ctrl,

    input  logic     trap_write_en,
    input  u64       trap_mstatus_next,
    input  CSR_WRITE wb_csr_write,
    input  logic     wb_commit_valid,

    output u64       mip_hw,
    output logic     int_fire,
    output u64       int_mcause,
    output u64       int_epc
);

    logic prev_trint;
    logic prev_swint;
    logic prev_exint;
    logic pending_latched;
    logic int_changed;
    logic global_en;
    logic int_pending;
    logic int_take;
    logic mie_open_commit;
    logic mtip_take_m;
    logic other_int_take;
    u64   irq_pc;
    u64   mstatus_eff;
    u64   mip_full;
    logic meip_pending;
    logic msip_pending;
    logic mtip_pending;

    assign mip_hw = (64'(exint) << 11) | (64'(trint) << 7) | (64'(swint) << 3);
    assign mip_full = mip_sw | mip_hw;

    assign int_changed = (trint != prev_trint)
                      || (swint != prev_swint)
                      || (exint != prev_exint);

    // WB 提交 mstatus 当拍即参与判定（csrsi 开 MIE 的唯一窗口靠此 bypass）
    always_comb begin
        mstatus_eff = mstatus;
        if (trap_write_en)
            mstatus_eff = trap_mstatus_next;
        else if (wb_commit_valid
                 && wb_csr_write.write_en
                 && (wb_csr_write.write_addr == CSR_MSTATUS))
            mstatus_eff = (wb_csr_write.write_data & MSTATUS_MASK)
                        | (mstatus & ~MSTATUS_MASK);
    end

    assign global_en    = (priv_mode != PRIV_M) || mstatus_get_mie(mstatus_eff);
    assign meip_pending = mip_full[11] && mie[11];
    assign msip_pending = mip_full[3]  && mie[3];
    assign mtip_pending = mip_full[7]  && mie[7];
    assign int_pending  = meip_pending || msip_pending || mtip_pending;

    // csrsi 在 WB 提交开 MIE 的唯一窗口
    assign mie_open_commit = wb_commit_valid
                          && wb_csr_write.write_en
                          && (wb_csr_write.write_addr == CSR_MSTATUS)
                          && wb_csr_write.write_data[MSTATUS_MIE_BIT];

    // M 模式 MTIP：仅在 MIE 打开当拍投递，避免 int_changed 在错误流水阶段取 epc
    assign mtip_take_m = (priv_mode == PRIV_M)
                      && mtip_pending
                      && mie_open_commit
                      && (pending_latched || (trint != prev_trint));

    assign other_int_take = global_en
                         && (meip_pending || msip_pending)
                         && (int_changed || pending_latched);

    assign int_take = !mem_2_ctrl.is_atomic_busy
                    && ((priv_mode == PRIV_M)
                        ? (mtip_take_m || other_int_take)
                        : (global_en && int_pending && (int_changed || pending_latched)));

    // M 模式 MTIP：被中断指令为 csrsi 下一条（mem+4）；其余同前
    always_comb begin
        if (mie_open_commit && mtip_pending && (priv_mode == PRIV_M))
            irq_pc = mem_inst_ctx.pc_inst_address + 64'd4;
        else if ((priv_mode == PRIV_M) && (ex_inst_ctx.inst != 32'b0))
            irq_pc = ex_inst_ctx.pc_inst_address;
        else if (if_2_id.inst != 32'b0)
            irq_pc = if_2_id.pc_inst_address;
        else
            irq_pc = if_pc;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_fire        <= 1'b0;
            int_mcause      <= 64'b0;
            int_epc         <= 64'b0;
            pending_latched <= 1'b0;
        end else begin
            int_fire <= int_take;

            if (int_take) begin
                int_epc <= irq_pc;
                if (meip_pending)
                    int_mcause <= MCAUSE_MEI;
                else if (msip_pending)
                    int_mcause <= MCAUSE_MSI;
                else
                    int_mcause <= MCAUSE_MTI;
            end

            if (int_take)
                pending_latched <= 1'b0;
            else if (int_pending && !global_en)
                pending_latched <= 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_trint <= 1'b0;
            prev_swint <= 1'b0;
            prev_exint <= 1'b0;
        end else begin
            prev_trint <= trint;
            prev_swint <= swint;
            prev_exint <= exint;
        end
    end

endmodule
