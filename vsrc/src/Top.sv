// ----------------------------------------------------------------------------
// File        : Top.sv
// Description : v2 五段流水线顶层：IF → ID → EX → MEM → WB + Control_Unit
//               对外暴露 ibus/dbus，由外层在 CBus 仲裁后统一接 MMU
//               commit 信号按 v1 做法：MEM/WB 寄存器 + 1-cycle prev 比较，检测"推进"沿
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/ID_PKG.sv"
`include "src/ID/V_PKG.sv"
`include "src/IF/IF_Stage.sv"
`include "src/ID/ID_Stage.sv"
`include "src/EX/EX_Stage.sv"
`include "src/MEM/MEM_Stage.sv"
`include "src/WB/WB_Stage.sv"
`include "src/WB/Commit_Unit.sv"
`include "src/CTRL/Control_Unit.sv"
`include "src/CTRL/Forward_Unit.sv"
`include "src/CTRL/Privilege_Unit.sv"
`include "src/CTRL/Interrupt_Unit.sv"
`include "src/CTRL/Scoreboard_Unit.sv"
`endif

import common::*;
import top_pkg::*;
import ID_PKG::*;
import V_PKG::*;

module Top (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       trint,
    input  logic       swint,
    input  logic       exint,

    output ibus_req_t  ibus_req_o,
    input  ibus_resp_t ibus_resp_i,
    output dbus_req_t  dbus_req_o,
    input  dbus_resp_t dbus_resp_i,

    output logic       commit_valid_o,
    output u64         commit_pc_o,
    output u32         commit_instr_o,
    output logic       commit_wen_o,
    output u8          commit_wdest_o,
    output u64         commit_wdata_o,
    output logic       commit_sc_failed_o,
    output logic       commit_skip_o,   // 外设 MMIO 访存跳过 Difftest 对账
    output u64         gpr_o [0:31],
    output CSR_STATE   csr_state_o,     // CSR 快照：DifftestCSRState 字段表内的 9 个 CSR
    output PRIV_MODE   priv_mode_o,
    output PRIV_MODE   mmu_priv_mode_o
);

    // ------------------------------------------------------------------------
    // Stage-to-stage bundles
    // ------------------------------------------------------------------------
    IF_2_ID   if_2_id;
    IF_2_CTRL if_2_ctrl;

    INST_CTX  id_inst_ctx;
    TRAP_CTX  id_trap_ctx;
    ID_2_EX   id_2_ex;
    ID_2_FWD  id_2_fwd;
    ID_2_CTRL id_2_ctrl;
    ID_2_VEX  id_2_vex;
    ID_2_VMEM id_2_vmem;

    INST_CTX  ex_inst_ctx;
    TRAP_CTX  ex_trap_ctx;
    EX_2_MEM  ex_2_mem;
    EX_2_FWD  ex_2_fwd;
    EX_2_CTRL ex_2_ctrl;

    INST_CTX   mem_inst_ctx;
    TRAP_CTX   mem_trap_ctx;
    MEM_2_WB   mem_2_wb;
    MEM_2_FWD  mem_2_fwd;
    MEM_2_CTRL mem_2_ctrl;

    FWD_2_EX  fwd_2_ex;

    WB_2_ID   wb_2_id;
    CSR_WRITE wb_2_csr;
    V_WRITE   wb_2_vcsr;
    VREG_WRITE wb_2_vreg;
    WB_TRAP_EVENT wb_trap_event;

    // CSR 写请求贯穿链：ID 段算好 → EX/MEM 透传 → WB 段反向送给 ID 内 CSRFile
    CSR_WRITE id_csr_write;
    CSR_WRITE ex_csr_write;
    CSR_WRITE mem_csr_write;
    V_WRITE   id_vcsr_write;
    V_WRITE   ex_vcsr_write;
    V_WRITE   mem_vcsr_write;

    // trap / privilege 协调
    PRIV_2_CTRL priv_2_ctrl;
    logic       trap_write_en;
    u64         trap_mstatus_next;
    u64         trap_mepc_next;
    u64         trap_mcause_next;
    u64         trap_mtval_next;
    u64         mtvec_value;
    u64         mepc_value;
    u64         if_pc;
    u64         mip_hw;
    u64         mip_sw;
    logic       int_fire;
    u64         int_mcause;
    u64         int_epc;
    logic       kill_new_req;

    // EX / MEM 对控制层的裸端口反馈
    logic ex_pc_should_jump;
    u64   ex_pc_jump_address;
    logic is_mem_ready;

    dbus_req_t  if_dbus_req;
    dbus_resp_t if_dbus_resp;
    dbus_req_t  mem_dbus_req;
    dbus_resp_t mem_dbus_resp;
    PRIV_MODE   mmu_priv_mode;

    // 控制层输出
    logic stall_if, stall_id, stall_ex, stall_mem;
    logic insert_bubble;
    logic flush_if_id;
    logic flush_ex, flush_mem;
    logic pc_should_jump;
    u64   pc_jump_address;
    logic wb_commit_valid;
    SCOREBOARD_2_CTRL scoreboard_2_ctrl;

    Scoreboard_Unit u_scoreboard (
        .id_2_ctrl          ( id_2_ctrl ),
        .ex_2_ctrl          ( ex_2_ctrl ),
        .mem_2_ctrl         ( mem_2_ctrl ),
        .scoreboard_2_ctrl  ( scoreboard_2_ctrl )
    );

    Forward_Unit u_fwd (
        .id_2_fwd  ( id_2_fwd ),
        .ex_2_fwd  ( ex_2_fwd ),
        .mem_2_fwd ( mem_2_fwd ),

        .fwd_2_ex  ( fwd_2_ex )
    );

    Control_Unit u_ctrl (
        .if_2_ctrl          ( if_2_ctrl ),
        .id_2_ctrl          ( id_2_ctrl ),
        .ex_2_ctrl          ( ex_2_ctrl ),
        .mem_2_ctrl         ( mem_2_ctrl ),
        .scoreboard_2_ctrl  ( scoreboard_2_ctrl ),
        .is_mem_ready       ( is_mem_ready ),

        .ex_pc_should_jump  ( ex_pc_should_jump ),
        .ex_pc_jump_address ( ex_pc_jump_address ),
        .priv_2_ctrl        ( priv_2_ctrl ),

        .stall_if           ( stall_if ),
        .stall_id           ( stall_id ),
        .stall_ex           ( stall_ex ),
        .stall_mem          ( stall_mem ),
        .insert_bubble      ( insert_bubble ),
        .flush_if_id        ( flush_if_id ),
        .flush_ex           ( flush_ex ),
        .flush_mem          ( flush_mem ),

        .pc_should_jump     ( pc_should_jump ),
        .pc_jump_address    ( pc_jump_address )
    );

    Interrupt_Unit u_int (
        .clk        ( clk ),
        .rst_n      ( rst_n ),

        .trint      ( trint ),
        .swint      ( swint ),
        .exint      ( exint ),

        .mstatus    ( csr_state_o.mstatus ),
        .mip_sw     ( mip_sw ),
        .mie        ( csr_state_o.mie ),
        .priv_mode  ( priv_mode_o ),
        .if_pc      ( if_pc ),
        .if_2_id    ( if_2_id ),
        .ex_inst_ctx( ex_inst_ctx ),
        .mem_inst_ctx( mem_inst_ctx ),
        .mem_2_ctrl ( mem_2_ctrl ),

        .trap_write_en      ( trap_write_en ),
        .trap_mstatus_next  ( trap_mstatus_next ),
        .wb_csr_write       ( wb_2_csr ),
        .wb_commit_valid    ( wb_commit_valid ),

        .mip_hw     ( mip_hw ),
        .int_fire   ( int_fire ),
        .int_mcause ( int_mcause ),
        .int_epc    ( int_epc )
    );

    Privilege_Unit u_priv (
        .clk                 ( clk ),
        .rst_n               ( rst_n ),

        .wb_trap_event       ( wb_trap_event ),
        .int_fire            ( int_fire ),
        .int_mcause          ( int_mcause ),
        .int_epc             ( int_epc ),
        .mstatus             ( csr_state_o.mstatus ),
        .mcause              ( csr_state_o.mcause ),
        .mtval               ( csr_state_o.mtval ),
        .mtvec_value         ( mtvec_value ),
        .mepc_value          ( mepc_value ),

        .trap_write_en       ( trap_write_en ),
        .trap_mstatus_next   ( trap_mstatus_next ),
        .trap_mepc_next      ( trap_mepc_next ),
        .trap_mcause_next    ( trap_mcause_next ),
        .trap_mtval_next     ( trap_mtval_next ),

        .priv_2_ctrl         ( priv_2_ctrl ),
        .priv_mode           ( priv_mode_o )
    );

    always_comb begin
        if (priv_2_ctrl.is_trap_fire)
            mmu_priv_mode = PRIV_M;
        else if (priv_2_ctrl.is_mret_fire)
            mmu_priv_mode = PRIV_MODE'(csr_state_o.mstatus[12:11]);
        else
            mmu_priv_mode = priv_mode_o;
    end
    assign mmu_priv_mode_o = mmu_priv_mode;
    assign kill_new_req    = priv_2_ctrl.is_trap_fire || priv_2_ctrl.is_mret_fire;

    IF_Stage u_if (
        .clk             ( clk ),
        .rst_n           ( rst_n ),

        .stall           ( stall_if ),
        .flush           ( flush_if_id ),
        .pc_should_jump  ( pc_should_jump ),
        .pc_jump_address ( pc_jump_address ),

        .if_2_id         ( if_2_id ),
        .if_2_ctrl       ( if_2_ctrl ),
        .if_pc           ( if_pc ),

        .dbus_request    ( if_dbus_req ),
        .dbus_response   ( if_dbus_resp )
    );

    ID_Stage u_id (
        .clk           ( clk ),
        .rst_n         ( rst_n ),

        .stall         ( stall_id ),
        .insert_bubble ( insert_bubble ),
        .if_2_id       ( if_2_id ),
        .wb_2_id       ( wb_2_id ),
        .wb_2_csr      ( wb_2_csr ),
        .wb_2_vcsr     ( wb_2_vcsr ),
        .wb_2_vreg     ( wb_2_vreg ),
        .trap_write_en     ( trap_write_en ),
        .trap_mstatus_next ( trap_mstatus_next ),
        .trap_mepc_next    ( trap_mepc_next ),
        .trap_mcause_next  ( trap_mcause_next ),
        .trap_mtval_next   ( trap_mtval_next ),
        .mip_hw            ( mip_hw ),

        .inst_ctx      ( id_inst_ctx ),
        .mip_sw        ( mip_sw ),
        .trap_ctx      ( id_trap_ctx ),
        .id_2_ex       ( id_2_ex ),
        .id_2_fwd      ( id_2_fwd ),
        .id_2_vex      ( id_2_vex ),
        .id_2_vmem     ( id_2_vmem ),
        .csr_write     ( id_csr_write ),
        .vcsr_write    ( id_vcsr_write ),
        .gpr           ( gpr_o ),
        .id_2_ctrl     ( id_2_ctrl ),
        .csr_state     ( csr_state_o ),
        .mtvec_value   ( mtvec_value ),
        .mepc_value    ( mepc_value )
    );

    EX_Stage u_ex (
        .clk             ( clk ),
        .rst_n           ( rst_n ),

        .stall           ( stall_ex ),
        .flush           ( flush_ex ),

        .inst_ctx_in     ( id_inst_ctx ),
        .trap_ctx_in     ( id_trap_ctx ),
        .id_2_ex         ( id_2_ex ),
        .id_2_vex        ( id_2_vex ),
        .id_2_vmem       ( id_2_vmem ),
        .fwd_2_ex        ( fwd_2_ex ),
        .csr_write_in    ( id_csr_write ),
        .vcsr_write_in   ( id_vcsr_write ),

        .inst_ctx_out    ( ex_inst_ctx ),
        .trap_ctx_out    ( ex_trap_ctx ),
        .ex_2_mem        ( ex_2_mem ),
        .ex_2_fwd        ( ex_2_fwd ),
        .ex_2_ctrl       ( ex_2_ctrl ),
        .csr_write_out   ( ex_csr_write ),
        .vcsr_write_out  ( ex_vcsr_write ),

        .pc_should_jump  ( ex_pc_should_jump ),
        .pc_jump_address ( ex_pc_jump_address )
    );

    MEM_Stage u_mem (
        .clk           ( clk ),
        .rst_n         ( rst_n ),

        .stall         ( stall_mem ),
        .flush         ( flush_mem ),

        .inst_ctx_in   ( ex_inst_ctx ),
        .trap_ctx_in   ( ex_trap_ctx ),
        .ex_2_mem      ( ex_2_mem ),
        .csr_write_in  ( ex_csr_write ),
        .vcsr_write_in ( ex_vcsr_write ),
        .kill_new_req  ( kill_new_req ),

        .inst_ctx_out  ( mem_inst_ctx ),
        .trap_ctx_out  ( mem_trap_ctx ),
        .mem_2_wb      ( mem_2_wb ),
        .mem_2_fwd     ( mem_2_fwd ),
        .mem_2_ctrl    ( mem_2_ctrl ),
        .csr_write_out ( mem_csr_write ),
        .vcsr_write_out( mem_vcsr_write ),

        .is_mem_ready  ( is_mem_ready ),

        .dbus_request  ( mem_dbus_req ),
        .dbus_response ( mem_dbus_resp )
    );

    assign ibus_req_o.valid = if_dbus_req.valid;
    assign ibus_req_o.addr  = if_dbus_req.addr;

    assign if_dbus_resp.addr_ok = ibus_resp_i.addr_ok;
    assign if_dbus_resp.data_ok = ibus_resp_i.data_ok;
    assign if_dbus_resp.data    = {ibus_resp_i.data, ibus_resp_i.data};

    assign dbus_req_o  = mem_dbus_req;
    assign mem_dbus_resp = dbus_resp_i;

    WB_Stage u_wb (
        .inst_ctx        ( mem_inst_ctx ),
        .trap_ctx        ( mem_trap_ctx ),
        .mem_2_wb        ( mem_2_wb ),
        .csr_write       ( mem_csr_write ),
        .vcsr_write      ( mem_vcsr_write ),
        .commit_valid    ( wb_commit_valid ),

        .wb_2_id         ( wb_2_id ),
        .wb_2_csr        ( wb_2_csr ),
        .wb_2_vcsr       ( wb_2_vcsr ),
        .wb_2_vreg       ( wb_2_vreg ),
        .wb_trap_event   ( wb_trap_event )
    );

    // 提交收敛：把 MEM/WB 边界、commit 判定和 Difftest 对账统一收口
    Commit_Unit u_commit (
        .clk             ( clk ),
        .rst_n           ( rst_n ),
        .mem_inst_ctx    ( mem_inst_ctx ),
        .mem_2_wb        ( mem_2_wb ),

        .wb_commit_valid ( wb_commit_valid ),
        .commit_valid_o  ( commit_valid_o ),
        .commit_pc_o     ( commit_pc_o ),
        .commit_instr_o  ( commit_instr_o ),
        .commit_wen_o    ( commit_wen_o ),
        .commit_wdest_o  ( commit_wdest_o ),
        .commit_wdata_o  ( commit_wdata_o ),
        .commit_sc_failed_o ( commit_sc_failed_o ),
        .commit_skip_o   ( commit_skip_o )
    );

endmodule
