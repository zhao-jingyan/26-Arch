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
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import ID_PKG::*;
import CSR_PKG::*;
import V_PKG::*;

module MEM_Stage (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       stall,
    input  logic       flush,

    input  INST_CTX    inst_ctx_in,
    input  TRAP_CTX    trap_ctx_in,
    input  EX_2_MEM    ex_2_mem,
    input  CSR_WRITE   csr_write_in,
    input  V_WRITE     vcsr_write_in,
    input  logic       kill_new_req,

    output INST_CTX    inst_ctx_out,
    output TRAP_CTX    trap_ctx_out,
    output MEM_2_WB    mem_2_wb,
    output MEM_2_FWD   mem_2_fwd,
    output MEM_2_CTRL  mem_2_ctrl,
    output CSR_WRITE   csr_write_out,
    output V_WRITE     vcsr_write_out,

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
    logic is_vmem;
    logic vmem_busy;
    logic vmem_done;
    logic scalar_is_mem_ready;
    dbus_req_t scalar_dbus_req;
    dbus_req_t vector_dbus_req;
    dbus_resp_t scalar_dbus_resp;
    TRAP_CTX trap_ctx_next;

    assign is_load  = (inst_ctx_in.opcode == OP_LOAD);
    assign is_store = (inst_ctx_in.opcode == OP_STORE);
    assign is_atomic = (inst_ctx_in.opcode == OP_AMO);
    assign funct3   = inst_ctx_in.inst[14:12];
    assign is_vmem  = ex_2_mem.vmem.valid;
    assign scalar_dbus_resp = is_vmem ? '0 : dbus_response;

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
        end else if ((is_load || is_store || is_atomic) && dbus_response.exc_valid) begin
            trap_ctx_next.exc_valid = 1'b1;
            trap_ctx_next.exc_cause = dbus_response.exc_cause;
            trap_ctx_next.exc_tval  = dbus_response.exc_tval;
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
        .is_load         ( is_load && !is_mem_exc && !is_vmem ),
        .is_store        ( is_store && !is_mem_exc && !is_vmem ),
        .amo_op          ( (is_atomic && !is_mem_exc && !is_vmem) ? ex_2_mem.amo_op : AMO_OP_NONE ),
        .store_data      ( ex_2_mem.rs2_data ),
        .kill_new_req    ( kill_new_req ),

        .load_data       ( load_data ),
        .is_mem_ready    ( scalar_is_mem_ready ),
        .atomic_busy     ( atomic_busy ),
        .sc_failed       ( sc_failed_w ),

        .dbus_request    ( scalar_dbus_req ),
        .dbus_response   ( scalar_dbus_resp )
    );

    // rd 写回数据 mux：load → 对齐后的 load_data；其他 → ex_result
    u64 rd_data;
    assign rd_data = (is_load || is_atomic) ? load_data : ex_2_mem.ex_result;

    typedef enum logic [1:0] {
        VM_IDLE,
        VM_REQ,
        VM_DONE
    } VM_STATE;

    VM_STATE vmem_state;
    u64      vmem_idx;
    vreg_t   vmem_load_data;

    function automatic u64 vmem_read_elem(input vreg_t data, input u64 idx);
        int elem_index;
        begin
            elem_index = int'(idx);
            vmem_read_elem = data[elem_index * 64 +: 64];
        end
    endfunction

    function automatic vreg_t vmem_write_elem(input vreg_t data, input u64 idx, input u64 value);
        vreg_t next_data;
        int elem_index;
        begin
            elem_index = int'(idx);
            next_data = data;
            next_data[elem_index * 64 +: 64] = value;
            vmem_write_elem = next_data;
        end
    endfunction

    assign vmem_busy = is_vmem && (vmem_state != VM_DONE);
    assign vmem_done = is_vmem && (vmem_state == VM_DONE);

    always_comb begin
        vector_dbus_req.valid  = is_vmem && (vmem_state == VM_REQ);
        vector_dbus_req.addr   = ex_2_mem.ex_result + (vmem_idx << 3);
        vector_dbus_req.size   = MSIZE8;
        vector_dbus_req.strobe = ex_2_mem.vmem.is_store ? 8'hff : 8'h00;
        vector_dbus_req.data   = vmem_read_elem(ex_2_mem.vmem.store_data, vmem_idx);
    end

    assign dbus_request = is_vmem ? vector_dbus_req : scalar_dbus_req;

    // MEM/WB 流水寄存器：!stall && is_mem_ready 时前进；复位清零
    // csr_write 与 inst_ctx 同 latch 节奏，原样透传到 WB 段
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx_out  <= '0;
            trap_ctx_out  <= '0;
            mem_2_wb      <= '0;
            csr_write_out <= '0;
            vcsr_write_out <= '0;
        end
        else if (flush) begin
            inst_ctx_out  <= '0;
            trap_ctx_out  <= '0;
            mem_2_wb      <= '0;
            csr_write_out <= '0;
            vcsr_write_out <= '0;
        end
        else if (!stall && is_mem_ready) begin
            inst_ctx_out      <= inst_ctx_in;
            trap_ctx_out      <= trap_ctx_next;
            mem_2_wb.rd_data  <= rd_data;
            mem_2_wb.mem_addr <= ex_2_mem.ex_result;  // 供 commit 层做 Difftest skip 判定
            mem_2_wb.sc_failed <= sc_failed_w;
            mem_2_wb.vex_2_vwb <= is_vmem
                                ? '{write_en: ex_2_mem.vmem.is_load,
                                    vd:       ex_2_mem.vmem.vd,
                                    result:   vmem_load_data}
                                : ex_2_mem.vex_2_vwb;
            csr_write_out     <= csr_write_in;
            vcsr_write_out    <= vcsr_write_in;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vmem_state     <= VM_IDLE;
            vmem_idx       <= 64'b0;
            vmem_load_data <= '0;
        end
        else if (flush || kill_new_req) begin
            vmem_state     <= VM_IDLE;
            vmem_idx       <= 64'b0;
            vmem_load_data <= '0;
        end
        else begin
            unique case (vmem_state)
                VM_IDLE: begin
                    if (is_vmem) begin
                        vmem_idx       <= 64'b0;
                        vmem_load_data <= ex_2_mem.vmem.store_data;
                        if (ex_2_mem.vmem.state.vl == 64'b0)
                            vmem_state <= VM_DONE;
                        else
                            vmem_state <= VM_REQ;
                    end
                end

                VM_REQ: begin
                    if (dbus_response.data_ok) begin
                        if (ex_2_mem.vmem.is_load)
                            vmem_load_data <= vmem_write_elem(vmem_load_data, vmem_idx, dbus_response.data);

                        if (vmem_idx + 64'd1 >= ex_2_mem.vmem.state.vl)
                            vmem_state <= VM_DONE;
                        else
                            vmem_idx <= vmem_idx + 64'd1;
                    end
                end

                VM_DONE: begin
                    if (!stall)
                        vmem_state <= VM_IDLE;
                end

                default: vmem_state <= VM_IDLE;
            endcase
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
    assign mem_2_ctrl.is_vwrite = ex_2_mem.vex_2_vwb.write_en
                                || (is_vmem && ex_2_mem.vmem.is_load);
    assign mem_2_ctrl.v_rd_addr = is_vmem ? ex_2_mem.vmem.vd : ex_2_mem.vex_2_vwb.vd;
    assign mem_2_ctrl.is_vcsr_write = vcsr_write_in.write_en;
    assign mem_2_ctrl.is_vmem_busy = vmem_busy;

    assign is_mem_ready = is_vmem ? vmem_done : scalar_is_mem_ready;

endmodule
