`ifndef __VTOP_SV
`define __VTOP_SV

`ifdef VERILATOR
`include "include/common.sv"
`include "src/core.sv"
`include "util/IBusToCBus.sv"
`include "util/DBusToCBus.sv"
`include "util/CBusArbiter.sv"
`include "src/MMU/CBusMMU.sv"

`endif
module VTop 
	import common::*;(
	input logic clk, reset,

	output cbus_req_t  oreq,
	input  cbus_resp_t oresp,
	input logic trint, swint, exint
);

    ibus_req_t  ireq;
    ibus_resp_t iresp;
    dbus_req_t  dreq;
    dbus_resp_t dresp;
    CSR_STATE   csr_state;
    PRIV_MODE   priv_mode;
    PRIV_MODE   mmu_priv_mode;
    logic       mmu_fence;

    cbus_req_t  icreq;
    cbus_resp_t icresp;
    cbus_req_t  dcreq;
    cbus_resp_t dcresp;
    cbus_req_t  arb_req;
    cbus_resp_t arb_resp;
    cbus_req_t  arb_ireqs [1:0];
    cbus_resp_t arb_iresps [1:0];

    core core(
        .clk(clk),
        .reset(reset),
        .ireq(ireq),
        .iresp(iresp),
        .dreq(dreq),
        .dresp(dresp),
        .csr_state_o(csr_state),
        .priv_mode_o(priv_mode),
        .mmu_priv_mode_o(mmu_priv_mode),
        .mmu_fence_o(mmu_fence),
        .trint(trint),
        .swint(swint),
        .exint(exint)
    );

    IBusToCBus icvt(.*);
    DBusToCBus dcvt(.*);

    assign arb_ireqs[0] = icreq;
    assign arb_ireqs[1] = dcreq;
    assign icresp       = arb_iresps[0];
    assign dcresp       = arb_iresps[1];

    CBusArbiter #(.NUM_INPUTS(2)) arbiter(
        .clk(clk),
        .reset(reset),
        .ireqs(arb_ireqs),
        .iresps(arb_iresps),
        .oreq(arb_req),
        .oresp(arb_resp)
    );

    CBusMMU mmu(
        .clk(clk),
        .reset(reset),
        .upstream_request(arb_req),
        .upstream_response(arb_resp),
        .downstream_request(oreq),
        .downstream_response(oresp),
        .satp(csr_state.satp),
        .priv_mode(mmu_priv_mode),
        .flush_req(mmu_fence)
    );

	always_ff @(posedge clk) begin
		if (~reset) begin
			// $display("icreq %x, %x", icreq.valid, icreq.addr);
			// if (oreq.valid || dcreq.addr == 64'h40600004) $display("dcreq %x, %x, oreq %x, %x, dcresp %x", dcreq.addr, dcreq.valid, oreq.valid, oreq.addr, dcresp.ready);
		end
	end
	

endmodule



`endif
