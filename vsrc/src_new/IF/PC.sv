// ----------------------------------------------------------------------------
// File        : PC.sv
// Description : 程序计数器；优先级 rst_n > pc_should_jump > stall > 自增
// ----------------------------------------------------------------------------

import common::*;

module PC (
    input  logic clk,
    input  logic rst_n,

    input  logic stall,
    input  logic pc_should_jump,
    input  u64   pc_jump_address,

    output u64   pc_inst_address
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_inst_address <= PCINIT;
        else if (pc_should_jump)
            pc_inst_address <= pc_jump_address;
        else if (stall)
            pc_inst_address <= pc_inst_address;
        else
            pc_inst_address <= pc_inst_address + 64'd4;
    end

endmodule
