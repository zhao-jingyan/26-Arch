// ----------------------------------------------------------------------------
// File        : VectorSemantic.sv
// Description : 向量指令语义收敛：把 vset*、向量访存与非法态集中计算
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import V_PKG::*;

module VectorSemantic (
    input  V_DECODE v_decode,
    input  V_STATE  v_state,
    input  u64      rf_read_data_1,
    input  u64      rf_read_data_2,
    input  u64      vlen_bits,

    output V_SEMANTICS v_semantics
);

    function automatic u64 calc_vlmax(input u3 vsew, input u3 vlmul);
        u64 base_elems;
        begin
            base_elems = vlen_bits >> (vsew + 3);
            unique case (vlmul)
                3'b000: calc_vlmax = base_elems;
                3'b001: calc_vlmax = base_elems << 1;
                3'b010: calc_vlmax = base_elems << 2;
                3'b011: calc_vlmax = base_elems << 3;
                3'b111: calc_vlmax = base_elems >> 1;
                3'b110: calc_vlmax = base_elems >> 2;
                3'b101: calc_vlmax = base_elems >> 3;
                default: calc_vlmax = 64'b0;
            endcase
        end
    endfunction

    function automatic logic is_supported_vtype(input u64 vtype_value);
        begin
            is_supported_vtype = (vtype_value[63] == 1'b0)
                              && (vtype_value[62:8] == 55'b0)
                              && (vtype_value[5:3] <= 3'd3)
                              && (vtype_value[2:0] != 3'b100)
                              && (calc_vlmax(vtype_value[5:3], vtype_value[2:0]) != 64'b0);
        end
    endfunction

    logic vset_vtype_ok;
    u64   vset_vtype_raw;
    u64   vset_vlmax;
    u64   vset_avl;

    always_comb begin
        v_semantics = '0;

        v_semantics.is_vset     = v_decode.valid
                               && (v_decode.op_class == V_CLASS_CONFIG)
                               && (v_decode.cfg_kind != V_CFG_NONE);
        v_semantics.is_vset_imm = (v_decode.cfg_kind == V_CFG_SETIVLI);
        v_semantics.is_vset_rs2 = (v_decode.cfg_kind == V_CFG_SETVL);
        v_semantics.is_valusize = v_decode.valid
                               && (v_decode.op_class == V_CLASS_ALU)
                               && (v_decode.alu_op != V_ALU_NONE);
        v_semantics.is_vmem_load = v_decode.valid
                                && (v_decode.op_class == V_CLASS_LOAD)
                                && (v_decode.width == 3'b111)
                                && (v_decode.mop == 2'b00)
                                && (v_decode.nf == 3'b000);
        v_semantics.is_vmem_store = v_decode.valid
                                 && (v_decode.op_class == V_CLASS_STORE)
                                 && (v_decode.width == 3'b111)
                                 && (v_decode.mop == 2'b00)
                                 && (v_decode.nf == 3'b000);
        v_semantics.is_vmem = v_semantics.is_vmem_load || v_semantics.is_vmem_store;
        v_semantics.vector_state_illegal = (v_semantics.is_valusize || v_semantics.is_vmem)
                                        && v_state.vtype[63];

        vset_vtype_raw = 64'b0;
        unique case (v_decode.cfg_kind)
            V_CFG_SETVLI,
            V_CFG_SETIVLI: vset_vtype_raw = {53'b0, v_decode.vtypei};
            V_CFG_SETVL:   vset_vtype_raw = rf_read_data_2;
            default:       vset_vtype_raw = 64'b0;
        endcase

        vset_vtype_ok = is_supported_vtype(vset_vtype_raw);
        vset_vlmax    = calc_vlmax(vset_vtype_raw[5:3], vset_vtype_raw[2:0]);

        unique case (v_decode.cfg_kind)
            V_CFG_SETIVLI: vset_avl = {59'b0, v_decode.uimm};
            V_CFG_SETVLI,
            V_CFG_SETVL: begin
                if (v_decode.vs1 != 5'b0)
                    vset_avl = rf_read_data_1;
                else if (v_decode.vd != 5'b0)
                    vset_avl = 64'hffff_ffff_ffff_ffff;
                else
                    vset_avl = v_state.vl;
            end
            default: vset_avl = 64'b0;
        endcase

        if (!v_semantics.is_vset) begin
            v_semantics.v_req_write_en = 1'b0;
            v_semantics.v_req_vl       = 64'b0;
            v_semantics.v_req_vtype    = 64'b0;
        end else if (!vset_vtype_ok) begin
            v_semantics.v_req_write_en = 1'b1;
            v_semantics.v_req_vl       = 64'b0;
            v_semantics.v_req_vtype    = 64'h8000_0000_0000_0000;
        end else begin
            v_semantics.v_req_write_en = 1'b1;
            v_semantics.v_req_vl       = (vset_avl < vset_vlmax) ? vset_avl : vset_vlmax;
            v_semantics.v_req_vtype    = vset_vtype_raw;
        end
    end

endmodule
