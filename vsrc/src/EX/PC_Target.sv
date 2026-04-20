// ----------------------------------------------------------------------------
// File        : PC_Target.sv
// Description : 产 pc_plus_4（JAL/JALR 的 rd 源）与 jump_target，纯组合
//               JAL / BR : target = PC + imm
//               JALR     : target = (rs1 + imm) & ~1
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/EX/EX_PKG.sv"
`endif

import common::*;
import EX_PKG::*;

module PC_Target (
    input  JUMP_TYPE jump_type,
    input  u64       pc_inst_address,
    input  u64       rs1_data,
    input  u64       imm,

    output u64       pc_plus_4,
    output u64       jump_target
);

    assign pc_plus_4 = pc_inst_address + 64'd4;

    always_comb begin
        unique case (jump_type)
            JT_JALR: jump_target = (rs1_data + imm) & ~64'd1;
            JT_JAL:  jump_target = pc_inst_address + imm;
            JT_BR:   jump_target = pc_inst_address + imm;
            default: jump_target = 64'b0;  // JT_NONE 时外部不消费
        endcase
    end

endmodule
