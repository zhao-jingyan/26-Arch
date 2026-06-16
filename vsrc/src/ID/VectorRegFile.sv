// ----------------------------------------------------------------------------
// File        : VectorRegFile.sv
// Description : 32 x VLEN 向量寄存器堆；提供三读一写和独立 mask 读视图
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import V_PKG::*;

module VectorRegFile (
    input  logic  clk,
    input  logic  rst_n,

    input  VREG_WRITE write,

    input  u5     read_addr_1,
    input  u5     read_addr_2,
    input  u5     read_addr_3,
    input  u5     mask_addr,
    output vreg_t read_data_1,
    output vreg_t read_data_2,
    output vreg_t read_data_3,
    output vreg_t mask_data
);

    vreg_t vreg_file [0:VREG_NUM-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < VREG_NUM; i++) begin
                vreg_file[i] <= '0;
            end
        end else if (write.write_en) begin
            vreg_file[write.write_addr] <= write.write_data;
        end
    end

    // 向量寄存器没有 x0 语义；同周期读写相同寄存器时采用写优先旁路。
    assign read_data_1 = (write.write_en && (write.write_addr == read_addr_1)) ? write.write_data : vreg_file[read_addr_1];
    assign read_data_2 = (write.write_en && (write.write_addr == read_addr_2)) ? write.write_data : vreg_file[read_addr_2];
    assign read_data_3 = (write.write_en && (write.write_addr == read_addr_3)) ? write.write_data : vreg_file[read_addr_3];
    assign mask_data   = (write.write_en && (write.write_addr == mask_addr))   ? write.write_data : vreg_file[mask_addr];

endmodule
