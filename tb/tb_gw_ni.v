// tb_gw_ni.v
// System test of the gateway: 2x2 mesh (with start-up link BIST), tiles 0 and
// 1 driven by the testbench as cores through real ni.v instances, tile 2 a
// plain responder, tile 3 = gw_ni wired to axi_dma_model. Default 2x2 knobs.
//
// FAULT = 0 (healthy)
//   1  BIST: every tile available, statuses readable at the gateway
//   2  no lock, no DMA: writes refused (reason 1), DMA never started
//   3  lock: claim, repeat-claim, contention, round-robin handoff, release
//   4  DDR -> owner's RAM (MM2S) and owner's RAM -> DDR (S2MM)
//   5  misprograms refused: other tile, zone, alignment, window overrun,
//      unarmed MM2S, count mismatch, non-direct-mode register, busy release
//   6  lease: a silent owner loses the lock
//   7  DMA register reads, SLVERR -> POISON, illegal offset
// FAULT = 1 (router 2's north output disabled by the external port_disable:
//   a one-way cut the link BIST cannot see, so nothing routes around it)
//   the gateway can hear tile 0 but not answer it: tile 0 is marked
//   unavailable, its blind DMA attempt is refused (reason 8), and tile 1,
//   whose paths avoid the fault, still moves data.
// FAULT = 2 (link tile2 -> north silent from power-up)
//   BIST finds it and every router routes around link 0-2: all four tiles
//   stay available and tile 0, whose replies used that link, moves data.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_gw_ni;

    parameter integer FAULT = 0;

    localparam NT = `NOC_NUM_TILES;
    localparam FW = `NOC_FLIT_W;
    localparam [31:0] GW  = 32'h0000_3000;   // tile 3 window
    localparam [31:0] DMA = GW + 32'h200;
    localparam [31:0] T0  = 32'h0000_0000;
    localparam [31:0] T1  = 32'h0000_1000;
    localparam [31:0] T2  = 32'h0000_2000;
    localparam [15:0] FMASK = (FAULT == 2) ? (16'b1 << (2*4 + `NOC_P_N)) : 16'b0;
    localparam [4*5-1:0] PDIS = (FAULT == 1) ? (20'b1 << (2*5 + `NOC_P_N)) : 20'b0;
    // short lease for a quick lease test; the fault runs need the real one,
    // because a lease must outlast the cores' NI retries (3 x 1024 cycles)
    localparam integer LEASE = (FAULT != 0) ? 16384 : 400;

    generate
        if (NT != 4) begin : tb_check_nt
            TB_ERROR_tb_gw_ni_assumes_a_2x2_mesh u_err ();
        end
    endgenerate

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- mesh ----------------
    wire [NT-1:0]    ni2r_valid, ni2r_ready;
    wire [NT*FW-1:0] ni2r_flit;
    wire [NT-1:0]    r2ni_valid, r2ni_ready, r2ni_room;
    wire [NT*FW-1:0] r2ni_flit;
    wire [NT*5*`NOC_E_W-1:0] rt_in_err;
    wire [NT*5-1:0]  rt_out_dead, rt_out_wd;
    wire [NT*8-1:0]  rt_drop_cnt;
    wire [NT*10-1:0] bist_status;
    wire             mesh_done;

    noc_mesh #(.LINK_FAULT_MASK(FMASK), .LINK_FAULT_MODE(1)) u_mesh (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .port_disable(PDIS), .err_clear(1'b0),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt),
        .fault_rt_mask({4*NT{1'b0}}), .fault_rt_flip(1'b0),
        .bist_status(bist_status), .bist_done(mesh_done)
    );

    // ---------------- tiles 0, 1: testbench cores ----------------
    reg  [1:0]  c_valid = 0;
    reg  [31:0] c_addr [0:1];
    reg  [31:0] c_wdata [0:1];
    reg  [3:0]  c_wstrb [0:1];
    wire [1:0]  c_ready;
    wire [31:0] c_rdata [0:1];
    wire [4:0]  err0, err1, err2;
    wire [31:0] sw0, sw1, sw2;

    ni #(.MY_ID(0), .GW_ID(3)) u_ni0 (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(c_valid[0]), .mem_instr(1'b0), .mem_ready(c_ready[0]),
        .mem_addr(c_addr[0]), .mem_wdata(c_wdata[0]), .mem_wstrb(c_wstrb[0]), .mem_rdata(c_rdata[0]),
        .in_valid(r2ni_valid[0]), .in_ready(r2ni_ready[0]), .in_room(r2ni_room[0]),
        .in_flit(r2ni_flit[0*FW +: FW]),
        .out_valid(ni2r_valid[0]), .out_ready(ni2r_ready[0]), .out_flit(ni2r_flit[0*FW +: FW]),
        .err_flags(err0), .sw_status(sw0), .bist_status(bist_status[0*10 +: 10])
    );
    ni #(.MY_ID(1), .GW_ID(3)) u_ni1 (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(c_valid[1]), .mem_instr(1'b0), .mem_ready(c_ready[1]),
        .mem_addr(c_addr[1]), .mem_wdata(c_wdata[1]), .mem_wstrb(c_wstrb[1]), .mem_rdata(c_rdata[1]),
        .in_valid(r2ni_valid[1]), .in_ready(r2ni_ready[1]), .in_room(r2ni_room[1]),
        .in_flit(r2ni_flit[1*FW +: FW]),
        .out_valid(ni2r_valid[1]), .out_ready(ni2r_ready[1]), .out_flit(ni2r_flit[1*FW +: FW]),
        .err_flags(err1), .sw_status(sw1), .bist_status(bist_status[1*10 +: 10])
    );
    // ---------------- tile 2: responder ----------------
    ni #(.MY_ID(2), .GW_ID(3)) u_ni2 (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(1'b0), .mem_instr(1'b0), .mem_ready(), .mem_addr(32'b0),
        .mem_wdata(32'b0), .mem_wstrb(4'b0), .mem_rdata(),
        .in_valid(r2ni_valid[2]), .in_ready(r2ni_ready[2]), .in_room(r2ni_room[2]),
        .in_flit(r2ni_flit[2*FW +: FW]),
        .out_valid(ni2r_valid[2]), .out_ready(ni2r_ready[2]), .out_flit(ni2r_flit[2*FW +: FW]),
        .err_flags(err2), .sw_status(sw2), .bist_status(bist_status[2*10 +: 10])
    );

    // ---------------- tile 3: gateway + DMA model ----------------
    wire [9:0]  awaddr, araddr;
    wire        awvalid, awready, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rvalid, rready;
    wire [31:0] wdata, rdata;
    wire [3:0]  wstrb;
    wire [1:0]  bresp, rresp;
    wire [31:0] mm_tdata, s2_tdata;
    wire [3:0]  mm_tkeep, s2_tkeep;
    wire        mm_tlast, mm_tvalid, mm_tready, s2_tlast, s2_tvalid, s2_tready;
    wire [4:0]  err3;
    wire [31:0] sw3, gw_info;
    wire [2:0]  gw_flags;
    wire        sys_ready;
    wire [NT-1:0] avail;

    gw_ni #(.MY_ID(3), .LEASE_CYCLES(LEASE)) u_gw (
        .clk(clk), .rst_n(rst_n),
        .in_valid(r2ni_valid[3]), .in_ready(r2ni_ready[3]), .in_room(r2ni_room[3]),
        .in_flit(r2ni_flit[3*FW +: FW]),
        .out_valid(ni2r_valid[3]), .out_ready(ni2r_ready[3]), .out_flit(ni2r_flit[3*FW +: FW]),
        .m_axil_awaddr(awaddr), .m_axil_awvalid(awvalid), .m_axil_awready(awready),
        .m_axil_wdata(wdata), .m_axil_wstrb(wstrb), .m_axil_wvalid(wvalid), .m_axil_wready(wready),
        .m_axil_bresp(bresp), .m_axil_bvalid(bvalid), .m_axil_bready(bready),
        .m_axil_araddr(araddr), .m_axil_arvalid(arvalid), .m_axil_arready(arready),
        .m_axil_rdata(rdata), .m_axil_rresp(rresp), .m_axil_rvalid(rvalid), .m_axil_rready(rready),
        .s_axis_mm2s_tdata(mm_tdata), .s_axis_mm2s_tkeep(mm_tkeep), .s_axis_mm2s_tlast(mm_tlast),
        .s_axis_mm2s_tvalid(mm_tvalid), .s_axis_mm2s_tready(mm_tready),
        .m_axis_s2mm_tdata(s2_tdata), .m_axis_s2mm_tkeep(s2_tkeep), .m_axis_s2mm_tlast(s2_tlast),
        .m_axis_s2mm_tvalid(s2_tvalid), .m_axis_s2mm_tready(s2_tready),
        .err_flags(err3), .sw_status(sw3), .gw_flags(gw_flags), .gw_info(gw_info),
        .bist_mesh_done(mesh_done), .bist_own_status(bist_status[3*10 +: 10]),
        .sys_ready(sys_ready), .avail(avail)
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

    // ---------------- core bus-functional model, one per core tile ----------------
    // Drive on edge+1ns so the DUT never samples a changing input.
    reg [31:0] rd;
    task core_xfer;
        input        who;
        input [31:0] a;
        input [31:0] d;
        input [3:0]  s;
        integer n;
        begin
            c_addr[who] = a;  c_wdata[who] = d;  c_wstrb[who] = s;  c_valid[who] = 1'b1;
            n = 0;
            @(posedge clk); #1;
            while (!c_ready[who] && n < 20000) begin @(posedge clk); #1; n = n + 1; end
            if (n >= 20000) begin
                $display("FAIL: bus hang at addr %h (tile %0d)", a, who);
                $finish;
            end
            rd = c_rdata[who];
            c_valid[who] = 1'b0;
        end
    endtask
    task wr;  input who; input [31:0] a; input [31:0] d; begin core_xfer(who, a, d, 4'hF); end endtask
    task rdw; input who; input [31:0] a; begin core_xfer(who, a, 32'b0, 4'h0); end endtask

    integer fails = 0, checks = 0;
    task check;
        input        cond;
        input [8*60-1:0] name;
        begin
            checks = checks + 1;
            if (cond) $display("  ok   %0s", name);
            else begin $display("  FAIL %0s", name); fails = fails + 1; end
        end
    endtask

    // poll gateway STATUS until (status & mask) != 0
    task wait_status;
        input        who;
        input [3:0]  mask;
        integer n;
        begin
            n = 0;
            rdw(who, GW + 32'h10C);
            while (((rd & mask) == 0) && n < 400) begin rdw(who, GW + 32'h10C); n = n + 1; end
            if (n >= 400) begin $display("  FAIL status wait timed out (mask %h)", mask); fails = fails + 1; end
        end
    endtask

    // the last refusal must be `why` from tile `who`; then clear it
    task expect_reject;
        input        who;
        input [3:0]  why;
        input [8*60-1:0] name;
        begin
            rdw(who, GW + 32'h118);
            check(rd[31] && rd[3:0] == why && rd[23:16] == who, name);
            if (!(rd[31] && rd[3:0] == why && rd[23:16] == who))
                $display("       DMA_REJECT = %h", rd);
            wr(who, GW + 32'h118, 32'h8000_0000);
        end
    endtask

    integer i;
    reg ok;

    initial begin
        c_addr[0] = 0; c_addr[1] = 0; c_wdata[0] = 0; c_wdata[1] = 0; c_wstrb[0] = 0; c_wstrb[1] = 0;
        #3000000;
        $display("FAIL: global timeout");
        $finish;
    end

    initial begin
        repeat (6) @(posedge clk);
        #1 rst_n = 1;
        while (!sys_ready) @(posedge clk);
        #1;

        if (FAULT == 0) begin
            // ---- 1. BIST ----
            $display("[1] start-up BIST, collected at the gateway");
            check(avail == 4'b1111, "every tile available");
            rdw(0, GW + 32'h120);  check(rd[31] && rd[3:0] == 4'b1111, "BIST CSR: done, bitmap 1111");
            for (i = 0; i < NT; i = i + 1) begin
                rdw(0, GW + 32'h130 + 4*i);
                check(rd[9:0] == bist_status[i*10 +: 10] && rd[25:16] == ~rd[9:0],
                      "per-tile status stored at the gateway (with complement)");
            end
            rdw(0, GW + 32'h000);  check(rd == 3, "tile ID reads 3");
            rdw(0, GW + 32'h010);  check(rd == 1, "tile kind reads 1 (gateway)");

            // ---- 2. no lock ----
            $display("[2] no lock, no DMA");
            wr (0, GW + 32'h100, T0 + 32'h200);
            expect_reject(0, 4'd1, "MM2S_DST without the lock: reason 1");
            wr (0, DMA + 32'h28, 32'd32);
            expect_reject(0, 4'd1, "DMA LENGTH without the lock: reason 1");
            check(u_dma.mm2s_busy == 1'b0, "DMA never started");

            // ---- 3. lock ----
            $display("[3] DMA lock");
            rdw(0, GW + 32'h114);  check(rd[31] && rd[7:0] == 0, "tile 0 claims: granted");
            rdw(0, GW + 32'h114);  check(rd[31] && rd[7:0] == 0, "repeat claim: still granted (retry-safe)");
            rdw(1, GW + 32'h114);  check(!rd[31] && rd[30] && rd[7:0] == 0, "tile 1 claims: busy, owner 0");
            wr (1, GW + 32'h100, T1 + 32'h200);
            expect_reject(1, 4'd1, "non-owner write refused");
            wr (0, GW + 32'h114, 32'h0);                       // tile 0 releases
            rdw(1, GW + 32'h114);  check(rd[31] && rd[7:0] == 1, "handoff: queued tile 1 now owns it");
            rdw(0, GW + 32'h114);  check(!rd[31] && rd[7:0] == 1, "tile 0 queued behind tile 1");
            wr (1, GW + 32'h114, 32'h0);                       // tile 1 releases
            rdw(0, GW + 32'h114);  check(rd[31] && rd[7:0] == 0, "round robin: back to tile 0");

            // ---- 4. transfers (owner tile 0, its own RAM, DDR zone Z0) ----
            $display("[4] MM2S DDR -> tile 0 RAM, S2MM tile 0 RAM -> DDR");
            for (i = 0; i < 8; i = i + 1) u_dma.mem[16 + i] = 32'hA000_0000 + i;
            wr (0, GW + 32'h100, T0 + 32'h200);                // arm: dst = tile 0 + 0x200
            wr (0, DMA + 32'h00, 32'h1);                       // MM2S_DMACR.RS
            wr (0, DMA + 32'h18, 32'h40);                      // SA = word 16
            wr (0, DMA + 32'h28, 32'd32);                      // LENGTH = 8 words: checked, starts
            wait_status(0, 4'b0010);
            ok = 1;
            for (i = 0; i < 8; i = i + 1)
                if (u_ni0.mem[(32'h200 >> 2) + i] !== 32'hA000_0000 + i) ok = 0;
            check(ok, "8 words landed in tile 0 RAM");
            rdw(0, GW + 32'h110);  check(rd == 8, "MM2S_CNT = 8");
            wr (0, GW + 32'h10C, 32'h2);

            for (i = 0; i < 6; i = i + 1) u_ni0.mem[(32'h100 >> 2) + i] = 32'hB000_0000 + i;
            wr (0, GW + 32'h104, T0 + 32'h100);                // src
            wr (0, DMA + 32'h30, 32'h1);                       // S2MM_DMACR.RS
            wr (0, DMA + 32'h48, 32'h100);                     // DA = word 64
            wr (0, DMA + 32'h58, 32'd24);                      // LENGTH = 6 words: checked
            wr (0, GW + 32'h108, 32'd5);
            expect_reject(0, 4'd5, "S2MM_CNT 5 vs length 6 words: reason 5");
            wr (0, GW + 32'h114, 32'h0);
            expect_reject(0, 4'd7, "release while a transfer is set up: reason 7");
            wr (0, GW + 32'h108, 32'd6);                       // go
            wait_status(0, 4'b1000);
            ok = 1;
            for (i = 0; i < 6; i = i + 1)
                if (u_dma.mem[64 + i] !== 32'hB000_0000 + i) ok = 0;
            check(ok, "6 words landed in DDR model");
            wr (0, GW + 32'h10C, 32'h8);

            // ---- 5. misprograms ----
            $display("[5] misprogrammed requests are refused");
            wr (0, GW + 32'h100, T1 + 32'h200);                // another tile's RAM
            wr (0, DMA + 32'h18, 32'h40);
            wr (0, DMA + 32'h28, 32'd32);
            expect_reject(0, 4'd3, "MM2S into another tile: reason 3");
            wr (0, GW + 32'h100, T0 + 32'hF80);                // 128 B left in the window
            wr (0, DMA + 32'h28, 32'd256);
            expect_reject(0, 4'd3, "MM2S running past the 4KB window: reason 3");
            wr (0, GW + 32'h100, T0 + 32'h200);
            wr (0, DMA + 32'h18, 32'h02C0_0000);               // zone Z1 (tile 1's)
            wr (0, DMA + 32'h28, 32'd32);
            expect_reject(0, 4'd2, "DDR source in another core's zone: reason 2");
            wr (0, DMA + 32'h18, 32'h027F_FFF0);               // straddles Z0 / B0
            wr (0, DMA + 32'h28, 32'd32);
            expect_reject(0, 4'd2, "range straddling two regions: reason 2");
            wr (0, DMA + 32'h18, 32'h42);
            wr (0, DMA + 32'h28, 32'd32);
            expect_reject(0, 4'd4, "unaligned DDR address: reason 4");
            wr (0, DMA + 32'h18, 32'h0280_0000);               // shared window B0: allowed for tile 0
            wr (0, DMA + 32'h28, 32'd32);
            wait_status(0, 4'b0010);
            rdw(0, GW + 32'h118);  check(!rd[31], "shared window B0 accepted for tile 0");
            wr (0, GW + 32'h10C, 32'h2);
            wr (0, DMA + 32'h28, 32'd32);                      // destination no longer armed
            expect_reject(0, 4'd9, "MM2S go with no armed destination: reason 9");
            wr (0, DMA + 32'h1C, 32'h0);                       // MM2S_SA_MSB: not direct-mode 32-bit
            expect_reject(0, 4'd6, "register outside the allow-list: reason 6");
            check(err3 == 5'b0, "refusals do not raise NI error flags");
            check(gw_flags[0] == 1'b1, "gw_flags: request-rejected flag");
            wr (0, GW + 32'h004, 32'hE0);
            wr (0, GW + 32'h114, 32'h0);

            // ---- 6. lease ----
            $display("[6] lock lease");
            rdw(1, GW + 32'h114);  check(rd[31] && rd[7:0] == 1, "tile 1 takes the lock");
            repeat (LEASE + 50) @(posedge clk); #1;            // tile 1 goes silent
            check(gw_flags[1] == 1'b1 && gw_info[19:12] == 1, "lease expired, tile 1 recorded");
            rdw(0, GW + 32'h114);  check(rd[31] && rd[7:0] == 0, "lock free again: tile 0 granted");
            wr (0, GW + 32'h114, 32'h0);
            wr (0, GW + 32'h004, 32'hE0);

            // ---- 7. reads ----
            $display("[7] DMA register reads and illegal offsets");
            rdw(0, DMA + 32'h34);  check(rd[1] == 1, "S2MM_DMASR idle (reads need no lock)");
            rdw(0, DMA + 32'h5C);  check(rd == 32'hDEAD_BEEF, "SLVERR read -> POISON");
            check(err3[1] == 1, "err_illegal set by SLVERR");
            rdw(0, GW + 32'h400);  check(rd == 32'hDEAD_BEEF, "offset 0x400 read -> POISON");
            check(gw_flags[2] == 1'b0, "model reports no DMA error bits");
        end else if (FAULT == 2) begin
            // ---- a dead link found by BIST, routed around ----
            $display("[F2] link tile2 -> north silent from power-up");
            check(bist_status[2*10 + `NOC_P_N] == 1'b0, "BIST: router 2 outlink N failed");
            check(u_mesh.dead_links === {NT{8'h02}}, "every router knows link 0-2 is dead");
            check(avail == 4'b1111, "all four tiles still available");
            rdw(0, GW + 32'h114);  check(rd[31] && rd[7:0] == 0, "tile 0 claims the lock (reply rerouted)");
            wr (0, GW + 32'h004, 32'hE0);
            for (i = 0; i < 4; i = i + 1) u_dma.mem[16 + i] = 32'hD000_0000 + i;
            wr (0, GW + 32'h100, T0 + 32'h200);
            wr (0, DMA + 32'h00, 32'h1);
            wr (0, DMA + 32'h18, 32'h40);
            wr (0, DMA + 32'h28, 32'd16);
            wait_status(0, 4'b0010);
            ok = 1;
            for (i = 0; i < 4; i = i + 1)
                if (u_ni0.mem[(32'h200 >> 2) + i] !== 32'hD000_0000 + i) ok = 0;
            check(ok, "DDR -> tile 0 RAM over the detour");
            wr (0, GW + 32'h114, 32'h0);
            check(err0 == 5'b0 && gw_flags == 3'b0, "no timeout, no refusal");
            check(rt_drop_cnt == {NT*8{1'b0}}, "nothing dropped anywhere");
        end else begin
            // ---- availability gate ----
            $display("[F1] router 2 north output disabled (one-way, unseen by BIST)");
            check(avail == 4'b1110, "tile 0 unavailable, the others available");
            check(u_gw.bc_st[0] == 10'b0, "tile 0's status could not be read: stored as 0");
            // tile 0's claim reaches the gateway but the reply is lost
            rdw(0, GW + 32'h114);
            check(rd == 32'hDEAD_BEEF && err0[0], "tile 0 sees only POISON + timeout");
            check(u_gw.lk_held && u_gw.lk_owner == 0, "...yet the gateway granted it the lock");
            wr (0, GW + 32'h100, T0 + 32'h200);                // blind, posted writes
            wr (0, DMA + 32'h18, 32'h40);
            wr (0, DMA + 32'h28, 32'd32);
            repeat (200) @(posedge clk); #1;
            check(u_gw.err_rej && u_gw.rej_reason == 4'd8, "DMA go refused: tile 0 unavailable (reason 8)");
            check(u_dma.mm2s_busy == 1'b0, "DMA never started");
            wr (0, GW + 32'h114, 32'h0);                       // release (posted, arrives)
            repeat (50) @(posedge clk); #1;
            // tile 1 is unaffected
            rdw(1, GW + 32'h114);  check(rd[31] && rd[7:0] == 1, "tile 1 claims the lock");
            wr (1, GW + 32'h004, 32'hE0);
            wr (1, GW + 32'h100, T1 + 32'h300);
            wr (1, DMA + 32'h00, 32'h1);
            wr (1, DMA + 32'h18, 32'h02C0_0000);               // tile 1's zone Z1
            for (i = 0; i < 4; i = i + 1) u_dma.mem[((32'h02C0_0000 >> 2) % 1024) + i] = 32'hC000_0000 + i;
            wr (1, DMA + 32'h28, 32'd16);
            wait_status(1, 4'b0010);
            ok = 1;
            for (i = 0; i < 4; i = i + 1)
                if (u_ni1.mem[(32'h300 >> 2) + i] !== 32'hC000_0000 + i) ok = 0;
            check(ok, "tile 1 still moves data through the gateway");
        end

        $display("");
        if (fails == 0) $display("PASS: tb_gw_ni FAULT=%0d (%0d checks)", FAULT, checks);
        else            $display("FAIL: tb_gw_ni FAULT=%0d (%0d of %0d checks failed)", FAULT, fails, checks);
        $finish;
    end

endmodule
