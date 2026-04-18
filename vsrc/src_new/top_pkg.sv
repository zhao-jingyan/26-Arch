// ----------------------------------------------------------------------------
// File        : top_pkg.sv
// Description : v2 stage 间流水线寄存器类型登记
// ----------------------------------------------------------------------------

`ifndef TOP_PKG
`define TOP_PKG

`include "src_new/EX/EX_PKG.sv"

import common::*;
import EX_PKG::*;

package top_pkg;
    import common::*;
    import EX_PKG::*;

    // IF/ID 流水线寄存器
    typedef struct packed {
        u32 inst;
        u64 pc_inst_address;
    } IF_2_ID;

    // IF 对控制层反馈
    typedef struct packed {
        logic is_inst_ready;
    } IF_2_CTRL;

    // 贯穿 pipeline 的指令上下文：从 ID 起各 stage 原样透传
    typedef struct packed {
        u64 pc_inst_address;
        u32 inst;
        u5  rd_addr;  // S/B-type 已在 Decoder 清零
        u7  opcode;   // MEM 识别 load/store 用
    } INST_CTX;

    // WB 对 ID 的反馈：仅写回三元组，不含 commit 信息
    typedef struct packed {
        logic write_en;
        u5    write_addr;
        u64   write_data;
    } WB_2_ID;

    // ID → EX 专属：EX 消费后不再往下传
    typedef struct packed {
        u64         rs1_data;
        u64         rs2_data;
        u64         imm;
        logic       is_op1_zero;   // LUI 场景
        logic       is_op1_pc;     // AUIPC：ALU op1 = PC
        logic       is_op2_imm;    // OP-IMM / Load / Store / LUI / AUIPC
        ALU_OP_CODE alu_op_code;
        ALU_INST    alu_inst_type;
        BRANCH_OP   branch_op;     // 条件类型（非分支指令为 BR_NONE）
        JUMP_TYPE   jump_type;     // 跳转类型
        RD_SRC      rd_src;        // rd 写回数据源
    } ID_2_EX;

    // EX → MEM：EX 末尾流水寄存器的业务输出
    typedef struct packed {
        u64 ex_result;   // rd 写回候选（已做 ALU vs PC+4 的 mux）
        u64 rs2_data;    // store 用，原样透传
    } EX_2_MEM;

    // MEM → WB：MEM 末尾流水寄存器的业务输出
    typedef struct packed {
        u64 rd_data;     // load 走对齐后的 load_data，其他走 ex_result
    } MEM_2_WB;

    // ID → 控制层：字段集合待控制层形态明确后再定
    typedef struct packed {
        logic placeholder;
    } ID_2_CTRL;

endpackage

`endif
