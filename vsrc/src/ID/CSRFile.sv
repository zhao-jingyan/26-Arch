// ----------------------------------------------------------------------------
// File        : CSRFile.sv
// Description : 11 个 M/S 模式 CSR 寄存器组，方案 A（ID 段读 + WB 段写，与 commit 同拍）
//               读端口组合：当拍 csr_addr 命中即输出对应寄存器值；
//                 含 read-during-write bypass，覆盖 distance-1 RAW
//               写端口同步：write_en 在下沿把 write_data 经 WARL mask 写入
//               mhartid 硬连 0；mcycle 每周期自增（软件写覆盖优先）
//               非法地址：读返回 0，写忽略
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/top_pkg.sv"
`include "src/ID/CSR_PKG.sv"
`endif

import common::*;
import top_pkg::*;
import CSR_PKG::*;

module CSRFile (
    input  logic     clk,
    input  logic     rst_n,

    // 读口（组合）
    input  u12       read_addr,
    output u64       read_data,

    // 写口（同步）；非 CSR 指令或 read-only 操作时 write_en=0
    input  logic     write_en,
    input  u12       write_addr,
    input  u64       write_data,

    // trap 写口（同步），优先级高于软件 CSR 写
    input  logic     trap_write_en,
    input  u64       trap_mstatus_next,
    input  u64       trap_mepc_next,
    input  u64       trap_mcause_next,
    input  u64       trap_mtval_next,
    input  u64       trap_sepc_next,
    input  u64       trap_scause_next,
    input  u64       trap_stval_next,
    input  u64       mip_hw,

    // CSRFile 快照：DifftestCSRState 字段表内的 9 个 CSR；mcycle / mhartid 不在内
    output CSR_STATE csr_state,
    output u64       mip_sw,
    output u64       mtvec_value,
    output u64       mepc_value,
    output u64       stvec_value,
    output u64       sepc_value
);

    // 内部寄存器（mhartid 不分配，硬连 0）
    u64 mstatus;
    u64 mtvec;
    u64 stvec;
    u64 mip;
    u64 mie;
    u64 sip;
    u64 sie;
    u64 mscratch;
    u64 sscratch;
    u64 mcause;
    u64 scause;
    u64 mtval;
    u64 stval;
    u64 mepc;
    u64 sepc;
    u64 mcycle;
    u64 satp;
    u64 medeleg;
    u64 mideleg;
    u64 mip_full;
    u64 sip_full;

    assign mip_full = mip | mip_hw;
    assign sip_full = (sip | mip_full | ((mideleg[5] && mip_full[7]) ? (64'b1 << 5) : 64'b0)) & SIP_MASK;

    // ------------------------------------------------------------------------
    // WARL mask：mstatus / mtvec / mip 应用对应 mask；其余直写
    // ------------------------------------------------------------------------
    function automatic u64 apply_mask(input u12 addr, input u64 data, input u64 prev);
        unique case (addr)
            CSR_MSTATUS: apply_mask = (data & MSTATUS_MASK) | (prev & ~MSTATUS_MASK);
            CSR_SSTATUS: apply_mask = sstatus_to_mstatus(data, prev);
            CSR_MTVEC:   apply_mask = (data & MTVEC_MASK)   | (prev & ~MTVEC_MASK);
            CSR_STVEC:   apply_mask = (data & MTVEC_MASK)   | (prev & ~MTVEC_MASK);
            CSR_MIP:     apply_mask = (data & MIP_MASK)     | (prev & ~MIP_MASK);
            CSR_SIP:     apply_mask = (data & SIP_MASK)     | (prev & ~SIP_MASK);
            default:     apply_mask = data;
        endcase
    endfunction

    // ------------------------------------------------------------------------
    // 当拍寄存器输出值（无 bypass）；用于 read-during-write bypass 与 csr_state 快照
    // ------------------------------------------------------------------------
    u64 reg_value;
    always_comb begin
        unique case (read_addr)
            CSR_MSTATUS:  reg_value = mstatus;
            CSR_SSTATUS:  reg_value = mstatus & SSTATUS_MASK;
            CSR_MTVEC:    reg_value = mtvec;
            CSR_STVEC:    reg_value = stvec;
            CSR_MIP:      reg_value = mip_full;
            CSR_SIP:      reg_value = sip_full;
            CSR_MIE:      reg_value = mie;
            CSR_SIE:      reg_value = sie;
            CSR_MSCRATCH: reg_value = mscratch;
            CSR_SSCRATCH: reg_value = sscratch;
            CSR_MCAUSE:   reg_value = mcause;
            CSR_SCAUSE:   reg_value = scause;
            CSR_MTVAL:    reg_value = mtval;
            CSR_STVAL:    reg_value = stval;
            CSR_MEPC:     reg_value = mepc;
            CSR_SEPC:     reg_value = sepc;
            CSR_MCYCLE:   reg_value = mcycle;
            CSR_MHARTID:  reg_value = 64'b0;
            CSR_SATP:     reg_value = satp;
            CSR_MEDELEG:  reg_value = medeleg;
            CSR_MIDELEG:  reg_value = mideleg;
            default:      reg_value = 64'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // 组合读 + read-during-write bypass：
    //   WB 段当拍命中正在写的同地址时直出 mask 后的写值，覆盖 distance-1 RAW；
    //   非法地址或 mhartid 忽略 bypass（read 端默认 0 / 硬 0），由下方 hit 判定屏蔽
    // ------------------------------------------------------------------------
    logic bypass_hit;
    assign bypass_hit = !trap_write_en
                     && write_en
                     && (read_addr == write_addr)
                     && (read_addr != CSR_MHARTID);

    assign read_data = bypass_hit ? apply_mask(write_addr, write_data, reg_value)
                                  : reg_value;

    // ------------------------------------------------------------------------
    // 同步写：复位 + 软件写 + mcycle 自增
    // 软件写 mcycle 优先于自增（同拍命中则写入值；下一拍才在该值基础上自增）
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 64'b0;
            mtvec    <= 64'b0;
            stvec    <= 64'b0;
            mip      <= 64'b0;
            mie      <= 64'b0;
            sip      <= 64'b0;
            sie      <= 64'b0;
            mscratch <= 64'b0;
            sscratch <= 64'b0;
            mcause   <= 64'b0;
            scause   <= 64'b0;
            mtval    <= 64'b0;
            stval    <= 64'b0;
            mepc     <= 64'b0;
            sepc     <= 64'b0;
            mcycle   <= 64'b0;
            satp     <= 64'b0;
            medeleg  <= 64'b0;
            mideleg  <= 64'b0;
        end else begin
            // mcycle 默认每拍自增，被软件写覆盖时优先采用写值
            if (!trap_write_en && write_en && write_addr == CSR_MCYCLE)
                mcycle <= write_data;
            else
                mcycle <= mcycle + 64'b1;

            if (trap_write_en) begin
                mstatus <= apply_mask(CSR_MSTATUS, trap_mstatus_next, mstatus);
                mepc    <= trap_mepc_next;
                mcause  <= trap_mcause_next;
                mtval   <= trap_mtval_next;
                sepc    <= trap_sepc_next;
                scause  <= trap_scause_next;
                stval   <= trap_stval_next;
            end
            else if (write_en) begin
                unique case (write_addr)
                    CSR_MSTATUS:  mstatus  <= apply_mask(CSR_MSTATUS, write_data, mstatus);
                    CSR_SSTATUS:  mstatus  <= apply_mask(CSR_SSTATUS, write_data, mstatus);
                    CSR_MTVEC:    mtvec    <= apply_mask(CSR_MTVEC,   write_data, mtvec);
                    CSR_STVEC:    stvec    <= apply_mask(CSR_STVEC,   write_data, stvec);
                    CSR_MIP:      mip      <= apply_mask(CSR_MIP,     write_data, mip);
                    CSR_SIP:      sip      <= apply_mask(CSR_SIP,     write_data, sip);
                    CSR_MIE:      mie      <= write_data;
                    CSR_SIE:      sie      <= write_data & SIP_MASK;
                    CSR_MSCRATCH: mscratch <= write_data;
                    CSR_SSCRATCH: sscratch <= write_data;
                    CSR_MCAUSE:   mcause   <= write_data;
                    CSR_SCAUSE:   scause   <= write_data;
                    CSR_MTVAL:    mtval    <= write_data;
                    CSR_STVAL:    stval    <= write_data;
                    CSR_MEPC:     mepc     <= write_data;
                    CSR_SEPC:     sepc     <= write_data;
                    CSR_SATP:     satp     <= write_data;
                    CSR_MEDELEG:  medeleg  <= write_data;
                    CSR_MIDELEG:  mideleg  <= write_data;
                    // mcycle 已在上面单独处理；mhartid 只读忽略；其余非法地址忽略
                    default: ;
                endcase
            end
        end
    end

    // CSRFile 快照：直出当前寄存器值，供 Difftest 比对
    assign csr_state.mstatus  = mstatus;
    assign csr_state.mtvec    = mtvec;
    assign mip_sw             = mip;
    assign csr_state.mip      = mip_full;
    assign csr_state.mie      = mie;
    assign csr_state.mscratch = mscratch;
    assign csr_state.mcause   = mcause;
    assign csr_state.mtval    = mtval;
    assign csr_state.mepc     = mepc;
    assign csr_state.satp     = satp;
    assign csr_state.stvec    = stvec;
    assign csr_state.sip      = sip_full;
    assign csr_state.sie      = sie;
    assign csr_state.sscratch = sscratch;
    assign csr_state.scause   = scause;
    assign csr_state.stval    = stval;
    assign csr_state.sepc     = sepc;
    assign csr_state.medeleg  = medeleg;
    assign csr_state.mideleg  = mideleg;

    assign mtvec_value = mtvec;
    assign mepc_value  = mepc;
    assign stvec_value = stvec;
    assign sepc_value  = sepc;

endmodule
