// ----------------------------------------------------------------------------
// File        : ALUStage.sv
// Description : Clean ALU stage, decoupled from Hazard/Forwarding logic.
//               Operands and Control are pre-packaged in alu_input_t.
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"
`include "src/ALU/ALU_Core.sv"

import common::*;
import ALU_PKG::*;
import pipeline_pkg::*;

module ALUStage (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       stall_i,   // 来自 Hazard Unit
    input  logic       flush_i,   // 来自 Hazard Unit

    input  alu_input_t alu_input_i, // 纯净的输入包

    output alu_out_t   alu_out_o    // 加工后的输出包
);

    u64 alu_res_w;

    // 核心运算单元：只负责处理数据，不关心流水线控制
    ALU_Core u_core (
        .op_code_i      ( alu_input_i.ctrl.alu_op_code ),
        .inst_type_i    ( alu_input_i.ctrl.alu_inst_type ),
        .op1_i          ( alu_input_i.op1_val ),
        .op2_i          ( alu_input_i.op2_val ),
        .alu_core_res_o ( alu_res_w )
    );

    // 组合逻辑：封包
    alu_out_t alu_out_d;

    always_comb begin
        alu_out_d.ctx         = alu_input_i.ctx;
        alu_out_d.alu_res     = alu_res_w;
        alu_out_d.store_data  = alu_input_i.store_val;
    end

    // 流水线寄存器：时序隔离
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_out_o <= '0;
        end else if (!stall_i) begin
            if (flush_i) begin
                alu_out_o <= '0;
            end else begin
                alu_out_o <= alu_out_d;
            end
        end
    end

endmodule
