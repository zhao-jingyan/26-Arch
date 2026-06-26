// ----------------------------------------------------------------------------
// File        : Privilege_Unit.sv
// Description : 特权级与 trap/mret 原子协调单元
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import CSR_PKG::*;

module Privilege_Unit (
    input  logic         clk,
    input  logic         rst_n,

    input  WB_TRAP_EVENT wb_trap_event,
    input  logic         int_fire,
    input  u64           int_mcause,
    input  u64           int_epc,
    input  u64           mstatus,
    input  u64           mcause,
    input  u64           mtval,
    input  u64           scause,
    input  u64           stval,
    input  u64           medeleg,
    input  u64           mideleg,
    input  u64           mtvec_value,
    input  u64           mepc_value,
    input  u64           stvec_value,
    input  u64           sepc_value,

    output logic         trap_write_en,
    output u64           trap_mstatus_next,
    output u64           trap_mepc_next,
    output u64           trap_mcause_next,
    output u64           trap_mtval_next,
    output u64           trap_sepc_next,
    output u64           trap_scause_next,
    output u64           trap_stval_next,

    output PRIV_2_CTRL   priv_2_ctrl,
    output PRIV_MODE     priv_mode,

    // 仅由 WB 段已提交事件决定（不含 int_fire），供 Interrupt_Unit 做优先级屏蔽、打破组合环
    output logic         wb_event_active
);

    PRIV_MODE priv_mode_q;
    PRIV_MODE mstatus_mpp;
    PRIV_MODE sret_priv;
    u64       trap_mstatus_w;
    u64       strap_mstatus_w;
    u64       mret_mstatus_w;
    u64       sret_mstatus_w;
    u64       cause_w;
    u64       tval_w;
    u64       epc_w;
    logic     cause_is_interrupt;
    logic [5:0] cause_code;
    logic     delegated_to_s;

    logic is_wb_trap_fire;
    logic is_trap_fire;
    logic is_mret_fire;
    logic is_sret_fire;

    assign priv_mode = priv_mode_q;
    assign mstatus_mpp = PRIV_MODE'(mstatus_get_mpp(mstatus));

    assign is_wb_trap_fire = wb_trap_event.is_trap_commit
                          && (wb_trap_event.trap_ctx.is_ecall
                           || wb_trap_event.trap_ctx.exc_valid);
    assign is_trap_fire = int_fire || is_wb_trap_fire;
    assign is_mret_fire = wb_trap_event.is_trap_commit
                       && wb_trap_event.trap_ctx.is_mret;
    assign is_sret_fire = wb_trap_event.is_trap_commit
                       && wb_trap_event.trap_ctx.is_sret;

    assign cause_w = int_fire ? int_mcause
                              : (wb_trap_event.trap_ctx.exc_valid
                                 ? wb_trap_event.trap_ctx.exc_cause
                                 : ((priv_mode_q == PRIV_M)
                                    ? MCAUSE_ECALL_M
                                    : ((priv_mode_q == PRIV_S) ? MCAUSE_ECALL_S : MCAUSE_ECALL_U)));
    assign tval_w = int_fire ? 64'b0 : wb_trap_event.trap_ctx.exc_tval;
    assign epc_w  = int_fire ? int_epc : wb_trap_event.epc;
    assign cause_is_interrupt = cause_w[63];
    assign cause_code = cause_w[5:0];
    assign delegated_to_s = (priv_mode_q != PRIV_M)
                         && ((cause_is_interrupt && mideleg[cause_code])
                          || (!cause_is_interrupt && medeleg[cause_code]));

    always_comb begin
        trap_mstatus_w = mstatus;
        trap_mstatus_w = mstatus_set_mpie(trap_mstatus_w, mstatus_get_mie(mstatus));
        trap_mstatus_w = mstatus_set_mie(trap_mstatus_w, 1'b0);
        trap_mstatus_w = mstatus_set_mpp(trap_mstatus_w, priv_mode_q);

        strap_mstatus_w = mstatus;
        strap_mstatus_w = mstatus_set_spie(strap_mstatus_w, mstatus_get_sie(mstatus));
        strap_mstatus_w = mstatus_set_sie(strap_mstatus_w, 1'b0);
        strap_mstatus_w = mstatus_set_spp(strap_mstatus_w, priv_mode_q == PRIV_S);

        mret_mstatus_w = mstatus;
        mret_mstatus_w = mstatus_set_mie(mret_mstatus_w, mstatus_get_mpie(mstatus));
        mret_mstatus_w = mstatus_set_mpie(mret_mstatus_w, 1'b1);
        mret_mstatus_w = mstatus_set_mpp(mret_mstatus_w, PRIV_U);
        mret_mstatus_w = mstatus_set_xs(mret_mstatus_w, 2'b00);
        if (mstatus_mpp != PRIV_M)
            mret_mstatus_w = mstatus_set_mprv(mret_mstatus_w, 1'b0);

        sret_mstatus_w = mstatus;
        sret_mstatus_w = mstatus_set_sie(sret_mstatus_w, mstatus_get_spie(mstatus));
        sret_mstatus_w = mstatus_set_spie(sret_mstatus_w, 1'b1);
        sret_mstatus_w = mstatus_set_spp(sret_mstatus_w, 1'b0);
        sret_mstatus_w = mstatus_set_xs(sret_mstatus_w, 2'b00);
    end

    always_comb begin
        trap_write_en      = is_trap_fire || is_mret_fire || is_sret_fire;
        trap_mstatus_next = mstatus;
        trap_mepc_next    = mepc_value;
        trap_mcause_next  = mcause;
        trap_mtval_next   = mtval;
        trap_sepc_next    = sepc_value;
        trap_scause_next  = scause;
        trap_stval_next   = stval;

        if (is_trap_fire) begin
            if (delegated_to_s) begin
                trap_mstatus_next = strap_mstatus_w;
                trap_sepc_next    = epc_w;
                trap_scause_next  = cause_w;
                trap_stval_next   = tval_w;
            end else begin
                trap_mstatus_next = trap_mstatus_w;
                trap_mcause_next  = cause_w;
                trap_mtval_next   = tval_w;
                trap_mepc_next    = epc_w;
            end
        end
        else if (is_mret_fire) begin
            trap_mstatus_next = mret_mstatus_w;
        end
        else if (is_sret_fire) begin
            trap_mstatus_next = sret_mstatus_w;
        end
    end

    assign wb_event_active = is_wb_trap_fire || is_mret_fire || is_sret_fire;

    assign priv_2_ctrl.is_trap_fire = is_trap_fire;
    assign priv_2_ctrl.is_mret_fire = is_mret_fire;
    assign priv_2_ctrl.is_sret_fire = is_sret_fire;
    assign priv_2_ctrl.trap_vector  = delegated_to_s ? stvec_value : mtvec_value;
    assign priv_2_ctrl.ret_pc_value = is_sret_fire ? sepc_value : mepc_value;
    assign sret_priv = mstatus_get_spp(mstatus) ? PRIV_S : PRIV_U;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priv_mode_q <= PRIV_M;
        end
        else if (is_trap_fire) begin
            priv_mode_q <= delegated_to_s ? PRIV_S : PRIV_M;
        end
        else if (is_mret_fire) begin
            priv_mode_q <= mstatus_mpp;
        end
        else if (is_sret_fire) begin
            priv_mode_q <= sret_priv;
        end
    end

endmodule
