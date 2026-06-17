// ----------------------------------------------------------------------------
// File        : V_PKG.sv
// Description : RVV 向量译码与寄存器堆的基础类型；当前只作为架构入口使用
// ----------------------------------------------------------------------------

`ifndef V_PKG
`define V_PKG

import common::*;

package V_PKG;
    import common::*;

    // 第一阶段固定实现 Zvl128b 的最小物理宽度，后续可以参数化到更大的 VLEN。
    localparam int VLEN_BITS  = 128;
    localparam int VLEN_BYTES = VLEN_BITS / 8;
    localparam int VREG_NUM   = 32;

    typedef u128 vreg_t;

    typedef enum logic [3:0] {
        V_CLASS_NONE    = 4'd0,
        V_CLASS_CONFIG  = 4'd1,
        V_CLASS_LOAD    = 4'd2,
        V_CLASS_STORE   = 4'd3,
        V_CLASS_ALU     = 4'd4,
        V_CLASS_MASK    = 4'd5,
        V_CLASS_PERMUTE = 4'd6,
        V_CLASS_REDUCE  = 4'd7,
        V_CLASS_UNKNOWN = 4'd15
    } V_CLASS;

    typedef enum logic [2:0] {
        V_FMT_NONE = 3'd0,
        V_FMT_VV   = 3'd1,
        V_FMT_VX   = 3'd2,
        V_FMT_VI   = 3'd3,
        V_FMT_VF   = 3'd4,
        V_FMT_MEM  = 3'd5,
        V_FMT_CFG  = 3'd6
    } V_FORMAT;

    typedef enum logic [1:0] {
        V_CFG_NONE    = 2'd0,
        V_CFG_SETVLI  = 2'd1,
        V_CFG_SETIVLI = 2'd2,
        V_CFG_SETVL   = 2'd3
    } V_CFG_KIND;

    typedef enum logic [3:0] {
        V_ALU_NONE = 4'd0,
        V_ALU_ADD  = 4'd1,
        V_ALU_SUB  = 4'd2,
        V_ALU_AND  = 4'd3,
        V_ALU_OR   = 4'd4,
        V_ALU_XOR  = 4'd5,
        V_ALU_SLL  = 4'd6,
        V_ALU_SRL  = 4'd7,
        V_ALU_SRA  = 4'd8
    } V_ALU_OP;

    typedef struct packed {
        logic    valid;        // 当前指令是否落在向量编码空间
        logic    illegal;      // 向量子译码发现的非法组合；执行接入前主 Decoder 暂不消费
        V_CLASS  op_class;
        V_FORMAT format;
        V_CFG_KIND cfg_kind;
        V_ALU_OP alu_op;
        u5       vd;
        u5       vs1;
        u5       vs2;
        u5       uimm;
        logic    vm;           // inst[25]，1 表示不使用 v0 mask
        u3       funct3;
        u6       funct6;
        u3       width;        // 向量访存宽度字段，非访存时保留原 funct3
        u2       mop;          // 向量访存寻址模式
        u3       nf;           // segment field，实际 NFIELDS = nf + 1
        u11      vtypei;       // vsetvli/vsetivli 立即数字段
    } V_DECODE;

    // 向量语义收敛结果：把 vset*、向量执行/访存分类和状态合法性集中表达。
    typedef struct packed {
        logic is_vset;
        logic is_vset_imm;
        logic is_vset_rs2;
        logic is_vmem_load;
        logic is_vmem_store;
        logic is_vmem;
        logic is_valusize;
        logic vector_state_illegal;
        logic v_req_write_en;
        u64   v_req_vl;
        u64   v_req_vtype;
    } V_SEMANTICS;

    typedef struct packed {
        u64 vl;
        u64 vtype;
        u64 vstart;
        u64 vxrm;
        u64 vxsat;
        u64 vcsr;
        u64 vlenb;
    } V_STATE;

    typedef struct packed {
        logic write_en;
        u64   vl;
        u64   vtype;
        u64   vstart;
    } V_WRITE;

    typedef struct packed {
        logic write_en;
        u5    write_addr;
        vreg_t write_data;
    } VREG_WRITE;

    typedef struct packed {
        logic    valid;
        V_ALU_OP alu_op;
        V_FORMAT format;
        u5       vd;
        u5       vs1;
        u5       vs2;
        logic    vm;
        u5       uimm;
        V_STATE  state;
        vreg_t   vs1_data;
        vreg_t   vs2_data;
        vreg_t   vd_old_data;
        vreg_t   mask_data;
        u64      scalar_rs1_data;
    } ID_2_VEX;

    typedef struct packed {
        logic  write_en;
        u5     vd;
        vreg_t result;
    } VEX_2_VWB;

    typedef struct packed {
        logic  valid;
        logic  is_load;
        logic  is_store;
        u5     vd;
        u5     vs3;
        V_STATE state;
        vreg_t store_data;
    } ID_2_VMEM;

endpackage

`endif
