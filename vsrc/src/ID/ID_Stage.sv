// ----------------------------------------------------------------------------
// File        : ID_Stage.sv
// Description : ID Stage 顶层：装配 Decoder + RegFile + Sign_Extend + ID/EX 流水寄存器
//               ID 不做 op1/op2 mux（v2 规约：mux 在 EX 做）
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`include "src/ID/Decoder.sv"
`include "src/ID/RegFile.sv"
`include "src/ID/Sign_Extend.sv"
`include "src/ID/CSRFile.sv"
`endif

import common::*;
import top_pkg::*;
import CSR_PKG::*;

module ID_Stage (
    input  logic     clk,
    input  logic     rst_n,

    input  logic     stall,
    input  logic     insert_bubble,    // load-use / csr-rs1 / jump-flush 时向 ID/EX 注入 NOP
    input  IF_2_ID   if_2_id,
    input  WB_2_ID   wb_2_id,
    input  CSR_WRITE wb_2_csr,         // 来自 WB 的 CSR 写口（与 wb_2_id 同步生效）
    input  logic     trap_write_en,
    input  u64       trap_mstatus_next,
    input  u64       trap_mepc_next,
    input  u64       trap_mcause_next,
    input  u64       trap_mtval_next,

    output INST_CTX  inst_ctx,
    output TRAP_CTX  trap_ctx,
    output ID_2_EX   id_2_ex,
    output ID_2_FWD  id_2_fwd,
    output CSR_WRITE csr_write,        // CSR 写请求 ID/EX 寄存器输出，随流水线透传到 WB
    output u64       gpr [0:31],
    output ID_2_CTRL id_2_ctrl,
    output CSR_STATE csr_state,
    output u64       mtvec_value,
    output u64       mepc_value
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
    logic       dec_is_csr;
    logic       dec_is_csr_imm;
    logic       dec_is_ecall;
    logic       dec_is_mret;
    CSR_OP      dec_csr_op;
    u12         dec_csr_addr;
    u5          dec_csr_uimm;

    // RegFile 读出
    u64         rf_read_data_1;
    u64         rf_read_data_2;

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

        .is_csr        ( dec_is_csr ),
        .is_csr_imm    ( dec_is_csr_imm ),
        .csr_op        ( dec_csr_op ),
        .csr_addr      ( dec_csr_addr ),
        .csr_uimm      ( dec_csr_uimm ),

        .is_ecall      ( dec_is_ecall ),
        .is_mret       ( dec_is_mret )
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

        .csr_state   ( csr_state ),
        .mtvec_value ( mtvec_value ),
        .mepc_value  ( mepc_value )
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

    // ID/EX 流水寄存器：物理上同一组，按语义拆成 inst_ctx / id_2_ex / id_2_fwd / csr_write 四个输出
    // 优先级：rst_n > insert_bubble（hazard / jump-flush）> !stall（正常推进）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ctx  <= '0;
            trap_ctx  <= '0;
            id_2_ex   <= '0;
            id_2_fwd  <= '0;
            csr_write <= '0;
        end else if (insert_bubble) begin
            inst_ctx  <= '0;
            trap_ctx  <= '0;
            id_2_ex   <= '0;
            id_2_fwd  <= '0;
            csr_write <= '0;
        end else if (!stall) begin
            inst_ctx.pc_inst_address <= if_2_id.pc_inst_address;
            inst_ctx.inst            <= if_2_id.inst;
            inst_ctx.rd_addr         <= dec_rd_addr;
            inst_ctx.opcode          <= dec_opcode;

            trap_ctx.is_ecall  <= dec_is_ecall;
            trap_ctx.is_mret   <= dec_is_mret;
            trap_ctx.exc_valid <= 1'b0;
            trap_ctx.exc_cause <= 4'b0;
            trap_ctx.exc_tval  <= 64'b0;

            id_2_ex.imm           <= se_imm;
            id_2_ex.csr_old       <= csr_read_data;  // CSR 旧值，EX 在 RD_FROM_CSR 时选它
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

            csr_write.write_en   <= csr_req_write_en;
            csr_write.write_addr <= dec_csr_addr;
            csr_write.write_data <= csr_req_write_data;
        end
    end

    // 控制层反馈：组合透出 ID 位当前指令（即 Decoder 输出）的 rs 号 + CSR 标志
    // is_csr / is_csr_imm 供 Control_Unit 做 CSR rs1 hazard 判定（仅非 imm 形式触发）
    assign id_2_ctrl.rs1_addr   = dec_rs1_addr;
    assign id_2_ctrl.rs2_addr   = dec_rs2_addr;
    assign id_2_ctrl.is_csr     = dec_is_csr;
    assign id_2_ctrl.is_csr_imm = dec_is_csr_imm;

endmodule
