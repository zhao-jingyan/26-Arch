`ifdef VERILATOR
`include "include/common.sv"
`include "src/core.sv"
`include "util/DBusToCBus.sv"

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

    dbus_req_t  dreq;
    dbus_resp_t dresp;
    cbus_req_t  dcreq;
    cbus_resp_t dcresp;

    core core(
      .clk(clock), .reset, .dreq, .dresp, .trint, .swint, .exint
    );

    DBusToCBus dcvt(.*);
    assign oreq   = dcreq;
    assign dcresp = oresp;

    RAMHelper2 ram(
        .clk(clock), .reset, .oreq, .oresp, .trint, .swint, .exint
    );

    assign {io_uart_out_valid, io_uart_out_ch, io_uart_in_valid} = '0;

endmodule
`endif
