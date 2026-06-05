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

    // 11 个支持的 CSR 地址
    localparam logic [11:0] CSR_MSTATUS  = 12'h300;
    localparam logic [11:0] CSR_MIE      = 12'h304;
    localparam logic [11:0] CSR_MTVEC    = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH = 12'h340;
    localparam logic [11:0] CSR_MEPC     = 12'h341;
    localparam logic [11:0] CSR_MCAUSE   = 12'h342;
    localparam logic [11:0] CSR_MTVAL    = 12'h343;
    localparam logic [11:0] CSR_MIP      = 12'h344;
    localparam logic [11:0] CSR_MCYCLE   = 12'hb00;
    localparam logic [11:0] CSR_MHARTID  = 12'hf14;
    localparam logic [11:0] CSR_SATP     = 12'h180;

    // mcause 异常编码（bit63=0）
    localparam logic [63:0] MCAUSE_INSTR_MISALIGN = 64'd0;
    localparam logic [63:0] MCAUSE_ILLEGAL_INST  = 64'd2;
    localparam logic [63:0] MCAUSE_LOAD_MISALIGN = 64'd4;
    localparam logic [63:0] MCAUSE_STORE_MISALIGN = 64'd6;
    localparam logic [63:0] MCAUSE_ECALL_U       = 64'd8;
    localparam logic [63:0] MCAUSE_ECALL_M       = 64'd11;

    // mcause 中断编码（bit63=1）
    localparam logic [63:0] MCAUSE_MSI = 64'h8000_0000_0000_0003;
    localparam logic [63:0] MCAUSE_MTI = 64'h8000_0000_0000_0007;
    localparam logic [63:0] MCAUSE_MEI = 64'h8000_0000_0000_000b;

    localparam int MSTATUS_XS_LSB = 15;

    // mstatus 字段位置
    localparam int MSTATUS_MIE_BIT  = 3;
    localparam int MSTATUS_MPIE_BIT = 7;
    localparam int MSTATUS_MPRV_BIT = 17;
    localparam int MSTATUS_MPP_LSB  = 11;

    // WARL / WPRI mask（与 include/csr.sv 对齐）
    // mstatus：仅保留可写位
    localparam logic [63:0] MSTATUS_MASK = 64'h7e79bb;
    // mtvec：低 2 位 mode，仅允许 mode[0]（Direct/Vectored），mode[1] 保留为 0
    localparam logic [63:0] MTVEC_MASK   = ~64'h2;
    // mip：仅 SSIP/MSIP/STIP/MTIP/SEIP/MEIP 可由软件写
    localparam logic [63:0] MIP_MASK     = 64'h333;

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
