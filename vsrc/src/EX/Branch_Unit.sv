// ----------------------------------------------------------------------------
// File        : Branch_Unit.sv
// Description : 根据 BRANCH_OP 与 rs1/rs2 输出 is_branch_taken，纯组合
// ----------------------------------------------------------------------------

`include "src/EX/EX_PKG.sv"

import common::*;
import EX_PKG::*;

module Branch_Unit (
    input  BRANCH_OP branch_op,
    input  u64       rs1_data,
    input  u64       rs2_data,

    output logic     is_branch_taken
);

    always_comb begin
        unique case (branch_op)
            BR_EQ:   is_branch_taken = (rs1_data == rs2_data);
            BR_NE:   is_branch_taken = (rs1_data != rs2_data);
            BR_LT:   is_branch_taken = ($signed(rs1_data) <  $signed(rs2_data));
            BR_GE:   is_branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
            BR_LTU:  is_branch_taken = (rs1_data <  rs2_data);
            BR_GEU:  is_branch_taken = (rs1_data >= rs2_data);
            default: is_branch_taken = 1'b0;
        endcase
    end

endmodule
