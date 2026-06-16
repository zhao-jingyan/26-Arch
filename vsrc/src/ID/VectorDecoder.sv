// ----------------------------------------------------------------------------
// File        : VectorDecoder.sv
// Description : RVV 指令空间子译码；只产生命名后的向量语义，不驱动执行
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "src/ID/ID_PKG.sv"
`include "src/ID/V_PKG.sv"
`endif

import common::*;
import ID_PKG::*;
import V_PKG::*;

module VectorDecoder (
    input  u32      inst,
    output V_DECODE v_decode
);

    u7 opcode_w;
    u3 funct3;
    u6 funct6;

    assign opcode_w = inst[6:0];
    assign funct3   = inst[14:12];
    assign funct6   = inst[31:26];

    always_comb begin
        v_decode = '0;

        v_decode.vd      = inst[11:7];
        v_decode.vs1     = inst[19:15];
        v_decode.vs2     = inst[24:20];
        v_decode.vm      = inst[25];
        v_decode.funct3  = funct3;
        v_decode.funct6  = funct6;
        v_decode.width   = funct3;
        v_decode.mop     = inst[27:26];
        v_decode.nf      = inst[31:29];
        v_decode.vtypei  = inst[30:20];
        v_decode.format  = V_FMT_NONE;
        v_decode.op_class = V_CLASS_NONE;

        unique case (opcode_w)
            OP_VECTOR: begin
                v_decode.valid = 1'b1;

                unique case (funct3)
                    // vsetvli / vsetivli / vsetvl 都在 OP-V + funct3=111 空间内。
                    3'b111: begin
                        v_decode.op_class = V_CLASS_CONFIG;
                        v_decode.format   = V_FMT_CFG;
                    end

                    // OPIVV / OPIVI / OPIVX：第一阶段统一归入整数 ALU，具体指令留给执行单元细分。
                    3'b000: begin
                        v_decode.op_class = V_CLASS_ALU;
                        v_decode.format   = V_FMT_VV;
                    end
                    3'b011: begin
                        v_decode.op_class = V_CLASS_ALU;
                        v_decode.format   = V_FMT_VI;
                    end
                    3'b100: begin
                        v_decode.op_class = V_CLASS_ALU;
                        v_decode.format   = V_FMT_VX;
                    end

                    // OPMVV / OPMVX 通常承载 mask、归约、重排等操作，先按 funct6 做粗分类。
                    3'b010, 3'b110: begin
                        v_decode.format = (funct3 == 3'b010) ? V_FMT_VV : V_FMT_VX;
                        unique casez (funct6)
                            6'b010111: v_decode.op_class = V_CLASS_MASK;     // vmerge/vmv 一类
                            6'b001100: v_decode.op_class = V_CLASS_PERMUTE;  // vrgather 一类
                            6'b001110: v_decode.op_class = V_CLASS_PERMUTE;  // vslide 一类
                            6'b0000??: v_decode.op_class = V_CLASS_REDUCE;   // 简化捕获常见 reduction 区间
                            default:   v_decode.op_class = V_CLASS_UNKNOWN;
                        endcase
                    end

                    // 浮点向量指令后续放到 Zve64f/Zve64d 阶段。
                    3'b001, 3'b101: begin
                        v_decode.op_class = V_CLASS_UNKNOWN;
                        v_decode.format   = V_FMT_VF;
                    end

                    default: begin
                        v_decode.op_class = V_CLASS_UNKNOWN;
                        v_decode.illegal  = 1'b1;
                    end
                endcase
            end

            OP_VECTOR_LOAD: begin
                v_decode.valid    = 1'b1;
                v_decode.op_class = V_CLASS_LOAD;
                v_decode.format   = V_FMT_MEM;
            end

            OP_VECTOR_STORE: begin
                v_decode.valid    = 1'b1;
                v_decode.op_class = V_CLASS_STORE;
                v_decode.format   = V_FMT_MEM;
            end

            default: ;
        endcase
    end

endmodule
