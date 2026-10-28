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
// RGB LEDs (GATEWAY = 1)
//   LED16_G     DDR2 calibration complete (MIG init_calib_complete)
//   LED17_B     AXI DMA interrupt pending (MM2S or S2MM)
//
// GATEWAY = 1: tile 3 is the DMA/DDR gateway (gw_ni in mesh_top, no core) and
// the cook_gw block design (rtl/dma_ddr/create_cook_gw.tcl: axi_dma +
// SmartConnect + MIG) connects it to the on-board 128 MB DDR2. The MMCM's
// CLKOUT1 supplies the MIG's 200 MHz system clock. The DDR2 pin locations
// and I/O standards come from the MIG IP (rtl/dma_ddr/mig_nexys4ddr.prj).
// GATEWAY = 0: the original four-core system; the DDR2 ports are unused.
// The MIG has no simulation model here, so testbenches of this top use
// GATEWAY = 0; the gateway is simulated with the real axi_dma in
// tb/tb_gw_dma_ip.v.
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
    parameter integer REFRESH_CYCLES = CLK_MHZ * 1_000,     // 1 ms per digit
    parameter integer GATEWAY        = 1                    // tile 3 = DMA/DDR gateway
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNC,
    output wire [15:0] LED,
    output wire [6:0]  SEG,     // {CG,CF,CE,CD,CC,CB,CA}
    output wire        DP,
    output wire [7:0]  AN,
    output wire        LED16_G,
    output wire        LED17_B,

    // DDR2 SDRAM (MT47H64M16HR-25E), driven by the MIG in cook_gw
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
    wire clk200;        // MIG system/reference clock (GATEWAY = 1)
    wire locked;

`ifdef SYNTHESIS
    wire clk_mmcm, clk200_mmcm, clk_fb;
    // VCO = 100 MHz * 10 = 1000 MHz (legal range for -1 is 600..1200 MHz)
    // CLKOUT1 = 1000 / 5 = 200 MHz for the MIG
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0),
        .CLKOUT0_DIVIDE_F(1000.0 / CLK_MHZ),
        .CLKOUT1_DIVIDE(5)
    ) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb), .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_mmcm), .CLKOUT1(clk200_mmcm), .LOCKED(locked),
        .PWRDWN(1'b0), .RST(1'b0),
        .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG u_bufg    (.I(clk_mmcm),    .O(clk));
    BUFG u_bufg200 (.I(clk200_mmcm), .O(clk200));
`else
    assign clk    = CLK100MHZ;
    assign clk200 = 1'b0;
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

    // gateway <-> block design
    wire [9:0]  gw_awaddr, gw_araddr;
    wire        gw_awvalid, gw_awready, gw_wvalid, gw_wready, gw_bvalid, gw_bready;
    wire        gw_arvalid, gw_arready, gw_rvalid, gw_rready;
    wire [31:0] gw_wdata, gw_rdata;
    wire [3:0]  gw_wstrb;
    wire [1:0]  gw_bresp, gw_rresp;
    wire [31:0] gw_mm2s_tdata, gw_s2mm_tdata;
    wire [3:0]  gw_mm2s_tkeep, gw_s2mm_tkeep;
    wire        gw_mm2s_tlast, gw_mm2s_tvalid, gw_mm2s_tready;
    wire        gw_s2mm_tlast, gw_s2mm_tvalid, gw_s2mm_tready;
    wire        mm2s_irq, s2mm_irq, ddr_calib_done;

    mesh_top #(
        .MEM_INIT(1),
        .MEM_PREFIX(MEM_PREFIX),
        .GW_EN(GATEWAY),
        .GW_TILE(NT - 1)
    ) u_sys (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}),     // BIST drives this later
        .err_clear(err_clear),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt),
        .gw_axil_awaddr(gw_awaddr), .gw_axil_awvalid(gw_awvalid), .gw_axil_awready(gw_awready),
        .gw_axil_wdata(gw_wdata), .gw_axil_wstrb(gw_wstrb), .gw_axil_wvalid(gw_wvalid),
        .gw_axil_wready(gw_wready),
        .gw_axil_bresp(gw_bresp), .gw_axil_bvalid(gw_bvalid), .gw_axil_bready(gw_bready),
        .gw_axil_araddr(gw_araddr), .gw_axil_arvalid(gw_arvalid), .gw_axil_arready(gw_arready),
        .gw_axil_rdata(gw_rdata), .gw_axil_rresp(gw_rresp), .gw_axil_rvalid(gw_rvalid),
        .gw_axil_rready(gw_rready),
        .gw_mm2s_tdata(gw_mm2s_tdata), .gw_mm2s_tkeep(gw_mm2s_tkeep), .gw_mm2s_tlast(gw_mm2s_tlast),
        .gw_mm2s_tvalid(gw_mm2s_tvalid), .gw_mm2s_tready(gw_mm2s_tready),
        .gw_s2mm_tdata(gw_s2mm_tdata), .gw_s2mm_tkeep(gw_s2mm_tkeep), .gw_s2mm_tlast(gw_s2mm_tlast),
        .gw_s2mm_tvalid(gw_s2mm_tvalid), .gw_s2mm_tready(gw_s2mm_tready)
    );

    generate
        if (GATEWAY != 0) begin : g_gw
            // axi_dma + SmartConnect + MIG; axi_dma's AXI4-Lite port has no
            // WSTRB (it ignores byte strobes), so gw_wstrb stays unconnected
            cook_gw_wrapper u_bd (
                .clk50(clk), .clk200(clk200), .rst_n(rst_n),
                .dma_ctrl_awaddr(gw_awaddr), .dma_ctrl_awvalid(gw_awvalid), .dma_ctrl_awready(gw_awready),
                .dma_ctrl_wdata(gw_wdata), .dma_ctrl_wvalid(gw_wvalid), .dma_ctrl_wready(gw_wready),
                .dma_ctrl_bresp(gw_bresp), .dma_ctrl_bvalid(gw_bvalid), .dma_ctrl_bready(gw_bready),
                .dma_ctrl_araddr(gw_araddr), .dma_ctrl_arvalid(gw_arvalid), .dma_ctrl_arready(gw_arready),
                .dma_ctrl_rdata(gw_rdata), .dma_ctrl_rresp(gw_rresp), .dma_ctrl_rvalid(gw_rvalid),
                .dma_ctrl_rready(gw_rready),
                .mm2s_axis_tdata(gw_mm2s_tdata), .mm2s_axis_tkeep(gw_mm2s_tkeep),
                .mm2s_axis_tlast(gw_mm2s_tlast), .mm2s_axis_tvalid(gw_mm2s_tvalid),
                .mm2s_axis_tready(gw_mm2s_tready),
                .s2mm_axis_tdata(gw_s2mm_tdata), .s2mm_axis_tkeep(gw_s2mm_tkeep),
                .s2mm_axis_tlast(gw_s2mm_tlast), .s2mm_axis_tvalid(gw_s2mm_tvalid),
                .s2mm_axis_tready(gw_s2mm_tready),
                .mm2s_introut(mm2s_irq), .s2mm_introut(s2mm_irq),
                .init_calib_complete(ddr_calib_done),
                .ddr2_sdram_addr(ddr2_addr), .ddr2_sdram_ba(ddr2_ba),
                .ddr2_sdram_cas_n(ddr2_cas_n), .ddr2_sdram_ck_n(ddr2_ck_n),
                .ddr2_sdram_ck_p(ddr2_ck_p), .ddr2_sdram_cke(ddr2_cke),
                .ddr2_sdram_cs_n(ddr2_cs_n), .ddr2_sdram_dm(ddr2_dm),
                .ddr2_sdram_dq(ddr2_dq), .ddr2_sdram_dqs_n(ddr2_dqs_n),
                .ddr2_sdram_dqs_p(ddr2_dqs_p), .ddr2_sdram_odt(ddr2_odt),
                .ddr2_sdram_ras_n(ddr2_ras_n), .ddr2_sdram_we_n(ddr2_we_n)
            );
        end else begin : g_no_gw
            assign gw_awready = 1'b0;  assign gw_wready  = 1'b0;
            assign gw_bresp   = 2'b0;  assign gw_bvalid  = 1'b0;
            assign gw_arready = 1'b0;  assign gw_rdata   = 32'b0;
            assign gw_rresp   = 2'b0;  assign gw_rvalid  = 1'b0;
            assign gw_mm2s_tdata = 32'b0;  assign gw_mm2s_tkeep = 4'b0;
            assign gw_mm2s_tlast = 1'b0;   assign gw_mm2s_tvalid = 1'b0;
            assign gw_s2mm_tready = 1'b0;
            assign mm2s_irq = 1'b0;  assign s2mm_irq = 1'b0;  assign ddr_calib_done = 1'b0;
            // DDR2 idle: clock disabled, chip deselected
            assign ddr2_addr = 13'b0;  assign ddr2_ba = 3'b0;
            assign ddr2_cas_n = 1'b1;  assign ddr2_ras_n = 1'b1;  assign ddr2_we_n = 1'b1;
            assign ddr2_ck_n = 1'b1;   assign ddr2_ck_p = 1'b0;   assign ddr2_cke = 1'b0;
            assign ddr2_cs_n = 1'b1;   assign ddr2_dm = 2'b0;     assign ddr2_odt = 1'b0;
            assign ddr2_dq = 16'bz;    assign ddr2_dqs_n = 2'bz;  assign ddr2_dqs_p = 2'bz;
        end
    endgenerate

    assign LED16_G = ddr_calib_done;
    assign LED17_B = mm2s_irq | s2mm_irq;

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
