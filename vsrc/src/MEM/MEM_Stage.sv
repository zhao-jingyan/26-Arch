// ----------------------------------------------------------------------------
// File        : MEM_Stage.sv
// Description : MEM Stage 顶层：装配 Fetch_Data；rd mux；末尾落 MEM/WB 流水寄存器
//               is_mem_ready 为裸端口反馈忙状态，未来并入控制层
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/ID_PKG.sv"
`include "src/MEM/Fetch_Data.sv"
`include "src/ID/CSR_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import ID_PKG::*;
import CSR_PKG::*;

module MEM_Stage (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       stall,
    input  logic       flush,

    input  INST_CTX    inst_ctx_in,
    input  TRAP_CTX    trap_ctx_in,
    input  EX_2_MEM    ex_2_mem,
    input  CSR_WRITE   csr_write_in,
    input  logic       kill_new_req,

    output INST_CTX    inst_ctx_out,
    output TRAP_CTX    trap_ctx_out,
    output MEM_2_WB    mem_2_wb,
    output MEM_2_FWD   mem_2_fwd,
    output MEM_2_CTRL  mem_2_ctrl,
    output CSR_WRITE   csr_write_out,

    output logic       is_mem_ready,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    logic is_load;
    logic is_store;
    logic is_atomic;
    u3    funct3;
    logic load_misalign;
    logic store_misalign;
    logic atomic_misalign;
    logic is_mem_exc;
    logic atomic_busy;
    logic sc_failed_w;
    TRAP_CTX trap_ctx_next;

    assign is_load  = (inst_ctx_in.opcode == OP_LOAD);
    assign is_store = (inst_ctx_in.opcode == OP_STORE);
    assign is_atomic = (inst_ctx_in.opcode == OP_AMO);
    assign funct3   = inst_ctx_in.inst[14:12];

    always_comb begin
        load_misalign  = 1'b0;
        store_misalign = 1'b0;
        atomic_misalign = 1'b0;
        if (is_load) begin
            unique case (funct3)
                3'b001: load_misalign = ex_2_mem.ex_result[0];
                3'b010: load_misalign = |ex_2_mem.ex_result[1:0];
                3'b011: load_misalign = |ex_2_mem.ex_result[2:0];
                default: load_misalign = 1'b0;
            endcase
        end
        if (is_store) begin
            unique case (funct3)
                3'b001: store_misalign = ex_2_mem.ex_result[0];
                3'b010: store_misalign = |ex_2_mem.ex_result[1:0];
                3'b011: store_misalign = |ex_2_mem.ex_result[2:0];
                default: store_misalign = 1'b0;
            endcase
        end
        if (is_atomic) begin
            atomic_misalign = |ex_2_mem.ex_result[1:0];
        end
    end

    always_comb begin
        trap_ctx_next = trap_ctx_in;
        if (load_misalign) begin
            trap_ctx_next.exc_valid = 1'b1;
            trap_ctx_next.exc_cause = MCAUSE_LOAD_MISALIGN;
            trap_ctx_next.exc_tval  = ex_2_mem.ex_result;
        end else if (store_misalign) begin
            trap_ctx_next.exc_valid = 1'b1;
            trap_ctx_next.exc_cause = MCAUSE_STORE_MISALIGN;
            trap_ctx_next.exc_tval  = ex_2_mem.ex_result;
        end else if (atomic_misalign) begin
            trap_ctx_next.exc_valid = 1'b1;
            trap_ctx_next.exc_cause = (ex_2_mem.amo_op == AMO_OP_LR) ? MCAUSE_LOAD_MISALIGN
                                                                     : MCAUSE_STORE_MISALIGN;
            trap_ctx_next.exc_tval  = ex_2_mem.ex_result;
        end
    end

    assign is_mem_exc = trap_ctx_next.exc_valid;

    u64 load_data;

    Fetch_Data u_fetch_data (
        .clk             ( clk ),
        .rst_n           ( rst_n ),

        .pc_inst_address ( inst_ctx_in.pc_inst_address ),
        .inst            ( inst_ctx_in.inst ),
        .mem_addr        ( ex_2_mem.ex_result ),
        .funct3          ( funct3 ),
        .is_load         ( is_load && !is_mem_exc ),
        .is_store        ( is_store && !is_mem_exc ),
        .amo_op          ( (is_atomic && !is_mem_exc) ? ex_2_mem.amo_op : AMO_OP_NONE ),
        .store_data      ( ex_2_mem.rs2_data ),
        .kill_new_req    ( kill_new_req ),

        .load_data       ( load_data ),
        .is_mem_ready    ( is_mem_ready ),
        .atomic_busy     ( atomic_busy ),
        .sc_failed       ( sc_failed_w ),

        .dbus_request    ( dbus_request ),
        .dbus_response   ( dbus_response )
    );

    // rd 写回数据 mux：load → 对齐后的 load_data；其他 → ex_result
    u64 rd_data;
    assign rd_data = (is_load || is_atomic) ? load_data : ex_2_mem.ex_result;

    // MEM/WB 流水寄存器：!stall && is_mem_ready 时前进；复位清零
    // csr_write 与 inst_ctx 同 latch 节奏，原样透传到 WB 段
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx_out  <= '0;
            trap_ctx_out  <= '0;
            mem_2_wb      <= '0;
            csr_write_out <= '0;
        end
        else if (flush) begin
            inst_ctx_out  <= '0;
            trap_ctx_out  <= '0;
            mem_2_wb      <= '0;
            csr_write_out <= '0;
        end
        else if (!stall && is_mem_ready) begin
            inst_ctx_out      <= inst_ctx_in;
            trap_ctx_out      <= trap_ctx_next;
            mem_2_wb.rd_data  <= rd_data;
            mem_2_wb.mem_addr <= ex_2_mem.ex_result;  // 供 commit 层做 Difftest skip 判定
            mem_2_wb.sc_failed <= sc_failed_w;
            csr_write_out     <= csr_write_in;
        end
    end

    // MEM → FWD：MEM/WB 寄存器 tap，供 distance-2 RAW forward
    assign mem_2_fwd.rd_addr = inst_ctx_out.rd_addr;
    assign mem_2_fwd.rd_data = mem_2_wb.rd_data;

    // MEM → 控制层：MEM 位指令的 rd（distance-2 写者），供 CSR rs1 hazard 检测
    // 用 inst_ctx_in（EX/MEM 寄存器输出 = MEM 段当拍处理的指令）；
    // inst_ctx_out 是 MEM/WB 寄存器输出 = WB 段指令（distance-3），由 RegFile 内部 bypass 解决，无需 stall
    assign mem_2_ctrl.rd_addr = inst_ctx_in.rd_addr;
    assign mem_2_ctrl.is_atomic_busy = atomic_busy;

endmodule
