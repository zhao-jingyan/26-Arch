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
    input  u64       mip_hw,

    // CSRFile 快照：DifftestCSRState 字段表内的 9 个 CSR；mcycle / mhartid 不在内
    output CSR_STATE csr_state,
    output u64       mip_sw,
    output u64       mtvec_value,
    output u64       mepc_value
);

    // 内部寄存器（mhartid 不分配，硬连 0）
    u64 mstatus;
    u64 mtvec;
    u64 mip;
    u64 mie;
    u64 mscratch;
    u64 mcause;
    u64 mtval;
    u64 mepc;
    u64 mcycle;
    u64 satp;

    // ------------------------------------------------------------------------
    // WARL mask：mstatus / mtvec / mip 应用对应 mask；其余直写
    // ------------------------------------------------------------------------
    function automatic u64 apply_mask(input u12 addr, input u64 data, input u64 prev);
        unique case (addr)
            CSR_MSTATUS: apply_mask = (data & MSTATUS_MASK) | (prev & ~MSTATUS_MASK);
            CSR_MTVEC:   apply_mask = (data & MTVEC_MASK)   | (prev & ~MTVEC_MASK);
            CSR_MIP:     apply_mask = (data & MIP_MASK)     | (prev & ~MIP_MASK);
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
            CSR_MTVEC:    reg_value = mtvec;
            CSR_MIP:      reg_value = mip | mip_hw;
            CSR_MIE:      reg_value = mie;
            CSR_MSCRATCH: reg_value = mscratch;
            CSR_MCAUSE:   reg_value = mcause;
            CSR_MTVAL:    reg_value = mtval;
            CSR_MEPC:     reg_value = mepc;
            CSR_MCYCLE:   reg_value = mcycle;
            CSR_MHARTID:  reg_value = 64'b0;
            CSR_SATP:     reg_value = satp;
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
            mip      <= 64'b0;
            mie      <= 64'b0;
            mscratch <= 64'b0;
            mcause   <= 64'b0;
            mtval    <= 64'b0;
            mepc     <= 64'b0;
            mcycle   <= 64'b0;
            satp     <= 64'b0;
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
            end
            else if (write_en) begin
                unique case (write_addr)
                    CSR_MSTATUS:  mstatus  <= apply_mask(CSR_MSTATUS, write_data, mstatus);
                    CSR_MTVEC:    mtvec    <= apply_mask(CSR_MTVEC,   write_data, mtvec);
                    CSR_MIP:      mip      <= apply_mask(CSR_MIP,     write_data, mip);
                    CSR_MIE:      mie      <= write_data;
                    CSR_MSCRATCH: mscratch <= write_data;
                    CSR_MCAUSE:   mcause   <= write_data;
                    CSR_MTVAL:    mtval    <= write_data;
                    CSR_MEPC:     mepc     <= write_data;
                    CSR_SATP:     satp     <= write_data;
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
    assign csr_state.mip      = mip | mip_hw;
    assign csr_state.mie      = mie;
    assign csr_state.mscratch = mscratch;
    assign csr_state.mcause   = mcause;
    assign csr_state.mtval    = mtval;
    assign csr_state.mepc     = mepc;
    assign csr_state.satp     = satp;

    assign mtvec_value = mtvec;
    assign mepc_value  = mepc;

endmodule
