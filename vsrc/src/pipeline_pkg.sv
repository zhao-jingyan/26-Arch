// ----------------------------------------------------------------------------
// File        : pipeline_pkg.sv
// Description : Pipeline stage interface structs
// Author      : zhao-jingyan | Date: 2026-03-10
// ----------------------------------------------------------------------------

`ifndef PIPELINE_PKG
`define PIPELINE_PKG

import common::*;
import ALU_PKG::*;

package pipeline_pkg;

    // WB to RegFile + commit info for Difftest
    typedef struct packed {
        logic       wen;
        u5          rd_addr;
        u64         rd_data;
        u64         pc;       // for commit
        logic [31:0] inst;    // for commit
    } wb_reg_t;

    // IF/ID: input to DecodeStage
    typedef struct packed {
        logic [31:0] inst;
        u64          pc;
    } if_id_t;

    // ID/EX: output from DecodeStage, input to ALU stage
    typedef struct packed {
        u64          pc;
        logic [31:0] inst;
        u5           rd_addr;
        u5           rs1_addr;
        u5           rs2_addr;
        u64          rs1_data;
        u64          rs2_data;
        u64          imm;
        ALU_OP_CODE  alu_op_code;
        ALU_INST     alu_inst_type;
        u7           opcode;
    } id_ex_t;

    // EX/MEM: output from ALU stage
    typedef struct packed {
        u64         pc;
        logic [31:0] inst;
        u5          rd_addr;
        u64         alu_res;
        u7          opcode;
    } ex_mem_t;

    // ------------------------------------------------------------------------
    // Instruction Memory: IF fetch interface
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic valid;
        u64   addr;      // PC
    } im_req_t;

    typedef struct packed {
        logic valid;
        u32   data;      // instruction
    } im_rsp_t;

    // ------------------------------------------------------------------------
    // Data Memory (DM): abstract LSU interface, implementation can be buffer/cache
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic       valid;
        logic       is_write;
        u64         addr;
        msize_t     size;
        strobe_t    strobe;     // for write
        u64         wdata;      // for write
    } dm_req_t;

    typedef struct packed {
        logic valid;     // transaction done
        u64   rdata;     // for read
    } dm_rsp_t;

endpackage

`endif
