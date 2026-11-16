// nexys4ddr_live_top.v
// Board top for the LIVE DEMO only (the laptop link). It is the normal board
// top, nexys4ddr_top, with the three options the demo needs switched on:
//   LIVE_UART  = 1  the serial port on core 0 (uart_port.v) and text on the
//                   display (seven_seg_text.v), both in this folder
//   RD_PROTECT = 1  a tile's memory outside its mailbox cannot be read by
//                   other tiles, so core 1's keys stay in core 1
//   MEM_PREFIX      the link programs (encryption_code/run_link_sim.py --board)
// Nothing else differs: same pins, same constraints file, same LEDs.
//
// To build the live demo, make THIS module the synthesis top and add the
// three files of this folder to the project. To build anything else, use
// nexys4ddr_top as before: it contains no serial port and needs none of
// these files.
// The project must also define NOC_OFFSET_BITS=16 (64 KB tiles): the link
// programs are C and do not fit in 4 KB. That is a Verilog define for the
// whole project, so it cannot be set from here.

`timescale 1ns/1ps
`include "noc_defs.vh"

module nexys4ddr_live_top #(
    parameter         MEM_PREFIX = "link_board_t",   // link_board_t00.mem .. t02.mem
    parameter integer GATEWAY    = 1
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNC,
    input  wire [15:0] SW,
    input  wire        UART_TXD_IN,
    output wire        UART_RXD_OUT,
    output wire [15:0] LED,
    output wire [6:0]  SEG,
    output wire        DP,
    output wire [7:0]  AN,
    output wire        LED16_G,
    output wire        LED17_B,
    output wire        LED17_R,
    output wire [12:0] ddr2_addr,
    output wire [2:0]  ddr2_ba,
    output wire        ddr2_cas_n,
    output wire [0:0]  ddr2_ck_n,
    output wire [0:0]  ddr2_ck_p,
    output wire [0:0]  ddr2_cke,
    output wire [0:0]  ddr2_cs_n,
    output wire [1:0]  ddr2_dm,
    inout  wire [15:0] ddr2_dq,
    inout  wire [1:0]  ddr2_dqs_n,
    inout  wire [1:0]  ddr2_dqs_p,
    output wire [0:0]  ddr2_odt,
    output wire        ddr2_ras_n,
    output wire        ddr2_we_n
);

    generate
        if (`NOC_OFFSET_BITS < 14) begin : live_check_tiles
            BOARD_CONFIG_ERROR_live_demo_needs_NOC_OFFSET_BITS_16 u_err ();
        end
    endgenerate

    nexys4ddr_top #(
        .MEM_PREFIX(MEM_PREFIX), .GATEWAY(GATEWAY), .LIVE_UART(1), .RD_PROTECT(1)
    ) u_board (
        .CLK100MHZ(CLK100MHZ), .CPU_RESETN(CPU_RESETN), .BTNC(BTNC), .SW(SW),
        .UART_TXD_IN(UART_TXD_IN), .UART_RXD_OUT(UART_RXD_OUT),
        .LED(LED), .SEG(SEG), .DP(DP), .AN(AN),
        .LED16_G(LED16_G), .LED17_B(LED17_B), .LED17_R(LED17_R),
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n), .ddr2_ck_p(ddr2_ck_p), .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n), .ddr2_dm(ddr2_dm), .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p), .ddr2_odt(ddr2_odt),
        .ddr2_ras_n(ddr2_ras_n), .ddr2_we_n(ddr2_we_n)
    );

endmodule
