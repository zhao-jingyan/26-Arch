`ifndef __MYCPU_TOP_SV
`define __MYCPU_TOP_SV

module mycpu_top
  import common::*;
(
    input logic clk,
    reset,

    output logic valid,
    output logic [63:0] addr,
    output logic [63:0] wdata,
    input logic [63:0] rdata,
    output logic [7:0] wstrobe,
    output logic [1:0] burst,
    output logic [7:0] len,
    output logic [2:0] size,

    input logic ready,
    input logic last
);

  cbus_req_t  oreq;
  cbus_resp_t oresp;
  cbus_req_t  board_req;
  logic       board_busy;

  VTop VTop_inst (
      .clk,
      .reset,
      .oreq,
      .oresp
  );

  // 上板外设/BRAM 返回较慢，请求发出后保持地址和写数据稳定直到响应完成。
  always_ff @(posedge clk) begin
    if (reset) begin
      board_busy <= 1'b0;
      board_req  <= '0;
    end
    else if (board_busy) begin
      if (ready && last) begin
        board_busy <= 1'b0;
        board_req  <= '0;
      end
    end
    else if (oreq.valid) begin
      board_busy <= 1'b1;
      board_req  <= oreq;
    end
  end

  assign valid = board_busy;
  assign addr = board_req.addr;
  assign wdata = board_req.data;
  assign oresp.data = rdata;
  assign wstrobe = board_req.strobe;
  assign burst = board_req.burst;
  assign len = board_req.len;
  assign oresp.ready = ready;
  assign oresp.last = last;
  assign size = board_req.size;

endmodule


`endif
