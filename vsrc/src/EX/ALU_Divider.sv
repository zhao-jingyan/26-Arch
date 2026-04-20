// ----------------------------------------------------------------------------
// File        : ALU_Divider.sv
// Description : 多周期恢复余数除法器；支持 NORM (64/64) 与 WORD (32/32 → sext64)
//               有符号场景由调用方拆出 |op|，最后按 quotient / remainder 符号取补
//               处理两个 RISC-V 异常：除零（quotient=-1, remainder=op1）
//                                     有符号溢出（INT_MIN / -1 → quotient=INT_MIN, remainder=0）
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/EX/EX_PKG.sv"
`include "src/EX/ALU_PKG.sv"
`endif

import common::*;
import EX_PKG::*;
import ALU_PKG::*;

module ALU_Divider (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     div_start,
    input  logic     div_cancel,
    input  ALU_INST  inst_type,
    input  logic     is_signed,
    input  u64       op1,
    input  u64       op2,

    output u64       quotient,
    output u64       remainder,
    output logic     is_div_ready,
    output logic     is_div_done
);

    ALU_STATE state;
    u7        count;
    u64       divisor;
    u64       quotient_reg;
    u64       remainder_reg;
    logic     res_sign;
    logic     rem_sign;
    logic     is_word;

    // is_word / res_sign / rem_sign / divisor 的 next 信号
    // 拆出来单独做纯 D 触发器 + 异步复位，避免 Vivado 把 IDLE 分支里
    // 可能为 0 或 1 的赋值识别成同步 set / reset，与 rst_n 冲突
    logic is_word_next;
    logic res_sign_next;
    logic rem_sign_next;
    u64   divisor_next;

    u64   op1_abs, op2_abs;
    logic op1_sign, op2_sign;
    assign op1_sign = (inst_type == WORD) ? op1[31] : op1[63];
    assign op2_sign = (inst_type == WORD) ? op2[31] : op2[63];

    // 取绝对值（有符号才取）
    // WORD 场景需在 32 位内取反+1，再零扩到 64 位
    // 否则 `~{32'b0, op[31:0]} + 1` 会把 op_abs 高 32 位污染为全 1
    always_comb begin
        if (is_signed) begin
            if (inst_type == WORD) begin
                op1_abs = op1_sign ? {32'b0, (~op1[31:0] + 1'b1)} : {32'b0, op1[31:0]};
                op2_abs = op2_sign ? {32'b0, (~op2[31:0] + 1'b1)} : {32'b0, op2[31:0]};
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

    // is_div_done 单独拆一个 DFF:仅异步复位 + 纯 D 输入
    // 避免 Vivado 在合并的 always_ff 里把 DONE→1 和 div_cancel/IDLE→0 分别识别
    // 为同步 set 与同步 reset 引脚,从而报 "set and reset have same priority"
    logic is_div_done_next;
    assign is_div_done_next = (state == DONE) && !div_cancel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) is_div_done <= 1'b0;
        else        is_div_done <= is_div_done_next;
    end

    // is_word / res_sign / rem_sign / divisor 仅在 IDLE 接受 div_start 时更新
    // 其它时刻保持旧值；div_cancel 不清它们（下次 IDLE 接新任务时会覆盖）
    always_comb begin
        is_word_next  = is_word;
        res_sign_next = res_sign;
        rem_sign_next = rem_sign;
        divisor_next  = divisor;
        if ((state == IDLE) && div_start && !div_cancel) begin
            is_word_next  = (inst_type == WORD);
            res_sign_next = is_signed & (op1_sign ^ op2_sign);
            rem_sign_next = is_signed & op1_sign;
            divisor_next  = op2_abs;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_word  <= 1'b0;
            res_sign <= 1'b0;
            rem_sign <= 1'b0;
            divisor  <= 64'b0;
        end
        else begin
            is_word  <= is_word_next;
            res_sign <= res_sign_next;
            rem_sign <= rem_sign_next;
            divisor  <= divisor_next;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            count         <= 7'd0;
            quotient_reg  <= 64'b0;
            remainder_reg <= 64'b0;
        end
        else if (div_cancel) begin
            state <= IDLE;
        end
        else begin
            case (state)
                IDLE: begin
                    if (div_start) begin
                        state         <= COMPUTE;
                        count         <= 7'd63;
                        remainder_reg <= 64'b0;
                        quotient_reg  <= op1_abs;

                        // 异常提前结束
                        if (op2_abs == 64'b0) begin
                            state <= DONE;
                        end
                        else if (is_signed && op1 == 64'h8000_0000_0000_0000 && op2 == 64'hFFFF_FFFF_FFFF_FFFF) begin
                            state <= DONE;
                        end
                    end
                end

                COMPUTE: begin
                    automatic u65 sub_res;
                    automatic u64 next_rem;
                    next_rem = {remainder_reg[62:0], quotient_reg[63]};
                    sub_res  = {1'b0, next_rem} - {1'b0, divisor};

                    if (sub_res[64]) begin
                        remainder_reg <= next_rem;
                        quotient_reg  <= {quotient_reg[62:0], 1'b0};
                    end else begin
                        remainder_reg <= sub_res[63:0];
                        quotient_reg  <= {quotient_reg[62:0], 1'b1};
                    end

                    if (count == 7'd0) begin
                        state <= DONE;
                    end else begin
                        count <= count - 7'd1;
                    end
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign is_div_ready = (state == IDLE);

    // 取符号 + 异常修正 + WORD/NORM 输出选择
    always_comb begin
        automatic u64   q_final;
        automatic u64   r_final;
        automatic logic overflow_detected;

        overflow_detected = 1'b0;
        q_final = res_sign ? (~quotient_reg  + 1'b1) : quotient_reg;
        r_final = rem_sign ? (~remainder_reg + 1'b1) : remainder_reg;

        // 异常处理
        if (divisor == 64'b0) begin
            q_final = 64'hFFFF_FFFF_FFFF_FFFF;
            r_final = is_word ? {{32{op1[31]}}, op1[31:0]} : op1;
        end else if (is_signed) begin
            if (is_word) begin
                overflow_detected = (op1[31:0] == 32'h8000_0000) && (op2[31:0] == 32'hFFFF_FFFF);
                if (overflow_detected) begin
                    q_final = 64'hFFFF_FFFF_8000_0000;
                    r_final = 64'b0;
                end
            end else begin
                overflow_detected = (op1 == 64'h8000_0000_0000_0000) && (op2 == 64'hFFFF_FFFF_FFFF_FFFF);
                if (overflow_detected) begin
                    q_final = 64'h8000_0000_0000_0000;
                    r_final = 64'b0;
                end
            end
        end

        if (is_word) begin
            quotient  = {{32{q_final[31]}}, q_final[31:0]};
            remainder = {{32{r_final[31]}}, r_final[31:0]};
        end else begin
            quotient  = q_final;
            remainder = r_final;
        end
    end
endmodule
