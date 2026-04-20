// ----------------------------------------------------------------------------
// File        : ALU_PKG.sv
// Description : ALU 子单元（Multiplier / Divider）共用的 FSM 状态枚举
// ----------------------------------------------------------------------------

`ifndef ALU_PKG
`define ALU_PKG

package ALU_PKG;
    // 多周期乘除法 FSM 三态
    typedef enum logic [1:0] {
        IDLE    = 2'd0,
        COMPUTE = 2'd1,
        DONE    = 2'd2
    } ALU_STATE;
endpackage

`endif
