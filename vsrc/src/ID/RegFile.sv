// ----------------------------------------------------------------------------
// File        : RegFile.sv
// Description : 32 x 64-bit 寄存器堆；一写两读，x0 硬 0，附 32 根 gpr 快照
// ----------------------------------------------------------------------------

import common::*;

module RegFile (
    input  logic clk,
    input  logic rst_n,

    input  logic write_en,
    input  u5    write_addr,
    input  u64   write_data,

    input  u5    read_addr_1,
    input  u5    read_addr_2,
    output u64   read_data_1,
    output u64   read_data_2,

    output u64   gpr [0:31]
);

    u64 reg_file [1:31];  // x1..x31，x0 硬连 0

    assign gpr[0] = 64'b0;
    generate
        for (genvar i = 1; i < 32; i++) begin : g_gpr
            assign gpr[i] = reg_file[i];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 1; i < 32; i++) begin
                reg_file[i] <= 64'b0;
            end
        end else if (write_en && |write_addr) begin
            reg_file[write_addr] <= write_data;
        end
    end

    // 组合读含 write-during-read bypass：同周期 WB 写入与 ID 读的 distance-3 RAW 由此覆盖
    assign read_data_1 = (read_addr_1 == 5'b0)                                 ? 64'b0
                       : (write_en && |write_addr && write_addr == read_addr_1) ? write_data
                       :                                                          reg_file[read_addr_1];
    assign read_data_2 = (read_addr_2 == 5'b0)                                 ? 64'b0
                       : (write_en && |write_addr && write_addr == read_addr_2) ? write_data
                       :                                                          reg_file[read_addr_2];

endmodule
