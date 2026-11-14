// tb_bench.v
// Runs one benchmark image set on either architecture and prints one line:
//   BENCH cycles=<n> st0=<status> st1=<status> st2=<status> trap=<bits> bus=<busy cycles>
// Three picorv32 cores (tiles 0..2), each loaded from its own image:
//   vvp bench.out +img0=<file> +img1=<file> +img2=<file> [+limit=<cycles>]
// Compile with -DBENCH_BUS for the single-bus baseline (sb_top + AXI4 memory
// model), without it for the NoC (mesh_top with the gateway on tile 3, DMA
// side idle). Cycles are counted from the moment the cores leave reset (on
// the NoC that is after the start-up BIST) until every core has written a
// pass or fail word to its status CSR, or trapped.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_bench;

    localparam integer NT = `NOC_NUM_TILES;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]    tile_trap;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire             started, active;

    generate
        if (NT != 4) begin : tb_check_nt
            TB_ERROR_tb_bench_assumes_four_tile_ids u_err ();
        end
    endgenerate

`ifdef BENCH_BUS
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [7:0]  awlen, arlen;
    wire [1:0]  bresp, rresp;
    wire [3:0]  wstrb;
    wire        awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rlast, rvalid, rready;
    sb_top dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .fault_grant(1'b0), .fault_flip(1'b0), .bus_err_drop(), .bus_active(active),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(), .m_axi_awburst(),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );
    axi4_mem_model #(.MEM_WORDS(65536), .LAT(3)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(awaddr), .s_awlen(awlen), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arlen(arlen), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready)
    );
    assign started = rst_n;
    `define TILE_MEM(t) dut.g_tile[t].u_ni.mem
`else
    mesh_top #(.GW_EN(1), .GW_TILE(NT - 1)) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(),
        .fault_rt_mask({4*NT{1'b0}}), .fault_rt_flip(1'b0),
        .bist_status(), .sys_ready(started), .avail(), .gw_flags(), .gw_info(),
        .gw_axil_awaddr(), .gw_axil_awvalid(), .gw_axil_awready(1'b0),
        .gw_axil_wdata(), .gw_axil_wstrb(), .gw_axil_wvalid(), .gw_axil_wready(1'b0),
        .gw_axil_bresp(2'b0), .gw_axil_bvalid(1'b0), .gw_axil_bready(),
        .gw_axil_araddr(), .gw_axil_arvalid(), .gw_axil_arready(1'b0),
        .gw_axil_rdata(32'b0), .gw_axil_rresp(2'b0), .gw_axil_rvalid(1'b0), .gw_axil_rready(),
        .gw_mm2s_tdata(32'b0), .gw_mm2s_tkeep(4'b0), .gw_mm2s_tlast(1'b0),
        .gw_mm2s_tvalid(1'b0), .gw_mm2s_tready(),
        .gw_s2mm_tdata(), .gw_s2mm_tkeep(), .gw_s2mm_tlast(),
        .gw_s2mm_tvalid(), .gw_s2mm_tready(1'b0)
    );
    // a flit entering the mesh from any tile
    assign active = |(dut.ni2r_valid & dut.ni2r_ready);
    `define TILE_MEM(t) dut.g_tile[t].g_ni.u_ni.mem
`endif

    reg [8*256-1:0] img;
    integer limit, cyc, act, t, sig_lo, sig_hi, fd;
    reg [2:0] fin;

    initial begin
        if (!$value$plusargs("limit=%d", limit)) limit = 2000000;
        // a tile with no image holds zeros: its core traps on the first fetch
        for (t = 0; t < (1 << (`NOC_OFFSET_BITS - 2)); t = t + 1) begin
            `TILE_MEM(0)[t] = 32'b0;  `TILE_MEM(1)[t] = 32'b0;  `TILE_MEM(2)[t] = 32'b0;
        end
        if ($value$plusargs("img0=%s", img)) $readmemh(img, `TILE_MEM(0));
        if ($value$plusargs("img1=%s", img)) $readmemh(img, `TILE_MEM(1));
        if ($value$plusargs("img2=%s", img)) $readmemh(img, `TILE_MEM(2));
        repeat (4) @(posedge clk);
        rst_n = 1;
        while (!started) @(posedge clk);
        cyc = 0; act = 0; fin = 3'b0;
        while (fin != 3'b111 && cyc < limit) begin
            @(posedge clk);
            cyc = cyc + 1;
            if (active) act = act + 1;
            for (t = 0; t < 3; t = t + 1)
                fin[t] = tile_trap[t] || tile_sw[t*32 + 16 +: 16] === 16'h600D ||
                         tile_sw[t*32 + 16 +: 16] === 16'hFA11;
        end
        // +sig=<file> +sig_lo=<word> +sig_hi=<word>: dump tile 0's memory words
        // [sig_lo, sig_hi) for a signature comparison (riscv-arch-test)
        if ($value$plusargs("sig=%s", img) && $value$plusargs("sig_lo=%d", sig_lo) &&
            $value$plusargs("sig_hi=%d", sig_hi)) begin
            fd = $fopen(img, "w");
            for (t = sig_lo; t < sig_hi; t = t + 1) $fdisplay(fd, "%08x", `TILE_MEM(0)[t]);
            $fclose(fd);
        end
        $display("BENCH cycles=%0d st0=%h st1=%h st2=%h trap=%b bus=%0d",
                 cyc, tile_sw[0 +: 32], tile_sw[32 +: 32], tile_sw[64 +: 32], tile_trap[2:0], act);
        $finish;
    end
endmodule
