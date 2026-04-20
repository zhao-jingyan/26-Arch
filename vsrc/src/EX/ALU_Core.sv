// ----------------------------------------------------------------------------
// File        : ALU_Core.sv
// Description : 64-bit ALU：算术 / 逻辑 / 移位 / 比较 + 多周期乘除法
//               单周期段：NORM 全 64-bit；WORD 低 32-bit 运算结果 sext 回 64
//               多周期段：内嵌 ALU_Multiplier / ALU_Divider
//                          op_code ∈ {MUL,DIV,DIVU,REM,REMU} 时启动对应单元
//                          运行期间拉高 is_alu_busy 让控制层冻结全流水
//                          DONE 拍 is_alu_busy 降沿 + alu_core_res 出值，EX/MEM 当拍 latch
// ----------------------------------------------------------------------------

`include "src/EX/EX_PKG.sv"
`include "src/EX/ALU_Multiplier.sv"
`include "src/EX/ALU_Divider.sv"

import common::*;
import EX_PKG::*;

module ALU_Core (
    input  logic       clk,
    input  logic       rst_n,

    input  ALU_OP_CODE op_code,
    input  ALU_INST    inst_type,
    input  u64         alu_input_1,
    input  u64         alu_input_2,

    output u64         alu_core_res,
    output logic       is_alu_busy
);

    // ----------------------------------------------------------------
    // 单周期 ALU 段（原 v1 行为，结果存 single_cycle_res）
    // ----------------------------------------------------------------
    logic [5:0] shamt64;
    logic [4:0] shamt32;
    assign shamt64 = alu_input_2[5:0];
    assign shamt32 = alu_input_2[4:0];

    u32 res32;
    u64 single_cycle_res;

    always_comb begin
        single_cycle_res = 64'b0;
        res32            = 32'b0;

        unique case (inst_type)
            NORM: begin
                unique case (op_code)
                    ADD:  single_cycle_res = alu_input_1 + alu_input_2;
                    SUB:  single_cycle_res = alu_input_1 - alu_input_2;
                    AND:  single_cycle_res = alu_input_1 & alu_input_2;
                    OR :  single_cycle_res = alu_input_1 | alu_input_2;
                    XOR:  single_cycle_res = alu_input_1 ^ alu_input_2;
                    SLL:  single_cycle_res = alu_input_1 << shamt64;
                    SRL:  single_cycle_res = alu_input_1 >> shamt64;
                    SRA:  single_cycle_res = u64'($signed(alu_input_1) >>> shamt64);
                    SLT:  single_cycle_res = {63'b0, ($signed(alu_input_1) < $signed(alu_input_2))};
                    SLTU: single_cycle_res = {63'b0, (alu_input_1 < alu_input_2)};
                    default: single_cycle_res = 64'b0;
                endcase
            end

            WORD: begin
                unique case (op_code)
                    ADD: begin
                        res32            = alu_input_1[31:0] + alu_input_2[31:0];
                        single_cycle_res = {{32{res32[31]}}, res32};
                    end
                    SUB: begin
                        res32            = alu_input_1[31:0] - alu_input_2[31:0];
                        single_cycle_res = {{32{res32[31]}}, res32};
                    end
                    SLL: begin
                        res32            = alu_input_1[31:0] << shamt32;
                        single_cycle_res = {{32{res32[31]}}, res32};
                    end
                    SRL: begin
                        res32            = alu_input_1[31:0] >> shamt32;
                        single_cycle_res = {{32{res32[31]}}, res32};
                    end
                    SRA: begin
                        res32            = u32'($signed(alu_input_1[31:0]) >>> shamt32);
                        single_cycle_res = {{32{res32[31]}}, res32};
                    end
                    default: single_cycle_res = 64'b0;
                endcase
            end

            default: single_cycle_res = 64'b0;
        endcase
    end

    // ----------------------------------------------------------------
    // 多周期段：op_code 译码 + Multiplier / Divider
    // ----------------------------------------------------------------
    logic is_mul_op;
    logic is_div_op;
    logic is_muldiv_op;
    logic is_div_signed;
    logic is_div_quotient;     // DIV/DIVU 取 quotient；REM/REMU 取 remainder

    assign is_mul_op       = (op_code == MUL);
    assign is_div_op       = (op_code == DIV) || (op_code == DIVU)
                          || (op_code == REM) || (op_code == REMU);
    assign is_muldiv_op    = is_mul_op || is_div_op;
    assign is_div_signed   = (op_code == DIV) || (op_code == REM);
    assign is_div_quotient = (op_code == DIV) || (op_code == DIVU);

    // 子单元 ↔ ALU_Core
    u64   mul_res;
    logic is_mul_ready;
    logic is_mul_done;

    u64   div_quotient;
    u64   div_remainder;
    logic is_div_ready;
    logic is_div_done;

    // 启动条件：当前指令是 mul/div 且对应单元处于 IDLE（is_*_ready）
    // is_*_done 这一拍单元仍在 DONE，下一拍才回 IDLE，避免 DONE 拍立即重启
    logic mul_start;
    logic div_start;
    assign mul_start = is_mul_op && is_mul_ready && !is_mul_done;
    assign div_start = is_div_op && is_div_ready && !is_div_done;

    ALU_Multiplier u_mul (
        .clk          ( clk ),
        .rst_n        ( rst_n ),

        .mul_start    ( mul_start ),
        .mul_cancel   ( 1'b0 ),
        .is_signed    ( 1'b0 ),         // MUL 取低 64，符号无关；恒走 unsigned
        .inst_type    ( inst_type ),
        .op1          ( alu_input_1 ),
        .op2          ( alu_input_2 ),

        .mul_res      ( mul_res ),
        .is_mul_ready ( is_mul_ready ),
        .is_mul_done  ( is_mul_done )
    );

    ALU_Divider u_div (
        .clk          ( clk ),
        .rst_n        ( rst_n ),

        .div_start    ( div_start ),
        .div_cancel   ( 1'b0 ),
        .inst_type    ( inst_type ),
        .is_signed    ( is_div_signed ),
        .op1          ( alu_input_1 ),
        .op2          ( alu_input_2 ),

        .quotient     ( div_quotient ),
        .remainder    ( div_remainder ),
        .is_div_ready ( is_div_ready ),
        .is_div_done  ( is_div_done )
    );

    // ----------------------------------------------------------------
    // 输出 mux + busy 信号
    //   - 乘除法指令运行期间 busy=1，DONE 拍降沿
    //   - alu_core_res 在 DONE 拍取对应子单元结果；其它时刻取单周期结果
    // ----------------------------------------------------------------
    assign is_alu_busy = (is_mul_op && !is_mul_done)
                      || (is_div_op && !is_div_done);

    always_comb begin
        if (is_mul_op) begin
            alu_core_res = mul_res;
        end
        else if (is_div_op) begin
            alu_core_res = is_div_quotient ? div_quotient : div_remainder;
        end
        else begin
            alu_core_res = single_cycle_res;
        end
    end

endmodule
