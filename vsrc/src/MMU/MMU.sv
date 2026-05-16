// ----------------------------------------------------------------------------
// File        : MMU.sv
// Description : Sv39 happy-path page walker + dbus address translation
// ----------------------------------------------------------------------------

`ifdef VERILATOR
`include "include/common.sv"
`include "src/top_pkg.sv"
`endif

import common::*;
import top_pkg::*;

module MMU (
    input  logic       clk,
    input  logic       rst_n,

    input  dbus_req_t  upstream_request,
    output dbus_resp_t upstream_response,
    output dbus_req_t  downstream_request,
    input  dbus_resp_t downstream_response,

    input  u64         satp,
    input  PRIV_MODE   priv_mode
);

    typedef enum logic [2:0] {
        IDLE,
        PASSTHROUGH,
        WALK_L2,
        WALK_L1,
        WALK_L0,
        ACCESS
    } state_t;

    state_t    state;
    dbus_req_t saved_request;
    u64        pte;
    logic [1:0] leaf_level;  // 2=L2 1GiB, 1=L1 2MiB, 0=L0 4KiB

    logic is_virtual_priv;
    logic is_sv39_mode;
    logic should_translate;

    // 仅 S/U 模式且 satp.MODE=Sv39 时启用地址翻译
    assign is_virtual_priv  = (priv_mode == PRIV_S) || (priv_mode == PRIV_U);
    assign is_sv39_mode     = satp[63:60] == 4'd8;
    assign should_translate = is_virtual_priv && is_sv39_mode;

    function automatic u64 pte_addr(input u64 base, input logic [8:0] vpn);
        pte_addr = base + {52'b0, vpn, 3'b000};
    endfunction

    u64 root_base;
    u64 pte_base;
    u64 walk_addr;
    u64 translated_addr;

    assign root_base = {8'b0, satp[43:0], 12'b0};
    assign pte_base  = {8'b0, pte[53:10], 12'b0};

    always_comb begin
        unique case (leaf_level)
            2'd2:    translated_addr = {8'b0, pte[53:28], saved_request.addr[29:0]};
            2'd1:    translated_addr = {8'b0, pte[53:19], saved_request.addr[20:0]};
            default: translated_addr = {8'b0, pte[53:10], saved_request.addr[11:0]};
        endcase
    end

    always_comb begin
        unique case (state)
            WALK_L2:  walk_addr = pte_addr(root_base, saved_request.addr[38:30]);
            WALK_L1:  walk_addr = pte_addr(pte_base,  saved_request.addr[29:21]);
            default:  walk_addr = pte_addr(pte_base,  saved_request.addr[20:12]);
        endcase
    end

    always_comb begin
        downstream_request = '0;
        upstream_response  = '0;

        unique case (state)
            PASSTHROUGH: begin
                downstream_request = saved_request;
                upstream_response  = downstream_response;
            end
            WALK_L2, WALK_L1, WALK_L0: begin
                downstream_request.valid  = 1'b1;
                downstream_request.addr   = walk_addr;
                downstream_request.size   = MSIZE8;
                downstream_request.strobe = 8'b0;
                downstream_request.data   = 64'b0;
            end
            ACCESS: begin
                downstream_request        = saved_request;
                downstream_request.addr   = translated_addr;
                upstream_response         = downstream_response;
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            saved_request <= '0;
            pte           <= '0;
            leaf_level    <= 2'd0;
        end
        else begin
            unique case (state)
                IDLE: begin
                    if (upstream_request.valid) begin
                        saved_request <= upstream_request;
                        state <= should_translate ? WALK_L2 : PASSTHROUGH;
                    end
                end
                PASSTHROUGH: begin
                    if (downstream_response.data_ok) begin
                        state <= IDLE;
                    end
                end
                WALK_L2: begin
                    if (downstream_response.data_ok) begin
                        pte   <= downstream_response.data;
                        if (downstream_response.data[1] || downstream_response.data[3]) begin
                            leaf_level <= 2'd2;
                            state      <= ACCESS;
                        end
                        else begin
                            state <= WALK_L1;
                        end
                    end
                end
                WALK_L1: begin
                    if (downstream_response.data_ok) begin
                        pte   <= downstream_response.data;
                        if (downstream_response.data[1] || downstream_response.data[3]) begin
                            leaf_level <= 2'd1;
                            state      <= ACCESS;
                        end
                        else begin
                            state <= WALK_L0;
                        end
                    end
                end
                WALK_L0: begin
                    if (downstream_response.data_ok) begin
                        pte        <= downstream_response.data;
                        leaf_level <= 2'd0;
                        state      <= ACCESS;
                    end
                end
                ACCESS: begin
                    if (downstream_response.data_ok) begin
                        state <= IDLE;
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
