// nexys4ddr_top.v
// Board top for the Digilent Nexys4 DDR (xc7a100tcsg324-1).
//
//   CLK100MHZ -> MMCM -> CLK_MHZ system clock (100 MHz passes straight
//                through in simulation; the MMCM is only instantiated when
//                the synthesis tool defines SYNTHESIS, as Vivado does)
//   CPU_RESETN (red button) and MMCM lock -> reset_sync -> rst_n
//   BTNC      clears router error flags (err_clear). BIST will OR its own
//             clear into this later.
//
// LEDs
//   LED[3:0]    tile 0..3 has any error
//   LED[7:4]    tile 0..3 software reported pass (status CSR 0x600Dxxxx)
//   LED[11:8]   tile 0..3 software reported fail (status CSR 0xFA11xxxx)
//   LED[12]     heartbeat, 1 Hz: the clock is running
//   LED[13]     out of reset (MMCM locked, reset released)
//   LED[14]     slow blink code: TILE+1 blinks
//   LED[15]     slow blink code: error CODE blinks (table in status_panel.v)
// 7-segment display: code, tile, 0, and the low half of that tile's status CSR.
//
// BIST ATTACH POINT: port_disable and err_clear go into mesh_top from here,
// and every status signal is observed, never consumed. When BIST arrives it
// is instantiated in this file, drives port_disable, ORs into err_clear, and
// reads the same status buses.

`timescale 1ns/1ps
`include "noc_defs.vh"

module nexys4ddr_top #(
    parameter integer CLK_MHZ        = 50,          // system clock after the MMCM
    parameter         MEM_PREFIX     = "tile",      // tileNN.mem from sw/build.sh
    parameter integer UNIT_CYCLES    = CLK_MHZ * 250_000,   // 0.25 s
    parameter integer HEART_CYCLES   = CLK_MHZ * 500_000,   // 0.5 s half period
    parameter integer REFRESH_CYCLES = CLK_MHZ * 1_000      // 1 ms per digit
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNC,
    output wire [15:0] LED,
    output wire [6:0]  SEG,     // {CG,CF,CE,CD,CC,CB,CA}
    output wire        DP,
    output wire [7:0]  AN
);

    localparam integer NT = `NOC_NUM_TILES;

    generate
        if ((1000 % CLK_MHZ) != 0 || (1000 / CLK_MHZ) < 2 || (1000 / CLK_MHZ) > 128) begin : top_check_clk
            BOARD_CONFIG_ERROR_CLK_MHZ_must_divide_1000_with_divider_2_to_128 u_err ();
        end
    endgenerate

    // ---------------------------------------------------------------
    // clock
    // ---------------------------------------------------------------
    wire clk;
    wire locked;

`ifdef SYNTHESIS
    wire clk_mmcm, clk_fb;
    // VCO = 100 MHz * 10 = 1000 MHz (legal range for -1 is 600..1200 MHz)
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0),
        .CLKOUT0_DIVIDE_F(1000.0 / CLK_MHZ)
    ) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb), .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_mmcm), .LOCKED(locked),
        .PWRDWN(1'b0), .RST(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG u_bufg (.I(clk_mmcm), .O(clk));
`else
    assign clk    = CLK100MHZ;
    assign locked = 1'b1;
`endif

    // ---------------------------------------------------------------
    // reset and button
    // ---------------------------------------------------------------
    wire rst_n;
    reset_sync #(.STAGES(3)) u_rst (.clk(clk), .arst_n(CPU_RESETN & locked), .rst_n(rst_n));

    (* ASYNC_REG = "TRUE" *) reg [1:0] btnc_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) btnc_sync <= 2'b00;
        else        btnc_sync <= {btnc_sync[0], BTNC};
    wire err_clear = btnc_sync[1];

    // ---------------------------------------------------------------
    // the system
    // ---------------------------------------------------------------
    wire [NT-1:0]                 tile_trap;
    wire [NT*5-1:0]               tile_err;
    wire [NT*32-1:0]              tile_sw;
    wire [NT*5*`NOC_E_W-1:0]      rt_in_err;
    wire [NT*5-1:0]               rt_out_dead, rt_out_wd;
    wire [NT*8-1:0]               rt_drop_cnt;

    mesh_top #(
        .MEM_INIT(1),
        .MEM_PREFIX(MEM_PREFIX)
    ) u_sys (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}),     // BIST drives this later
        .err_clear(err_clear),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt)
    );

    // ---------------------------------------------------------------
    // status: LEDs and display
    // ---------------------------------------------------------------
    wire          code_led, tile_led, heartbeat;
    wire [NT-1:0] tile_bad, tile_pass, tile_fail;
    wire [31:0]   display;

    status_panel #(
        .UNIT_CYCLES(UNIT_CYCLES), .HEART_CYCLES(HEART_CYCLES)
    ) u_panel (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead), .rt_out_wd(rt_out_wd),
        .code_led(code_led), .tile_led(tile_led), .heartbeat(heartbeat),
        .tile_bad(tile_bad), .tile_pass(tile_pass), .tile_fail(tile_fail),
        .display(display), .cur_code(), .cur_tile()
    );

    seven_seg #(.REFRESH_CYCLES(REFRESH_CYCLES)) u_7seg (
        .clk(clk), .rst_n(rst_n), .value(display), .seg(SEG), .an(AN)
    );
    assign DP = 1'b1;   // decimal points off

    // first four tiles get individual LEDs; the blink codes cover every tile
    localparam integer NL = (NT < 4) ? NT : 4;
    wire [3:0] led_bad  = {{(4-NL){1'b0}}, tile_bad [NL-1:0]};
    wire [3:0] led_pass = {{(4-NL){1'b0}}, tile_pass[NL-1:0]};
    wire [3:0] led_fail = {{(4-NL){1'b0}}, tile_fail[NL-1:0]};

    assign LED = {code_led, tile_led, rst_n, heartbeat, led_fail, led_pass, led_bad};

endmodule
