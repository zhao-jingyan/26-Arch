// ----------------------------------------------------------------------------
// File        : Forward_Unit.sv
// Description : v2 转发单元：RAW 数据冒险解析（纯组合）
//               优先级 EX_2_FWD > MEM_2_FWD > id_2_fwd 原值（越新越优先）
//               覆盖 distance-1/2 RAW；distance-3 由 RegFile write-during-read bypass 覆盖
//               load-use（EX 位是 load 的 distance-1）由 Control_Unit 注入 bubble + 冻结
//               IF/ID 化为 distance-2，下一拍走 MEM_2_FWD 路径
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`endif

import common::*;
import top_pkg::*;

module Forward_Unit (
    input  ID_2_FWD  id_2_fwd,
    input  EX_2_FWD  ex_2_fwd,
    input  MEM_2_FWD mem_2_fwd,

    output FWD_2_EX  fwd_2_ex
);

    logic hit_ex_rs1;
    logic hit_mem_rs1;
    logic hit_ex_rs2;
    logic hit_mem_rs2;

    assign hit_ex_rs1  = (id_2_fwd.rs1_addr != 5'b0)
                      && (ex_2_fwd.rd_addr  == id_2_fwd.rs1_addr);
    assign hit_mem_rs1 = (id_2_fwd.rs1_addr != 5'b0)
                      && (mem_2_fwd.rd_addr == id_2_fwd.rs1_addr);

    assign hit_ex_rs2  = (id_2_fwd.rs2_addr != 5'b0)
                      && (ex_2_fwd.rd_addr  == id_2_fwd.rs2_addr);
    assign hit_mem_rs2 = (id_2_fwd.rs2_addr != 5'b0)
                      && (mem_2_fwd.rd_addr == id_2_fwd.rs2_addr);

    assign fwd_2_ex.rs1_data = hit_ex_rs1  ? ex_2_fwd.ex_result
                             : hit_mem_rs1 ? mem_2_fwd.rd_data
                             :               id_2_fwd.rs1_data;

    assign fwd_2_ex.rs2_data = hit_ex_rs2  ? ex_2_fwd.ex_result
                             : hit_mem_rs2 ? mem_2_fwd.rd_data
                             :               id_2_fwd.rs2_data;

endmodule
