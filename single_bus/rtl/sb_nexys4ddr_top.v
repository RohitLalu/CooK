// sb_nexys4ddr_top.v
// Board top of the single-bus baseline for the Digilent Nexys4 DDR
// (xc7a100tcsg324-1). Same pins, clocking, reset, LEDs and display as the
// NoC's nexys4ddr_top, so the two boards read the same way and share
// rtl/board/nexys4ddr/nexys4ddr.xdc. Its own Vivado project:
// single_bus/vivado_proj.
//
//   CLK100MHZ -> MMCM -> CLK_MHZ system clock, and 200 MHz for the MIG (the
//                MMCM is only instantiated when SYNTHESIS is defined)
//   CPU_RESETN and MMCM lock -> reset_sync -> rst_n
//
// LEDs
//   LED[2:0]    core 0..2 has any error      LED[3]   memory node has an error
//   LED[6:4]    core 0..2 software reported pass (status CSR 0x600Dxxxx)
//   LED[10:8]   core 0..2 software reported fail (status CSR 0xFA11xxxx)
//   LED[12]     heartbeat, 1 Hz
//   LED[13]     system ready: reset released (there is no BIST to wait for)
//   LED[14]     slow blink code: TILE+1      LED[15]  slow blink code: error CODE
//   LED16_G     DDR2 calibration complete    LED17_R  a bus fault is switched in
// 7-segment display: code, tile, 0, low half of that tile's status CSR
// (codes in rtl/board/status_panel.v; the router and BIST codes cannot occur).
//
// FAULT INJECTION SWITCHES (metric M3, the counterpart of the NoC's)
//   SW[12] on = inject a bus fault, SW[11] = 0 stuck arbiter / 1 flipped data
//   wire. Set them, press CPU_RESET: every core times out and reports failure.
//
// DDR = 1: the sb_mem block design (single_bus/rtl/create_sb_mem.tcl:
// SmartConnect + MIG) connects the memory node's AXI4 master to the on-board
// DDR2. DDR = 0: no memory controller; the memory node's AXI port answers
// every access with SLVERR, so DDR reads return POISON. Testbenches use 0.

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_nexys4ddr_top #(
    parameter integer CLK_MHZ        = 50,
    parameter         MEM_PREFIX     = "tile",      // tileNN.mem from sw/build.sh
    parameter integer UNIT_CYCLES    = CLK_MHZ * 250_000,
    parameter integer HEART_CYCLES   = CLK_MHZ * 500_000,
    parameter integer REFRESH_CYCLES = CLK_MHZ * 1_000,
    parameter integer DDR            = 1
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNC,          // unused: kept so the NoC's constraints apply as they are
    input  wire [15:0] SW,
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

    localparam integer NT = `NOC_NUM_TILES;

    generate
        if ((1000 % CLK_MHZ) != 0 || (1000 / CLK_MHZ) < 2 || (1000 / CLK_MHZ) > 128) begin : top_check_clk
            BOARD_CONFIG_ERROR_CLK_MHZ_must_divide_1000_with_divider_2_to_128 u_err ();
        end
        if (NT != 4) begin : top_check_nt
            BOARD_CONFIG_ERROR_bus_board_assumes_four_node_ids u_err ();
        end
    endgenerate

    // ---------------------------------------------------------------
    // clock and reset (as nexys4ddr_top)
    // ---------------------------------------------------------------
    wire clk, clk200, locked;
`ifdef SYNTHESIS
    wire clk_mmcm, clk200_mmcm, clk_fb;
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

    wire rst_n;
    reset_sync #(.STAGES(3)) u_rst (.clk(clk), .arst_n(CPU_RESETN & locked), .rst_n(rst_n));

    (* ASYNC_REG = "TRUE" *) reg [15:0] sw_s1, sw_s2;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin sw_s1 <= 16'b0; sw_s2 <= 16'b0; end
        else        begin sw_s1 <= SW;    sw_s2 <= sw_s1; end
    wire fault_grant = sw_s2[12] && !sw_s2[11];
    wire fault_flip  = sw_s2[12] &&  sw_s2[11];

    // ---------------------------------------------------------------
    // the system
    // ---------------------------------------------------------------
    wire [NT-1:0]    tile_trap, bus_err_drop;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;

    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [7:0]  awlen, arlen;
    wire [2:0]  awsize, arsize;
    wire [1:0]  awburst, arburst, bresp, rresp;
    wire [3:0]  wstrb;
    wire        awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rlast, rvalid, rready;
    wire        ddr_calib_done;

    sb_top #(.MEM_INIT(1), .MEM_PREFIX(MEM_PREFIX)) u_sys (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .fault_grant(fault_grant), .fault_flip(fault_flip),
        .bus_err_drop(bus_err_drop), .bus_active(),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    generate
        if (DDR != 0) begin : g_ddr
            // SmartConnect (clock crossing to the MIG's ui_clk) + MIG
            sb_mem_wrapper u_bd (
                .clk50(clk), .clk200(clk200), .rst_n(rst_n),
                .mem_axi_awaddr(awaddr), .mem_axi_awlen(awlen), .mem_axi_awsize(awsize),
                .mem_axi_awburst(awburst), .mem_axi_awvalid(awvalid), .mem_axi_awready(awready),
                .mem_axi_wdata(wdata), .mem_axi_wstrb(wstrb), .mem_axi_wlast(wlast),
                .mem_axi_wvalid(wvalid), .mem_axi_wready(wready),
                .mem_axi_bresp(bresp), .mem_axi_bvalid(bvalid), .mem_axi_bready(bready),
                .mem_axi_araddr(araddr), .mem_axi_arlen(arlen), .mem_axi_arsize(arsize),
                .mem_axi_arburst(arburst), .mem_axi_arvalid(arvalid), .mem_axi_arready(arready),
                .mem_axi_rdata(rdata), .mem_axi_rresp(rresp), .mem_axi_rlast(rlast),
                .mem_axi_rvalid(rvalid), .mem_axi_rready(rready),
                .init_calib_complete(ddr_calib_done),
                .ddr2_sdram_addr(ddr2_addr), .ddr2_sdram_ba(ddr2_ba),
                .ddr2_sdram_cas_n(ddr2_cas_n), .ddr2_sdram_ck_n(ddr2_ck_n),
                .ddr2_sdram_ck_p(ddr2_ck_p), .ddr2_sdram_cke(ddr2_cke),
                .ddr2_sdram_cs_n(ddr2_cs_n), .ddr2_sdram_dm(ddr2_dm),
                .ddr2_sdram_dq(ddr2_dq), .ddr2_sdram_dqs_n(ddr2_dqs_n),
                .ddr2_sdram_dqs_p(ddr2_dqs_p), .ddr2_sdram_odt(ddr2_odt),
                .ddr2_sdram_ras_n(ddr2_ras_n), .ddr2_sdram_we_n(ddr2_we_n)
            );
        end else begin : g_no_ddr
            // no memory behind the node: accept everything, answer SLVERR
            assign awready = 1'b1;  assign wready = 1'b1;
            assign bvalid  = 1'b1;  assign bresp  = 2'b10;
            assign arready = 1'b1;  assign rvalid = 1'b1;
            assign rdata   = 32'b0; assign rresp  = 2'b10;  assign rlast = 1'b1;
            assign ddr_calib_done = 1'b0;
            // DDR2 idle: clock disabled, chip deselected
            assign ddr2_addr = 13'b0;  assign ddr2_ba = 3'b0;
            assign ddr2_cas_n = 1'b1;  assign ddr2_ras_n = 1'b1;  assign ddr2_we_n = 1'b1;
            assign ddr2_ck_n = 1'b1;   assign ddr2_ck_p = 1'b0;   assign ddr2_cke = 1'b0;
            assign ddr2_cs_n = 1'b1;   assign ddr2_dm = 2'b0;     assign ddr2_odt = 1'b0;
            assign ddr2_dq = 16'bz;    assign ddr2_dqs_n = 2'bz;  assign ddr2_dqs_p = 2'bz;
        end
    endgenerate

    assign LED16_G = ddr_calib_done;
    assign LED17_B = 1'b0;
    assign LED17_R = sw_s2[12];

    // ---------------------------------------------------------------
    // status: the NoC's panel, with the router and BIST inputs tied off
    // ---------------------------------------------------------------
    wire          code_led, tile_led, heartbeat;
    wire [NT-1:0] tile_bad, tile_pass, tile_fail;
    wire [31:0]   display;

    status_panel #(.UNIT_CYCLES(UNIT_CYCLES), .HEART_CYCLES(HEART_CYCLES), .GW_TILE(-1)) u_panel (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .rt_in_err({NT*5*`NOC_E_W{1'b0}}), .rt_out_dead({NT*5{1'b0}}), .rt_out_wd({NT*5{1'b0}}),
        .bist_status({NT*10{1'b1}}), .bist_done(1'b0), .gw_flags(3'b0), .gw_info(32'b0),
        .bist_fault(),
        .code_led(code_led), .tile_led(tile_led), .heartbeat(heartbeat),
        .tile_bad(tile_bad), .tile_pass(tile_pass), .tile_fail(tile_fail),
        .display(display), .cur_code(), .cur_tile()
    );

    seven_seg #(.REFRESH_CYCLES(REFRESH_CYCLES)) u_7seg (
        .clk(clk), .rst_n(rst_n), .value(display), .seg(SEG), .an(AN)
    );
    assign DP = 1'b1;

    assign LED = {code_led, tile_led, rst_n, heartbeat, tile_fail, tile_pass, tile_bad};

endmodule
