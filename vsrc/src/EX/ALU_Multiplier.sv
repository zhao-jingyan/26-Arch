// ----------------------------------------------------------------------------
// File        : ALU_Multiplier.sv
// Description : 多周期无符号位移加法乘法器；带 8-bit 粒度 Early-Out
//               支持 NORM (64×64 → 低 64) 与 WORD (32×32 → sext64)
//               有符号场景由调用方拆出 |op|，最后按结果符号取补
//               MULH / MULHU / MULHSU 暂不支持（不暴露 product 上半截）
// ----------------------------------------------------------------------------

`include "src/EX/EX_PKG.sv"
`include "src/EX/ALU_PKG.sv"

import common::*;
import EX_PKG::*;
import ALU_PKG::*;

module ALU_Multiplier (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     mul_start,
    input  logic     mul_cancel,
    input  logic     is_signed,
    input  ALU_INST  inst_type,
    input  u64       op1,
    input  u64       op2,

    output u64       mul_res,
    output logic     is_mul_ready,
    output logic     is_mul_done
);

    ALU_STATE state;
    u6        count;
    u128      multiplier;
    u128      multiplicand;
    u128      product;
    logic     is_word;
    logic     res_sign;

    // 取绝对值（有符号才取）
    u64   op1_abs, op2_abs;
    logic op1_sign, op2_sign;
    assign op1_sign = (inst_type == WORD) ? op1[31] : op1[63];
    assign op2_sign = (inst_type == WORD) ? op2[31] : op2[63];

    always_comb begin
        if (is_signed) begin
            if (inst_type == WORD) begin
                op1_abs = op1_sign ? (~{32'b0, op1[31:0]} + 1'b1) : {32'b0, op1[31:0]};
                op2_abs = op2_sign ? (~{32'b0, op2[31:0]} + 1'b1) : {32'b0, op2[31:0]};
            end else begin
                op1_abs = op1_sign ? (~op1 + 1'b1) : op1;
                op2_abs = op2_sign ? (~op2 + 1'b1) : op2;
            end
        end else begin
            if (inst_type == WORD) begin
                op1_abs = {32'b0, op1[31:0]};
                op2_abs = {32'b0, op2[31:0]};
            end else begin
                op1_abs = op1;
                op2_abs = op2;
            end
        end
    end

    // 8-bit 粒度 Early-Out：multiplier 已剩 0，可直接收尾
    logic next_multiplier_is_zero;
    assign next_multiplier_is_zero = ((multiplier >> 1) == 128'b0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            count        <= 6'd0;
            product      <= 128'b0;
            is_mul_done  <= 1'b0;
            is_word      <= 1'b0;
            res_sign     <= 1'b0;
            multiplier   <= 128'b0;
            multiplicand <= 128'b0;
        end
        else if (mul_cancel) begin
            state       <= IDLE;
            is_mul_done <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    is_mul_done <= 1'b0;
                    if (mul_start) begin
                        state    <= COMPUTE;
                        count    <= 6'd0;
                        product  <= 128'b0;
                        res_sign <= is_signed & (op1_sign ^ op2_sign);
                        if (inst_type == WORD) begin
                            is_word      <= 1'b1;
                            multiplicand <= {96'b0, op1_abs[31:0]};
                            multiplier   <= {96'b0, op2_abs[31:0]};
                        end
                        else begin
                            is_word      <= 1'b0;
                            multiplicand <= {64'b0, op1_abs};
                            multiplier   <= {64'b0, op2_abs};
                        end
                    end
                end

                COMPUTE: begin
                    if (multiplier[0]) begin
                        product <= product + multiplicand;
                    end
                    if (count == 6'd63 || (count[2:0] == 3'b111 && next_multiplier_is_zero)) begin
                        state <= DONE;
                    end
                    else begin
                        multiplicand <= multiplicand << 1;
                        multiplier   <= multiplier >> 1;
                        count        <= count + 6'd1;
                    end
                end

                DONE: begin
                    is_mul_done <= 1'b1;
                    state       <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign is_mul_ready = (state == IDLE);

    // 取符号 + WORD/NORM 输出选择
    always_comb begin
        automatic u64 product_abs    = product[63:0];
        automatic u64 signed_product = res_sign ? (~product_abs + 1'b1) : product_abs;
        if (is_word) begin
            automatic u32 res32 = signed_product[31:0];
            mul_res = {{32{res32[31]}}, res32};
        end else begin
            mul_res = signed_product;
        end
    end
endmodule
