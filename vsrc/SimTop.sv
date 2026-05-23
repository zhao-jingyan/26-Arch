`ifdef VERILATOR
`include "include/common.sv"
`include "src/core.sv"
`include "util/IBusToCBus.sv"
`include "util/DBusToCBus.sv"
`include "util/CBusArbiter.sv"
`include "src/MMU/CBusMMU.sv"

module SimTop import common::*;(
  input         clock,
  input         reset,
  input  [63:0] io_logCtrl_log_begin,
  input  [63:0] io_logCtrl_log_end,
  input  [63:0] io_logCtrl_log_level,
  input         io_perfInfo_clean,
  input         io_perfInfo_dump,
  output        io_uart_out_valid,
  output [7:0]  io_uart_out_ch,
  output        io_uart_in_valid,
  input  [7:0]  io_uart_in_ch
);

    cbus_req_t  oreq;
    cbus_resp_t oresp;
    logic trint, swint, exint;

    ibus_req_t  ireq;
    ibus_resp_t iresp;
    dbus_req_t  dreq;
    dbus_resp_t dresp;
    CSR_STATE   csr_state;
    PRIV_MODE   priv_mode;
    PRIV_MODE   mmu_priv_mode;

    cbus_req_t  icreq;
    cbus_resp_t icresp;
    cbus_req_t  dcreq;
    cbus_resp_t dcresp;
    cbus_req_t  arb_req;
    cbus_resp_t arb_resp;
    cbus_req_t  arb_ireqs [1:0];
    cbus_resp_t arb_iresps [1:0];

    core core(
      .clk(clock), .reset,
      .ireq, .iresp,
      .dreq, .dresp,
      .csr_state_o(csr_state),
      .priv_mode_o(priv_mode),
      .mmu_priv_mode_o(mmu_priv_mode),
      .trint, .swint, .exint
    );

    IBusToCBus icvt(.*);
    DBusToCBus dcvt(.*);

    assign arb_ireqs[0] = icreq;
    assign arb_ireqs[1] = dcreq;
    assign icresp       = arb_iresps[0];
    assign dcresp       = arb_iresps[1];

    CBusArbiter #(.NUM_INPUTS(2)) arbiter(
        .clk(clock),
        .reset(reset),
        .ireqs(arb_ireqs),
        .iresps(arb_iresps),
        .oreq(arb_req),
        .oresp(arb_resp)
    );

    CBusMMU mmu(
        .clk(clock),
        .reset(reset),
        .upstream_request(arb_req),
        .upstream_response(arb_resp),
        .downstream_request(oreq),
        .downstream_response(oresp),
        .satp(csr_state.satp),
        .priv_mode(mmu_priv_mode)
    );

    RAMHelper2 ram(
        .clk(clock), .reset, .oreq, .oresp, .trint, .swint, .exint
    );

    assign {io_uart_out_valid, io_uart_out_ch, io_uart_in_valid} = '0;

endmodule
`endif
