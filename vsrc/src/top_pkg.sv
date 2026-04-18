// ----------------------------------------------------------------------------
// File        : top_pkg.sv
// Description : v2 stage 间流水线寄存器类型登记
// ----------------------------------------------------------------------------

`ifndef TOP_PKG
`define TOP_PKG

`include "src/EX/EX_PKG.sv"

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
    // 注：rs1_data / rs2_data 已剥离到 ID_2_FWD，EX 读 rs 走 fwd_2_ex
    typedef struct packed {
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
        u64 mem_addr;    // load/store 访存地址（= ex_2_mem.ex_result），非访存指令无意义；供 Difftest skip 判定
    } MEM_2_WB;

    // ID → FWD：供 Forward_Unit 判定与默认回退（ID/EX 寄存器 tap）
    typedef struct packed {
        u5  rs1_addr;
        u5  rs2_addr;
        u64 rs1_data;    // RegFile 原始读值（forward miss 时用）
        u64 rs2_data;
    } ID_2_FWD;

    // EX → FWD：EX/MEM 流水寄存器 tap，供 distance-1 RAW forward
    typedef struct packed {
        u5  rd_addr;
        u64 ex_result;   // load 场景是地址（见 load-use 例外）
    } EX_2_FWD;

    // MEM → FWD：MEM/WB 流水寄存器 tap，供 distance-2 RAW forward
    typedef struct packed {
        u5  rd_addr;
        u64 rd_data;     // load 已对齐
    } MEM_2_FWD;

    // FWD → EX：forward 解析后的操作数
    typedef struct packed {
        u64 rs1_data;
        u64 rs2_data;
    } FWD_2_EX;

    // ID → 控制层：供 load-use 检测的 ID 位当前指令 rs 号（组合，源自 Decoder）
    typedef struct packed {
        u5 rs1_addr;
        u5 rs2_addr;
    } ID_2_CTRL;

    // EX → 控制层：供 load-use 检测的 EX 位当前指令信息（组合，源自 ID/EX 寄存器输出）
    typedef struct packed {
        logic is_ex_load;   // EX 位指令是否为 load
        u5    rd_addr;      // EX 位指令的 rd
    } EX_2_CTRL;

endpackage

`endif
