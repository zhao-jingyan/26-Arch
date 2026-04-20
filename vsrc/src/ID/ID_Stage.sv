// ----------------------------------------------------------------------------
// File        : ID_Stage.sv
// Description : ID Stage 顶层：装配 Decoder + RegFile + Sign_Extend + ID/EX 流水寄存器
//               ID 不做 op1/op2 mux（v2 规约：mux 在 EX 做）
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/Decoder.sv"
`include "src/ID/RegFile.sv"
`include "src/ID/Sign_Extend.sv"
`endif

import common::*;
import top_pkg::*;

module ID_Stage (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     stall,
    input  logic     insert_bubble,    // load-use 时向 ID/EX 寄存器注入 NOP
    input  IF_2_ID   if_2_id,
    input  WB_2_ID   wb_2_id,

    output INST_CTX  inst_ctx,
    output ID_2_EX   id_2_ex,
    output ID_2_FWD  id_2_fwd,
    output u64       gpr [0:31],
    output ID_2_CTRL id_2_ctrl
);

    // Decoder 输出
    u7          dec_opcode;
    u5          dec_rd_addr;
    u5          dec_rs1_addr;
    u5          dec_rs2_addr;
    ALU_OP_CODE dec_alu_op_code;
    ALU_INST    dec_alu_inst_type;
    logic       dec_is_op1_zero;
    logic       dec_is_op1_pc;
    logic       dec_is_op2_imm;
    BRANCH_OP   dec_branch_op;
    JUMP_TYPE   dec_jump_type;
    RD_SRC      dec_rd_src;

    // RegFile 读出
    u64         rf_read_data_1;
    u64         rf_read_data_2;

    // Sign_Extend 输出
    u64         se_imm;

    Decoder u_decoder (
        .inst          ( if_2_id.inst ),

        .opcode        ( dec_opcode ),
        .rd_addr       ( dec_rd_addr ),
        .rs1_addr      ( dec_rs1_addr ),
        .rs2_addr      ( dec_rs2_addr ),

        .alu_op_code   ( dec_alu_op_code ),
        .alu_inst_type ( dec_alu_inst_type ),
        .is_op1_zero   ( dec_is_op1_zero ),
        .is_op1_pc     ( dec_is_op1_pc ),
        .is_op2_imm    ( dec_is_op2_imm ),

        .branch_op     ( dec_branch_op ),
        .jump_type     ( dec_jump_type ),
        .rd_src        ( dec_rd_src )
    );

    RegFile u_regfile (
        .clk          ( clk ),
        .rst_n        ( rst_n ),

        .write_en     ( wb_2_id.write_en ),
        .write_addr   ( wb_2_id.write_addr ),
        .write_data   ( wb_2_id.write_data ),

        .read_addr_1  ( dec_rs1_addr ),
        .read_addr_2  ( dec_rs2_addr ),
        .read_data_1  ( rf_read_data_1 ),
        .read_data_2  ( rf_read_data_2 ),

        .gpr          ( gpr )
    );

    Sign_Extend u_sign_extend (
        .inst   ( if_2_id.inst ),
        .opcode ( dec_opcode ),
        .imm    ( se_imm )
    );

    // ID/EX 流水寄存器：物理上同一组，按语义拆成 inst_ctx / id_2_ex / id_2_fwd 三个输出
    // 优先级：rst_n > insert_bubble（load-use 注入 NOP）> !stall（正常推进）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx <= '0;
            id_2_ex  <= '0;
            id_2_fwd <= '0;
        end else if (insert_bubble) begin
            inst_ctx <= '0;
            id_2_ex  <= '0;
            id_2_fwd <= '0;
        end else if (!stall) begin
            inst_ctx.pc_inst_address <= if_2_id.pc_inst_address;
            inst_ctx.inst            <= if_2_id.inst;
            inst_ctx.rd_addr         <= dec_rd_addr;
            inst_ctx.opcode          <= dec_opcode;

            id_2_ex.imm           <= se_imm;
            id_2_ex.is_op1_zero   <= dec_is_op1_zero;
            id_2_ex.is_op1_pc     <= dec_is_op1_pc;
            id_2_ex.is_op2_imm    <= dec_is_op2_imm;
            id_2_ex.alu_op_code   <= dec_alu_op_code;
            id_2_ex.alu_inst_type <= dec_alu_inst_type;
            id_2_ex.branch_op     <= dec_branch_op;
            id_2_ex.jump_type     <= dec_jump_type;
            id_2_ex.rd_src        <= dec_rd_src;

            id_2_fwd.rs1_addr <= dec_rs1_addr;
            id_2_fwd.rs2_addr <= dec_rs2_addr;
            id_2_fwd.rs1_data <= rf_read_data_1;
            id_2_fwd.rs2_data <= rf_read_data_2;
        end
    end

    // 控制层反馈：组合透出 ID 位当前指令（即 Decoder 输出）的 rs 号，供 load-use 检测
    assign id_2_ctrl.rs1_addr = dec_rs1_addr;
    assign id_2_ctrl.rs2_addr = dec_rs2_addr;

endmodule
