// ----------------------------------------------------------
// File        : RegFile.sv
// Description : 32 x 64-bit Register File, x0 always 0
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------

import common::*;

module RegFile (
    input logic clk,
    input logic rst_n,
    input logic write_en_i,

    input u5  write_addr_i,
    input u64 write_data_i,

    input u5  read_addr1_i,
    input u5  read_addr2_i,
    output u64 read_data1_o,
    output u64 read_data2_o,

    output u64 gpr_o [0:31]  // x0..x31 for Difftest
);

    u64 reg_file[1:31];  // x1..x31, x0 hardwired to 0

    assign gpr_o[0] = 64'b0;
    generate
        for (genvar i = 1; i < 32; i++) begin : g_gpr
            assign gpr_o[i] = reg_file[i];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 1; i < 32; i++) begin
                reg_file[i] <= 64'b0;
            end
        end else if (write_en_i && |write_addr_i) begin
            reg_file[write_addr_i] <= write_data_i;
        end
    end

    assign read_data1_o = (read_addr1_i == 5'b0) ? 64'b0 : reg_file[read_addr1_i];
    assign read_data2_o = (read_addr2_i == 5'b0) ? 64'b0 : reg_file[read_addr2_i];
endmodule