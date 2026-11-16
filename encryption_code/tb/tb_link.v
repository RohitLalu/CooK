// tb_link.v
// The live demo's laptop link in simulation: the NoC with the gateway on
// tile 3, real picorv32 cores on tiles 0..2, and the optional serial port on
// core 0 (UART_EN = 1). The testbench plays the laptop: it sends the bytes of
// a frame file down the serial line and collects what comes back.
//   vvp link.out +img0=<file> +img1=<file> +img2=<file>
//                +frame=<hex bytes, one per line> +nbytes=<n> +nreply=<n> [+limit=<cycles>]
// Prints   LINK reply=<hex bytes>   and   LINK text=<16 hex digits>   (the 8
// display characters, character 0 in the low byte), which run_link_sim.py
// checks against the laptop's own AES.
// The serial line runs at 16 clock cycles per bit so the simulation is short.
//
// -DLINK_LIVE_TOP: the same test through the board top of the live demo,
// nexys4ddr_live_top, as it is built for the FPGA (no gateway: the memory
// controller has no simulation model). The programs then come from the
// board images through MEM_PREFIX, the serial line runs at the real 115200
// baud (434 cycles per bit at 50 MHz), and the text is read from the pins of
// the 7-segment display, not from an internal signal.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_link;

    localparam integer NT  = `NOC_NUM_TILES;
`ifdef LINK_LIVE_TOP
    localparam integer BIT = 434;                // 50 MHz / 115200 baud, as on the board
    parameter PREFIX = "benchmarks/build/link_board_t";
`else
    localparam integer BIT = 16;                 // clock cycles per serial bit
`endif

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         rx = 1'b1;                       // laptop -> board
    wire        tx;                              // board -> laptop
    wire [63:0] text;
    wire        text_en, sys_ready;
    wire [NT-1:0]    tile_trap;
    wire [NT*32-1:0] tile_sw;

`ifdef LINK_LIVE_TOP
    wire [6:0] SEG;
    wire [7:0] AN;
    wire [15:0] LED;
    nexys4ddr_live_top #(.MEM_PREFIX(PREFIX), .GATEWAY(0)) dut (
        .CLK100MHZ(clk), .CPU_RESETN(rst_n), .BTNC(1'b0), .SW(16'b0),
        .UART_TXD_IN(rx), .UART_RXD_OUT(tx), .LED(LED), .SEG(SEG), .DP(), .AN(AN),
        .LED16_G(), .LED17_B(), .LED17_R()
    );
    assign sys_ready = LED[13];
    assign tile_trap = dut.u_board.tile_trap;
    assign tile_sw   = dut.u_board.tile_sw;
    assign text_en   = dut.u_board.uart_text_en;
    // read the display as an eye would: remember the segments lit on each digit
    reg [6:0] seen_seg [0:7];
    integer d;
    always @(posedge clk)
        for (d = 0; d < 8; d = d + 1)
            if (AN[d] === 1'b0) seen_seg[d] <= ~SEG;
    // the eight digits, leftmost first, as 7-segment patterns {g,f,e,d,c,b,a}
    // (AN[7] is the leftmost digit on the board)
    assign text = {1'b0, seen_seg[7], 1'b0, seen_seg[6], 1'b0, seen_seg[5], 1'b0, seen_seg[4],
                   1'b0, seen_seg[3], 1'b0, seen_seg[2], 1'b0, seen_seg[1], 1'b0, seen_seg[0]};
`else
    mesh_top #(.GW_EN(1), .GW_TILE(NT - 1), .UART_EN(1), .UART_CLKS_PER_BIT(BIT)) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(),
        .fault_rt_mask({4*NT{1'b0}}), .fault_rt_flip(1'b0), .fault_router({`NOC_NUM_TILES{1'b0}}),
        .bist_status(), .sys_ready(sys_ready), .avail(), .gw_flags(), .gw_info(),
        .gw_axil_awaddr(), .gw_axil_awvalid(), .gw_axil_awready(1'b0),
        .gw_axil_wdata(), .gw_axil_wstrb(), .gw_axil_wvalid(), .gw_axil_wready(1'b0),
        .gw_axil_bresp(2'b0), .gw_axil_bvalid(1'b0), .gw_axil_bready(),
        .gw_axil_araddr(), .gw_axil_arvalid(), .gw_axil_arready(1'b0),
        .gw_axil_rdata(32'b0), .gw_axil_rresp(2'b0), .gw_axil_rvalid(1'b0), .gw_axil_rready(),
        .gw_mm2s_tdata(32'b0), .gw_mm2s_tkeep(4'b0), .gw_mm2s_tlast(1'b0),
        .gw_mm2s_tvalid(1'b0), .gw_mm2s_tready(),
        .gw_s2mm_tdata(), .gw_s2mm_tkeep(), .gw_s2mm_tlast(),
        .gw_s2mm_tvalid(), .gw_s2mm_tready(1'b0),
        .uart_rx(rx), .uart_tx(tx), .uart_text(text), .uart_text_en(text_en)
    );

`endif

    reg [7:0]       frame [0:255];
    reg [7:0]       got   [0:255];
    reg [8*256-1:0] name;
    integer nbytes, nreply, ngot, limit, i, b, t;

    // the laptop's sender
    task send_byte;
        input [7:0] v;
        integer k;
        begin
            rx = 1'b0;  repeat (BIT) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin rx = v[k]; repeat (BIT) @(posedge clk); end
            rx = 1'b1;  repeat (BIT) @(posedge clk);
        end
    endtask

    // the laptop's receiver: wait for a start bit, sample each bit in its middle
    reg [7:0] rbyte;
    always begin
        @(negedge tx);
        repeat (BIT + BIT / 2) @(posedge clk);
        for (b = 0; b < 8; b = b + 1) begin rbyte[b] = tx; repeat (BIT) @(posedge clk); end
        got[ngot] = rbyte;
        ngot = ngot + 1;
    end

    initial begin
        ngot = 0;
        if (!$value$plusargs("limit=%d", limit)) limit = 3000000;
        if (!$value$plusargs("nbytes=%d", nbytes)) nbytes = 0;
        if (!$value$plusargs("nreply=%d", nreply)) nreply = 0;
        if ($value$plusargs("frame=%s", name)) $readmemh(name, frame, 0, nbytes - 1);
`ifndef LINK_LIVE_TOP
        for (t = 0; t < (1 << (`NOC_OFFSET_BITS - 2)); t = t + 1) begin
            dut.g_tile[0].g_ni.u_ni.mem[t] = 32'b0;
            dut.g_tile[1].g_ni.u_ni.mem[t] = 32'b0;
            dut.g_tile[2].g_ni.u_ni.mem[t] = 32'b0;
        end
        if ($value$plusargs("img0=%s", name)) $readmemh(name, dut.g_tile[0].g_ni.u_ni.mem);
        if ($value$plusargs("img1=%s", name)) $readmemh(name, dut.g_tile[1].g_ni.u_ni.mem);
        if ($value$plusargs("img2=%s", name)) $readmemh(name, dut.g_tile[2].g_ni.u_ni.mem);
`endif
        repeat (4) @(posedge clk);
        rst_n = 1;
        while (!sys_ready) @(posedge clk);
        // the whole message goes out at once, as a laptop would send it; the
        // serial port's queue holds what core 0 has not read yet
        for (i = 0; i < nbytes; i = i + 1) send_byte(frame[i]);
        t = 0;
        while (ngot < nreply && t < limit && tile_trap[2:0] == 3'b0) begin @(posedge clk); t = t + 1; end
        repeat (4 * BIT) @(posedge clk);
`ifdef LINK_LIVE_TOP
        repeat (450000) @(posedge clk);          // one full scan of the display: 8 digits x 1 ms
`endif
        $write("LINK reply=");
        for (i = 0; i < ngot; i = i + 1) $write("%02x", got[i]);
        $write("\n");
        $display("LINK text=%h en=%b status0=%h trap=%b cycles=%0d", text, text_en, tile_sw[31:0], tile_trap[2:0], t);
        $finish;
    end
endmodule
