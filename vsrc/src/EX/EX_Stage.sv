// ----------------------------------------------------------------------------
// File        : EX_Stage.sv
// Description : EX Stage 顶层：装配 ALU_Core + Branch_Unit + PC_Target
//               op1/op2 mux 在这里做；rd mux 在这里做；
//               pc_should_jump / pc_jump_address 为组合直出，当拍反馈给 IF
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/ID_PKG.sv"
`include "src/EX/ALU_Core.sv"
`include "src/EX/Branch_Unit.sv"
`include "src/EX/PC_Target.sv"
`include "src/ID/CSR_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import ID_PKG::*;
import CSR_PKG::*;

module EX_Stage (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     stall,
    input  logic     flush,

    input  INST_CTX  inst_ctx_in,
    input  TRAP_CTX  trap_ctx_in,
    input  ID_2_EX   id_2_ex,
    input  FWD_2_EX  fwd_2_ex,
    input  CSR_WRITE csr_write_in,

    output INST_CTX  inst_ctx_out,
    output TRAP_CTX  trap_ctx_out,
    output EX_2_MEM  ex_2_mem,
    output EX_2_FWD  ex_2_fwd,
    output EX_2_CTRL ex_2_ctrl,
    output CSR_WRITE csr_write_out,

    output logic     pc_should_jump,
    output u64       pc_jump_address
);

    // op1 / op2 mux（mux 在 EX 做，不在 ID 做）
    // rs1/rs2 源已由 Forward_Unit 解析，统一走 fwd_2_ex
    u64 alu_input_1;
    u64 alu_input_2;

    always_comb begin
        if (id_2_ex.is_op1_zero)
            alu_input_1 = 64'b0;
        else if (id_2_ex.is_op1_pc)
            alu_input_1 = inst_ctx_in.pc_inst_address;
        else
            alu_input_1 = fwd_2_ex.rs1_data;
    end

    assign alu_input_2 = id_2_ex.is_op2_imm ? id_2_ex.imm : fwd_2_ex.rs2_data;

    // 三个子单元
    u64   alu_core_res;
    logic is_alu_busy;
    logic is_branch_taken;
    u64   pc_plus_4;
    u64   jump_target;

    ALU_Core u_alu_core (
        .clk          ( clk ),
        .rst_n        ( rst_n ),

        .op_code      ( id_2_ex.alu_op_code ),
        .inst_type    ( id_2_ex.alu_inst_type ),
        .alu_input_1  ( alu_input_1 ),
        .alu_input_2  ( alu_input_2 ),

        .alu_core_res ( alu_core_res ),
        .is_alu_busy  ( is_alu_busy )
    );

    Branch_Unit u_branch_unit (
        .branch_op       ( id_2_ex.branch_op ),
        // 分支判定吃 forward 后的 rs1/rs2
        .rs1_data        ( fwd_2_ex.rs1_data ),
        .rs2_data        ( fwd_2_ex.rs2_data ),
        .is_branch_taken ( is_branch_taken )
    );

    PC_Target u_pc_target (
        .jump_type       ( id_2_ex.jump_type ),
        .pc_inst_address ( inst_ctx_in.pc_inst_address ),
        .rs1_data        ( fwd_2_ex.rs1_data ),
        .imm             ( id_2_ex.imm ),
        .pc_plus_4       ( pc_plus_4 ),
        .jump_target     ( jump_target )
    );

    // rd mux：ALU 结果 / PC+4 / CSR 旧值
    u64 ex_result;
    always_comb begin
        unique case (id_2_ex.rd_src)
            RD_FROM_PC_PLUS_4: ex_result = pc_plus_4;
            RD_FROM_CSR:       ex_result = id_2_ex.csr_old;
            default:           ex_result = alu_core_res;
        endcase
    end

    // JALR 目标未对齐：记异常且禁止跳转
    logic jalr_misalign;
    assign jalr_misalign = (id_2_ex.jump_type == JT_JALR) && (jump_target[1:0] != 2'b00);

    // 跳转判定组合直出
    // JT_CSR 走"永远预测失败"语义，无条件拉高让 Control_Unit 触发 flush + PC 重定向到 pc+4
    always_comb begin
        unique case (id_2_ex.jump_type)
            JT_JAL:  pc_should_jump = 1'b1;
            JT_JALR: pc_should_jump = !jalr_misalign;
            JT_BR:   pc_should_jump = is_branch_taken;
            JT_CSR:  pc_should_jump = 1'b1;
            default: pc_should_jump = 1'b0;
        endcase
    end
    assign pc_jump_address = jump_target;

    // EX/MEM 流水寄存器：!stall 前进；复位清零
    // csr_write 与 inst_ctx 同 latch 节奏，原样透传到 MEM 段
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx_out  <= '0;
            trap_ctx_out  <= '0;
            ex_2_mem      <= '0;
            csr_write_out <= '0;
        end else if (flush) begin
            inst_ctx_out  <= '0;
            trap_ctx_out  <= '0;
            ex_2_mem      <= '0;
            csr_write_out <= '0;
        end else if (!stall) begin
            inst_ctx_out        <= inst_ctx_in;
            if (jalr_misalign) begin
                trap_ctx_out.exc_valid <= 1'b1;
                trap_ctx_out.exc_cause <= MCAUSE_INSTR_MISALIGN;
                trap_ctx_out.exc_tval  <= jump_target;
                trap_ctx_out.is_ecall  <= trap_ctx_in.is_ecall;
                trap_ctx_out.is_mret   <= trap_ctx_in.is_mret;
            end else begin
                trap_ctx_out        <= trap_ctx_in;
            end
            ex_2_mem.ex_result  <= ex_result;
            ex_2_mem.rs2_data   <= fwd_2_ex.rs2_data;
            ex_2_mem.amo_op     <= id_2_ex.amo_op;
            csr_write_out       <= csr_write_in;
        end
    end

    // EX → FWD：EX/MEM 寄存器 tap，供 distance-1 RAW forward
    assign ex_2_fwd.rd_addr   = inst_ctx_out.rd_addr;
    assign ex_2_fwd.ex_result = ex_2_mem.ex_result;

    // EX → 控制层：EX 位当前指令（即 ID/EX 寄存器输出）的 load / rd 信息，供 load-use 检测
    // is_alu_busy 由 ALU_Core 直接给出，乘除法运行期间触发全流水冻结
    assign ex_2_ctrl.is_ex_load  = (inst_ctx_in.opcode == OP_LOAD)
                                || (inst_ctx_in.opcode == OP_AMO);
    assign ex_2_ctrl.rd_addr     = inst_ctx_in.rd_addr;
    assign ex_2_ctrl.is_alu_busy = is_alu_busy;

endmodule
