// ----------------------------------------------------------------------------
// File        : VectorALU.sv
// Description : RVV 最小整数向量 ALU；支持 VLEN=128 的 vv/vx/vi 基础算术逻辑
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import V_PKG::*;

module VectorALU (
    input  ID_2_VEX  id_2_vex,
    output VEX_2_VWB vex_2_vwb
);

    function automatic u64 sext5(input u5 value);
        begin
            sext5 = {{59{value[4]}}, value};
        end
    endfunction

    function automatic u64 elem_mask(input int sew_bits);
        begin
            unique case (sew_bits)
                8:  elem_mask = 64'hff;
                16: elem_mask = 64'hffff;
                32: elem_mask = 64'hffff_ffff;
                default: elem_mask = 64'hffff_ffff_ffff_ffff;
            endcase
        end
    endfunction

    function automatic u64 read_elem(input vreg_t data, input int index, input int sew_bits);
        u64 value;
        begin
            value = 64'b0;
            unique case (sew_bits)
                8:  value[7:0]   = data[index * 8 +: 8];
                16: value[15:0]  = data[index * 16 +: 16];
                32: value[31:0]  = data[index * 32 +: 32];
                default: value   = data[index * 64 +: 64];
            endcase
            read_elem = value;
        end
    endfunction

    function automatic vreg_t write_elem(input vreg_t data, input int index, input int sew_bits, input u64 value);
        vreg_t next_data;
        begin
            next_data = data;
            unique case (sew_bits)
                8:  next_data[index * 8 +: 8]   = value[7:0];
                16: next_data[index * 16 +: 16] = value[15:0];
                32: next_data[index * 32 +: 32] = value[31:0];
                default: next_data[index * 64 +: 64] = value;
            endcase
            write_elem = next_data;
        end
    endfunction

    function automatic u64 sra_elem(input u64 lhs, input u64 rhs, input int sew_bits);
        begin
            unique case (sew_bits)
                8:  sra_elem = {56'b0, u8'($signed(lhs[7:0]) >>> rhs[2:0])};
                16: sra_elem = {48'b0, u16'($signed(lhs[15:0]) >>> rhs[3:0])};
                32: sra_elem = {32'b0, u32'($signed(lhs[31:0]) >>> rhs[4:0])};
                default: sra_elem = u64'($signed(lhs) >>> rhs[5:0]);
            endcase
        end
    endfunction

    int sew_bits;
    int elem_count;
    u64 lhs;
    u64 rhs;
    u64 res;
    u64 mask_value;
    u64 shift_mask;
    vreg_t result_w;

    always_comb begin
        unique case (id_2_vex.state.vtype[5:3])
            3'd0: sew_bits = 8;
            3'd1: sew_bits = 16;
            3'd2: sew_bits = 32;
            default: sew_bits = 64;
        endcase

        elem_count = VLEN_BITS / sew_bits;
        mask_value = elem_mask(sew_bits);
        shift_mask = (sew_bits == 64) ? 64'h3f
                   : (sew_bits == 32) ? 64'h1f
                   : (sew_bits == 16) ? 64'h0f
                   :                    64'h07;

        result_w = id_2_vex.vd_old_data;

        for (int i = 0; i < VLEN_BITS / 8; i++) begin
            lhs = 64'b0;
            rhs = 64'b0;
            res = 64'b0;

            if (i < elem_count) begin
                lhs = read_elem(id_2_vex.vs2_data, i, sew_bits);
                unique case (id_2_vex.format)
                    V_FMT_VV: rhs = read_elem(id_2_vex.vs1_data, i, sew_bits);
                    V_FMT_VX: rhs = id_2_vex.scalar_rs1_data;
                    V_FMT_VI: rhs = sext5(id_2_vex.uimm);
                    default:  rhs = 64'b0;
                endcase

                unique case (id_2_vex.alu_op)
                    V_ALU_ADD: res = (lhs + rhs) & mask_value;
                    V_ALU_SUB: res = (lhs - rhs) & mask_value;
                    V_ALU_AND: res = (lhs & rhs) & mask_value;
                    V_ALU_OR:  res = (lhs | rhs) & mask_value;
                    V_ALU_XOR: res = (lhs ^ rhs) & mask_value;
                    V_ALU_SLL: res = (lhs << (rhs & shift_mask)) & mask_value;
                    V_ALU_SRL: res = (lhs >> (rhs & shift_mask)) & mask_value;
                    V_ALU_SRA: res = sra_elem(lhs, rhs, sew_bits) & mask_value;
                    default:   res = lhs & mask_value;
                endcase

                if ((i < id_2_vex.state.vl) && (id_2_vex.vm || id_2_vex.mask_data[i])) begin
                    result_w = write_elem(result_w, i, sew_bits, res);
                end
            end
        end
    end

    assign vex_2_vwb.write_en = id_2_vex.valid;
    assign vex_2_vwb.vd       = id_2_vex.vd;
    assign vex_2_vwb.result   = result_w;

endmodule
