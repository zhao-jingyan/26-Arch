`include "include/common.sv"

import "DPI-C" function int get_switch();

// latency
`define LATENCY
`ifndef RANDOMIZE_DELAY
/* verilator lint_off REDEFMACRO */
`define RANDOMIZE_DELAY 3
`endif

`define IDX(addr) (addr > 64'h8000_0000 ? ((addr - 64'h8000_0000) >> 3) : 0)

/* verilator lint_off WIDTH */

module RAMHelper2 import common::*;
(
	input logic clk, reset,
	input cbus_req_t  oreq,
	output  cbus_resp_t oresp,
	output logic trint, swint, exint
);

import "DPI-C" function void sd_read64(
	input  longint addr,
	output longint data
);

import "DPI-C" function void sd_write64(
	input longint addr,
	input longint data,
	input byte    strobe
);

// 从仿真宿主 stdin 非阻塞读一字节；无输入返回 -1
import "DPI-C" function int mmio_uart_rx();

localparam u64 SDCARD_ADDR_REG = 64'h4060_1000;
localparam u64 SDCARD_DATA_REG = 64'h4060_1008;

// UART 接收寄存器：读返回 {valid, 55'b0, char[7:0]}，读即消费
localparam u64 UART_RX_REG = 64'h4060_0010;

task automatic check_req_modification(cbus_req_t req, cbus_req_t saved_req);
	if (req.valid != saved_req.valid || 
		req.is_write != saved_req.is_write ||
		req.size != saved_req.size ||
		req.addr != saved_req.addr ||
		req.len != saved_req.len ||
		req.burst != saved_req.burst) begin
		$display("ERROR: Unexpected CBus request modification.\n");
		$finish();
	end
endtask

	cbus_req_t saved_oreq;
	enum i2 {NONE, WAIT, READ, WRITE} state;
	i8 count_down;
	i4 size;
	addr_t addr, idx, wrap1, wrap2;
	longint cyc_cnt, ms_cnt;
	assign idx = `IDX(addr);
	u64 wmask;
	u64 saved_wmask;
	for (genvar i = 0; i < 8; i++) begin
		assign wmask[i * 8 + 7 -: 8] = {8{oreq.strobe[i]}};
		assign saved_wmask[i * 8 + 7 -: 8] = {8{saved_oreq.strobe[i]}};
	end

	u64 mtime, mtimecmp;
	logic msip;
	u64 sdcard_addr;
	u64 sdcard_data;

	u8    uart_rx_char;
	logic uart_rx_valid;
	int   uart_rx_poll;

	always_ff @(posedge clk) begin
		if (~reset) begin
			if (cyc_cnt == 25) begin
				ms_cnt <= ms_cnt + 1;
				mtime <= mtime + 1;
				cyc_cnt <= 0;
				// 周期性从 stdin 取一字符（不阻塞），缓存供 UART_RX 读取
				if (!uart_rx_valid) begin
					uart_rx_poll = mmio_uart_rx();
					if (uart_rx_poll >= 0) begin
						uart_rx_char  <= uart_rx_poll[7:0];
						uart_rx_valid <= 1'b1;
					end
				end
			end else begin
				cyc_cnt <= cyc_cnt + 1;
			end
			trint <= mtime > mtimecmp;
			swint <= msip;
			exint <= uart_rx_valid;  // 有待读字符时拉高外部中断
			unique case (state)
			NONE: begin
				if (oreq.valid) begin
					saved_oreq <= oreq;
					if (count_down == 0) begin
						if (oreq.is_write) begin
							unique case (oreq.addr)
							64'h40600004: if (oreq.strobe[4]) begin
								$fwrite(32'h8000_0001, "%c", oreq.data[39:32]); // stdout
								$fflush(32'h8000_0001);
							end
							64'h23333000: if (oreq.data == 64'h233 && oreq.strobe == '1) $display("Pass!");
							64'h38000000: msip <= oreq.data[0];
							64'h38004000: mtimecmp <= oreq.data;
							64'h3800bff8: mtime <= oreq.data;
							SDCARD_ADDR_REG: begin
								sdcard_addr <= oreq.data;
							end
							SDCARD_DATA_REG: begin
								sd_write64(sdcard_addr, oreq.data, oreq.strobe);
								sdcard_addr <= sdcard_addr + 64'd8;
							end
							default: if (addr != 64'h4060000c) ram_write_helper(`IDX(oreq.addr), oreq.data, wmask, '1);
							endcase
							count_down <= {$random()} % `RANDOMIZE_DELAY;
						end else begin
							if (oreq.addr == SDCARD_DATA_REG)
								sd_read64(sdcard_addr, sdcard_data);
							if (`IDX(oreq.addr) >= 'h10000000) begin
								$display("ERROR: Load address %x out of range!\n", oreq.addr);
								$finish;
							end
							count_down <= {$random()} % `RANDOMIZE_DELAY;
						end
					end else begin
						count_down <= count_down - 1;
						state <= WAIT;
					end				
				end
			end
			WAIT: begin
				check_req_modification(oreq, saved_oreq);
				unique if (count_down == 0) begin
					state <= oreq.is_write ? WRITE : READ;
					addr <= oreq.addr;
					if (!oreq.is_write && oreq.addr == SDCARD_DATA_REG)
						sd_read64(sdcard_addr, sdcard_data);
					count_down <= oreq.len;
					size <= 1 << oreq.size;
					unique case (oreq.burst)
					AXI_BURST_FIXED: begin
						wrap1 <= oreq.addr;
						wrap2 <= oreq.addr + (1 << oreq.size);
					end
					AXI_BURST_WRAP: begin
						wrap1 <= oreq.addr & ~(((64'(oreq.len) + 1) << oreq.size) - 1);
						wrap2 <= (oreq.addr & ~(((64'(oreq.len) + 1) << oreq.size) - 1)) + ((64'(oreq.len) + 1) << oreq.size);
					end
					default: {wrap1, wrap2} <= '0;
					endcase
				end else
					count_down <= count_down - 1;
			end
			READ: begin
				check_req_modification(oreq, saved_oreq);
				if (idx >= 'h10000000) begin
					$display("ERROR: Load address %x out of range!\n", addr);
					$finish;
				end
				unique if (oresp.last) begin
					state <= NONE;
					count_down <= {$random()} % `RANDOMIZE_DELAY;
				end else begin
					count_down <= count_down - 1;
					addr <= (addr + size == wrap2) ? wrap1 : addr + size;
				end
			end
			WRITE: begin
				check_req_modification(oreq, saved_oreq);
				unique case (addr)
				64'h40600004: if (saved_oreq.strobe[4]) begin
					$fwrite(32'h8000_0001, "%c", saved_oreq.data[39:32]); // stdout
					$fflush(32'h8000_0001);
				end
				64'h23333000: if (saved_oreq.data == 64'h233 && saved_oreq.strobe == '1) $display("Pass!");
				64'h38000000: msip <= saved_oreq.data[0];
				64'h38004000: mtimecmp <= saved_oreq.data;
				64'h3800bff8: mtime <= saved_oreq.data;
				SDCARD_ADDR_REG: begin
					sdcard_addr <= saved_oreq.data;
				end
				SDCARD_DATA_REG: begin
					sd_write64(sdcard_addr, saved_oreq.data, saved_oreq.strobe);
					sdcard_addr <= sdcard_addr + 64'd8;
				end
				default: if (addr != 64'h4060000c) ram_write_helper(idx, saved_oreq.data, saved_wmask, '1);
				endcase
				unique if (oresp.last) begin
					state <= NONE;
					count_down <= {$random()} % `RANDOMIZE_DELAY;
				end else begin
					count_down <= count_down - 1;
					addr <= addr + size;
				end
			end
			endcase

			// UART_RX 读响应交付的当拍消费一个字符（与轮询补充互斥）
			if (uart_rx_valid && oreq.valid && ~oreq.is_write
				&& (oreq.addr == UART_RX_REG) && (count_down == 0)
				&& (state == READ || state == NONE)) begin
				uart_rx_valid <= 1'b0;
			end
		end else begin
			{state, cyc_cnt, ms_cnt, addr, size, saved_oreq} <= '0;
			count_down <= {$random()} % `RANDOMIZE_DELAY;
			mtime <= '0;
			mtimecmp <= '1;
			msip <= '0;
			sdcard_addr <= '0;
			sdcard_data <= '0;
			{trint, swint, exint} <= '0;
			uart_rx_char  <= '0;
			uart_rx_valid <= '0;
		end
	end

	always_comb begin
		oresp = '0;
		unique if (state == READ || (state == NONE && oreq.valid && count_down == 0 && ~oreq.is_write)) begin
			oresp.ready = '1;
			oresp.last = count_down == 0;
			unique case (oreq.addr)
			64'h40600008: oresp.data = '0;
			64'h38000000: oresp.data = {63'b0, msip};
			64'h38004000: oresp.data = mtimecmp;
			64'h3800bff8: oresp.data = mtime;
			SDCARD_ADDR_REG: oresp.data = sdcard_addr;
			SDCARD_DATA_REG: oresp.data = sdcard_data;
			UART_RX_REG: oresp.data = {uart_rx_valid, 55'b0, uart_rx_char};
			64'h20003000: oresp.data = ms_cnt;
			64'h23333008: oresp.data = {'0, get_switch()};
			default: oresp.data = ram_read_helper('1, `IDX(oreq.addr));
			endcase
		end else if (state == WRITE || (state == NONE && oreq.valid && count_down == 0 && oreq.is_write)) begin
			oresp.ready = '1;
			oresp.last = count_down == 0;
		end else
			oresp = '0;
	end

endmodule
