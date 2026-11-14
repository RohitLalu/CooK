// tb_fabric.v
// Fabric benchmark: the same endpoints on two interconnects, loaded hard
// enough for the interconnect to matter. Compile with -DFABRIC_BUS for the
// shared bus (sb_bus), without it for the 2x2 mesh (noc_mesh). Everything
// else is identical: three tiles behind ni.v, the DMA gateway gw_ni on
// tile 3 with the behavioural DMA model as the DDR.
//
// The cores are replaced by bus-functional drivers that issue the next
// access as soon as the last one is accepted. A PicoRV32 needs so many cycles
// per access that it leaves either fabric mostly idle, which is why the CPU
// benchmarks give equal numbers on both.
//
// THREE FLOWS, chosen so that on the mesh no two share a link:
//   DMA  DDR -> tile 0 RAM, NW words streamed by the gateway   (3 -> 2 -> 0)
//   W1   tile 1 posts NW words into tile 2's mailbox           (1 -> 0 -> 2)
//   W2   tile 2 posts NW words into tile 1's mailbox           (2 -> 3 -> 1)
// CASES: each flow alone, then all three started on the same cycle.
// One line per case:
//   FABRIC case=<name> dma=<cycles> w1=<cycles> w2=<cycles> total=<cycles> ok=<0|1>
// (0 = that flow did not run). ok = every word arrived and no error flag is set.
// Default 2x2 knobs, 4 KB tiles.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_fabric;

    parameter integer NW = 448;                  // words per flow (a mailbox holds 448)

    localparam NT = `NOC_NUM_TILES;
    localparam FW = `NOC_FLIT_W;
    localparam [31:0] GW  = 32'h0000_3000, DMA = GW + 32'h200;
    localparam [31:0] T0  = 32'h0000_0000, T1 = 32'h0000_1000, T2 = 32'h0000_2000;
    localparam [31:0] DST = 32'h400;             // DMA destination offset in tile 0
    localparam [31:0] MBX = 32'h800;

    generate
        if (NT != 4 || `NOC_OFFSET_BITS != 12) begin : tb_check_cfg
            TB_ERROR_tb_fabric_assumes_default_knobs u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- the fabric ----------------
    wire [NT-1:0]    ni2r_valid, ni2r_ready, r2ni_valid, r2ni_ready, r2ni_room;
    wire [NT*FW-1:0] ni2r_flit, r2ni_flit;
    wire [NT*10-1:0] bist_status;
    wire             fabric_ready;
    wire             fabric_err;

`ifdef FABRIC_BUS
    wire [NT-1:0] err_drop;
    sb_bus #(.N(NT)) u_fabric (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .fault_grant(1'b0), .fault_flip(1'b0), .err_drop(err_drop), .bus_active()
    );
    assign bist_status  = {NT*10{1'b1}};         // no link BIST on a bus: report healthy
    assign fabric_ready = 1'b1;
    assign fabric_err   = |err_drop;
`else
    wire [NT*8-1:0] rt_drop_cnt;
    wire [NT*5-1:0] rt_out_dead;
    noc_mesh u_fabric (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(rt_out_dead), .rt_out_wd(), .rt_drop_cnt(rt_drop_cnt),
        .fault_rt_mask({4*NT{1'b0}}), .fault_rt_flip(1'b0),
        .bist_status(bist_status), .bist_done(fabric_ready)
    );
    assign fabric_err = (|rt_drop_cnt) || (|rt_out_dead);
`endif

    // ---------------- tiles 0..2: driver + ni ----------------
    reg  [2:0]  c_valid = 0;
    reg  [31:0] c_addr [0:2];
    reg  [31:0] c_wdata [0:2];
    reg  [3:0]  c_wstrb [0:2];
    wire [2:0]  c_ready;
    wire [31:0] c_rdata [0:2];
    wire [4:0]  err [0:3];

    genvar g;
    generate
        for (g = 0; g < 3; g = g + 1) begin : g_tile
            ni #(.MY_ID(g), .GW_ID(3)) u_ni (
                .clk(clk), .rst_n(rst_n),
                .mem_valid(c_valid[g]), .mem_instr(1'b0), .mem_ready(c_ready[g]),
                .mem_addr(c_addr[g]), .mem_wdata(c_wdata[g]), .mem_wstrb(c_wstrb[g]),
                .mem_rdata(c_rdata[g]),
                .in_valid(r2ni_valid[g]), .in_ready(r2ni_ready[g]), .in_room(r2ni_room[g]),
                .in_flit(r2ni_flit[g*FW +: FW]),
                .out_valid(ni2r_valid[g]), .out_ready(ni2r_ready[g]), .out_flit(ni2r_flit[g*FW +: FW]),
                .err_flags(err[g]), .sw_status(), .bist_status(bist_status[g*10 +: 10])
            );
        end
    endgenerate

    // ---------------- tile 3: gateway + DMA model (the DDR) ----------------
    wire [9:0]  awaddr, araddr;
    wire        awvalid, awready, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rvalid, rready;
    wire [31:0] wdata, rdata, mm_tdata, s2_tdata;
    wire [3:0]  wstrb, mm_tkeep, s2_tkeep;
    wire [1:0]  bresp, rresp;
    wire        mm_tlast, mm_tvalid, mm_tready, s2_tlast, s2_tvalid, s2_tready;
    wire [2:0]  gw_flags;
    wire        sys_ready;

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
        .err_flags(err[3]), .sw_status(), .gw_flags(gw_flags), .gw_info(),
        .bist_mesh_done(fabric_ready), .bist_own_status(bist_status[3*10 +: 10]),
        .sys_ready(sys_ready), .avail()
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

    // ---------------- drivers ----------------
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

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

    reg [31:0] junk0;
    event dma_go;            // the DMA's "go" write is being issued

    // DDR -> tile 0: tile 0 claims the DMA lock and programs the transfer, the
    // gateway then streams. Time runs from the "go" write to the last word landing.
    task automatic flow_dma;
        input  [31:0] pat;
        output integer t;
        integer i, t0;
        begin
            for (i = 0; i < NW; i = i + 1) u_dma.mem[16 + i] = pat + i;
            xfer(0, GW + 32'h114, 0, 4'h0, junk0);               // claim the lock
            xfer(0, GW + 32'h100, T0 + DST, 4'hF, junk0);        // arm: destination
            xfer(0, DMA + 32'h00, 32'h1, 4'hF, junk0);           // MM2S_DMACR.RS
            xfer(0, DMA + 32'h18, 32'h40, 4'hF, junk0);          // source address (zone Z0)
            t0 = cyc;
            -> dma_go;
            xfer(0, DMA + 32'h28, NW * 4, 4'hF, junk0);          // LENGTH: go
            while (g_tile[0].u_ni.mem[(DST >> 2) + NW - 1] !== pat + NW - 1) @(posedge clk);
            t = cyc - t0;
            repeat (20) @(posedge clk); #1;
            xfer(0, GW + 32'h10C, 32'h2, 4'hF, junk0);           // clear done
            xfer(0, GW + 32'h114, 0, 4'hF, junk0);               // release the lock
        end
    endtask

    // tile `who` posts NW words into tile `to`'s mailbox, as fast as its NI takes them
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

    // every word of a finished flow is where it should be
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
            ok = (err[0] == 0) && (err[1] == 0) && (err[2] == 0) && (err[3] == 0) &&
                 (gw_flags == 0) && !fabric_err &&
                 (td == 0 || landed(0, DST, 32'hD000_0000)) &&
                 (t1 == 0 || landed(2, MBX, 32'hA100_0000)) &&
                 (t2 == 0 || landed(1, MBX, 32'hA200_0000));
            $display("FABRIC case=%0s dma=%0d w1=%0d w2=%0d total=%0d ok=%0d", name, td, t1, t2, tot, ok);
        end
    endtask

    // wipe the destinations so a later case cannot pass on an earlier one's data
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
        while (!sys_ready) @(posedge clk);
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
        fork
            flow_dma(32'hD000_0000, td);
            begin @(dma_go); flow_wr(1, 2, 32'hA100_0000, t1); end   // all three start together
            begin @(dma_go); flow_wr(2, 1, 32'hA200_0000, t2); end
        join
        tot = (td > t1 ? (td > t2 ? td : t2) : (t1 > t2 ? t1 : t2));
        report("all");
        $finish;
    end
endmodule
