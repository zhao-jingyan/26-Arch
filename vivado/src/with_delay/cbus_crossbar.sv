module cbus_crossbar (
	input logic clk, reset,

	/* From CPU */
	input logic valid,
	input logic [63:0] addr,
	input logic [63:0] wdata,
	input logic [1:0] burst,
	input logic [7:0] len,
	input logic [7:0] wstrobe,
	output logic [63:0] rdata,
	output logic ready,
	output logic last,

	/* To RAM */
	output logic ram_valid,
	output logic [63:0] ram_addr,
	output logic [63:0] ram_wdata,
	output logic [1:0] ram_burst,
	output logic [7:0] ram_len,
	output logic [7:0] ram_wstrobe,
	input logic [63:0] ram_rdata,
	input logic ram_ready,
	input logic ram_last,

	/* To Device */
	output logic device_valid,
	output logic [63:0] device_addr,
	output logic [63:0] device_wdata,
	output logic device_wvalid,
	input logic [63:0] device_rdata,
	input logic device_ready,
	input logic device_last
);
	logic pending;
	logic pending_ram;
	logic [63:0] pending_addr;
	logic [63:0] pending_wdata;
	logic [1:0] pending_burst;
	logic [7:0] pending_len;
	logic [7:0] pending_wstrobe;

	logic select_ram;
	logic [63:0] req_addr;
	logic [63:0] req_wdata;
	logic [1:0] req_burst;
	logic [7:0] req_len;
	logic [7:0] req_wstrobe;
	logic active_valid;
	logic complete;

	// 板上 BRAM/device 可能多拍返回，必须锁存一次 transaction 的路由与请求字段。
	// 否则等待期间上游 addr 变化会把 RAM 响应错选成 device 响应，仿真短延迟不易暴露。
	assign select_ram  = pending ? pending_ram : addr[31];
	assign req_addr    = pending ? pending_addr : addr;
	assign req_wdata   = pending ? pending_wdata : wdata;
	assign req_burst   = pending ? pending_burst : burst;
	assign req_len     = pending ? pending_len : len;
	assign req_wstrobe = pending ? pending_wstrobe : wstrobe;
	assign active_valid = pending || valid;

	assign rdata = select_ram ? ram_rdata : device_rdata;
	assign ready = select_ram ? ram_ready : device_ready;
	assign last = select_ram ? ram_last : device_last;
	assign complete = ready && last;

	assign ram_valid = select_ram && active_valid;
	assign ram_addr = req_addr;
	assign ram_wdata = req_wdata;
	assign ram_burst = req_burst;
	assign ram_len = req_len;
	assign ram_wstrobe = req_wstrobe;
	
	assign device_valid = ~select_ram && active_valid;
	assign device_addr = req_addr;
	assign device_wdata = req_wdata;
	assign device_wvalid = |req_wstrobe;

	always_ff @(posedge clk) begin
		if (reset) begin
			pending <= 1'b0;
			pending_ram <= 1'b0;
			pending_addr <= 64'b0;
			pending_wdata <= 64'b0;
			pending_burst <= 2'b0;
			pending_len <= 8'b0;
			pending_wstrobe <= 8'b0;
		end
		else if (pending) begin
			if (complete) begin
				pending <= 1'b0;
			end
		end
		else if (valid && !complete) begin
			pending <= 1'b1;
			pending_ram <= addr[31];
			pending_addr <= addr;
			pending_wdata <= wdata;
			pending_burst <= burst;
			pending_len <= len;
			pending_wstrobe <= wstrobe;
		end
	end
	
endmodule
