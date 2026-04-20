// ----------------------------------------------------------------------------
// File        : WB_Stage.sv
// Description : WB Stage 顶层：纯组合，将 MEM 输出打包成 wb_2_id 送回 ID 写回 RegFile
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`endif

import common::*;
import top_pkg::*;

module WB_Stage (
    input  INST_CTX inst_ctx,
    input  MEM_2_WB mem_2_wb,

    output WB_2_ID  wb_2_id
);

    // rd_addr 为 0（x0 或 Decoder 已清零的 S/B-type）时不写回；
    // RegFile 内部亦会屏蔽 x0 写入，此处预先置 write_en=0 语义更清晰
    assign wb_2_id.write_en   = (inst_ctx.rd_addr != 5'b0);
    assign wb_2_id.write_addr = inst_ctx.rd_addr;
    assign wb_2_id.write_data = mem_2_wb.rd_data;

endmodule
