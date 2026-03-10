// ------------------------------------------------------------------------------
// File        : ALU_Controller.sv
// Description : ALU Controller instantiates Core and MDU, arbitrates output.
//               MDU has priority over Core when both have valid results.
// Author      : zhao-jingyan | Date: 2026-03-07
// ------------------------------------------------------------------------------

import ALU_PKG::*;
import common::*;

module ALU_Controller (
    input logic clk,
    input logic rst_n,

    input logic alu_valid_i,
    input logic mul_cancel_i,
    input logic div_cancel_i,
    input logic is_signed_i,

    input ALU_OP_CODE op_code_i,
    input ALU_INST inst_type_i,

    input u64 op1_i,
    input u64 op2_i,

    output u64 alu_res_o,
    output logic alu_write_valid_o,
    output logic mul_ready_o,
    output logic div_ready_o
);

    u64 alu_core_res;
    u64 mdu_res;
    logic mdu_write_valid;

    logic is_core_op;
    assign is_core_op = (op_code_i inside {ADD, SUB, AND, OR, XOR});

    logic mul_start, div_start;
    assign mul_start = alu_valid_i && (op_code_i == MUL);
    assign div_start = alu_valid_i && (op_code_i inside {DIV, REM});

    ALU_Core u_core (
        .op_code_i      ( op_code_i ),
        .inst_type_i    ( inst_type_i ),
        .op1_i          ( op1_i ),
        .op2_i          ( op2_i ),
        .alu_core_res_o ( alu_core_res )
    );

    ALU_MDU u_mdu (
        .clk               ( clk ),
        .rst_n             ( rst_n ),
        .mul_start_i       ( mul_start ),
        .div_start_i       ( div_start ),
        .mul_cancel_i      ( mul_cancel_i ),
        .div_cancel_i      ( div_cancel_i ),
        .is_signed_i       ( is_signed_i ),
        .op_code_i         ( op_code_i ),
        .inst_type_i       ( inst_type_i ),
        .op1_i             ( op1_i ),
        .op2_i             ( op2_i ),
        .mdu_res_o         ( mdu_res ),
        .mdu_write_valid_o ( mdu_write_valid ),
        .mul_ready_o       ( mul_ready_o ),
        .div_ready_o       ( div_ready_o )
    );

    // Arbiter: MDU priority over Core
    always_comb begin
        if (mdu_write_valid) begin
            alu_res_o         = mdu_res;
            alu_write_valid_o = 1'b1;
        end else if (is_core_op && alu_valid_i) begin
            alu_res_o         = alu_core_res;
            alu_write_valid_o = 1'b1;
        end else begin
            alu_res_o         = 64'b0;
            alu_write_valid_o = 1'b0;
        end
    end

endmodule
