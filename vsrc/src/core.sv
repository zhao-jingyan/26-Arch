`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "src/Top.sv"
`include "src/pipeline_pkg.sv"
`endif

module core import common::*;(
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	input  logic       trint, swint, exint
);

	logic rst_n;
	assign rst_n = ~reset;

	logic       commit_valid;
	word_t      commit_pc;
	logic [31:0] commit_instr;
	logic       commit_wen;
	logic [7:0] commit_wdest;
	word_t      commit_wdata;
	word_t      gpr [0:31];

	Top u_top (
		.clk            ( clk ),
		.rst_n          ( rst_n ),
		.ibus_req_o     ( ireq ),
		.ibus_resp_i    ( iresp ),
		.dbus_req_o     ( dreq ),
		.dbus_resp_i    ( dresp ),
		.commit_valid_o ( commit_valid ),
		.commit_pc_o    ( commit_pc ),
		.commit_instr_o ( commit_instr ),
		.commit_wen_o   ( commit_wen ),
		.commit_wdest_o ( commit_wdest ),
		.commit_wdata_o ( commit_wdata ),
		.gpr_o          ( gpr )
	);

`ifdef VERILATOR
	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),              // 无需改动
		.index              (0),              // 无需改动
		.valid              (commit_valid),   // 0 代表无提交
		.pc                 (commit_pc),      // 这条指令的 pc
		.instr              (commit_instr),   // 这条指令的内容
		.skip               (0),              // 暂时无需改动
		.isRVC              (0),              // 无需改动
		.scFailed           (0),              // 无需改动
		.wen                (commit_wen),     // 是否写入 GPR
		.wdest              (commit_wdest),   // 写入哪个 GPR
		.wdata              (commit_wdata)    // 写入的值
	);

	DifftestArchIntRegState DifftestArchIntRegState (
		.clock              (clk),
		.coreid             (0),
		.gpr_0              (gpr[0]),
		.gpr_1              (gpr[1]),
		.gpr_2              (gpr[2]),
		.gpr_3              (gpr[3]),
		.gpr_4              (gpr[4]),
		.gpr_5              (gpr[5]),
		.gpr_6              (gpr[6]),
		.gpr_7              (gpr[7]),
		.gpr_8              (gpr[8]),
		.gpr_9              (gpr[9]),
		.gpr_10             (gpr[10]),
		.gpr_11             (gpr[11]),
		.gpr_12             (gpr[12]),
		.gpr_13             (gpr[13]),
		.gpr_14             (gpr[14]),
		.gpr_15             (gpr[15]),
		.gpr_16             (gpr[16]),
		.gpr_17             (gpr[17]),
		.gpr_18             (gpr[18]),
		.gpr_19             (gpr[19]),
		.gpr_20             (gpr[20]),
		.gpr_21             (gpr[21]),
		.gpr_22             (gpr[22]),
		.gpr_23             (gpr[23]),
		.gpr_24             (gpr[24]),
		.gpr_25             (gpr[25]),
		.gpr_26             (gpr[26]),
		.gpr_27             (gpr[27]),
		.gpr_28             (gpr[28]),
		.gpr_29             (gpr[29]),
		.gpr_30             (gpr[30]),
		.gpr_31             (gpr[31])
	);

    DifftestTrapEvent DifftestTrapEvent(
		.clock              (clk),
		.coreid             (0),
		.valid              (0),
		.code               (0),
		.pc                 (0),
		.cycleCnt           (0),
		.instrCnt           (0)
	);

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (0),
		.priviledgeMode     (3),
		.mstatus            (0),
		.sstatus            (0 /* mstatus & 64'h800000030001e000 */),
		.mepc               (0),
		.sepc               (0),
		.mtval              (0),
		.stval              (0),
		.mtvec              (0),
		.stvec              (0),
		.mcause             (0),
		.scause             (0),
		.satp               (0),
		.mip                (0),
		.mie                (0),
		.mscratch           (0),
		.sscratch           (0),
		.mideleg            (0),
		.medeleg            (0)
	);
`endif
endmodule
`endif