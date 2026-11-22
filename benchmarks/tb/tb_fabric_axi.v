// tb_fabric_axi.v
// Fabric benchmark, AXI baseline side: the same three flows as tb_fabric.v,
// on the shared AXI4-Lite bus (sb_axil_bus). Tiles 0..2 are sb_axil_tile
// (master and slave on the bus); the DMA engine is a fourth bus master that
// writes the transfer into tile 0's RAM with AxPROT[0] set (a privileged,
// DMA access, allowed outside the mailbox window).
//
// The DMA engine's DDR side is not on the shared bus (as on the mesh, where
// the DDR sits behind the gateway), so only its writes into tile 0 load the
// bus. It issues the next write as soon as the last one has its response:
// the interconnect carries one transaction at a time anyway.
//
// FLOWS and CASES as in tb_fabric.v; the same output line:
//   FABRIC case=<name> dma=<cycles> w1=<cycles> w2=<cycles> total=<cycles> ok=<0|1>
// ok = every word arrived, no tile error flag is set and every DMA write got OKAY.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_fabric_axi;

    parameter integer NW = 448;                  // words per flow (a mailbox holds 448)

    localparam NM = 4;                           // masters: tiles 0..2, then the DMA engine
    localparam NS = 3;                           // slaves: tiles 0..2
    localparam [31:0] DST = 32'h400;             // DMA destination offset in tile 0
    localparam [31:0] MBX = 32'h800;

    generate
        if (`NOC_OFFSET_BITS != 12) begin : tb_check_cfg
            TB_ERROR_tb_fabric_axi_assumes_default_knobs u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- the bus ----------------
    wire [NM*32-1:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    wire [NM*3-1:0]  s_awprot, s_arprot;
    wire [NM*4-1:0]  s_wstrb;
    wire [NM*2-1:0]  s_bresp, s_rresp;
    wire [NM-1:0]    s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
    wire [NM-1:0]    s_arvalid, s_arready, s_rvalid, s_rready;
    wire [NS*32-1:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    wire [NS*3-1:0]  m_awprot, m_arprot;
    wire [NS*4-1:0]  m_wstrb;
    wire [NS*2-1:0]  m_bresp, m_rresp;
    wire [NS-1:0]    m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    wire [NS-1:0]    m_arvalid, m_arready, m_rvalid, m_rready;

    sb_axil_bus #(.MASTERS(NM), .NODES(NS), .DDR(0)) u_fabric (
        .clk(clk), .rst_n(rst_n), .fault_grant(1'b0), .fault_flip(1'b0), .active(),
        .s_awaddr(s_awaddr), .s_awprot(s_awprot), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arprot(s_arprot), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awaddr(m_awaddr), .m_awprot(m_awprot), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arprot(m_arprot), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

    // ---------------- tiles 0..2: driver + sb_axil_tile ----------------
    reg  [2:0]  c_valid = 0;
    reg  [31:0] c_addr [0:2];
    reg  [31:0] c_wdata [0:2];
    reg  [3:0]  c_wstrb [0:2];
    wire [2:0]  c_ready;
    wire [31:0] c_rdata [0:2];
    wire [4:0]  err [0:2];

    genvar g;
    generate
        for (g = 0; g < 3; g = g + 1) begin : g_tile
            sb_axil_tile #(.MY_ID(g)) u_ni (
                .clk(clk), .rst_n(rst_n),
                .mem_valid(c_valid[g]), .mem_instr(1'b0), .mem_ready(c_ready[g]),
                .mem_addr(c_addr[g]), .mem_wdata(c_wdata[g]), .mem_wstrb(c_wstrb[g]),
                .mem_rdata(c_rdata[g]),
                .m_axil_awaddr(s_awaddr[g*32 +: 32]), .m_axil_awprot(s_awprot[g*3 +: 3]),
                .m_axil_awvalid(s_awvalid[g]), .m_axil_awready(s_awready[g]),
                .m_axil_wdata(s_wdata[g*32 +: 32]), .m_axil_wstrb(s_wstrb[g*4 +: 4]),
                .m_axil_wvalid(s_wvalid[g]), .m_axil_wready(s_wready[g]),
                .m_axil_bresp(s_bresp[g*2 +: 2]), .m_axil_bvalid(s_bvalid[g]), .m_axil_bready(s_bready[g]),
                .m_axil_araddr(s_araddr[g*32 +: 32]), .m_axil_arprot(s_arprot[g*3 +: 3]),
                .m_axil_arvalid(s_arvalid[g]), .m_axil_arready(s_arready[g]),
                .m_axil_rdata(s_rdata[g*32 +: 32]), .m_axil_rresp(s_rresp[g*2 +: 2]),
                .m_axil_rvalid(s_rvalid[g]), .m_axil_rready(s_rready[g]),
                .s_axil_awaddr(m_awaddr[g*32 +: 32]), .s_axil_awprot(m_awprot[g*3 +: 3]),
                .s_axil_awvalid(m_awvalid[g]), .s_axil_awready(m_awready[g]),
                .s_axil_wdata(m_wdata[g*32 +: 32]), .s_axil_wstrb(m_wstrb[g*4 +: 4]),
                .s_axil_wvalid(m_wvalid[g]), .s_axil_wready(m_wready[g]),
                .s_axil_bresp(m_bresp[g*2 +: 2]), .s_axil_bvalid(m_bvalid[g]), .s_axil_bready(m_bready[g]),
                .s_axil_araddr(m_araddr[g*32 +: 32]), .s_axil_arprot(m_arprot[g*3 +: 3]),
                .s_axil_arvalid(m_arvalid[g]), .s_axil_arready(m_arready[g]),
                .s_axil_rdata(m_rdata[g*32 +: 32]), .s_axil_rresp(m_rresp[g*2 +: 2]),
                .s_axil_rvalid(m_rvalid[g]), .s_axil_rready(m_rready[g]),
                .err_flags(err[g]), .sw_status(), .bist_status(10'b0),
                .core_trap(1'b0), .core_restart()
            );
        end
    endgenerate

    // ---------------- master 3: the DMA engine (write side only) ----------------
    reg [31:0] d_awaddr = 0, d_wdata = 0;
    reg        d_awvalid = 0, d_wvalid = 0;
    assign s_awaddr[3*32 +: 32] = d_awaddr;  assign s_awprot[3*3 +: 3] = 3'b001;
    assign s_awvalid[3] = d_awvalid;         assign s_wdata[3*32 +: 32] = d_wdata;
    assign s_wstrb[3*4 +: 4] = 4'hF;         assign s_wvalid[3] = d_wvalid;
    assign s_bready[3] = 1'b1;
    assign s_araddr[3*32 +: 32] = 32'b0;     assign s_arprot[3*3 +: 3] = 3'b001;
    assign s_arvalid[3] = 1'b0;              assign s_rready[3] = 1'b1;

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    reg dma_bad = 0;                             // a DMA write got a non-OKAY response

    task automatic flow_dma;
        input  [31:0] pat;
        output integer t;
        integer i, t0, n;
        reg aw_done, w_done;
        begin
            t0 = cyc;
            for (i = 0; i < NW; i = i + 1) begin
                d_awaddr = DST + 4 * i;  d_wdata = pat + i;
                d_awvalid = 1'b1;  d_wvalid = 1'b1;  aw_done = 0;  w_done = 0;  n = 0;
                while (!(aw_done && w_done) || !s_bvalid[3]) begin
                    @(posedge clk);
                    if (d_awvalid && s_awready[3]) aw_done = 1;
                    if (d_wvalid && s_wready[3]) w_done = 1;
                    if (s_bvalid[3] && s_bresp[3*2 +: 2] != 2'b00) dma_bad = 1;
                    #1;
                    if (aw_done) d_awvalid = 1'b0;
                    if (w_done) d_wvalid = 1'b0;
                    n = n + 1;
                    if (n > 20000) begin $display("FAIL: DMA hang at word %0d", i); $finish; end
                end
            end
            while (g_tile[0].u_ni.mem[(DST >> 2) + NW - 1] !== pat + NW - 1) @(posedge clk);
            t = cyc - t0;
        end
    endtask

    // ---------------- core-side drivers (as in tb_fabric.v) ----------------
    task automatic xfer;
        input  [1:0]  who;
        input  [31:0] a;
        input  [31:0] d;
        input  [3:0]  s;
        output [31:0] r;
        integer n;
        begin
            c_addr[who] = a;  c_wdata[who] = d;  c_wstrb[who] = s;  c_valid[who] = 1'b1;
            n = 0;
            @(posedge clk); #1;
            while (!c_ready[who] && n < 20000) begin @(posedge clk); #1; n = n + 1; end
            if (n >= 20000) begin $display("FAIL: hang at addr %h (tile %0d)", a, who); $finish; end
            r = c_rdata[who];
            c_valid[who] = 1'b0;
        end
    endtask

    task automatic flow_wr;
        input  [1:0]  who;
        input  [1:0]  to;
        input  [31:0] pat;
        output integer t;
        integer i, t0;
        reg [31:0] j;
        begin
            t0 = cyc;
            for (i = 0; i < NW; i = i + 1)
                xfer(who, {18'b0, to, 12'b0} + MBX + 4 * i, pat + i, 4'hF, j);
            while ((to == 1 ? g_tile[1].u_ni.mem[(MBX >> 2) + NW - 1]
                            : g_tile[2].u_ni.mem[(MBX >> 2) + NW - 1]) !== pat + NW - 1) @(posedge clk);
            t = cyc - t0;
        end
    endtask

    function landed;
        input [1:0]  tile;
        input [31:0] off;
        input [31:0] pat;
        integer i;
        reg [31:0] w;
        begin
            landed = 1'b1;
            for (i = 0; i < NW; i = i + 1) begin
                w = (tile == 0) ? g_tile[0].u_ni.mem[(off >> 2) + i] :
                    (tile == 1) ? g_tile[1].u_ni.mem[(off >> 2) + i] : g_tile[2].u_ni.mem[(off >> 2) + i];
                if (w !== pat + i) landed = 1'b0;
            end
        end
    endfunction

    integer td, t1, t2, tot;
    reg ok;
    task report;
        input [8*8-1:0] name;
        begin
            ok = (err[0] == 0) && (err[1] == 0) && (err[2] == 0) && !dma_bad &&
                 (td == 0 || landed(0, DST, 32'hD000_0000)) &&
                 (t1 == 0 || landed(2, MBX, 32'hA100_0000)) &&
                 (t2 == 0 || landed(1, MBX, 32'hA200_0000));
            $display("FABRIC case=%0s dma=%0d w1=%0d w2=%0d total=%0d ok=%0d", name, td, t1, t2, tot, ok);
        end
    endtask

    task wipe;
        integer i;
        begin
            for (i = 0; i < NW; i = i + 1) begin
                g_tile[0].u_ni.mem[(DST >> 2) + i] = 32'b0;
                g_tile[1].u_ni.mem[(MBX >> 2) + i] = 32'b0;
                g_tile[2].u_ni.mem[(MBX >> 2) + i] = 32'b0;
            end
        end
    endtask

    initial begin
        c_addr[0] = 0; c_addr[1] = 0; c_addr[2] = 0;
        repeat (6) @(posedge clk);
        #1 rst_n = 1;
        repeat (4) @(posedge clk);
        #1;

        wipe; td = 0; t1 = 0; t2 = 0;
        flow_dma(32'hD000_0000, td); tot = td;
        report("dma");

        wipe; td = 0; t1 = 0; t2 = 0;
        flow_wr(1, 2, 32'hA100_0000, t1); tot = t1;
        report("w1");

        wipe; td = 0; t1 = 0; t2 = 0;
        flow_wr(2, 1, 32'hA200_0000, t2); tot = t2;
        report("w2");

        wipe; td = 0; t1 = 0; t2 = 0;
        fork                                     // all three start on the same cycle
            flow_dma(32'hD000_0000, td);
            flow_wr(1, 2, 32'hA100_0000, t1);
            flow_wr(2, 1, 32'hA200_0000, t2);
        join
        tot = (td > t1 ? (td > t2 ? td : t2) : (t1 > t2 ? t1 : t2));
        report("all");
        $finish;
    end
endmodule
