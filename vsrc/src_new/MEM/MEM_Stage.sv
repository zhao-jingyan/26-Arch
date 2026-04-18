// ----------------------------------------------------------------------------
// File        : MEM_Stage.sv
// Description : MEM Stage 顶层：装配 Fetch_Data；rd mux；末尾落 MEM/WB 流水寄存器
//               is_mem_ready 为裸端口反馈忙状态，未来并入控制层
// ----------------------------------------------------------------------------

`include "src_new/top_pkg.sv"
`include "src_new/ID/ID_PKG.sv"
`include "src_new/MEM/Fetch_Data.sv"

import common::*;
import top_pkg::*;
import ID_PKG::*;

module MEM_Stage (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       stall,

    input  INST_CTX    inst_ctx_in,
    input  EX_2_MEM    ex_2_mem,

    output INST_CTX    inst_ctx_out,
    output MEM_2_WB    mem_2_wb,
    output MEM_2_FWD   mem_2_fwd,

    output logic       is_mem_ready,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    logic is_load;
    logic is_store;
    u3    funct3;

    assign is_load  = (inst_ctx_in.opcode == OP_LOAD);
    assign is_store = (inst_ctx_in.opcode == OP_STORE);
    assign funct3   = inst_ctx_in.inst[14:12];

    u64 load_data;

    Fetch_Data u_fetch_data (
        .clk             ( clk ),
        .rst_n           ( rst_n ),

        .pc_inst_address ( inst_ctx_in.pc_inst_address ),
        .inst            ( inst_ctx_in.inst ),
        .mem_addr        ( ex_2_mem.ex_result ),
        .funct3          ( funct3 ),
        .is_load         ( is_load ),
        .is_store        ( is_store ),
        .store_data      ( ex_2_mem.rs2_data ),

        .load_data       ( load_data ),
        .is_mem_ready    ( is_mem_ready ),

        .dbus_request    ( dbus_request ),
        .dbus_response   ( dbus_response )
    );

    // rd 写回数据 mux：load → 对齐后的 load_data；其他 → ex_result
    u64 rd_data;
    assign rd_data = is_load ? load_data : ex_2_mem.ex_result;

    // MEM/WB 流水寄存器：!stall && is_mem_ready 时前进；复位清零
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx_out <= '0;
            mem_2_wb     <= '0;
        end
        else if (!stall && is_mem_ready) begin
            inst_ctx_out     <= inst_ctx_in;
            mem_2_wb.rd_data <= rd_data;
        end
    end

    // MEM → FWD：MEM/WB 寄存器 tap，供 distance-2 RAW forward
    assign mem_2_fwd.rd_addr = inst_ctx_out.rd_addr;
    assign mem_2_fwd.rd_data = mem_2_wb.rd_data;

endmodule
