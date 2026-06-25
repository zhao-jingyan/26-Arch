// ----------------------------------------------------------------------------
// File        : ID_PKG.sv
// Description : RISC-V 基础 opcode / funct 常量，仅供 ID Stage 内部使用
// ----------------------------------------------------------------------------

`ifndef ID_PKG
`define ID_PKG

package ID_PKG;
    // RISC-V base opcodes
    localparam logic [6:0] OP_IMM    = 7'b0010011;  // addi/xori/ori/andi/slti/sltiu/slli/srli/srai
    localparam logic [6:0] OP        = 7'b0110011;  // add/sub/xor/or/and/sll/srl/sra/slt/sltu
    localparam logic [6:0] OP_IMM32  = 7'b0011011;  // addiw/slliw/srliw/sraiw
    localparam logic [6:0] OP_32     = 7'b0111011;  // addw/subw/sllw/srlw/sraw
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_MISC_MEM = 7'b0001111;  // fence / fence.i，当前按流水线同步 NOP 处理
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;
    localparam logic [6:0] OP_AMO    = 7'b0101111;
    localparam logic [6:0] OP_VECTOR_LOAD  = 7'b0000111;  // RVV vector load，与浮点 load 共用主 opcode
    localparam logic [6:0] OP_VECTOR_STORE = 7'b0100111;  // RVV vector store，与浮点 store 共用主 opcode
    localparam logic [6:0] OP_VECTOR       = 7'b1010111;  // RVV OP-V

    // SYSTEM/funct3=000 指令
    localparam logic [11:0] FUNCT12_ECALL = 12'h000;
    localparam logic [11:0] FUNCT12_SRET  = 12'h102;
    localparam logic [11:0] FUNCT12_MRET  = 12'h302;

    // funct7 关键编码
    localparam logic [6:0] FUNCT7_M       = 7'b0000001;  // M 扩展（当前未迁移）
    localparam logic [6:0] FUNCT7_SUB_SRA = 7'b0100000;  // sub / subw / sra / srai / sraw / sraiw

    // A 扩展 funct5（inst[31:27]），本实验只实现 word 版本
    localparam logic [4:0] AMO_LR      = 5'b00010;
    localparam logic [4:0] AMO_SC      = 5'b00011;
    localparam logic [4:0] AMO_SWAP    = 5'b00001;
    localparam logic [4:0] AMO_ADD     = 5'b00000;
    localparam logic [4:0] AMO_XOR     = 5'b00100;
    localparam logic [4:0] AMO_AND     = 5'b01100;
    localparam logic [4:0] AMO_OR      = 5'b01000;
    localparam logic [4:0] AMO_MIN     = 5'b10000;
    localparam logic [4:0] AMO_MAX     = 5'b10100;
    localparam logic [4:0] AMO_MINU    = 5'b11000;
    localparam logic [4:0] AMO_MAXU    = 5'b11100;

    typedef enum logic [3:0] {
        AMO_OP_NONE  = 4'd0,
        AMO_OP_LR    = 4'd1,
        AMO_OP_SC    = 4'd2,
        AMO_OP_SWAP  = 4'd3,
        AMO_OP_ADD   = 4'd4,
        AMO_OP_XOR   = 4'd5,
        AMO_OP_AND   = 4'd6,
        AMO_OP_OR    = 4'd7,
        AMO_OP_MIN   = 4'd8,
        AMO_OP_MAX   = 4'd9,
        AMO_OP_MINU  = 4'd10,
        AMO_OP_MAXU  = 4'd11
    } AMO_OP;
endpackage

`endif
