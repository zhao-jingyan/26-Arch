// ----------------------------------------------------------------------------
// File        : Fetch_Data.sv
// Description : 访存单元；funct3 字节对齐 + 单槽 latch，驱动 DataMemory 请求 dbus
// ----------------------------------------------------------------------------

`include "src_new/MEM/DataMemory.sv"

import common::*;

module Fetch_Data (
    input  logic       clk,
    input  logic       rst_n,

    input  u64         pc_inst_address,
    input  u32         inst,
    input  u64         mem_addr,
    input  u3          funct3,
    input  logic       is_load,
    input  logic       is_store,
    input  u64         store_data,

    output u64         load_data,
    output logic       is_mem_ready,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    logic    is_mem;
    assign   is_mem = is_load || is_store;

    // funct3 → size / strobe / wdata（对齐到 8 字节 lane）
    u3       byte_idx;
    msize_t  req_size;
    strobe_t req_strobe;
    u64      req_wdata;

    assign byte_idx = mem_addr[2:0];

    assign req_size = (funct3 == 3'b000) ? MSIZE1 :
                      (funct3 == 3'b001) ? MSIZE2 :
                      (funct3 == 3'b010) ? MSIZE4 : MSIZE8;

    always_comb begin
        req_wdata  = 64'b0;
        req_strobe = 8'b0;
        if (is_store) begin
            unique case (funct3)
                3'b000: begin // sb
                    req_wdata  = ({56'b0, store_data[7:0]}  << (byte_idx * 8));
                    req_strobe = (8'b0000_0001 << byte_idx);
                end
                3'b001: begin // sh
                    req_wdata  = ({48'b0, store_data[15:0]} << (byte_idx * 8));
                    req_strobe = (8'b0000_0011 << byte_idx);
                end
                3'b010: begin // sw
                    req_wdata  = ({32'b0, store_data[31:0]} << (byte_idx * 8));
                    req_strobe = (8'b0000_1111 << byte_idx);
                end
                3'b011: begin // sd
                    req_wdata  = store_data;
                    req_strobe = 8'b1111_1111;
                end
                default: ;
            endcase
        end
    end

    // dbus 原始响应 → 对齐 + sext/zext
    u64   response_data;
    logic is_response_valid;
    u64   load_data_shifted;
    u64   load_data_ext;

    assign load_data_shifted = response_data >> (byte_idx * 8);

    always_comb begin
        load_data_ext = load_data_shifted;
        unique case (funct3)
            3'b000: load_data_ext = {{56{load_data_shifted[7]}},  load_data_shifted[7:0]};   // lb
            3'b001: load_data_ext = {{48{load_data_shifted[15]}}, load_data_shifted[15:0]};  // lh
            3'b010: load_data_ext = {{32{load_data_shifted[31]}}, load_data_shifted[31:0]};  // lw
            3'b011: load_data_ext = load_data_shifted;                                        // ld
            3'b100: load_data_ext = {56'b0, load_data_shifted[7:0]};                          // lbu
            3'b101: load_data_ext = {48'b0, load_data_shifted[15:0]};                         // lhu
            3'b110: load_data_ext = {32'b0, load_data_shifted[31:0]};                         // lwu
            default: load_data_ext = load_data_shifted;
        endcase
    end

    // 单槽 latch：记录"当前停留在 MEM 的指令"已完成访存的 load 数据
    // 关键：仅靠 (pc, inst) 比对不能区分循环里的「同 PC 不同实例」，
    //   必须在持有 latch 的指令离开 MEM 时主动失效，否则下次同 PC 进入会命中陈旧值
    u64   latched_pc;
    u32   latched_inst;
    u64   latched_data;
    logic latched_valid;
    logic is_same_inst;
    logic request_valid;

    assign is_same_inst = latched_valid
                       && (latched_pc   == pc_inst_address)
                       && (latched_inst == inst);

    assign is_mem_ready  = !is_mem || is_same_inst;
    assign request_valid = is_mem && !is_mem_ready;
    assign load_data     = is_same_inst ? latched_data : load_data_ext;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_pc    <= '0;
            latched_inst  <= '0;
            latched_data  <= '0;
            latched_valid <= 1'b0;
        end
        // 本拍响应回来（且尚未 latch）→ 覆盖式 latch 当前 pc/inst/data
        // 同时也覆盖了「上一条 mem 指令离开后 latch 残留」的清理需求
        else if (is_response_valid && !is_mem_ready) begin
            latched_pc    <= pc_inst_address;
            latched_inst  <= inst;
            latched_data  <= load_data_ext;  // store 不使用此字段
            latched_valid <= 1'b1;
        end
        // 持 latch 的指令已离开 MEM（本拍 pc/inst 与 latch 不同）→ 让 latch 失效
        // 防止循环中同 PC 再次进入时误命中陈旧 latched_data
        else if (latched_valid
                 && ((latched_pc != pc_inst_address) || (latched_inst != inst))) begin
            latched_valid <= 1'b0;
        end
    end

    DataMemory u_data_memory (
        .clk                ( clk ),
        .rst_n              ( rst_n ),

        .request_addr       ( mem_addr ),
        .request_valid      ( request_valid ),
        .request_size       ( req_size ),
        .request_strobe     ( req_strobe ),
        .request_write_data ( req_wdata ),

        .response_data      ( response_data ),
        .is_response_valid  ( is_response_valid ),

        .dbus_request       ( dbus_request ),
        .dbus_response      ( dbus_response )
    );

endmodule
