// ----------------------------------------------------------------------------
// File        : ALUStage.sv
// Description : ALU stage top, uses ALU_Core only (no Controller, no MDU)
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`include "src/pipeline_pkg.sv"
`include "src/DECODE/DECODE_PKG.sv"
`include "src/ALU/ALU_Core.sv"

import common::*;
import ALU_PKG::*;
import DECODE_PKG::*;
import pipeline_pkg::*;

module ALUStage (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       stall_i,

    input  id_ex_t     id_ex_i,
    input  ex_mem_t    ex_mem_i,
    input  wb_reg_t    wb_i,
    input  u64         load_bypass_data_i,
    input  logic [1:0] rs1_fwd_sel_i,
    input  logic [1:0] rs2_fwd_sel_i,
    input  logic [1:0] store_data_fwd_sel_i,

    output ex_mem_t    ex_mem_o
);

    u64 rs1_fwd;
    u64 rs2_fwd;
    u64 store_data_fwd;

    always_comb begin
        case (rs1_fwd_sel_i)
            2'b01: rs1_fwd = ex_mem_i.alu_res;
            2'b10: rs1_fwd = wb_i.rd_data;
            2'b11: rs1_fwd = load_bypass_data_i;
            default: rs1_fwd = id_ex_i.rs1_data;
        endcase
    end

    always_comb begin
        case (rs2_fwd_sel_i)
            2'b01: rs2_fwd = ex_mem_i.alu_res;
            2'b10: rs2_fwd = wb_i.rd_data;
            2'b11: rs2_fwd = load_bypass_data_i;
            default: rs2_fwd = id_ex_i.rs2_data;
        endcase
    end

    always_comb begin
        case (store_data_fwd_sel_i)
            2'b01: store_data_fwd = ex_mem_i.alu_res;
            2'b10: store_data_fwd = wb_i.rd_data;
            2'b11: store_data_fwd = load_bypass_data_i;
            default: store_data_fwd = id_ex_i.store_data;
        endcase
    end

    u64 op1;
    u64 op2;
    u64 alu_res;

    assign op1 = rs1_fwd;
    assign op2 = (id_ex_i.opcode == OP_IMM || id_ex_i.opcode == OP_IMM32)
                 ? id_ex_i.imm : rs2_fwd;

    ALU_Core u_core (
        .op_code_i      ( id_ex_i.alu_op_code ),
        .inst_type_i    ( id_ex_i.alu_inst_type ),
        .op1_i          ( op1 ),
        .op2_i          ( op2 ),
        .alu_core_res_o ( alu_res )
    );

    ex_mem_t ex_mem_d;
    assign ex_mem_d.pc      = id_ex_i.pc;
    assign ex_mem_d.inst    = id_ex_i.inst;
    assign ex_mem_d.rd_addr = id_ex_i.rd_addr;
    assign ex_mem_d.alu_res = alu_res;
    assign ex_mem_d.store_data = (id_ex_i.opcode == OP_STORE) ? store_data_fwd : id_ex_i.store_data;
    assign ex_mem_d.opcode  = id_ex_i.opcode;

    // EX/MEM pipeline reg
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_o <= '0;
        end else if (!stall_i) begin
            ex_mem_o <= ex_mem_d;
        end
    end

endmodule
