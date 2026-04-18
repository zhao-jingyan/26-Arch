// ----------------------------------------------------------------------------
// File        : EX_Stage.sv
// Description : EX Stage 顶层：装配 ALU_Core + Branch_Unit + PC_Target
//               op1/op2 mux 在这里做；rd mux 在这里做；
//               pc_should_jump / pc_jump_address 为组合直出，当拍反馈给 IF
// ----------------------------------------------------------------------------

`include "src_new/top_pkg.sv"
`include "src_new/EX/ALU_Core.sv"
`include "src_new/EX/Branch_Unit.sv"
`include "src_new/EX/PC_Target.sv"

import common::*;
import top_pkg::*;

module EX_Stage (
    input  logic    clk,
    input  logic    rst_n,

    input  logic    stall,

    input  INST_CTX inst_ctx_in,
    input  ID_2_EX  id_2_ex,

    output INST_CTX inst_ctx_out,
    output EX_2_MEM ex_2_mem,

    output logic    pc_should_jump,
    output u64      pc_jump_address
);

    // op1 / op2 mux（mux 在 EX 做，不在 ID 做）
    u64 alu_input_1;
    u64 alu_input_2;

    always_comb begin
        if (id_2_ex.is_op1_zero)
            alu_input_1 = 64'b0;
        else if (id_2_ex.is_op1_pc)
            alu_input_1 = inst_ctx_in.pc_inst_address;
        else
            alu_input_1 = id_2_ex.rs1_data;
    end

    assign alu_input_2 = id_2_ex.is_op2_imm ? id_2_ex.imm : id_2_ex.rs2_data;

    // 三个子单元
    u64   alu_core_res;
    logic is_branch_taken;
    u64   pc_plus_4;
    u64   jump_target;

    ALU_Core u_alu_core (
        .op_code      ( id_2_ex.alu_op_code ),
        .inst_type    ( id_2_ex.alu_inst_type ),
        .alu_input_1  ( alu_input_1 ),
        .alu_input_2  ( alu_input_2 ),
        .alu_core_res ( alu_core_res )
    );

    Branch_Unit u_branch_unit (
        .branch_op       ( id_2_ex.branch_op ),
        // 分支判定吃原始 rs1/rs2，不走 mux
        .rs1_data        ( id_2_ex.rs1_data ),
        .rs2_data        ( id_2_ex.rs2_data ),
        .is_branch_taken ( is_branch_taken )
    );

    PC_Target u_pc_target (
        .jump_type       ( id_2_ex.jump_type ),
        .pc_inst_address ( inst_ctx_in.pc_inst_address ),
        .rs1_data        ( id_2_ex.rs1_data ),
        .imm             ( id_2_ex.imm ),
        .pc_plus_4       ( pc_plus_4 ),
        .jump_target     ( jump_target )
    );

    // rd mux：ALU 结果 vs PC+4
    u64 ex_result;
    always_comb begin
        unique case (id_2_ex.rd_src)
            RD_FROM_PC_PLUS_4: ex_result = pc_plus_4;
            default:           ex_result = alu_core_res;
        endcase
    end

    // 跳转判定组合直出
    always_comb begin
        unique case (id_2_ex.jump_type)
            JT_JAL:  pc_should_jump = 1'b1;
            JT_JALR: pc_should_jump = 1'b1;
            JT_BR:   pc_should_jump = is_branch_taken;
            default: pc_should_jump = 1'b0;
        endcase
    end
    assign pc_jump_address = jump_target;

    // EX/MEM 流水寄存器：!stall 前进；复位清零
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx_out <= '0;
            ex_2_mem     <= '0;
        end else if (!stall) begin
            inst_ctx_out        <= inst_ctx_in;
            ex_2_mem.ex_result  <= ex_result;
            ex_2_mem.rs2_data   <= id_2_ex.rs2_data;
        end
    end

endmodule
