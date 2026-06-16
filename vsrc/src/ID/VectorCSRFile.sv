// ----------------------------------------------------------------------------
// File        : VectorCSRFile.sv
// Description : RVV 向量状态寄存器；第一阶段支持 vset* 写 vl/vtype/vstart
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import V_PKG::*;

module VectorCSRFile (
    input  logic   clk,
    input  logic   rst_n,

    input  V_WRITE write,
    output V_STATE state
);

    u64 vl;
    u64 vtype;
    u64 vstart;
    u64 vxrm;
    u64 vxsat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vl     <= 64'b0;
            vtype  <= 64'b0;
            vstart <= 64'b0;
            vxrm   <= 64'b0;
            vxsat  <= 64'b0;
        end else if (write.write_en) begin
            vl     <= write.vl;
            vtype  <= write.vtype;
            vstart <= write.vstart;
        end
    end

    assign state.vl     = vl;
    assign state.vtype  = vtype;
    assign state.vstart = vstart;
    assign state.vxrm   = vxrm;
    assign state.vxsat  = vxsat;
    assign state.vcsr   = {61'b0, vxrm[1:0], vxsat[0]};
    assign state.vlenb  = VLEN_BYTES;

endmodule
