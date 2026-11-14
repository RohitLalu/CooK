// tb_demo.v
// Runs a demo image set on the NoC as the board has it: gateway on tile 3
// with the behavioural DMA model as the DDR, real picorv32 cores on tiles
// 0..2. Unlike benchmarks/tb/tb_bench.v it can break a link in the middle of
// a run and it follows programs that never end.
//   vvp demo.out +img0=<file> +img1=<file> +img2=<file> +limit=<cycles>
//     +need=<mask>       stop early once these cores have all reported pass or fail
//     +fault=<hex>       link mask (bit tile*4 + direction), silent links
//     +fault_at=<cycle>  cycle (after the cores start) at which the fault appears;
//                        0 = from reset, so the start-up BIST sees it
// Prints   ST <core> <cycle> <status>   at every change of a status CSR, then
//   DEMO cycles=<n> st0=<..> st1=<..> st2=<..> trap=<bits> err=<NI flags of tiles 0..2> gw=<gateway flags>

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_demo;

    localparam integer NT = `NOC_NUM_TILES;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [4*NT-1:0]  fault = 0, fault_now = 0;
    wire [NT-1:0]    tile_trap;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire             sys_ready;
    wire [2:0]       gw_flags;

    wire [9:0]  awaddr, araddr;
    wire        awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
    wire [31:0] wdata, rdata, mm_tdata, s2_tdata;
    wire [3:0]  wstrb, mm_tkeep, s2_tkeep;
    wire [1:0]  bresp, rresp;
    wire        mm_tlast, mm_tvalid, mm_tready, s2_tlast, s2_tvalid, s2_tready;

    mesh_top #(.GW_EN(1), .GW_TILE(NT - 1)) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(),
        .fault_rt_mask(fault_now), .fault_rt_flip(1'b0),
        .bist_status(), .sys_ready(sys_ready), .avail(), .gw_flags(gw_flags), .gw_info(),
        .gw_axil_awaddr(awaddr), .gw_axil_awvalid(awvalid), .gw_axil_awready(awready),
        .gw_axil_wdata(wdata), .gw_axil_wstrb(wstrb), .gw_axil_wvalid(wvalid), .gw_axil_wready(wready),
        .gw_axil_bresp(bresp), .gw_axil_bvalid(bvalid), .gw_axil_bready(bready),
        .gw_axil_araddr(araddr), .gw_axil_arvalid(arvalid), .gw_axil_arready(arready),
        .gw_axil_rdata(rdata), .gw_axil_rresp(rresp), .gw_axil_rvalid(rvalid), .gw_axil_rready(rready),
        .gw_mm2s_tdata(mm_tdata), .gw_mm2s_tkeep(mm_tkeep), .gw_mm2s_tlast(mm_tlast),
        .gw_mm2s_tvalid(mm_tvalid), .gw_mm2s_tready(mm_tready),
        .gw_s2mm_tdata(s2_tdata), .gw_s2mm_tkeep(s2_tkeep), .gw_s2mm_tlast(s2_tlast),
        .gw_s2mm_tvalid(s2_tvalid), .gw_s2mm_tready(s2_tready),
        .uart_rx(1'b1), .uart_tx(), .uart_text(), .uart_text_en()
    );

    axi_dma_model u_dma (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(awaddr), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready),
        .mm2s_tdata(mm_tdata), .mm2s_tkeep(mm_tkeep), .mm2s_tlast(mm_tlast),
        .mm2s_tvalid(mm_tvalid), .mm2s_tready(mm_tready),
        .s2mm_tdata(s2_tdata), .s2mm_tkeep(s2_tkeep), .s2mm_tlast(s2_tlast),
        .s2mm_tvalid(s2_tvalid), .s2mm_tready(s2_tready)
    );

    reg [8*256-1:0] img;
    reg [NT*32-1:0] sw_q;
    reg [2:0]       need = 3'b000, fin;
    integer limit, fault_at, cyc, t;

    initial begin
        if (!$value$plusargs("limit=%d", limit)) limit = 200000;
        if (!$value$plusargs("fault_at=%d", fault_at)) fault_at = 0;
        if ($value$plusargs("fault=%h", fault)) ;
        if ($value$plusargs("need=%d", need)) ;
        for (t = 0; t < (1 << (`NOC_OFFSET_BITS - 2)); t = t + 1) begin
            dut.g_tile[0].g_ni.u_ni.mem[t] = 32'b0;
            dut.g_tile[1].g_ni.u_ni.mem[t] = 32'b0;
            dut.g_tile[2].g_ni.u_ni.mem[t] = 32'b0;
        end
        if ($value$plusargs("img0=%s", img)) $readmemh(img, dut.g_tile[0].g_ni.u_ni.mem);
        if ($value$plusargs("img1=%s", img)) $readmemh(img, dut.g_tile[1].g_ni.u_ni.mem);
        if ($value$plusargs("img2=%s", img)) $readmemh(img, dut.g_tile[2].g_ni.u_ni.mem);
        if (fault_at == 0) fault_now = fault;
        repeat (4) @(posedge clk);
        rst_n = 1;
        while (!sys_ready) @(posedge clk);
        cyc = 0; fin = 3'b0; sw_q = {NT*32{1'b0}};
        while (cyc < limit && !(need != 0 && (fin & need) == need)) begin
            @(posedge clk);
            cyc = cyc + 1;
            if (fault_at != 0 && cyc == fault_at) fault_now = fault;
            for (t = 0; t < 3; t = t + 1) begin
                if (tile_sw[t*32 +: 32] !== sw_q[t*32 +: 32])
                    $display("ST %0d %0d %h", t, cyc, tile_sw[t*32 +: 32]);
                fin[t] = tile_trap[t] || tile_sw[t*32 + 16 +: 16] === 16'h600D ||
                         tile_sw[t*32 + 16 +: 16] === 16'hFA11;
            end
            sw_q = tile_sw;
        end
        $display("DEMO cycles=%0d st0=%h st1=%h st2=%h trap=%b err=%h gw=%b",
                 cyc, tile_sw[0 +: 32], tile_sw[32 +: 32], tile_sw[64 +: 32], tile_trap[2:0],
                 tile_err[14:0], gw_flags);
        $finish;
    end
endmodule
