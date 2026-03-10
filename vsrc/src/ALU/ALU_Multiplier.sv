// -------------------------------------------------
// File        : ALU_Multiplier.sv
// Description : A Multi-Cycle multiplier unit
// Author      : zhao-jingyan | Date: 2026-03-06
// -------------------------------------------------

import ALU_PKG::*;
import common::*;

module ALU_Multiplier (
    input logic clk,
    input logic rst_n,

    input logic mul_start_i,
    input logic mul_cancel_i,
    input logic is_signed_i,
    input ALU_INST inst_type_i,

    input u64 op1_i,
    input u64 op2_i,
    output u64 mul_res_o,
    output logic mul_ready_o,
    output logic mul_done_o
);

    ALU_STATE state;
    u6   count;
    u128 multiplier_q;
    u128 multiplicand_q;
    u128 product_q;
    logic is_word_q;
    logic res_sign_q;

    u64 op1_abs, op2_abs;
    logic op1_sign, op2_sign;
    assign op1_sign = (inst_type_i == WORD) ? op1_i[31] : op1_i[63];
    assign op2_sign = (inst_type_i == WORD) ? op2_i[31] : op2_i[63];

    always_comb begin
        if (is_signed_i) begin
            if (inst_type_i == WORD) begin
                op1_abs = op1_sign ? (~{32'b0, op1_i[31:0]} + 1'b1) : {32'b0, op1_i[31:0]};
                op2_abs = op2_sign ? (~{32'b0, op2_i[31:0]} + 1'b1) : {32'b0, op2_i[31:0]};
            end else begin
                op1_abs = op1_sign ? (~op1_i + 1'b1) : op1_i;
                op2_abs = op2_sign ? (~op2_i + 1'b1) : op2_i;
            end
        end else begin
            if (inst_type_i == WORD) begin
                op1_abs = {32'b0, op1_i[31:0]};
                op2_abs = {32'b0, op2_i[31:0]};
            end else begin
                op1_abs = op1_i;
                op2_abs = op2_i;
            end
        end
    end

    // 8-bit granularity Early-Out logic to save cycles on small multipliers
    logic next_multiplier_is_zero;
    assign next_multiplier_is_zero = ((multiplier_q >> 1) == 128'b0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count <= 6'd0;
            product_q <= 128'b0;
            mul_done_o <= 1'b0;
            is_word_q  <= 1'b0;
            res_sign_q <= 1'b0;
            multiplier_q   <= 128'b0;
            multiplicand_q <= 128'b0;
        end 
        else if (mul_cancel_i) begin
            state      <= IDLE;
            mul_done_o <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    mul_done_o <= 1'b0;
                    if (mul_start_i) begin
                        state <= COMPUTE;
                        count <= 6'd0;
                        product_q <= 128'b0;
                        res_sign_q <= is_signed_i & (op1_sign ^ op2_sign);
                        if (inst_type_i == WORD) begin
                            is_word_q <= 1'b1;
                            multiplicand_q <= {96'b0, op1_abs[31:0]};
                            multiplier_q   <= {96'b0, op2_abs[31:0]};
                        end
                        else begin
                            is_word_q <= 1'b0;
                            multiplicand_q <= {64'b0, op1_abs};
                            multiplier_q   <= {64'b0, op2_abs};
                        end
                    end
                end

                COMPUTE: begin
                    if (multiplier_q[0]) begin
                        product_q <= product_q + multiplicand_q;
                    end
                    if (count == 6'd63 || (count[2:0] == 3'b111 && next_multiplier_is_zero)) begin
                        state <= DONE;
                    end 
                    else begin
                        multiplicand_q <= multiplicand_q << 1;
                        multiplier_q   <= multiplier_q >> 1;
                        count          <= count + 6'd1;
                    end
                end

                DONE: begin
                    mul_done_o <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign mul_ready_o = (state == IDLE);

    // Restore sign and select word/double output
    always_comb begin
        automatic u64 product_abs = product_q[63:0];
        automatic u64 signed_product = res_sign_q ? (~product_abs + 1'b1) : product_abs;
        if (is_word_q) begin
            automatic u32 res32 = signed_product[31:0];
            mul_res_o = {{32{res32[31]}}, res32};
        end else begin
            mul_res_o = signed_product;
        end
    end
endmodule

