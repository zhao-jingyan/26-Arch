// -----------------------------------------------------------------------
// File        : ALU_MDU.sv
// Description : This Unit is responsible of conducting mul, div, rem.
//               Mul/div can be started independently; 
//               Write arbitration: when both mul and div are done, 
//               div/rem is prioritized, mul is delayed by one cycle.
// Author      : zhao-jingyan | Date: 2026-03-07
// -----------------------------------------------------------------------

import ALU_PKG::*;
import common::*;

module ALU_MDU (
    input logic clk,
    input logic rst_n,

    input logic mul_start_i,
    input logic div_start_i,
    input logic mul_cancel_i,
    input logic div_cancel_i,
    input logic is_signed_i,

    input ALU_OP_CODE op_code_i,
    input ALU_INST inst_type_i,

    input u64 op1_i,
    input u64 op2_i,
    output u64 mdu_res_o,
    output logic mdu_write_valid_o,
    output logic mul_ready_o,
    output logic div_ready_o
);

    logic mul_done;
    logic div_done;
    u64   mul_res;
    u64   quotient_res;
    u64   remainder_res;

    logic mul_pending_q;
    u64   mul_pending_res_q;

    u64   div_res;
    assign div_res = (op_code_i == DIV) ? quotient_res : remainder_res;

    ALU_Multiplier u_multiplier (
        .clk          ( clk ),
        .rst_n        ( rst_n ),
        .mul_start_i  ( mul_start_i ),
        .mul_cancel_i ( mul_cancel_i ),
        .is_signed_i  ( is_signed_i ),
        .inst_type_i  ( inst_type_i ),
        .op1_i        ( op1_i ),
        .op2_i        ( op2_i ),
        .mul_res_o    ( mul_res ),
        .mul_ready_o  ( mul_ready_o ),
        .mul_done_o   ( mul_done )
    );

    ALU_Divider u_divider (
        .clk           ( clk ),
        .rst_n         ( rst_n ),
        .div_start_i   ( div_start_i ),
        .div_cancel_i  ( div_cancel_i ),
        .inst_type_i   ( inst_type_i ),
        .is_signed_i   ( is_signed_i ),
        .op1_i         ( op1_i ),
        .op2_i         ( op2_i ),
        .quotient_o    ( quotient_res ),
        .remainder_o   ( remainder_res ),
        .div_ready_o   ( div_ready_o ),
        .div_done_o    ( div_done )
    );

    // Write arbitration: when both mul and div are done, div/rem is prioritized
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_pending_q   <= 1'b0;
            mul_pending_res_q <= 64'b0;
        end else if (mul_cancel_i) begin
            mul_pending_q   <= 1'b0;
        end else begin
            if (mul_pending_q) begin
                mul_pending_q <= 1'b0;
            end else if (div_done && mul_done) begin
                mul_pending_q   <= 1'b1;
                mul_pending_res_q <= mul_res;
            end
        end
    end

    always_comb begin
        mdu_write_valid_o = 1'b0;
        mdu_res_o         = 64'b0;
        if (mul_pending_q) begin
            mdu_write_valid_o = 1'b1;
            mdu_res_o         = mul_pending_res_q;
        end else if (div_done) begin
            mdu_write_valid_o = 1'b1;
            mdu_res_o         = div_res;
        end else if (mul_done) begin
            mdu_write_valid_o = 1'b1;
            mdu_res_o         = mul_res;
        end
    end

endmodule