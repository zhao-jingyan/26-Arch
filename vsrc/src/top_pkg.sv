// ----------------------------------------------------------------------------
// File        : top_pkg.sv
// Description : v2 stage 间流水线寄存器类型登记
// ----------------------------------------------------------------------------

`ifndef TOP_PKG
`define TOP_PKG

`ifdef VERILATOR
`include "src/EX/EX_PKG.sv"
`include "src/ID/ID_PKG.sv"
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import EX_PKG::*;
import ID_PKG::*;
import V_PKG::*;

package top_pkg;
    import common::*;
    import EX_PKG::*;
    import ID_PKG::*;
    import V_PKG::*;

    typedef enum logic [1:0] {
        PRIV_U = 2'b00,
        PRIV_S = 2'b01,
        PRIV_M = 2'b11
    } PRIV_MODE;

    // IF/ID 流水线寄存器
    typedef struct packed {
        u32 inst;
        u64 pc_inst_address;
        logic predicted_taken;
        u64 predicted_target;
        logic fetch_exc_valid;
        u64   fetch_exc_cause;
        u64   fetch_exc_tval;
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
        logic predicted_taken;
        u64 predicted_target;
    } INST_CTX;

    // 与 INST_CTX 并行透传的 trap / exception 上下文
    typedef struct packed {
        logic is_ecall;
        logic is_mret;
        logic is_sret;
        logic exc_valid;
        u64   exc_cause;
        u64   exc_tval;
    } TRAP_CTX;

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
        u64         csr_old;       // CSR 指令的旧值；非 CSR 指令为 0；EX 在 RD_FROM_CSR 时选它
        u64         vector_rd_data; // vset* 写回 rd 的新 vl；非向量配置指令为 0
        AMO_OP      amo_op;        // A 扩展操作类型；非原子指令为 AMO_OP_NONE
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
        AMO_OP amo_op;   // A 扩展原子操作类型
        VEX_2_VWB vex_2_vwb; // 向量执行结果，随流水线到 WB 写回 VectorRegFile
        ID_2_VMEM vmem;
    } EX_2_MEM;

    // MEM → WB：MEM 末尾流水寄存器的业务输出
    typedef struct packed {
        u64 rd_data;     // load 走对齐后的 load_data，其他走 ex_result
        u64 mem_addr;    // load/store 访存地址（= ex_2_mem.ex_result），非访存指令无意义；供 Difftest skip 判定
        logic sc_failed;  // SC.W 失败标志，供 DifftestInstrCommit.scFailed
        VEX_2_VWB vex_2_vwb;
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

    // ID → 控制层：供 load-use 与 CSR rs1 hazard 检测（组合，源自 Decoder）
    // is_csr：当前 ID 位是否为 CSR 指令；is_csr_imm：CSRRWI/CSRRSI/CSRRCI（rs1 是立即数）
    typedef struct packed {
        u5    rs1_addr;
        u5    rs2_addr;
        logic is_csr;
        logic is_csr_imm;
        logic is_vset;
        logic is_vset_imm;
        logic is_vset_rs2;  // 仅 vsetvl 需要从 rs2 读取 vtype
        logic is_vector_alu;
        logic is_vector_mem;
        logic is_vector_vx;
        logic v_uses_vs1;
        logic v_uses_mask;
        logic v_uses_vs3;
        u5    vs1_addr;
        u5    vs2_addr;
        u5    vd_addr;
        u5    vs3_addr;
    } ID_2_CTRL;

    // EX → 控制层：供 load-use 检测的 EX 位当前指令信息（组合，源自 ID/EX 寄存器输出）
    // is_alu_busy 由 ALU_Core 直出，乘除法运行期间为 1，触发全流水冻结
    typedef struct packed {
        logic is_ex_load;   // EX 位指令是否为 load
        u5    rd_addr;      // EX 位指令的 rd
        logic is_alu_busy;  // ALU 多周期单元（乘除法）正在运行
        logic is_vwrite;    // EX 位指令是否将在 WB 写向量寄存器
        u5    v_rd_addr;
        logic is_vcsr_write; // EX 位指令是否将在 WB 写向量状态
        logic is_vmem_busy;
    } EX_2_CTRL;

    // MEM → 控制层：供 CSR rs1 hazard 检测（组合，源自 EX/MEM 寄存器输出）
    typedef struct packed {
        u5 rd_addr;         // MEM 位指令的 rd（distance-2 写者）
        logic is_atomic_busy; // 原子访存正在 MEM 多拍执行，延迟中断投递
        logic is_vwrite;      // MEM 位指令是否将在 WB 写向量寄存器
        u5    v_rd_addr;
        logic is_vcsr_write;  // MEM 位指令是否将在 WB 写向量状态
        logic is_vmem_busy;
    } MEM_2_CTRL;

    // Scoreboard → 控制层：集中表达整数 GPR 的等待关系。
    // 当前仍保持五段顺序提交；scoreboard 先收敛 load/AMO、乘除法和 ID 直读源的阻塞条件。
    typedef struct packed {
        logic gpr_raw_hazard;       // ID 位 rs 命中当前不可转发的整数写者
        logic id_direct_rs_hazard;  // CSR/vset/vector-vx 这类 ID 直读源命中 EX/MEM 写者
        logic csr_state_hazard;     // ID 位 CSR 读取命中尚未提交的 CSR 写者
    } SCOREBOARD_2_CTRL;

    // CSRFile 快照：从 ID Stage CSRFile 一路透传到 core.sv 供 Difftest 比对
    // 仅包含 DifftestCSRState 关心的 9 个 CSR；mcycle / mhartid 不在 Difftest 字段表内
    typedef struct packed {
        u64 mstatus;
        u64 mtvec;
        u64 mip;
        u64 mie;
        u64 mscratch;
        u64 mcause;
        u64 mtval;
        u64 mepc;
        u64 satp;
        u64 stvec;
        u64 sip;
        u64 sie;
        u64 sscratch;
        u64 scause;
        u64 stval;
        u64 sepc;
        u64 medeleg;
        u64 mideleg;
    } CSR_STATE;

    // CSR 写请求（贯穿型 bundle）：ID 段算好后随流水线透传到 WB 段，
    // WB 段再回送给 ID 内的 CSRFile 写口；这样 CSR 写时机与 commit 同拍，
    // 满足 Difftest 按 program order 的 CSR 一致性要求
    typedef struct packed {
        logic write_en;
        u12   write_addr;
        u64   write_data;
    } CSR_WRITE;

    // WB → Privilege_Unit：已提交 trap 事件
    typedef struct packed {
        logic    is_trap_commit;
        TRAP_CTX trap_ctx;
        u64      epc;
    } WB_TRAP_EVENT;

    // Privilege_Unit → Control_Unit：trap / mret 重定向反馈
    typedef struct packed {
        logic is_trap_fire;
        logic is_mret_fire;
        logic is_sret_fire;
        u64   trap_vector;
        u64   ret_pc_value;
    } PRIV_2_CTRL;

endpackage

`endif
