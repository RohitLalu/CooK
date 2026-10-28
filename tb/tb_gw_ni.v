// tb_gw_ni.v
// System test of the gateway: 2x2 mesh, tile 0 driven by the testbench as a
// core (through a real ni.v), tiles 1 and 2 plain responders, tile 3 = gw_ni
// wired to axi_dma_model. Assumes the default 2x2 knobs.
//   1. gateway CSR read through the mesh
//   2. DDR -> tile 1 RAM  (MM2S, 8 words)
//   3. tile 2 RAM -> DDR  (S2MM, 6 words)
//   4. DMA register read through the mesh, SLVERR -> POISON + err_illegal
//   5. illegal gateway offset, illegal MM2S destination (dropped, no crash)

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_gw_ni;

    localparam NT = `NOC_NUM_TILES;
    localparam FW = `NOC_FLIT_W;
    localparam [31:0] GW = 32'h0000_3000;   // tile 3 window
    localparam [31:0] T1 = 32'h0000_1000;
    localparam [31:0] T2 = 32'h0000_2000;

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

    noc_mesh u_mesh (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt)
    );

    // ---------------- tile 0: testbench core ----------------
    reg         c_valid = 0;
    reg  [31:0] c_addr = 0, c_wdata = 0;
    reg  [3:0]  c_wstrb = 0;
    wire        c_ready;
    wire [31:0] c_rdata;
    wire [4:0]  err0;
    wire [31:0] sw0;

    ni #(.MY_ID(0)) u_ni0 (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(c_valid), .mem_instr(1'b0), .mem_ready(c_ready),
        .mem_addr(c_addr), .mem_wdata(c_wdata), .mem_wstrb(c_wstrb), .mem_rdata(c_rdata),
        .in_valid(r2ni_valid[0]), .in_ready(r2ni_ready[0]), .in_room(r2ni_room[0]),
        .in_flit(r2ni_flit[0*FW +: FW]),
        .out_valid(ni2r_valid[0]), .out_ready(ni2r_ready[0]), .out_flit(ni2r_flit[0*FW +: FW]),
        .err_flags(err0), .sw_status(sw0)
    );

    // ---------------- tiles 1, 2: responders ----------------
    wire [4:0] err1, err2;
    wire [31:0] sw1, sw2;
    ni #(.MY_ID(1)) u_ni1 (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(1'b0), .mem_instr(1'b0), .mem_ready(), .mem_addr(32'b0),
        .mem_wdata(32'b0), .mem_wstrb(4'b0), .mem_rdata(),
        .in_valid(r2ni_valid[1]), .in_ready(r2ni_ready[1]), .in_room(r2ni_room[1]),
        .in_flit(r2ni_flit[1*FW +: FW]),
        .out_valid(ni2r_valid[1]), .out_ready(ni2r_ready[1]), .out_flit(ni2r_flit[1*FW +: FW]),
        .err_flags(err1), .sw_status(sw1)
    );
    ni #(.MY_ID(2)) u_ni2 (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(1'b0), .mem_instr(1'b0), .mem_ready(), .mem_addr(32'b0),
        .mem_wdata(32'b0), .mem_wstrb(4'b0), .mem_rdata(),
        .in_valid(r2ni_valid[2]), .in_ready(r2ni_ready[2]), .in_room(r2ni_room[2]),
        .in_flit(r2ni_flit[2*FW +: FW]),
        .out_valid(ni2r_valid[2]), .out_ready(ni2r_ready[2]), .out_flit(ni2r_flit[2*FW +: FW]),
        .err_flags(err2), .sw_status(sw2)
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
    wire [31:0] sw3;

    gw_ni #(.MY_ID(3)) u_gw (
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
        .err_flags(err3), .sw_status(sw3)
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

    // ---------------- core bus-functional model ----------------
    // Drive on edge+1ns so the DUT never samples a changing input.
    reg [31:0] rd;
    task core_xfer;
        input [31:0] a;
        input [31:0] d;
        input [3:0]  s;
        integer n;
        begin
            c_addr = a;  c_wdata = d;  c_wstrb = s;  c_valid = 1'b1;
            n = 0;
            @(posedge clk); #1;
            while (!c_ready && n < 20000) begin @(posedge clk); #1; n = n + 1; end
            if (n >= 20000) begin
                $display("FAIL: bus hang at addr %h", a);
                $finish;
            end
            rd = c_rdata;
            c_valid = 1'b0;
        end
    endtask
    task wr; input [31:0] a; input [31:0] d; begin core_xfer(a, d, 4'hF); end endtask
    task rdw; input [31:0] a; begin core_xfer(a, 32'b0, 4'h0); end endtask

    integer fails = 0;
    task check;
        input        cond;
        input [8*44-1:0] name;
        begin
            if (cond) $display("  ok   %0s", name);
            else begin $display("  FAIL %0s", name); fails = fails + 1; end
        end
    endtask

    // poll gateway STATUS until (status & mask) != 0
    task wait_status;
        input [3:0] mask;
        integer n;
        begin
            n = 0;
            rdw(GW + 32'h10C);
            while (((rd & mask) == 0) && n < 400) begin rdw(GW + 32'h10C); n = n + 1; end
            if (n >= 400) begin $display("FAIL: status wait timed out (mask %h)", mask); fails = fails + 1; end
        end
    endtask

    integer i;
    reg ok;

    initial begin
        #1000000;
        $display("FAIL: global timeout");
        $finish;
    end

    initial begin
        repeat (6) @(posedge clk);
        #1 rst_n = 1;
        repeat (4) @(posedge clk);
        #1;

        // ---- 1. gateway CSRs through the mesh ----
        $display("[1] gateway CSRs");
        rdw(GW + 32'h000);  check(rd == 3, "tile ID reads 3");
        rdw(GW + 32'h00C);  check(rd == NT, "tile count reads NT");
        rdw(GW + 32'h010);  check(rd == 1, "tile kind reads 1 (gateway)");
        rdw(T1 + 32'h010);  check(rd == 0, "core tile kind reads 0");
        wr (GW + 32'h008, 32'hA5A5_0001);
        rdw(GW + 32'h008);  check(rd == 32'hA5A5_0001, "software status r/w");

        // ---- 2. DDR -> tile 1 (MM2S) ----
        $display("[2] MM2S: DDR -> tile 1 RAM");
        for (i = 0; i < 8; i = i + 1) u_dma.mem[16 + i] = 32'hA000_0000 + i;
        wr (GW + 32'h100, T1 + 32'h200);          // arm: dst = tile 1 + 0x200
        wr (GW + 32'h200 + 32'h00, 32'h1);        // MM2S_DMACR.RS
        wr (GW + 32'h200 + 32'h18, 32'h40);       // SA = word 16
        wr (GW + 32'h200 + 32'h28, 32'd32);       // LENGTH = 8 words, starts
        wait_status(4'b0010);
        ok = 1;
        for (i = 0; i < 8; i = i + 1)
            if (u_ni1.mem[(32'h200 >> 2) + i] !== 32'hA000_0000 + i) ok = 0;
        check(ok, "8 words landed in tile 1 RAM");
        rdw(GW + 32'h110);  check(rd == 8, "MM2S_CNT = 8");
        rdw(GW + 32'h10C);  check(rd[0] == 0, "MM2S disarmed after TLAST");
        wr (GW + 32'h10C, 32'h2);                 // clear done
        rdw(GW + 32'h10C);  check(rd[1] == 0, "done cleared by w1c");

        // ---- 3. tile 2 -> DDR (S2MM) ----
        $display("[3] S2MM: tile 2 RAM -> DDR");
        for (i = 0; i < 6; i = i + 1) u_ni2.mem[(32'h100 >> 2) + i] = 32'hB000_0000 + i;
        wr (GW + 32'h104, T2 + 32'h100);          // src
        wr (GW + 32'h200 + 32'h30, 32'h1);        // S2MM_DMACR.RS
        wr (GW + 32'h200 + 32'h48, 32'h100);      // DA = word 64
        wr (GW + 32'h200 + 32'h58, 32'd24);       // LENGTH = 6 words, arms
        wr (GW + 32'h108, 32'd6);                 // go
        wait_status(4'b1000);
        ok = 1;
        for (i = 0; i < 6; i = i + 1)
            if (u_dma.mem[64 + i] !== 32'hB000_0000 + i) ok = 0;
        check(ok, "6 words landed in DDR model");
        rdw(GW + 32'h200 + 32'h58);  check(rd == 24, "DMA saw 24 bytes");
        rdw(GW + 32'h108);  check(rd == 0, "S2MM_CNT back to 0");

        // ---- 4. DMA register read, SLVERR path ----
        $display("[4] DMA register access");
        rdw(GW + 32'h200 + 32'h34);  check(rd[1] == 1, "S2MM_DMASR idle");
        check(err3 == 5'b0, "no gateway errors so far");
        rdw(GW + 32'h200 + 32'h5C);  check(rd == 32'hDEAD_BEEF, "SLVERR read -> POISON");
        check(err3[1] == 1, "err_illegal set by SLVERR");
        wr (GW + 32'h004, 32'h1F);
        rdw(GW + 32'h004);  check(rd == 0, "error flags cleared");

        // ---- 5. illegal use ----
        $display("[5] illegal use");
        rdw(GW + 32'h400);  check(rd == 32'hDEAD_BEEF, "offset 0x400 read -> POISON");
        check(err3[1] == 1, "err_illegal set");
        wr (GW + 32'h004, 32'h1F);
        wr (GW + 32'h100, T1 + 32'h010);          // dst below 0x100: would hit CSRs
        wr (GW + 32'h200 + 32'h18, 32'h40);
        wr (GW + 32'h200 + 32'h28, 32'd8);        // 2 words
        wait_status(4'b0010);
        check(err3[1] == 1, "bad MM2S dst flagged");
        check(sw1 == 32'b0, "tile 1 software status untouched");
        rdw(GW + 32'h110);  check(rd == 0, "no words sent to bad dst");
        wr (GW + 32'h004, 32'h1F);
        wr (GW + 32'h10C, 32'h2);

        $display("");
        if (fails == 0) $display("PASS: tb_gw_ni");
        else            $display("FAIL: tb_gw_ni (%0d checks failed)", fails);
        $finish;
    end

endmodule
