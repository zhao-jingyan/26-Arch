// ----------------------------------------------------------------------------
// File        : Fetch_Data.sv
// Description : 访存单元；普通 load/store + A 扩展 word 原子访存状态机
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/MEM/DataMemory.sv"
`include "src/ID/ID_PKG.sv"
`endif

import common::*;
import ID_PKG::*;

module Fetch_Data (
    input  logic       clk,
    input  logic       rst_n,

    input  u64         pc_inst_address,
    input  u32         inst,
    input  u64         mem_addr,
    input  u3          funct3,
    input  logic       is_load,
    input  logic       is_store,
    input  AMO_OP      amo_op,
    input  u64         store_data,
    input  logic       kill_new_req,

    output u64         load_data,
    output logic       is_mem_ready,
    output logic       atomic_busy,
    output logic       sc_failed,

    output dbus_req_t  dbus_request,
    input  dbus_resp_t dbus_response
);

    logic is_atomic;
    logic is_mem;
    assign is_atomic = (amo_op != AMO_OP_NONE);
    assign is_mem    = is_load || is_store;

    // ------------------------------------------------------------------------
    // 普通 load/store 路径
    // ------------------------------------------------------------------------
    u3       byte_idx;
    msize_t  req_size;
    strobe_t req_strobe;
    u64      req_wdata;
    logic    pending_valid;
    u64      pending_addr;
    msize_t  pending_size;
    strobe_t pending_strobe;
    u64      pending_wdata;
    u3       pending_funct3;
    u3       pending_byte_idx;
    u3       data_byte_idx;
    u3       data_funct3;

    assign byte_idx = mem_addr[2:0];

    assign req_size = (funct3 == 3'b000) ? MSIZE1 :
                      (funct3 == 3'b001) ? MSIZE2 :
                      (funct3 == 3'b010) ? MSIZE4 : MSIZE8;

    always_comb begin
        req_wdata  = 64'b0;
        req_strobe = 8'b0;
        if (is_store) begin
            unique case (funct3)
                3'b000: begin // sb
                    req_wdata  = ({56'b0, store_data[7:0]}  << (byte_idx * 8));
                    req_strobe = (8'b0000_0001 << byte_idx);
                end
                3'b001: begin // sh
                    req_wdata  = ({48'b0, store_data[15:0]} << (byte_idx * 8));
                    req_strobe = (8'b0000_0011 << byte_idx);
                end
                3'b010: begin // sw
                    req_wdata  = ({32'b0, store_data[31:0]} << (byte_idx * 8));
                    req_strobe = (8'b0000_1111 << byte_idx);
                end
                3'b011: begin // sd
                    req_wdata  = store_data;
                    req_strobe = 8'b1111_1111;
                end
                default: ;
            endcase
        end
    end

    u64   response_data;
    logic is_response_valid;
    u64   load_data_shifted;
    u64   load_data_ext;

    assign load_data_shifted = response_data >> (data_byte_idx * 8);

    always_comb begin
        load_data_ext = load_data_shifted;
        unique case (data_funct3)
            3'b000: load_data_ext = {{56{load_data_shifted[7]}},  load_data_shifted[7:0]};
            3'b001: load_data_ext = {{48{load_data_shifted[15]}}, load_data_shifted[15:0]};
            3'b010: load_data_ext = {{32{load_data_shifted[31]}}, load_data_shifted[31:0]};
            3'b011: load_data_ext = load_data_shifted;
            3'b100: load_data_ext = {56'b0, load_data_shifted[7:0]};
            3'b101: load_data_ext = {48'b0, load_data_shifted[15:0]};
            3'b110: load_data_ext = {32'b0, load_data_shifted[31:0]};
            default: load_data_ext = load_data_shifted;
        endcase
    end

    u64   latched_pc;
    u32   latched_inst;
    u64   latched_data;
    logic latched_valid;
    logic is_same_inst;
    logic normal_request_valid;
    logic normal_ready;

    assign is_same_inst = latched_valid
                       && (latched_pc   == pc_inst_address)
                       && (latched_inst == inst);

    assign normal_ready         = !pending_valid && (!is_mem || is_same_inst);
    assign normal_request_valid = !kill_new_req
                               && !is_atomic
                               && (pending_valid || (is_mem && !normal_ready));
    assign data_byte_idx = pending_valid ? pending_byte_idx : byte_idx;
    assign data_funct3   = pending_valid ? pending_funct3   : funct3;

    // ------------------------------------------------------------------------
    // LR/SC reservation set：单核实验中保存最多两个 word 地址
    // ------------------------------------------------------------------------
    logic resv0_valid;
    logic resv1_valid;
    u64   resv0_addr;
    u64   resv1_addr;
    logic reservation_hit;

    assign reservation_hit = (resv0_valid && (resv0_addr == {mem_addr[63:2], 2'b00}))
                          || (resv1_valid && (resv1_addr == {mem_addr[63:2], 2'b00}));

    // ------------------------------------------------------------------------
    // 原子访存路径：读旧值，必要时写新值，完成后一次性让指令离开 MEM
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        AT_IDLE,
        AT_READ,
        AT_WRITE,
        AT_DONE
    } AT_STATE;

    AT_STATE atomic_state;
    AMO_OP   atomic_op_q;
    u64      atomic_pc_q;
    u32      atomic_inst_q;
    u64      atomic_addr_q;
    u3       atomic_byte_idx_q;
    u32      atomic_rs2_word_q;
    u32      atomic_old_word_q;
    u64      atomic_read_shifted;
    u32      atomic_read_word;
    u32      atomic_new_word;
    u64      atomic_rd_data_q;
    logic    atomic_sc_failed_q;
    logic    atomic_latched_same;
    logic    atomic_request_valid;
    logic    atomic_is_write;
    logic    atomic_sc_can_store;

    assign atomic_latched_same = (atomic_state == AT_DONE)
                              && (atomic_pc_q   == pc_inst_address)
                              && (atomic_inst_q == inst);

    assign atomic_sc_can_store = (amo_op == AMO_OP_SC) && reservation_hit;
    assign atomic_busy         = is_atomic && !atomic_latched_same;
    assign sc_failed           = is_atomic && atomic_latched_same && atomic_sc_failed_q;
    assign atomic_read_shifted = response_data >> (atomic_byte_idx_q * 8);
    assign atomic_read_word    = atomic_read_shifted[31:0];

    always_comb begin
        unique case (atomic_op_q)
            AMO_OP_SWAP: atomic_new_word = atomic_rs2_word_q;
            AMO_OP_ADD:  atomic_new_word = atomic_old_word_q + atomic_rs2_word_q;
            AMO_OP_XOR:  atomic_new_word = atomic_old_word_q ^ atomic_rs2_word_q;
            AMO_OP_AND:  atomic_new_word = atomic_old_word_q & atomic_rs2_word_q;
            AMO_OP_OR:   atomic_new_word = atomic_old_word_q | atomic_rs2_word_q;
            AMO_OP_MIN:  atomic_new_word = ($signed(atomic_old_word_q) < $signed(atomic_rs2_word_q))
                                        ? atomic_old_word_q : atomic_rs2_word_q;
            AMO_OP_MAX:  atomic_new_word = ($signed(atomic_old_word_q) > $signed(atomic_rs2_word_q))
                                        ? atomic_old_word_q : atomic_rs2_word_q;
            AMO_OP_MINU: atomic_new_word = (atomic_old_word_q < atomic_rs2_word_q)
                                        ? atomic_old_word_q : atomic_rs2_word_q;
            AMO_OP_MAXU: atomic_new_word = (atomic_old_word_q > atomic_rs2_word_q)
                                        ? atomic_old_word_q : atomic_rs2_word_q;
            default:     atomic_new_word = atomic_rs2_word_q;
        endcase
    end

    assign atomic_request_valid = !kill_new_req
                               && ((atomic_state == AT_READ)
                                || (atomic_state == AT_WRITE));
    assign atomic_is_write = (atomic_state == AT_WRITE);

    // 原子指令和普通访存共享 dbus，原子状态机优先；流水冻结保证不会与普通访存并发。
    u64      dm_addr;
    logic    dm_valid;
    msize_t  dm_size;
    strobe_t dm_strobe;
    u64      dm_wdata;

    always_comb begin
        dm_addr   = pending_valid ? pending_addr   : mem_addr;
        dm_valid  = normal_request_valid;
        dm_size   = pending_valid ? pending_size   : req_size;
        dm_strobe = pending_valid ? pending_strobe : req_strobe;
        dm_wdata  = pending_valid ? pending_wdata  : req_wdata;

        if (atomic_request_valid) begin
            dm_addr   = atomic_addr_q;
            dm_valid  = 1'b1;
            dm_size   = MSIZE4;
            dm_strobe = atomic_is_write ? (8'b0000_1111 << atomic_byte_idx_q) : 8'b0;
            dm_wdata  = atomic_is_write ? ({32'b0, atomic_new_word} << (atomic_byte_idx_q * 8)) : 64'b0;
        end
    end

    assign is_mem_ready = is_atomic ? atomic_latched_same : normal_ready;
    assign load_data    = is_atomic ? atomic_rd_data_q
                                    : (is_same_inst ? latched_data : load_data_ext);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_pc          <= '0;
            latched_inst        <= '0;
            latched_data        <= '0;
            latched_valid       <= 1'b0;
            pending_valid       <= 1'b0;
            pending_addr        <= '0;
            pending_size        <= MSIZE1;
            pending_strobe      <= '0;
            pending_wdata       <= '0;
            pending_funct3      <= '0;
            pending_byte_idx    <= '0;
            resv0_valid         <= 1'b0;
            resv1_valid         <= 1'b0;
            resv0_addr          <= '0;
            resv1_addr          <= '0;
            atomic_state        <= AT_IDLE;
            atomic_op_q         <= AMO_OP_NONE;
            atomic_pc_q         <= '0;
            atomic_inst_q       <= '0;
            atomic_addr_q       <= '0;
            atomic_byte_idx_q   <= '0;
            atomic_rs2_word_q   <= '0;
            atomic_old_word_q   <= '0;
            atomic_rd_data_q    <= '0;
            atomic_sc_failed_q  <= 1'b0;
        end
        else begin
            if (kill_new_req) begin
                pending_valid <= 1'b0;
                atomic_state  <= AT_IDLE;
            end
            else begin
                if (!is_atomic) begin
                    if (is_response_valid && !normal_ready) begin
                        latched_pc    <= pc_inst_address;
                        latched_inst  <= inst;
                        latched_data  <= load_data_ext;
                        latched_valid <= 1'b1;
                        pending_valid <= 1'b0;
                    end
                    if (!pending_valid && is_mem && !normal_ready) begin
                        pending_valid    <= 1'b1;
                        pending_addr     <= mem_addr;
                        pending_size     <= req_size;
                        pending_strobe   <= req_strobe;
                        pending_wdata    <= req_wdata;
                        pending_funct3   <= funct3;
                        pending_byte_idx <= byte_idx;
                    end
                end

                if (latched_valid
                    && ((latched_pc != pc_inst_address) || (latched_inst != inst))) begin
                    latched_valid <= 1'b0;
                end

                unique case (atomic_state)
                    AT_IDLE: begin
                        if (is_atomic) begin
                            atomic_op_q        <= amo_op;
                            atomic_pc_q        <= pc_inst_address;
                            atomic_inst_q      <= inst;
                            atomic_addr_q      <= {mem_addr[63:2], 2'b00};
                            atomic_byte_idx_q  <= mem_addr[2:0];
                            atomic_rs2_word_q  <= store_data[31:0];
                            atomic_sc_failed_q <= 1'b0;

                            if (amo_op == AMO_OP_SC) begin
                                resv0_valid <= 1'b0;
                                resv1_valid <= 1'b0;
                                if (atomic_sc_can_store) begin
                                    atomic_rd_data_q <= 64'b0;
                                    atomic_state     <= AT_WRITE;
                                end
                                else begin
                                    atomic_rd_data_q    <= 64'b1;
                                    atomic_sc_failed_q  <= 1'b1;
                                    atomic_state        <= AT_DONE;
                                end
                            end
                            else begin
                                atomic_state <= AT_READ;
                            end
                        end
                    end

                    AT_READ: begin
                        if (is_response_valid) begin
                            atomic_old_word_q <= atomic_read_word;
                            atomic_rd_data_q  <= {{32{atomic_read_word[31]}}, atomic_read_word};
                            if (atomic_op_q == AMO_OP_LR) begin
                                if (!resv0_valid || (resv0_addr == atomic_addr_q)) begin
                                    resv0_valid <= 1'b1;
                                    resv0_addr  <= atomic_addr_q;
                                end
                                else begin
                                    resv1_valid <= 1'b1;
                                    resv1_addr  <= atomic_addr_q;
                                end
                                atomic_state <= AT_DONE;
                            end
                            else begin
                                atomic_state <= AT_WRITE;
                            end
                        end
                    end

                    AT_WRITE: begin
                        if (is_response_valid) begin
                            atomic_state <= AT_DONE;
                        end
                    end

                    AT_DONE: begin
                        if (!is_atomic
                            || (atomic_pc_q != pc_inst_address)
                            || (atomic_inst_q != inst)) begin
                            atomic_state <= AT_IDLE;
                        end
                    end

                    default: atomic_state <= AT_IDLE;
                endcase
            end
        end
    end

    DataMemory u_data_memory (
        .clk                ( clk ),
        .rst_n              ( rst_n ),

        .request_addr       ( dm_addr ),
        .request_valid      ( dm_valid ),
        .request_size       ( dm_size ),
        .request_strobe     ( dm_strobe ),
        .request_write_data ( dm_wdata ),

        .response_data      ( response_data ),
        .is_response_valid  ( is_response_valid ),

        .dbus_request       ( dbus_request ),
        .dbus_response      ( dbus_response )
    );

endmodule
