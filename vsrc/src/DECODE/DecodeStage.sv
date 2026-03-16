// ----------------------------------------------------------------------------
// File        : DecodeStage.sv
// Description : DECODE stage top, wraps Decoder/RegFile/Sign_Extend, output reg
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"
`include "src/DECODE/Decoder.sv"
`include "src/DECODE/RegFile.sv"
`include "src/DECODE/Sign_Extend.sv"

import common::*;
import ALU_PKG::*;
import pipeline_pkg::*;

module DecodeStage (
    input logic clk,
    input logic rst_n,
    input logic stall_i,

    input  if_id_t    if_id_i,
    input  wb_reg_t   wb_i,

    output id_ex_t    id_ex_o,
    output u64        gpr_o [0:31]
);

    // comb outputs from submodules
    logic [6:0]  opcode;
    logic [4:0]  rd_addr;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    u64          rs1_data;
    u64          rs2_data;
    u64          imm;
    ALU_OP_CODE  alu_op_code;
    ALU_INST     alu_inst_type;

    Decoder u_decoder (
        .inst_i         ( if_id_i.inst ),
        .opcode_o       ( opcode ),
        .rd_addr_o      ( rd_addr ),
        .rs1_addr_o     ( rs1_addr ),
        .rs2_addr_o     ( rs2_addr ),
        .alu_op_code_o  ( alu_op_code ),
        .alu_inst_type_o( alu_inst_type )
    );

    RegFile u_regfile (
        .clk          ( clk ),
        .rst_n        ( rst_n ),
        .write_en_i   ( wb_i.wen ),
        .write_addr_i ( wb_i.rd_addr ),
        .write_data_i ( wb_i.rd_data ),
        .read_addr1_i ( rs1_addr ),
        .read_addr2_i ( rs2_addr ),
        .read_data1_o ( rs1_data ),
        .read_data2_o ( rs2_data ),
        .gpr_o        ( gpr_o )
    );

    Sign_Extend u_sign_extend (
        .inst_i   ( if_id_i.inst ),
        .opcode_i ( opcode ),
        .imm_o    ( imm )
    );

    // ID/EX pipeline reg
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_o <= '0;
        end else if (!stall_i) begin
            id_ex_o.pc           <= if_id_i.pc;
            id_ex_o.inst         <= if_id_i.inst;
            id_ex_o.rd_addr      <= rd_addr;
            id_ex_o.rs1_addr     <= rs1_addr;
            id_ex_o.rs2_addr     <= rs2_addr;
            id_ex_o.rs1_data     <= rs1_data;
            id_ex_o.rs2_data     <= rs2_data;
            id_ex_o.imm          <= imm;
            id_ex_o.alu_op_code  <= alu_op_code;
            id_ex_o.alu_inst_type <= alu_inst_type;
            id_ex_o.opcode       <= opcode;
        end
    end

endmodule
