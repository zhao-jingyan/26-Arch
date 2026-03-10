// -------------------------------------------------
// File        : ALU_Divider.sv
// Description : A Multi-Cycle Divider unit
// Author      : zhao-jingyan | Date: 2026-03-06
// -------------------------------------------------

import ALU_PKG::*;
import common::*;

module ALU_Divider (
    input  logic           clk,
    input  logic           rst_n,

    input  logic           div_start_i,
    input  logic           div_cancel_i,
    input  ALU_INST        inst_type_i,
    input  logic           is_signed_i,

    input  u64             op1_i,
    input  u64             op2_i,
    output u64             quotient_o,
    output u64             remainder_o,
    output logic           div_ready_o,
    output logic           div_done_o
);

    ALU_STATE state;
    u7        count_q;
    u64       divisor_q;
    u64       quotient_q;
    u64       remainder_q;
    logic     res_sign_q;
    logic     rem_sign_q;
    logic     is_word_q;
    u64 op1_abs, op2_abs;
    logic op1_sign, op2_sign;

    assign op1_sign = (inst_type_i == WORD) ? op1_i[31] : op1_i[63];
    assign op2_sign = (inst_type_i == WORD) ? op2_i[31] : op2_i[63];

    // Get absolute value
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

    // FSM Part
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            count_q     <= 7'd0;
            quotient_q  <= 64'b0;
            remainder_q <= 64'b0;
            div_done_o  <= 1'b0;
        end 
        else if (div_cancel_i) begin
            state       <= IDLE;
            div_done_o  <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    div_done_o <= 1'b0;
                    if (div_start_i) begin
                        state       <= COMPUTE;
                        count_q     <= 7'd63;
                        is_word_q   <= (inst_type_i == WORD);
                        res_sign_q  <= is_signed_i & (op1_sign ^ op2_sign);
                        rem_sign_q  <= is_signed_i & op1_sign;
                        remainder_q <= 64'b0;
                        quotient_q  <= op1_abs;
                        divisor_q   <= op2_abs;

                        // Exceptions, early out
                        if (op2_abs == 64'b0) begin
                            state <= DONE;
                        end
                        else if (is_signed_i && op1_i == 64'h8000_0000_0000_0000 && op2_i == 64'hFFFF_FFFF_FFFF_FFFF) begin
                            state <= DONE; 
                        end
                    end
                end

                COMPUTE: begin
                    u65 sub_res;
                    u64 next_rem = {remainder_q[62:0], quotient_q[63]};
                    sub_res = {1'b0, next_rem} - {1'b0, divisor_q};

                    if (sub_res[64]) begin
                        remainder_q <= next_rem;
                        quotient_q  <= {quotient_q[62:0], 1'b0};
                    end else begin
                        remainder_q <= sub_res[63:0];
                        quotient_q  <= {quotient_q[62:0], 1'b1};
                    end

                    if (count_q == 7'd0) begin
                        state <= DONE;
                    end else begin
                        count_q <= count_q - 7'd1;
                    end
                end

                DONE: begin
                    div_done_o <= 1'b1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign div_ready_o = (state == IDLE);

    always_comb begin
        automatic u64 q_final;
        automatic u64 r_final;
        automatic logic overflow_detected = 1'b0;

        // Restore sign
        q_final = res_sign_q ? (~quotient_q + 1'b1)  : quotient_q;
        r_final = rem_sign_q ? (~remainder_q + 1'b1) : remainder_q;

        // Exception handling
        if (divisor_q == 64'b0) begin
            q_final = 64'hFFFF_FFFF_FFFF_FFFF;
            r_final = is_word_q ? {{32{op1_i[31]}}, op1_i[31:0]} : op1_i;
        end else if (is_signed_i) begin
            if (is_word_q) begin
                overflow_detected = (op1_i[31:0] == 32'h8000_0000) && (op2_i[31:0] == 32'hFFFF_FFFF);
                if (overflow_detected) begin
                    q_final = 64'hFFFF_FFFF_8000_0000;
                    r_final = 64'b0;
                end
            end else begin
                overflow_detected = (op1_i == 64'h8000_0000_0000_0000) && (op2_i == 64'hFFFF_FFFF_FFFF_FFFF);
                if (overflow_detected) begin
                    q_final = 64'h8000_0000_0000_0000;
                    r_final = 64'b0;
                end
            end
        end

        // Check word, double_word
        if (is_word_q) begin
            quotient_o  = {{32{q_final[31]}}, q_final[31:0]};
            remainder_o = {{32{r_final[31]}}, r_final[31:0]};
        end else begin
            quotient_o  = q_final;
            remainder_o = r_final;
        end
    end
endmodule