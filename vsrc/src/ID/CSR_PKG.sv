// ----------------------------------------------------------------------------
// File        : CSR_PKG.sv
// Description : CSR 操作枚举 + 11 个 M/S 模式 CSR 地址 + WARL mask
//               仅 ID Stage（Decoder / CSRFile）内部使用，不经 top_pkg 透出
// ----------------------------------------------------------------------------

`ifndef CSR_PKG
`define CSR_PKG

package CSR_PKG;
    // CSR 指令类型；CSR_NONE 表示非 CSR 指令
    typedef enum logic [2:0] {
        CSR_NONE = 3'd0,
        CSR_RW   = 3'd1,
        CSR_RS   = 3'd2,
        CSR_RC   = 3'd3,
        CSR_RWI  = 3'd4,
        CSR_RSI  = 3'd5,
        CSR_RCI  = 3'd6
    } CSR_OP;

    // funct3：CSR 指令子类型
    localparam logic [2:0] FUNCT3_CSRRW  = 3'b001;
    localparam logic [2:0] FUNCT3_CSRRS  = 3'b010;
    localparam logic [2:0] FUNCT3_CSRRC  = 3'b011;
    localparam logic [2:0] FUNCT3_CSRRWI = 3'b101;
    localparam logic [2:0] FUNCT3_CSRRSI = 3'b110;
    localparam logic [2:0] FUNCT3_CSRRCI = 3'b111;

    // M/S 模式常用 CSR 地址
    localparam logic [11:0] CSR_SSTATUS  = 12'h100;
    localparam logic [11:0] CSR_SIE      = 12'h104;
    localparam logic [11:0] CSR_STVEC    = 12'h105;
    localparam logic [11:0] CSR_SSCRATCH = 12'h140;
    localparam logic [11:0] CSR_SEPC     = 12'h141;
    localparam logic [11:0] CSR_SCAUSE   = 12'h142;
    localparam logic [11:0] CSR_STVAL    = 12'h143;
    localparam logic [11:0] CSR_SIP      = 12'h144;
    localparam logic [11:0] CSR_SATP     = 12'h180;

    localparam logic [11:0] CSR_MSTATUS  = 12'h300;
    localparam logic [11:0] CSR_MEDELEG  = 12'h302;
    localparam logic [11:0] CSR_MIDELEG  = 12'h303;
    localparam logic [11:0] CSR_MIE      = 12'h304;
    localparam logic [11:0] CSR_MTVEC    = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH = 12'h340;
    localparam logic [11:0] CSR_MEPC     = 12'h341;
    localparam logic [11:0] CSR_MCAUSE   = 12'h342;
    localparam logic [11:0] CSR_MTVAL    = 12'h343;
    localparam logic [11:0] CSR_MIP      = 12'h344;
    localparam logic [11:0] CSR_MCYCLE   = 12'hb00;
    localparam logic [11:0] CSR_MHARTID  = 12'hf14;

    // mcause 异常编码（bit63=0）
    localparam logic [63:0] MCAUSE_INSTR_MISALIGN = 64'd0;
    localparam logic [63:0] MCAUSE_ILLEGAL_INST  = 64'd2;
    localparam logic [63:0] MCAUSE_LOAD_MISALIGN = 64'd4;
    localparam logic [63:0] MCAUSE_STORE_MISALIGN = 64'd6;
    localparam logic [63:0] MCAUSE_ECALL_U       = 64'd8;
    localparam logic [63:0] MCAUSE_ECALL_S       = 64'd9;
    localparam logic [63:0] MCAUSE_ECALL_M       = 64'd11;
    localparam logic [63:0] MCAUSE_INST_PAGE_FAULT = 64'd12;
    localparam logic [63:0] MCAUSE_LOAD_PAGE_FAULT = 64'd13;
    localparam logic [63:0] MCAUSE_STORE_PAGE_FAULT = 64'd15;

    // mcause 中断编码（bit63=1）
    localparam logic [63:0] MCAUSE_SSI = 64'h8000_0000_0000_0001;
    localparam logic [63:0] MCAUSE_MSI = 64'h8000_0000_0000_0003;
    localparam logic [63:0] MCAUSE_STI = 64'h8000_0000_0000_0005;
    localparam logic [63:0] MCAUSE_MTI = 64'h8000_0000_0000_0007;
    localparam logic [63:0] MCAUSE_SEI = 64'h8000_0000_0000_0009;
    localparam logic [63:0] MCAUSE_MEI = 64'h8000_0000_0000_000b;

    localparam int MSTATUS_XS_LSB = 15;

    // mstatus 字段位置
    localparam int MSTATUS_SIE_BIT  = 1;
    localparam int MSTATUS_SPIE_BIT = 5;
    localparam int MSTATUS_SPP_BIT  = 8;
    localparam int MSTATUS_MIE_BIT  = 3;
    localparam int MSTATUS_MPIE_BIT = 7;
    localparam int MSTATUS_MPRV_BIT = 17;
    localparam int MSTATUS_MPP_LSB  = 11;

    // WARL / WPRI mask（与 include/csr.sv 对齐）
    // mstatus：仅保留可写位
    localparam logic [63:0] MSTATUS_MASK = 64'h7e79bb;
    localparam logic [63:0] SSTATUS_MASK = 64'h80000003000de122;
    // mtvec：低 2 位 mode，仅允许 mode[0]（Direct/Vectored），mode[1] 保留为 0
    localparam logic [63:0] MTVEC_MASK   = ~64'h2;
    // mip：仅 SSIP/MSIP/STIP/MTIP/SEIP/MEIP 可由软件写
    localparam logic [63:0] MIP_MASK     = 64'h333;
    localparam logic [63:0] SIP_MASK     = 64'h222;

    function automatic logic [63:0] sstatus_to_mstatus(input logic [63:0] data, input logic [63:0] prev);
        sstatus_to_mstatus = (data & SSTATUS_MASK) | (prev & ~SSTATUS_MASK);
    endfunction

    function automatic logic [63:0] mstatus_set_mie(input logic [63:0] value, input logic mie);
        mstatus_set_mie = value;
        mstatus_set_mie[MSTATUS_MIE_BIT] = mie;
    endfunction

    function automatic logic [63:0] mstatus_set_mpie(input logic [63:0] value, input logic mpie);
        mstatus_set_mpie = value;
        mstatus_set_mpie[MSTATUS_MPIE_BIT] = mpie;
    endfunction

    function automatic logic [63:0] mstatus_set_mpp(input logic [63:0] value, input logic [1:0] mpp);
        mstatus_set_mpp = value;
        mstatus_set_mpp[MSTATUS_MPP_LSB +: 2] = mpp;
    endfunction

    function automatic logic [63:0] mstatus_set_mprv(input logic [63:0] value, input logic mprv);
        mstatus_set_mprv = value;
        mstatus_set_mprv[MSTATUS_MPRV_BIT] = mprv;
    endfunction

    function automatic logic mstatus_get_mie(input logic [63:0] value);
        mstatus_get_mie = value[MSTATUS_MIE_BIT];
    endfunction

    function automatic logic [63:0] mstatus_set_sie(input logic [63:0] value, input logic sie);
        mstatus_set_sie = value;
        mstatus_set_sie[MSTATUS_SIE_BIT] = sie;
    endfunction

    function automatic logic [63:0] mstatus_set_spie(input logic [63:0] value, input logic spie);
        mstatus_set_spie = value;
        mstatus_set_spie[MSTATUS_SPIE_BIT] = spie;
    endfunction

    function automatic logic [63:0] mstatus_set_spp(input logic [63:0] value, input logic spp);
        mstatus_set_spp = value;
        mstatus_set_spp[MSTATUS_SPP_BIT] = spp;
    endfunction

    function automatic logic mstatus_get_sie(input logic [63:0] value);
        mstatus_get_sie = value[MSTATUS_SIE_BIT];
    endfunction

    function automatic logic mstatus_get_spie(input logic [63:0] value);
        mstatus_get_spie = value[MSTATUS_SPIE_BIT];
    endfunction

    function automatic logic mstatus_get_spp(input logic [63:0] value);
        mstatus_get_spp = value[MSTATUS_SPP_BIT];
    endfunction

    function automatic logic mstatus_get_mpie(input logic [63:0] value);
        mstatus_get_mpie = value[MSTATUS_MPIE_BIT];
    endfunction

    function automatic logic [1:0] mstatus_get_mpp(input logic [63:0] value);
        mstatus_get_mpp = value[MSTATUS_MPP_LSB +: 2];
    endfunction

    function automatic logic [63:0] mstatus_set_xs(input logic [63:0] value, input logic [1:0] xs);
        mstatus_set_xs = value;
        mstatus_set_xs[MSTATUS_XS_LSB +: 2] = xs;
    endfunction
endpackage

`endif
