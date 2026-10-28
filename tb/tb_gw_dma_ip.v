// tb_gw_dma_ip.v
// System test of the gateway with the REAL Xilinx axi_dma IP: mesh_top with
// GW_EN = 1 (gw_ni on tile 3) wired to cook_gw_sim_wrapper, the simulation
// variant of the block design (axi_dma + SmartConnect + 8 KB block RAM in
// place of the MIG -- built by rtl/dma_ddr/create_cook_gw.tcl with
// gw_variant sim). No cores: tile 0's memory bus is driven by the testbench
// through force, everything else is the real fabric.
//   1. gateway and DMA register reads through the mesh (DMA reset state)
//   2. tile 1 RAM -> memory (S2MM, 16 words), DMA reports idle + IOC
//   3. memory -> tile 2 RAM (MM2S, 16 words): round trip compares equal
//   4. interrupts, DMA error bits, NI and router error flags all clean
// Needs a Vivado project that has cook_gw_sim (for the IP simulation models).

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_gw_dma_ip;

    localparam NT = `NOC_NUM_TILES;
    localparam [31:0] GW  = 32'h0000_3000;
    localparam [31:0] DMA = GW + 32'h200;     // axi_dma register window
    localparam [31:0] T1  = 32'h0000_1000;
    localparam [31:0] T2  = 32'h0000_2000;
    localparam integer NW = 16;               // words per transfer

    // axi_dma register offsets and bits (PG021)
    localparam [31:0] MM2S_DMACR = 32'h00, MM2S_DMASR = 32'h04, MM2S_SA = 32'h18, MM2S_LENGTH = 32'h28;
    localparam [31:0] S2MM_DMACR = 32'h30, S2MM_DMASR = 32'h34, S2MM_DA = 32'h48, S2MM_LENGTH = 32'h58;
    localparam [31:0] CR_RS_IOCEN = 32'h0000_1001;     // run/stop + IOC interrupt enable
    localparam [31:0] SR_HALTED = 32'h1, SR_IDLE = 32'h2, SR_ERRS = 32'h70, SR_IOC = 32'h1000;

    reg clk = 0;
    reg rst_n = 0;
    always #10 clk = ~clk;                    // 50 MHz, as on the board

    // ---------------------------------------------------------------- DUT
    wire [NT-1:0]    tile_trap;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire [NT*5*`NOC_E_W-1:0] rt_in_err;
    wire [NT*5-1:0]  rt_out_dead, rt_out_wd;
    wire [NT*8-1:0]  rt_drop_cnt;

    wire [9:0]  awaddr, araddr;
    wire        awvalid, awready, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rvalid, rready;
    wire [31:0] wdata, rdata;
    wire [3:0]  wstrb;
    wire [1:0]  bresp, rresp;
    wire [31:0] mm_tdata, s2_tdata;
    wire [3:0]  mm_tkeep, s2_tkeep;
    wire        mm_tlast, mm_tvalid, mm_tready, s2_tlast, s2_tvalid, s2_tready;
    wire        mm2s_irq, s2mm_irq;

    mesh_top #(
        .CORE_MASK({NT{1'b0}}),
        .GW_EN(1), .GW_TILE(3)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt),
        .gw_axil_awaddr(awaddr), .gw_axil_awvalid(awvalid), .gw_axil_awready(awready),
        .gw_axil_wdata(wdata), .gw_axil_wstrb(wstrb), .gw_axil_wvalid(wvalid), .gw_axil_wready(wready),
        .gw_axil_bresp(bresp), .gw_axil_bvalid(bvalid), .gw_axil_bready(bready),
        .gw_axil_araddr(araddr), .gw_axil_arvalid(arvalid), .gw_axil_arready(arready),
        .gw_axil_rdata(rdata), .gw_axil_rresp(rresp), .gw_axil_rvalid(rvalid), .gw_axil_rready(rready),
        .gw_mm2s_tdata(mm_tdata), .gw_mm2s_tkeep(mm_tkeep), .gw_mm2s_tlast(mm_tlast),
        .gw_mm2s_tvalid(mm_tvalid), .gw_mm2s_tready(mm_tready),
        .gw_s2mm_tdata(s2_tdata), .gw_s2mm_tkeep(s2_tkeep), .gw_s2mm_tlast(s2_tlast),
        .gw_s2mm_tvalid(s2_tvalid), .gw_s2mm_tready(s2_tready)
    );

    cook_gw_sim_wrapper u_bd (
        .clk50(clk), .rst_n(rst_n),
        .dma_ctrl_awaddr(awaddr), .dma_ctrl_awvalid(awvalid), .dma_ctrl_awready(awready),
        .dma_ctrl_wdata(wdata), .dma_ctrl_wvalid(wvalid), .dma_ctrl_wready(wready),
        .dma_ctrl_bresp(bresp), .dma_ctrl_bvalid(bvalid), .dma_ctrl_bready(bready),
        .dma_ctrl_araddr(araddr), .dma_ctrl_arvalid(arvalid), .dma_ctrl_arready(arready),
        .dma_ctrl_rdata(rdata), .dma_ctrl_rresp(rresp), .dma_ctrl_rvalid(rvalid), .dma_ctrl_rready(rready),
        .mm2s_axis_tdata(mm_tdata), .mm2s_axis_tkeep(mm_tkeep), .mm2s_axis_tlast(mm_tlast),
        .mm2s_axis_tvalid(mm_tvalid), .mm2s_axis_tready(mm_tready),
        .s2mm_axis_tdata(s2_tdata), .s2mm_axis_tkeep(s2_tkeep), .s2mm_axis_tlast(s2_tlast),
        .s2mm_axis_tvalid(s2_tvalid), .s2mm_axis_tready(s2_tready),
        .mm2s_introut(mm2s_irq), .s2mm_introut(s2mm_irq)
    );

    // ---------------------------------------------------------------- tile 0 bus driver
    // Tile 0 has no core (CORE_MASK = 0); its bus is forced from here.
    reg         c_valid = 0;
    reg  [31:0] c_addr = 0, c_wdata = 0;
    reg  [3:0]  c_wstrb = 0;
    wire        c_ready = dut.g_tile[0].mem_ready;
    wire [31:0] c_rdata = dut.g_tile[0].mem_rdata;

    initial begin
        force dut.g_tile[0].mem_valid = c_valid;
        force dut.g_tile[0].mem_addr  = c_addr;
        force dut.g_tile[0].mem_wdata = c_wdata;
        force dut.g_tile[0].mem_wstrb = c_wstrb;
    end

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
    task wr;  input [31:0] a; input [31:0] d; begin core_xfer(a, d, 4'hF); end endtask
    task rdw; input [31:0] a; begin core_xfer(a, 32'b0, 4'h0); end endtask

    integer fails = 0;
    task check;
        input        cond;
        input [8*48-1:0] name;
        begin
            if (cond) $display("  ok   %0s", name);
            else begin $display("  FAIL %0s", name); fails = fails + 1; end
        end
    endtask

    // poll a register through the mesh until (value & mask) != 0
    task poll;
        input [31:0] a;
        input [31:0] mask;
        integer n;
        begin
            n = 0;
            rdw(a);
            while (((rd & mask) == 0) && n < 500) begin rdw(a); n = n + 1; end
            if (n >= 500) begin
                $display("  FAIL poll %h for mask %h (last %h)", a, mask, rd);
                fails = fails + 1;
            end
        end
    endtask

    integer i;
    reg ok;

    initial begin
        #2000000;
        $display("FAIL: global timeout");
        $finish;
    end

    initial begin
        for (i = 0; i < NW; i = i + 1) dut.g_tile[1].g_ni.u_ni.mem[(32'h200 >> 2) + i] = 32'hC0DE_0000 + i * 32'h0101;
        repeat (20) @(posedge clk);
        #1 rst_n = 1;
        repeat (60) @(posedge clk);         // proc_sys_reset releases the DMA
        #1;

        // ---- 1. register access through the mesh ----
        $display("[1] gateway + axi_dma registers");
        rdw(GW + 32'h000);         check(rd == 3, "gateway tile ID reads 3");
        rdw(DMA + MM2S_DMASR);     check(rd[0] == 1'b1, "MM2S_DMASR halted after reset");
        rdw(DMA + S2MM_DMASR);     check(rd[0] == 1'b1, "S2MM_DMASR halted after reset");
        wr (DMA + S2MM_DA, 32'h0000_0100);
        rdw(DMA + S2MM_DA);        check(rd == 32'h100, "S2MM_DA write/read-back");

        // ---- 2. tile 1 -> memory (S2MM) ----
        $display("[2] S2MM: tile 1 RAM -> memory");
        wr (GW + 32'h104, T1 + 32'h200);             // gateway source
        wr (DMA + S2MM_DMACR, CR_RS_IOCEN);
        wr (DMA + S2MM_DA, 32'h0000_0100);
        wr (DMA + S2MM_LENGTH, NW * 4);              // DMA now accepts the stream
        wr (GW + 32'h108, NW);                       // gateway starts streaming
        poll(GW + 32'h10C, 32'h8);                   // gateway S2MM done
        poll(DMA + S2MM_DMASR, SR_IOC);              // DMA completed the transfer
        check((rd & SR_IDLE) != 0, "S2MM idle after transfer");
        check((rd & SR_ERRS) == 0, "S2MM no DMA error bits");
        rdw(DMA + S2MM_LENGTH);    check(rd == NW * 4, "S2MM_LENGTH reports 64 bytes received");
        check(s2mm_irq == 1'b1, "s2mm_introut asserted");
        wr (DMA + S2MM_DMASR, SR_IOC);               // clear IOC (posted write)
        rdw(DMA + S2MM_DMASR);                       // same path: lands after the write
        check((rd & SR_IOC) == 0, "S2MM IOC cleared by W1C");
        repeat (4) @(posedge clk); #1;
        check(s2mm_irq == 1'b0, "s2mm_introut cleared by W1C");

        // ---- 3. memory -> tile 2 (MM2S) ----
        $display("[3] MM2S: memory -> tile 2 RAM");
        wr (GW + 32'h100, T2 + 32'h300);             // arm gateway destination
        wr (DMA + MM2S_DMACR, CR_RS_IOCEN);
        wr (DMA + MM2S_SA, 32'h0000_0100);
        wr (DMA + MM2S_LENGTH, NW * 4);
        poll(GW + 32'h10C, 32'h2);                   // gateway saw TLAST
        poll(DMA + MM2S_DMASR, SR_IOC);
        check((rd & SR_ERRS) == 0, "MM2S no DMA error bits");
        check(mm2s_irq == 1'b1, "mm2s_introut asserted");
        rdw(GW + 32'h110);         check(rd == NW, "gateway sent 16 words");
        repeat (100) @(posedge clk); #1;             // last posted writes land
        ok = 1;
        for (i = 0; i < NW; i = i + 1)
            if (dut.g_tile[2].g_ni.u_ni.mem[(32'h300 >> 2) + i] !== 32'hC0DE_0000 + i * 32'h0101) begin
                ok = 0;
                $display("    word %0d: got %h", i, dut.g_tile[2].g_ni.u_ni.mem[(32'h300 >> 2) + i]);
            end
        check(ok, "round trip tile1 -> memory -> tile2 matches");

        // ---- 4. nothing flagged anywhere ----
        $display("[4] error state");
        check(tile_err == {NT*5{1'b0}}, "no NI / gateway error flags");
        check(rt_in_err == {NT*5*`NOC_E_W{1'b0}}, "no router error flags");
        check(rt_drop_cnt == {NT*8{1'b0}}, "no router dropped anything");
        check(rt_out_dead == {NT*5{1'b0}}, "no output declared dead");

        $display("");
        if (fails == 0) $display("PASS: tb_gw_dma_ip");
        else            $display("FAIL: tb_gw_dma_ip (%0d checks failed)", fails);
        $finish;
    end

endmodule
