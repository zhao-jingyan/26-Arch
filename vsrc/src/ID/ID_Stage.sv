// ----------------------------------------------------------------------------
// File        : ID_Stage.sv
// Description : ID Stage 顶层：装配 Decoder + RegFile + Sign_Extend + ID/EX 流水寄存器
//               ID 不做 op1/op2 mux（v2 规约：mux 在 EX 做）
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`include "src/ID/V_PKG.sv"
`include "src/ID/Decoder.sv"
`include "src/ID/RegFile.sv"
`include "src/ID/VectorRegFile.sv"
`include "src/ID/VectorCSRFile.sv"
`include "src/ID/VectorSemantic.sv"
`include "src/ID/Sign_Extend.sv"
`include "src/ID/CSRFile.sv"
`endif

import common::*;
import top_pkg::*;
import CSR_PKG::*;
import V_PKG::*;

module ID_Stage (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     stall,
    input  logic     insert_bubble,    // load-use / csr-rs1 / jump-flush 时向 ID/EX 注入 NOP
    input  IF_2_ID   if_2_id,
    input  WB_2_ID   wb_2_id,
    input  CSR_WRITE wb_2_csr,         // 来自 WB 的 CSR 写口（与 wb_2_id 同步生效）
    input  V_WRITE   wb_2_vcsr,        // 来自 WB 的向量状态写口
    input  VREG_WRITE wb_2_vreg,       // 来自 WB 的向量寄存器写口
    input  logic     trap_write_en,
    input  u64       trap_mstatus_next,
    input  u64       trap_mepc_next,
    input  u64       trap_mcause_next,
    input  u64       trap_mtval_next,
    input  u64       trap_sepc_next,
    input  u64       trap_scause_next,
    input  u64       trap_stval_next,
    input  u64       mip_hw,

    output INST_CTX  inst_ctx,
    output u64       mip_sw,
    output TRAP_CTX  trap_ctx,
    output ID_2_EX   id_2_ex,
    output ID_2_FWD  id_2_fwd,
    output ID_2_VEX  id_2_vex,
    output ID_2_VMEM id_2_vmem,
    output CSR_WRITE csr_write,        // CSR 写请求 ID/EX 寄存器输出，随流水线透传到 WB
    output V_WRITE   vcsr_write,       // vset* 写请求，随流水线透传到 WB
    output u64       gpr [0:31],
    output ID_2_CTRL id_2_ctrl,
    output CSR_STATE csr_state,
    output u64       mtvec_value,
    output u64       mepc_value,
    output u64       stvec_value,
    output u64       sepc_value
);

    // Decoder 输出
    u7          dec_opcode;
    u5          dec_rd_addr;
    u5          dec_rs1_addr;
    u5          dec_rs2_addr;
    ALU_OP_CODE dec_alu_op_code;
    ALU_INST    dec_alu_inst_type;
    logic       dec_is_op1_zero;
    logic       dec_is_op1_pc;
    logic       dec_is_op2_imm;
    BRANCH_OP   dec_branch_op;
    JUMP_TYPE   dec_jump_type;
    RD_SRC      dec_rd_src;
    AMO_OP      dec_amo_op;
    logic       dec_is_csr;
    logic       dec_is_csr_imm;
    logic       dec_is_ecall;
    logic       dec_is_mret;
    logic       dec_is_sret;
    logic       dec_is_sfence;
    logic       dec_is_illegal;
    CSR_OP      dec_csr_op;
    u12         dec_csr_addr;
    u5          dec_csr_uimm;
    V_DECODE    dec_v_decode;

    // RegFile 读出
    u64         rf_read_data_1;
    u64         rf_read_data_2;

    // VectorRegFile 读出；执行通路接入前仅用于固定模块边界
    vreg_t      vrf_read_data_1;
    vreg_t      vrf_read_data_2;
    vreg_t      vrf_vd_old_data;
    vreg_t      vrf_mask_data;

    // Vector CSR 读出和向量语义收敛结果
    V_STATE     v_state;
    V_SEMANTICS v_semantics;

    // Sign_Extend 输出
    u64         se_imm;

    // CSRFile 读出
    u64   csr_read_data;

    // 当拍 ID 位 CSR 指令算出来的写请求（组合）；下沿 latch 进 ID/EX 流水寄存器后随 pipeline 透传
    logic csr_req_write_en;
    u64   csr_req_write_data;

    Decoder u_decoder (
        .inst          ( if_2_id.inst ),

        .opcode        ( dec_opcode ),
        .rd_addr       ( dec_rd_addr ),
        .rs1_addr      ( dec_rs1_addr ),
        .rs2_addr      ( dec_rs2_addr ),

        .alu_op_code   ( dec_alu_op_code ),
        .alu_inst_type ( dec_alu_inst_type ),
        .is_op1_zero   ( dec_is_op1_zero ),
        .is_op1_pc     ( dec_is_op1_pc ),
        .is_op2_imm    ( dec_is_op2_imm ),

        .branch_op     ( dec_branch_op ),
        .jump_type     ( dec_jump_type ),
        .rd_src        ( dec_rd_src ),
        .amo_op        ( dec_amo_op ),

        .is_csr        ( dec_is_csr ),
        .is_csr_imm    ( dec_is_csr_imm ),
        .csr_op        ( dec_csr_op ),
        .csr_addr      ( dec_csr_addr ),
        .csr_uimm      ( dec_csr_uimm ),

        .v_decode      ( dec_v_decode ),

        .is_ecall      ( dec_is_ecall ),
        .is_mret       ( dec_is_mret ),
        .is_sret       ( dec_is_sret ),
        .is_sfence     ( dec_is_sfence ),
        .is_illegal    ( dec_is_illegal )
    );

    RegFile u_regfile (
        .clk          ( clk ),
        .rst_n        ( rst_n ),

        .write_en     ( wb_2_id.write_en ),
        .write_addr   ( wb_2_id.write_addr ),
        .write_data   ( wb_2_id.write_data ),

        .read_addr_1  ( dec_rs1_addr ),
        .read_addr_2  ( dec_rs2_addr ),
        .read_data_1  ( rf_read_data_1 ),
        .read_data_2  ( rf_read_data_2 ),

        .gpr          ( gpr )
    );

    VectorRegFile u_vector_regfile (
        .clk         ( clk ),
        .rst_n       ( rst_n ),

        .write       ( wb_2_vreg ),

        .read_addr_1 ( dec_v_decode.vs1 ),
        .read_addr_2 ( dec_v_decode.vs2 ),
        .read_addr_3 ( dec_v_decode.vd ),
        .mask_addr   ( 5'b0 ),
        .read_data_1 ( vrf_read_data_1 ),
        .read_data_2 ( vrf_read_data_2 ),
        .read_data_3 ( vrf_vd_old_data ),
        .mask_data   ( vrf_mask_data )
    );

    VectorCSRFile u_vector_csr_file (
        .clk   ( clk ),
        .rst_n ( rst_n ),
        .write ( wb_2_vcsr ),
        .state ( v_state )
    );

    VectorSemantic u_vector_semantic (
        .v_decode       ( dec_v_decode ),
        .v_state        ( v_state ),
        .rf_read_data_1 ( rf_read_data_1 ),
        .rf_read_data_2 ( rf_read_data_2 ),
        .vlen_bits      ( u64'(VLEN_BITS) ),

        .v_semantics    ( v_semantics )
    );

    Sign_Extend u_sign_extend (
        .inst   ( if_2_id.inst ),
        .opcode ( dec_opcode ),
        .imm    ( se_imm )
    );

    // CSRFile：方案 A（ID 段读旧值 + WB 段写新值）
    // 读：用 Decoder 当拍解出的 csr_addr，组合输出 csr_read_data 给 rd 写回路径用
    // 写：通过 wb_2_csr 由 WB 段反向驱动；CSRFile 内部读端口含 read-during-write bypass，
    //     覆盖 distance-1 RAW（CSR 后紧跟读同一 CSR；JT_CSR flush 已禁止更远距离的 CSR RAW）
    CSRFile u_csr_file (
        .clk        ( clk ),
        .rst_n      ( rst_n ),

        .read_addr  ( dec_csr_addr ),
        .read_data  ( csr_read_data ),

        .write_en   ( wb_2_csr.write_en ),
        .write_addr ( wb_2_csr.write_addr ),
        .write_data ( wb_2_csr.write_data ),

        .trap_write_en     ( trap_write_en ),
        .trap_mstatus_next ( trap_mstatus_next ),
        .trap_mepc_next    ( trap_mepc_next ),
        .trap_mcause_next  ( trap_mcause_next ),
        .trap_mtval_next   ( trap_mtval_next ),
        .trap_sepc_next    ( trap_sepc_next ),
        .trap_scause_next  ( trap_scause_next ),
        .trap_stval_next   ( trap_stval_next ),
        .mip_hw            ( mip_hw ),

        .csr_state   ( csr_state ),
        .mip_sw      ( mip_sw ),
        .mtvec_value ( mtvec_value ),
        .mepc_value  ( mepc_value ),
        .stvec_value ( stvec_value ),
        .sepc_value  ( sepc_value )
    );

    // CSR 写数据：源操作数在 CSR-imm 时为 zero-extended uimm，否则为 RegFile 直读 rs1
    // rs1 in-flight 写者由 Control_Unit 的 csr_rs1_hazard stall 保证已落到 RegFile
    u64 csr_src;
    assign csr_src = dec_is_csr_imm ? {59'b0, dec_csr_uimm} : rf_read_data_1;

    always_comb begin
        unique case (dec_csr_op)
            CSR_RW, CSR_RWI: csr_req_write_data = csr_src;
            CSR_RS, CSR_RSI: csr_req_write_data = csr_read_data | csr_src;
            CSR_RC, CSR_RCI: csr_req_write_data = csr_read_data & ~csr_src;
            default:         csr_req_write_data = 64'b0;
        endcase
    end

    // 写请求 enable：严格遵循 CSRRS/RC/RSI/RCI 的 rs1=x0 / uimm=0 不写副作用规范
    // 注意：这里只产生"写请求"，真正写发生在 WB 段。stall / insert_bubble 不在此处屏蔽；
    // 由 ID/EX 寄存器在 insert_bubble 时整体写 0（含 csr_write）天然屏蔽，stall 时保持当前值
    logic csr_op_writes;
    always_comb begin
        unique case (dec_csr_op)
            CSR_RW:           csr_op_writes = 1'b1;
            CSR_RWI:          csr_op_writes = 1'b1;
            CSR_RS, CSR_RC:   csr_op_writes = (dec_rs1_addr != 5'b0);
            CSR_RSI, CSR_RCI: csr_op_writes = (dec_csr_uimm != 5'b0);
            default:          csr_op_writes = 1'b0;
        endcase
    end

    assign csr_req_write_en = dec_is_csr && csr_op_writes;

    // ID/EX 流水寄存器：物理上同一组，按语义拆成 inst_ctx / id_2_ex / id_2_fwd / csr_write / vcsr_write 五个输出
    // 优先级：rst_n > insert_bubble（hazard / jump-flush）> !stall（正常推进）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx  <= '0;
            trap_ctx  <= '0;
            id_2_ex   <= '0;
            id_2_fwd  <= '0;
            id_2_vex  <= '0;
            id_2_vmem <= '0;
            csr_write <= '0;
            vcsr_write <= '0;
        end else if (insert_bubble) begin
            inst_ctx  <= '0;
            trap_ctx  <= '0;
            id_2_ex   <= '0;
            id_2_fwd  <= '0;
            id_2_vex  <= '0;
            id_2_vmem <= '0;
            csr_write <= '0;
            vcsr_write <= '0;
        end else if (!stall) begin
            inst_ctx.pc_inst_address <= if_2_id.pc_inst_address;
            inst_ctx.inst            <= if_2_id.inst;
            inst_ctx.rd_addr         <= dec_rd_addr;
            inst_ctx.opcode          <= dec_opcode;
            inst_ctx.predicted_taken  <= if_2_id.predicted_taken;
            inst_ctx.predicted_target <= if_2_id.predicted_target;

            trap_ctx.is_ecall  <= dec_is_ecall;
            trap_ctx.is_mret   <= dec_is_mret;
            trap_ctx.is_sret   <= dec_is_sret;
            trap_ctx.is_sfence <= dec_is_sfence;
            if (if_2_id.fetch_exc_valid) begin
                trap_ctx.exc_valid <= 1'b1;
                trap_ctx.exc_cause <= if_2_id.fetch_exc_cause;
                trap_ctx.exc_tval  <= if_2_id.fetch_exc_tval;
            end else if (dec_is_illegal || v_semantics.vector_state_illegal) begin
                trap_ctx.exc_valid <= 1'b1;
                trap_ctx.exc_cause <= MCAUSE_ILLEGAL_INST;
                trap_ctx.exc_tval  <= {32'b0, if_2_id.inst};
            end else if (if_2_id.pc_inst_address[1:0] != 2'b00) begin
                trap_ctx.exc_valid <= 1'b1;
                trap_ctx.exc_cause <= MCAUSE_INSTR_MISALIGN;
                trap_ctx.exc_tval  <= if_2_id.pc_inst_address;
            end else begin
                trap_ctx.exc_valid <= 1'b0;
                trap_ctx.exc_cause <= 64'b0;
                trap_ctx.exc_tval  <= 64'b0;
            end

            id_2_ex.imm           <= se_imm;
            id_2_ex.csr_old       <= csr_read_data;  // CSR 旧值，EX 在 RD_FROM_CSR 时选它
            id_2_ex.vector_rd_data <= v_semantics.v_req_vl;
            id_2_ex.amo_op        <= dec_amo_op;
            id_2_ex.is_op1_zero   <= dec_is_op1_zero;
            id_2_ex.is_op1_pc     <= dec_is_op1_pc;
            id_2_ex.is_op2_imm    <= dec_is_op2_imm;
            id_2_ex.alu_op_code   <= dec_alu_op_code;
            id_2_ex.alu_inst_type <= dec_alu_inst_type;
            id_2_ex.branch_op     <= dec_branch_op;
            id_2_ex.jump_type     <= dec_jump_type;
            id_2_ex.rd_src        <= dec_rd_src;

            id_2_fwd.rs1_addr <= dec_rs1_addr;
            id_2_fwd.rs2_addr <= dec_rs2_addr;
            id_2_fwd.rs1_data <= rf_read_data_1;
            id_2_fwd.rs2_data <= rf_read_data_2;

            id_2_vex.valid           <= v_semantics.is_valusize && !v_semantics.vector_state_illegal;
            id_2_vex.alu_op          <= dec_v_decode.alu_op;
            id_2_vex.format          <= dec_v_decode.format;
            id_2_vex.vd              <= dec_v_decode.vd;
            id_2_vex.vs1             <= dec_v_decode.vs1;
            id_2_vex.vs2             <= dec_v_decode.vs2;
            id_2_vex.vm              <= dec_v_decode.vm;
            id_2_vex.uimm            <= dec_v_decode.uimm;
            id_2_vex.state           <= v_state;
            id_2_vex.vs1_data        <= vrf_read_data_1;
            id_2_vex.vs2_data        <= vrf_read_data_2;
            id_2_vex.vd_old_data     <= vrf_vd_old_data;
            id_2_vex.mask_data       <= vrf_mask_data;
            id_2_vex.scalar_rs1_data <= rf_read_data_1;

            id_2_vmem.valid      <= v_semantics.is_vmem && !v_semantics.vector_state_illegal;
            id_2_vmem.is_load    <= v_semantics.is_vmem_load;
            id_2_vmem.is_store   <= v_semantics.is_vmem_store;
            id_2_vmem.vd         <= dec_v_decode.vd;
            id_2_vmem.vs3        <= dec_v_decode.vd;
            id_2_vmem.state      <= v_state;
            id_2_vmem.store_data <= vrf_vd_old_data;

            csr_write.write_en   <= csr_req_write_en;
            csr_write.write_addr <= dec_csr_addr;
            csr_write.write_data <= csr_req_write_data;

            vcsr_write.write_en <= v_semantics.v_req_write_en;
            vcsr_write.vl       <= v_semantics.v_req_vl;
            vcsr_write.vtype    <= v_semantics.v_req_vtype;
            vcsr_write.vstart   <= 64'b0;
        end
    end

    // 控制层反馈：组合透出 ID 位当前指令（即 Decoder 输出）的 rs 号 + CSR 标志
    // is_csr / is_csr_imm 供 Control_Unit 做 CSR rs1 hazard 判定（仅非 imm 形式触发）
    assign id_2_ctrl.rs1_addr   = dec_rs1_addr;
    assign id_2_ctrl.rs2_addr   = dec_rs2_addr;
    assign id_2_ctrl.is_csr     = dec_is_csr;
    assign id_2_ctrl.is_csr_imm = dec_is_csr_imm;
    assign id_2_ctrl.is_vset    = v_semantics.is_vset;
    assign id_2_ctrl.is_vset_imm = v_semantics.is_vset_imm;
    assign id_2_ctrl.is_vset_rs2 = v_semantics.is_vset_rs2;
    assign id_2_ctrl.is_vector_alu = v_semantics.is_valusize;
    assign id_2_ctrl.is_vector_mem = v_semantics.is_vmem;
    assign id_2_ctrl.is_vector_vx = v_semantics.is_valusize && (dec_v_decode.format == V_FMT_VX);
    assign id_2_ctrl.v_uses_vs1 = v_semantics.is_valusize && (dec_v_decode.format == V_FMT_VV);
    assign id_2_ctrl.v_uses_mask = v_semantics.is_valusize && !dec_v_decode.vm;
    assign id_2_ctrl.v_uses_vs3 = v_semantics.is_vmem_store;
    assign id_2_ctrl.vs1_addr = dec_v_decode.vs1;
    assign id_2_ctrl.vs2_addr = dec_v_decode.vs2;
    assign id_2_ctrl.vd_addr = dec_v_decode.vd;
    assign id_2_ctrl.vs3_addr = dec_v_decode.vd;

endmodule
