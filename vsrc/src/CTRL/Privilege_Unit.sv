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
    input  u64           mstatus,
    input  u64           mcause,
    input  u64           mtval,
    input  u64           mtvec_value,
    input  u64           mepc_value,
    input  logic         interrupt_pending,

    output logic         trap_write_en,
    output u64           trap_mstatus_next,
    output u64           trap_mepc_next,
    output u64           trap_mcause_next,
    output u64           trap_mtval_next,

    output PRIV_2_CTRL   priv_2_ctrl,
    output PRIV_MODE     priv_mode
);

    PRIV_MODE priv_mode_q;
    PRIV_MODE mstatus_mpp;
    u64       trap_mstatus_w;
    u64       mret_mstatus_w;

    assign priv_mode = priv_mode_q;
    assign mstatus_mpp = PRIV_MODE'(mstatus_get_mpp(mstatus));

    logic is_trap_fire;
    logic is_mret_fire;

    assign is_trap_fire = wb_trap_event.is_trap_commit
                        && (wb_trap_event.trap_ctx.is_ecall || wb_trap_event.trap_ctx.exc_valid);
    assign is_mret_fire = wb_trap_event.is_trap_commit
                        && wb_trap_event.trap_ctx.is_mret;

    always_comb begin
        trap_mstatus_w = mstatus;
        trap_mstatus_w = mstatus_set_mpie(trap_mstatus_w, mstatus_get_mie(mstatus));
        trap_mstatus_w = mstatus_set_mie(trap_mstatus_w, 1'b0);
        trap_mstatus_w = mstatus_set_mpp(trap_mstatus_w, priv_mode_q);

        mret_mstatus_w = mstatus;
        mret_mstatus_w = mstatus_set_mie(mret_mstatus_w, mstatus_get_mpie(mstatus));
        mret_mstatus_w = mstatus_set_mpie(mret_mstatus_w, 1'b1);
        mret_mstatus_w = mstatus_set_mpp(mret_mstatus_w, PRIV_U);
        if (mstatus_mpp != PRIV_M)
            mret_mstatus_w = mstatus_set_mprv(mret_mstatus_w, 1'b0);
    end

    always_comb begin
        trap_write_en      = is_trap_fire || is_mret_fire;
        trap_mstatus_next = mstatus;
        trap_mepc_next    = mepc_value;
        trap_mcause_next  = mcause;
        trap_mtval_next   = mtval;

        if (is_trap_fire) begin
            trap_mstatus_next = trap_mstatus_w;
            trap_mepc_next    = wb_trap_event.epc;
            trap_mcause_next  = wb_trap_event.trap_ctx.exc_valid
                              ? {60'b0, wb_trap_event.trap_ctx.exc_cause}
                              : ((priv_mode_q == PRIV_M) ? MCAUSE_ECALL_M : MCAUSE_ECALL_U);
            trap_mtval_next   = wb_trap_event.trap_ctx.exc_tval;
        end
        else if (is_mret_fire) begin
            trap_mstatus_next = mret_mstatus_w;
        end
    end

    assign priv_2_ctrl.is_trap_fire = is_trap_fire;
    assign priv_2_ctrl.is_mret_fire = is_mret_fire;
    assign priv_2_ctrl.trap_vector  = mtvec_value;
    assign priv_2_ctrl.mepc_value   = mepc_value;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priv_mode_q <= PRIV_M;
        end
        else if (is_trap_fire || interrupt_pending) begin
            priv_mode_q <= PRIV_M;
        end
        else if (is_mret_fire) begin
            priv_mode_q <= mstatus_mpp;
        end
    end

endmodule
