// tb_sb_axi.v
// The AXI baseline's parts, driven the way cores drive them: tiles 0 and 1
// are sb_axil_tile with the testbench on their core ports, tile 2 is a tile
// with the remote read window on (RD_PROTECT = 1), node 3 is sb_axil_info,
// and the DDR (axi4_mem_model) sits at 0x8000_0000, all on sb_axil_bus.
// A fourth master stands in for a DMA engine (privileged accesses).
//   1  registers of other nodes: ID, node count, kind, availability
//   2  remote write and read in the mailbox window; byte strobes
//   3  write outside the window: dropped, SLVERR, illegal flag on both sides
//   4  a privileged (DMA) write outside the window lands
//   5  read window: private RAM refused with POISON, mailbox and CSRs answered,
//      privileged read answered
//   6  DDR read and write; an address that belongs to no slave: DECERR -> POISON
//   7  two cores at once into one tile's mailbox: every word right
//   8  stuck bus: the access times out with POISON and the timeout flag, no
//      hang; after the fault clears, accesses work again
//   9  core restart through another tile's CSR 0x018

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_sb_axi;

    localparam NT = `NOC_NUM_TILES;
    localparam NM = 3;                       // masters: tiles 0, 1, the DMA stand-in
    localparam NS = NT + 1;                  // slaves: nodes 0..3, the DDR
    localparam [31:0] T1 = 32'h0000_1000, T2 = 32'h0000_2000, MEMN = 32'h0000_3000;
    localparam [31:0] DDR = 32'h8000_0000;

    generate
        if (NT != 4 || `NOC_OFFSET_BITS != 12) begin : tb_check_cfg
            TB_ERROR_tb_sb_axi_assumes_default_knobs u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0, fault_grant = 0;
    always #5 clk = ~clk;

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

    sb_axil_bus #(.MASTERS(NM), .NODES(NT), .DDR(1)) u_bus (
        .clk(clk), .rst_n(rst_n), .fault_grant(fault_grant), .fault_flip(1'b0), .active(),
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

    // ---------------- tiles 0..2 ----------------
    reg  [2:0]  c_valid = 0;
    reg  [31:0] c_addr [0:2];
    reg  [31:0] c_wdata [0:2];
    reg  [3:0]  c_wstrb [0:2];
    wire [2:0]  c_ready;
    wire [31:0] c_rdata [0:2];
    wire [4:0]  err [0:2];
    wire [2:0]  restart;

    genvar g;
    generate
        for (g = 0; g < 3; g = g + 1) begin : g_tile
            // tile 2 has no master on the bus: its master port is tied off
            wire [31:0] mawaddr, mwdata, maraddr;
            wire [3:0]  mwstrb;
            wire        mawvalid, mwvalid, marvalid, mbready, mrready;
            sb_axil_tile #(.MY_ID(g), .RD_PROTECT(g == 2)) u_ni (
                .clk(clk), .rst_n(rst_n),
                .mem_valid(c_valid[g]), .mem_instr(1'b0), .mem_ready(c_ready[g]),
                .mem_addr(c_addr[g]), .mem_wdata(c_wdata[g]), .mem_wstrb(c_wstrb[g]), .mem_rdata(c_rdata[g]),
                .m_axil_awaddr(mawaddr), .m_axil_awprot(), .m_axil_awvalid(mawvalid),
                .m_axil_awready(g < 2 ? s_awready[g] : 1'b0),
                .m_axil_wdata(mwdata), .m_axil_wstrb(mwstrb), .m_axil_wvalid(mwvalid),
                .m_axil_wready(g < 2 ? s_wready[g] : 1'b0),
                .m_axil_bresp(g < 2 ? s_bresp[g*2 +: 2] : 2'b00), .m_axil_bvalid(g < 2 ? s_bvalid[g] : 1'b0),
                .m_axil_bready(mbready),
                .m_axil_araddr(maraddr), .m_axil_arprot(), .m_axil_arvalid(marvalid),
                .m_axil_arready(g < 2 ? s_arready[g] : 1'b0),
                .m_axil_rdata(g < 2 ? s_rdata[g*32 +: 32] : 32'b0), .m_axil_rresp(g < 2 ? s_rresp[g*2 +: 2] : 2'b00),
                .m_axil_rvalid(g < 2 ? s_rvalid[g] : 1'b0), .m_axil_rready(mrready),
                .s_axil_awaddr(m_awaddr[g*32 +: 32]), .s_axil_awprot(m_awprot[g*3 +: 3]),
                .s_axil_awvalid(m_awvalid[g]), .s_axil_awready(m_awready[g]),
                .s_axil_wdata(m_wdata[g*32 +: 32]), .s_axil_wstrb(m_wstrb[g*4 +: 4]),
                .s_axil_wvalid(m_wvalid[g]), .s_axil_wready(m_wready[g]),
                .s_axil_bresp(m_bresp[g*2 +: 2]), .s_axil_bvalid(m_bvalid[g]), .s_axil_bready(m_bready[g]),
                .s_axil_araddr(m_araddr[g*32 +: 32]), .s_axil_arprot(m_arprot[g*3 +: 3]),
                .s_axil_arvalid(m_arvalid[g]), .s_axil_arready(m_arready[g]),
                .s_axil_rdata(m_rdata[g*32 +: 32]), .s_axil_rresp(m_rresp[g*2 +: 2]),
                .s_axil_rvalid(m_rvalid[g]), .s_axil_rready(m_rready[g]),
                .err_flags(err[g]), .sw_status(), .bist_status(10'b0), .core_trap(1'b0),
                .core_restart(restart[g])
            );
            if (g < 2) begin : g_m
                assign s_awaddr[g*32 +: 32] = mawaddr;  assign s_awprot[g*3 +: 3] = 3'b000;
                assign s_awvalid[g] = mawvalid;
                assign s_wdata[g*32 +: 32] = mwdata;    assign s_wstrb[g*4 +: 4] = mwstrb;
                assign s_wvalid[g] = mwvalid;           assign s_bready[g] = mbready;
                assign s_araddr[g*32 +: 32] = maraddr;  assign s_arprot[g*3 +: 3] = 3'b000;
                assign s_arvalid[g] = marvalid;         assign s_rready[g] = mrready;
            end
        end
    endgenerate

    // ---------------- master 2: a DMA engine stand-in (privileged) ----------------
    reg [31:0] d_awaddr = 0, d_wdata = 0, d_araddr = 0;
    reg        d_awvalid = 0, d_wvalid = 0, d_arvalid = 0;
    assign s_awaddr[2*32 +: 32] = d_awaddr;  assign s_awprot[2*3 +: 3] = 3'b001;  assign s_awvalid[2] = d_awvalid;
    assign s_wdata[2*32 +: 32]  = d_wdata;   assign s_wstrb[2*4 +: 4] = 4'hF;     assign s_wvalid[2]  = d_wvalid;
    assign s_bready[2] = 1'b1;
    assign s_araddr[2*32 +: 32] = d_araddr;  assign s_arprot[2*3 +: 3] = 3'b001;  assign s_arvalid[2] = d_arvalid;
    assign s_rready[2] = 1'b1;

    task dma_write;
        input [31:0] a, d;
        begin
            d_awaddr = a; d_wdata = d; d_awvalid = 1; d_wvalid = 1;
            while (d_awvalid || d_wvalid) begin
                @(posedge clk);
                if (s_awready[2]) d_awvalid <= 0;
                if (s_wready[2])  d_wvalid  <= 0;
                #1;
            end
            while (!s_bvalid[2]) @(posedge clk);
            @(posedge clk); #1;
        end
    endtask
    reg [31:0] d_r;
    reg [1:0]  d_rr;
    task dma_read;
        input [31:0] a;
        begin
            d_araddr = a; d_arvalid = 1;
            @(posedge clk);
            while (!s_arready[2]) @(posedge clk);
            #1 d_arvalid = 0;
            while (!s_rvalid[2]) @(posedge clk);
            d_r = s_rdata[2*32 +: 32]; d_rr = s_rresp[2*2 +: 2];
            @(posedge clk); #1;
        end
    endtask

    // ---------------- node 3 and the DDR ----------------
    sb_axil_info #(.MY_ID(3)) u_info (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(m_awaddr[3*32 +: 32]), .s_axil_awvalid(m_awvalid[3]), .s_axil_awready(m_awready[3]),
        .s_axil_wvalid(m_wvalid[3]), .s_axil_wready(m_wready[3]),
        .s_axil_bvalid(m_bvalid[3]), .s_axil_bready(m_bready[3]),
        .s_axil_araddr(m_araddr[3*32 +: 32]), .s_axil_arvalid(m_arvalid[3]), .s_axil_arready(m_arready[3]),
        .s_axil_rdata(m_rdata[3*32 +: 32]), .s_axil_rvalid(m_rvalid[3]), .s_axil_rready(m_rready[3])
    );
    assign m_bresp[3*2 +: 2] = 2'b00;  assign m_rresp[3*2 +: 2] = 2'b00;

    wire [1:0] dd_bresp, dd_rresp;
    axi4_mem_model #(.MEM_WORDS(4096), .LAT(3)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr({5'b0, m_awaddr[4*32 +: 27]}), .s_awlen(8'd0), .s_awvalid(m_awvalid[4]), .s_awready(m_awready[4]),
        .s_wdata(m_wdata[4*32 +: 32]), .s_wstrb(m_wstrb[4*4 +: 4]), .s_wlast(1'b1), .s_wvalid(m_wvalid[4]),
        .s_wready(m_wready[4]),
        .s_bresp(dd_bresp), .s_bvalid(m_bvalid[4]), .s_bready(m_bready[4]),
        .s_araddr({5'b0, m_araddr[4*32 +: 27]}), .s_arlen(8'd0), .s_arvalid(m_arvalid[4]), .s_arready(m_arready[4]),
        .s_rdata(m_rdata[4*32 +: 32]), .s_rresp(dd_rresp), .s_rlast(), .s_rvalid(m_rvalid[4]), .s_rready(m_rready[4])
    );
    assign m_bresp[4*2 +: 2] = dd_bresp;  assign m_rresp[4*2 +: 2] = dd_rresp;

    // ---------------- core bus-functional model ----------------
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
    reg [31:0] rd, junk;
    task wr;  input [1:0] who; input [31:0] a; input [31:0] d; begin xfer(who, a, d, 4'hF, junk); end endtask
    task rdw; input [1:0] who; input [31:0] a; begin xfer(who, a, 32'b0, 4'h0, rd); end endtask

    integer errors = 0, checks = 0;
    task check;
        input cond;
        input [8*72-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
            else             $display("PASS: %0s", msg);
        end
    endtask

    task automatic hammer;
        input  [1:0]  who;
        input  [31:0] pat;
        output        ok;
        integer i;
        reg [31:0] r, j;
        begin
            ok = 1'b1;
            for (i = 0; i < 32; i = i + 1) xfer(who, T2 + 32'h800 + 128 * who + 4 * i, pat + i, 4'hF, j);
            for (i = 0; i < 32; i = i + 1) begin
                xfer(who, T2 + 32'h800 + 128 * who + 4 * i, 32'b0, 4'h0, r);
                if (r !== pat + i) ok = 1'b0;
            end
        end
    endtask

    reg ok0, ok1;
    integer k;
    initial begin
        for (k = 0; k < 3; k = k + 1) begin c_addr[k] = 0; c_wdata[k] = 0; c_wstrb[k] = 0; end
        repeat (4) @(posedge clk);
        #1 rst_n = 1;

        // ---- 1 ----
        rdw(0, T1 + 32'h000);    check(rd == 1, "1: tile 1's ID register reads 1");
        rdw(0, T1 + 32'h00C);    check(rd == 4, "1: node count reads 4");
        rdw(1, MEMN + 32'h010);  check(rd == 2, "1: node 3's kind reads 2 (memory)");
        rdw(1, MEMN + 32'h120);  check(rd == 32'h8000_000F, "1: availability: ready, all four nodes");

        // ---- 2 ----
        wr (0, T1 + 32'h800, 32'h1234_5678);
        rdw(0, T1 + 32'h800);    check(rd == 32'h1234_5678, "2: mailbox write, read back");
        check(g_tile[1].u_ni.mem[32'h800 >> 2] == 32'h1234_5678, "2: the word is in tile 1's RAM");
        xfer(0, T1 + 32'h800, 32'h00AB_0000, 4'b0100, junk);
        rdw(0, T1 + 32'h800);    check(rd == 32'h12AB_5678, "2: byte strobe wrote one byte");

        // ---- 3 ----
        g_tile[1].u_ni.mem[32'h400 >> 2] = 32'h0000_1111;
        wr (0, T1 + 32'h400, 32'hBAD0_0001);
        repeat (10) @(posedge clk);
        check(g_tile[1].u_ni.mem[32'h400 >> 2] == 32'h0000_1111, "3: write outside the mailbox dropped");
        check(err[0][1] && err[1][1], "3: SLVERR flagged on the writer and on the target");
        wr (0, 32'h004, 32'h2);  wr (1, 32'h004, 32'h2);
        rdw(0, 32'h004);         check(rd == 0, "3: flags cleared");

        // ---- 4 ----
        dma_write(T1 + 32'h400, 32'h0D3A_0001);
        check(g_tile[1].u_ni.mem[32'h400 >> 2] == 32'h0D3A_0001, "4: privileged (DMA) write outside the window lands");

        // ---- 5 ----
        g_tile[2].u_ni.mem[32'h300 >> 2] = 32'h5EC2_E700;
        g_tile[2].u_ni.mem[32'h900 >> 2] = 32'h0A11_0BED;
        rdw(0, T2 + 32'h300);    check(rd == 32'hDEAD_BEEF && err[2][1], "5: private RAM refused: POISON, flag on tile 2");
        rdw(0, T2 + 32'h900);    check(rd == 32'h0A11_0BED, "5: mailbox read answered");
        rdw(0, T2 + 32'h000);    check(rd == 2, "5: CSR read answered");
        dma_read(T2 + 32'h300);  check(d_r == 32'h5EC2_E700 && d_rr == 2'b00, "5: privileged read answered");

        // ---- 6 ----
        wr (1, DDR + 32'h40, 32'hDDDD_0040);
        rdw(1, DDR + 32'h40);    check(rd == 32'hDDDD_0040, "6: DDR write and read at 0x8000_0040");
        check(u_ddr.mem[16] == 32'hDDDD_0040, "6: the word is at DDR address 0x40");
        rdw(1, 32'h4000_0000);   check(rd == 32'hDEAD_BEEF && err[1][1], "6: address of no slave: DECERR -> POISON + flag");
        wr (1, 32'h004, 32'h2);

        // ---- 7 ----
        fork
            hammer(0, 32'hA5A5_0000, ok0);
            hammer(1, 32'h5A5A_0000, ok1);
        join
        check(ok0 && ok1, "7: two cores, 64 writes and 64 reads interleaved: every word right");

        // ---- 8 ----
        fault_grant = 1;
        rdw(0, T1 + 32'h000);    check(rd == 32'hDEAD_BEEF && err[0][0], "8: stuck bus: POISON and the timeout flag, no hang");
        #1 fault_grant = 0;
        wr (0, 32'h004, 32'h1);
        rdw(0, T1 + 32'h000);    check(rd == 1, "8: the fault cleared: accesses work again");

        // ---- 9 ----
        fork
            wr(0, T1 + 32'h018, 32'h1);
            begin : seen
                integer n; n = 0;
                while (!restart[1] && n < 200) begin @(posedge clk); n = n + 1; end
                check(restart[1] === 1'b1, "9: tile 0 restarts tile 1's core through its CSR 0x018");
            end
        join

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
