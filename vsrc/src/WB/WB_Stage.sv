// ----------------------------------------------------------------------------
// File        : WB_Stage.sv
// Description : WB Stage 顶层：纯组合
//               1. 把 MEM 输出打包成 wb_2_id 送回 ID 写回 RegFile
//               2. 把 csr_write 透传为 wb_2_csr 送回 ID Stage 内的 CSRFile 写口
//                  CSR 写时机与该指令自身 commit 同拍，满足 Difftest 一致性
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`endif

import common::*;
import top_pkg::*;

module WB_Stage (
    input  INST_CTX      inst_ctx,
    input  TRAP_CTX      trap_ctx,
    input  MEM_2_WB      mem_2_wb,
    input  CSR_WRITE     csr_write,
    input  logic         commit_valid,

    output WB_2_ID       wb_2_id,
    output CSR_WRITE     wb_2_csr,
    output WB_TRAP_EVENT wb_trap_event
);

    // rd_addr 为 0（x0 或 Decoder 已清零的 S/B-type）时不写回；
    // RegFile 内部亦会屏蔽 x0 写入，此处预先置 write_en=0 语义更清晰
    assign wb_2_id.write_en   = (inst_ctx.rd_addr != 5'b0);
    assign wb_2_id.write_addr = inst_ctx.rd_addr;
    assign wb_2_id.write_data = mem_2_wb.rd_data;

    // CSR 写直通：MEM/WB 寄存器输出当拍即驱动 CSRFile 写口
    assign wb_2_csr = csr_write;

    assign wb_trap_event.is_trap_commit = commit_valid;
    assign wb_trap_event.trap_ctx       = trap_ctx;
    assign wb_trap_event.epc            = inst_ctx.pc_inst_address;

endmodule
