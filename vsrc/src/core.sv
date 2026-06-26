`ifndef __CORE_SV
`define __CORE_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`include "src/Top.sv"
`endif

module core import common::*; import top_pkg::*; import CSR_PKG::*; (
	input  logic       clk, reset,
	output ibus_req_t  ireq,
	input  ibus_resp_t iresp,
	output dbus_req_t  dreq,
	input  dbus_resp_t dresp,
	output CSR_STATE   csr_state_o,
	output PRIV_MODE   priv_mode_o,
	output PRIV_MODE   mmu_priv_mode_o,
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
	logic       commit_sc_failed;
	logic       commit_skip;
	word_t      gpr [0:31];
	CSR_STATE   csr_state;
	PRIV_MODE   priv_mode;
	PRIV_MODE   mmu_priv_mode;

	Top u_top (
		.clk            ( clk ),
		.rst_n          ( rst_n ),
		.trint          ( trint ),
		.swint          ( swint ),
		.exint          ( exint ),
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
		.commit_sc_failed_o ( commit_sc_failed ),
		.commit_skip_o  ( commit_skip ),
		.gpr_o          ( gpr ),
		.csr_state_o    ( csr_state ),
		.priv_mode_o    ( priv_mode ),
		.mmu_priv_mode_o( mmu_priv_mode )
	);

	assign csr_state_o      = csr_state;
	assign priv_mode_o      = priv_mode;
	assign mmu_priv_mode_o  = mmu_priv_mode;

`ifdef VERILATOR
	word_t difftest_last_pc;
	word_t difftest_cycle_cnt;
	word_t difftest_instr_cnt;

	always_ff @(posedge clk) begin
		if (reset) begin
			difftest_last_pc    <= 64'b0;
			difftest_cycle_cnt  <= 64'b0;
			difftest_instr_cnt  <= 64'b0;
		end else begin
			difftest_cycle_cnt <= difftest_cycle_cnt + 64'b1;
			if (commit_valid) begin
				difftest_last_pc   <= commit_pc;
				difftest_instr_cnt <= difftest_instr_cnt + 64'b1;
			end
		end
	end

	DifftestInstrCommit DifftestInstrCommit(
		.clock              (clk),
		.coreid             (0),              // 无需改动
		.index              (0),              // 无需改动
		.valid              (commit_valid),   // 0 代表无提交
		.pc                 (commit_pc),      // 这条指令的 pc
		.instr              (commit_instr),   // 这条指令的内容
		.skip               (commit_skip),   // load/store 打到外设 MMIO 区（addr[31]==0）时跳过 Difftest 对账
		.isRVC              (0),              // 无需改动
		.scFailed           (commit_sc_failed),
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
		.pc                 (difftest_last_pc),
		.cycleCnt           (difftest_cycle_cnt),
		.instrCnt           (difftest_instr_cnt)
	);

	// sstatus 是 mstatus 的子集视图，掩码与 CSR_PKG.SSTATUS_MASK 一致
	word_t sstatus;
	assign sstatus = csr_state.mstatus & SSTATUS_MASK;

	DifftestCSRState DifftestCSRState(
		.clock              (clk),
		.coreid             (0),
		.priviledgeMode     (priv_mode),
		.mstatus            (csr_state.mstatus),
		.sstatus            (sstatus),
		.mepc               (csr_state.mepc),
		.sepc               (csr_state.sepc),
		.mtval              (csr_state.mtval),
		.stval              (csr_state.stval),
		.mtvec              (csr_state.mtvec),
		.stvec              (csr_state.stvec),
		.mcause             (csr_state.mcause),
		.scause             (csr_state.scause),
		.satp               (csr_state.satp),
		.mip                (csr_state.mip),
		.mie                (csr_state.mie),
		.mscratch           (csr_state.mscratch),
		.sscratch           (csr_state.sscratch),
		.mideleg            (csr_state.mideleg),
		.medeleg            (csr_state.medeleg)
	);
`endif
endmodule
`endif
