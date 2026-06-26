// ----------------------------------------------------------------------------
// File        : Scoreboard_Unit.sv
// Description : 整数 GPR 记分板（保守版）
//               1. load/AMO 的 EX→ID RAW 仍通过冻结 IF/ID + 注 bubble 解决
//               2. 乘除法当前仍占住 EX 槽，busy 期间全流水冻结；这里先把依赖关系集中表达
//               3. CSR / vset* / vector-vx 在 ID 直读 GPR，不能依赖 EX forward，需等写者到 WB
//               本模块暂不改变按序发射/按序提交语义，是后续独立乘除单元/LSQ 的控制边界
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/ID_PKG.sv"
`include "src/EX/EX_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import ID_PKG::*;
import EX_PKG::*;

module Scoreboard_Unit (
    input  ID_2_CTRL  id_2_ctrl,
    input  EX_2_CTRL  ex_2_ctrl,
    input  MEM_2_CTRL mem_2_ctrl,
    input  CSR_WRITE  ex_csr_write,
    input  CSR_WRITE  mem_csr_write,

    output SCOREBOARD_2_CTRL scoreboard_2_ctrl
);

    logic id_uses_rs1;
    logic id_uses_rs2;

    // 保守策略：当前 Decoder 没有透出精确 rs 使用位，先按 rs1/rs2 非零作为可能使用。
    // 对立即数类指令会多停一点，但不会错误放行等待中的 RAW。
    assign id_uses_rs1 = (id_2_ctrl.rs1_addr != 5'b0);
    assign id_uses_rs2 = (id_2_ctrl.rs2_addr != 5'b0);

    logic ex_writes_rd;
    logic mem_writes_rd;
    assign ex_writes_rd  = (ex_2_ctrl.rd_addr  != 5'b0);
    assign mem_writes_rd = (mem_2_ctrl.rd_addr != 5'b0);

    // load/AMO 在 EX 段时，EX forward 给出的还是地址/中间结果，不能给消费者使用。
    // 乘除法 busy 期间结果也尚未可用；虽然当前全流水会冻结，这里先保留统一入口。
    logic ex_result_not_forwardable;
    assign ex_result_not_forwardable = ex_2_ctrl.is_ex_load
                                    || ex_2_ctrl.is_alu_busy;

    logic ex_raw_hazard;
    assign ex_raw_hazard = ex_result_not_forwardable
                         && ex_writes_rd
                         && (  (id_uses_rs1 && (ex_2_ctrl.rd_addr == id_2_ctrl.rs1_addr))
                            || (id_uses_rs2 && (ex_2_ctrl.rd_addr == id_2_ctrl.rs2_addr)));

    // CSR / vset* / vector-vx 在 ID 段直接读取 RegFile，不能吃 EX/MEM forward。
    logic id_direct_uses_rs1;
    logic id_direct_uses_rs2;
    assign id_direct_uses_rs1 = (id_2_ctrl.is_csr && !id_2_ctrl.is_csr_imm)
                             || (id_2_ctrl.is_vset && !id_2_ctrl.is_vset_imm)
                             || id_2_ctrl.is_vector_vx;
    assign id_direct_uses_rs2 = id_2_ctrl.is_vset_rs2;

    logic id_direct_rs1_hazard;
    logic id_direct_rs2_hazard;
    assign id_direct_rs1_hazard = id_direct_uses_rs1
                               && (id_2_ctrl.rs1_addr != 5'b0)
                               && (  (ex_writes_rd  && (ex_2_ctrl.rd_addr  == id_2_ctrl.rs1_addr))
                                  || (mem_writes_rd && (mem_2_ctrl.rd_addr == id_2_ctrl.rs1_addr)));
    assign id_direct_rs2_hazard = id_direct_uses_rs2
                               && (id_2_ctrl.rs2_addr != 5'b0)
                               && (  (ex_writes_rd  && (ex_2_ctrl.rd_addr  == id_2_ctrl.rs2_addr))
                                  || (mem_writes_rd && (mem_2_ctrl.rd_addr == id_2_ctrl.rs2_addr)));

    assign scoreboard_2_ctrl.gpr_raw_hazard      = ex_raw_hazard;
    assign scoreboard_2_ctrl.id_direct_rs_hazard = id_direct_rs1_hazard || id_direct_rs2_hazard;
    assign scoreboard_2_ctrl.csr_state_hazard    = id_2_ctrl.is_csr
                                                && (ex_csr_write.write_en || mem_csr_write.write_en);

endmodule
