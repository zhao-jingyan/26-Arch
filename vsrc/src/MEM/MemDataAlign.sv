// ----------------------------------------------------------------------------
// File        : MemDataAlign.sv
// Description : Byte-lane format for load/store data path
// Author      : zhao-jingyan | Date: 2026-03-24
// ----------------------------------------------------------------------------

import common::*;

module MemDataAlign (
    input  logic [2:0] funct3_i,
    input  u64         addr_i,
    input  u64         store_data_i,
    input  u64         load_rdata_i,

    output msize_t     req_size_o,
    output strobe_t    req_strobe_o,
    output u64         req_wdata_o,
    output u64         load_data_o
);

    logic [2:0] byte_idx;
    u64         load_data_shifted;

    assign byte_idx          = addr_i[2:0];
    assign load_data_shifted = load_rdata_i >> (byte_idx * 8);

    assign req_size_o = (funct3_i == 3'b000) ? MSIZE1 :
                        (funct3_i == 3'b001) ? MSIZE2 :
                        (funct3_i == 3'b010) ? MSIZE4 : MSIZE8;

    always_comb begin
        req_wdata_o  = 64'b0;
        req_strobe_o = 8'b0;
        case (funct3_i)
            3'b000: begin // sb
                req_wdata_o  = ({56'b0, store_data_i[7:0]} << (byte_idx * 8));
                req_strobe_o = (8'b0000_0001 << byte_idx);
            end
            3'b001: begin // sh
                req_wdata_o  = ({48'b0, store_data_i[15:0]} << (byte_idx * 8));
                req_strobe_o = (8'b0000_0011 << byte_idx);
            end
            3'b010: begin // sw
                req_wdata_o  = ({32'b0, store_data_i[31:0]} << (byte_idx * 8));
                req_strobe_o = (8'b0000_1111 << byte_idx);
            end
            3'b011: begin // sd
                req_wdata_o  = store_data_i;
                req_strobe_o = 8'b1111_1111;
            end
            default: begin
                req_wdata_o  = 64'b0;
                req_strobe_o = 8'b0;
            end
        endcase
    end

    always_comb begin
        load_data_o = load_data_shifted;
        case (funct3_i)
            3'b000: load_data_o = {{56{load_data_shifted[7]}},  load_data_shifted[7:0]};    // lb
            3'b001: load_data_o = {{48{load_data_shifted[15]}}, load_data_shifted[15:0]};   // lh
            3'b010: load_data_o = {{32{load_data_shifted[31]}}, load_data_shifted[31:0]};   // lw
            3'b011: load_data_o = load_data_shifted;                                          // ld
            3'b100: load_data_o = {56'b0, load_data_shifted[7:0]};                            // lbu
            3'b101: load_data_o = {48'b0, load_data_shifted[15:0]};                           // lhu
            3'b110: load_data_o = {32'b0, load_data_shifted[31:0]};                           // lwu
            default: load_data_o = load_data_shifted;
        endcase
    end

endmodule
