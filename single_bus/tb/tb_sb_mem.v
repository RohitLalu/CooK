// tb_sb_mem.v
// The memory node on the bus, driven the way cores drive it: nodes 0 and 1
// are testbench "cores" behind real ni.v instances, node 2 is a plain tile,
// node 3 is sb_mem_ni wired to the AXI4 memory model. Default 2x2 ID space.
//   1  node registers: ID, node count, kind, availability
//   2  DDR words through the window: write, read back, byte strobes
//   3  DDR_BASE is per requester: two cores, two bases, no interference
//   4  both cores at the same word-rate at once: every word right (contention)
//   5  outside the DDR, and an AXI SLVERR: POISON and the illegal flag, no hang
//   6  tile-to-tile traffic still works beside it

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_sb_mem;

    localparam NT = `NOC_NUM_TILES;
    localparam FW = `NOC_FLIT_W;
    localparam [31:0] MEMN = 32'h0000_3000;      // node 3 window
    localparam [31:0] WIN  = MEMN + 32'h200;     // DDR window
    localparam [31:0] T2   = 32'h0000_2000;

    generate
        if (NT != 4 || `NOC_OFFSET_BITS != 12) begin : tb_check_cfg
            TB_ERROR_tb_sb_mem_assumes_default_knobs u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]    n2b_valid, n2b_ready, b2n_valid, b2n_ready, b2n_room;
    wire [NT*FW-1:0] n2b_flit, b2n_flit;
    wire [NT-1:0]    err_drop;

    sb_bus #(.N(NT)) u_bus (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(n2b_valid), .loc_in_ready(n2b_ready), .loc_in_flit(n2b_flit),
        .loc_out_valid(b2n_valid), .loc_out_ready(b2n_ready), .loc_out_room(b2n_room),
        .loc_out_flit(b2n_flit),
        .fault_grant(1'b0), .fault_flip(1'b0), .err_drop(err_drop), .bus_active()
    );

    // ---------------- nodes 0, 1: testbench cores; node 2: responder ----------------
    reg  [1:0]  c_valid = 0;
    reg  [31:0] c_addr [0:1];
    reg  [31:0] c_wdata [0:1];
    reg  [3:0]  c_wstrb [0:1];
    wire [1:0]  c_ready;
    wire [31:0] c_rdata [0:1];
    wire [4:0]  err [0:3];

    genvar g;
    generate
        for (g = 0; g < 3; g = g + 1) begin : g_ni
            if (g < 2) begin : g_core
                ni #(.MY_ID(g)) u_ni (
                    .clk(clk), .rst_n(rst_n),
                    .mem_valid(c_valid[g]), .mem_instr(1'b0), .mem_ready(c_ready[g]),
                    .mem_addr(c_addr[g]), .mem_wdata(c_wdata[g]), .mem_wstrb(c_wstrb[g]),
                    .mem_rdata(c_rdata[g]),
                    .in_valid(b2n_valid[g]), .in_ready(b2n_ready[g]), .in_room(b2n_room[g]),
                    .in_flit(b2n_flit[g*FW +: FW]),
                    .out_valid(n2b_valid[g]), .out_ready(n2b_ready[g]), .out_flit(n2b_flit[g*FW +: FW]),
                    .err_flags(err[g]), .sw_status(), .bist_status(10'b0)
                );
            end else begin : g_resp
                ni #(.MY_ID(g)) u_ni (
                    .clk(clk), .rst_n(rst_n),
                    .mem_valid(1'b0), .mem_instr(1'b0), .mem_ready(), .mem_addr(32'b0),
                    .mem_wdata(32'b0), .mem_wstrb(4'b0), .mem_rdata(),
                    .in_valid(b2n_valid[g]), .in_ready(b2n_ready[g]), .in_room(b2n_room[g]),
                    .in_flit(b2n_flit[g*FW +: FW]),
                    .out_valid(n2b_valid[g]), .out_ready(n2b_ready[g]), .out_flit(n2b_flit[g*FW +: FW]),
                    .err_flags(err[g]), .sw_status(), .bist_status(10'b0)
                );
            end
        end
    endgenerate

    // ---------------- node 3: memory node + AXI4 model ----------------
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [7:0]  awlen, arlen;
    wire [2:0]  awsize, arsize;
    wire [1:0]  awburst, arburst, bresp, rresp;
    wire [3:0]  wstrb;
    wire        awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rlast, rvalid, rready;

    sb_mem_ni #(.MY_ID(3)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .in_valid(b2n_valid[3]), .in_ready(b2n_ready[3]), .in_room(b2n_room[3]),
        .in_flit(b2n_flit[3*FW +: FW]),
        .out_valid(n2b_valid[3]), .out_ready(n2b_ready[3]), .out_flit(n2b_flit[3*FW +: FW]),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .err_flags(err[3])
    );

    // SLVERR at and above 64 MB, so test 5 can reach it with a legal DDR address
    axi4_mem_model #(.MEM_WORDS(65536), .LAT(3), .ERR_ADDR(32'h0400_0000)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(awaddr), .s_awlen(awlen), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arlen(arlen), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready)
    );

    // ---------------- core bus-functional model ----------------
    // Drive on edge+1ns so the DUT never samples a changing input. One task
    // instance per core (automatic), so the two can run in a fork.
    task automatic xfer;
        input         who;
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
            if (n >= 20000) begin $display("FAIL: bus hang at addr %h (node %0d)", a, who); $finish; end
            r = c_rdata[who];
            c_valid[who] = 1'b0;
        end
    endtask
    reg [31:0] rd, junk;
    task wr;  input who; input [31:0] a; input [31:0] d; begin xfer(who, a, d, 4'hF, junk); end endtask
    task rdw; input who; input [31:0] a; begin xfer(who, a, 32'b0, 4'h0, rd); end endtask

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

    // one core's share of test 4: 32 words written then read back through its own base
    task automatic hammer;
        input        who;
        input [31:0] pat;
        output       ok;
        integer i;
        reg [31:0] r, j;
        begin
            ok = 1'b1;
            for (i = 0; i < 32; i = i + 1) xfer(who, WIN + 4*i, pat + i, 4'hF, j);
            for (i = 0; i < 32; i = i + 1) begin
                xfer(who, WIN + 4*i, 32'b0, 4'h0, r);
                if (r !== pat + i) ok = 1'b0;
            end
        end
    endtask

    integer i;
    reg ok0, ok1;
    initial begin
        c_addr[0] = 0; c_addr[1] = 0; c_wdata[0] = 0; c_wdata[1] = 0; c_wstrb[0] = 0; c_wstrb[1] = 0;
        repeat (4) @(posedge clk);
        #1 rst_n = 1;

        // ---- 1 ----
        rdw(0, MEMN + 32'h000);  check(rd == 3, "1: node ID reads 3");
        rdw(0, MEMN + 32'h00C);  check(rd == 4, "1: node count reads 4");
        rdw(0, MEMN + 32'h010);  check(rd == 2, "1: node kind reads 2 (memory)");
        rdw(1, MEMN + 32'h120);  check(rd == 32'h8000_000F, "1: availability: ready, all four nodes");

        // ---- 2 ----
        wr (0, WIN + 32'h10, 32'hDEC0_DED0);
        rdw(0, WIN + 32'h10);    check(rd == 32'hDEC0_DED0, "2: DDR word written and read back");
        check(u_ddr.mem[4] == 32'hDEC0_DED0, "2: it landed at DDR address 0x10");
        xfer(0, WIN + 32'h10, 32'h0000_AB00, 4'b0010, junk);
        rdw(0, WIN + 32'h10);    check(rd == 32'hDEC0_ABD0, "2: byte strobe wrote one byte only");

        // ---- 3 ----
        wr (0, MEMN + 32'h020, 32'h0001_0000);
        wr (1, MEMN + 32'h020, 32'h0002_0000);
        rdw(0, MEMN + 32'h020);  check(rd == 32'h0001_0000, "3: node 0 reads back its own DDR_BASE");
        rdw(1, MEMN + 32'h020);  check(rd == 32'h0002_0000, "3: node 1 has a different one");
        wr (0, WIN, 32'h0000_AAAA);
        wr (1, WIN, 32'h0000_BBBB);
        rdw(0, WIN);             check(rd == 32'h0000_AAAA, "3: same offset, node 0 sees its own word");
        rdw(1, WIN);             check(rd == 32'h0000_BBBB, "3: same offset, node 1 sees its own word");
        check(u_ddr.mem[32'h4000] == 32'hAAAA && u_ddr.mem[32'h8000] == 32'hBBBB,
              "3: the words are at 0x10000 and 0x20000 in the DDR");

        // ---- 4 ----
        fork
            hammer(0, 32'hA5A5_0000, ok0);
            hammer(1, 32'h5A5A_0000, ok1);
        join
        check(ok0 && ok1, "4: two cores, 64 writes and 64 reads interleaved: every word right");
        check(u_ddr.protocol_errors == 0, "4: AXI4 single-beat rules kept (AxLEN = 0, WLAST)");

        // ---- 5 ----
        wr (0, MEMN + 32'h020, 32'h07FF_FF00);        // window runs off the end of 128 MB
        rdw(0, WIN + 32'h100);   check(rd == 32'hDEAD_BEEF, "5: read beyond the DDR returned POISON");
        check(err[3][1] == 1'b1, "5: illegal flag set on the memory node");
        wr (0, MEMN + 32'h004, 32'h2);
        rdw(0, MEMN + 32'h004);  check(rd == 0, "5: flag cleared through the error register");
        wr (0, MEMN + 32'h020, 32'h0400_0000);        // the model answers SLVERR here
        rdw(0, WIN);             check(rd == 32'hDEAD_BEEF && err[3][1], "5: AXI SLVERR -> POISON + flag");

        // ---- 6 ----
        wr (0, T2 + 32'h800, 32'h0BAD_CAFE);          // tile 2's remote write window
        rdw(1, T2 + 32'h800);    check(rd == 32'h0BAD_CAFE, "6: tile-to-tile write and read over the same bus");
        check(err[0] == 0 && err[1] == 0 && err[2] == 0 && err_drop == 0,
              "6: no NI error flags, nothing dropped by the bus");

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
