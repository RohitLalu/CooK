// tb_sb_top.v
// The single-bus baseline end to end: three real picorv32 cores, the memory
// node and the AXI4 memory model.
// TEST = 0  alltoall.mem, the NoC's own image, unchanged: every core tests
//           the two other cores (74 checks each) and the memory node (2) =
//           150 checks, the same count as on the NoC with its gateway.
// TEST = 1  ddr.mem on all three cores at once: 66 checks each through the
//           shared DDR, and the words are where they should be.
// TEST = 2  stuck arbiter from reset, alltoall.mem: no core hangs, every
//           core reports failure. Usable cores: 0 of 3 (metric M3).
// TEST = 3  flipped data wire from reset: the same result.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_sb_top;

    parameter integer TEST = 0;
`ifdef XILINX_SIMULATOR
    parameter SW_DIR = "../../../../../";       // repo root from the xsim run directory
`else
    parameter SW_DIR = "../";
`endif

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer ERR_IX = 32'hF00 >> 2, MARK_IX = 32'hF04 >> 2, CHK_IX = 32'hF08 >> 2;
    localparam integer CHECKS = (TEST == 1) ? 66 : 2 * 74 + 2;

    generate
        if (NT != 4) begin : tb_check_nt
            TB_ERROR_tb_sb_top_assumes_four_node_ids u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]    tile_trap, bus_err_drop;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire             bus_active;

    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [7:0]  awlen, arlen;
    wire [1:0]  bresp, rresp;
    wire [3:0]  wstrb;
    wire        awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rlast, rvalid, rready;

    sb_top dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .fault_grant(TEST == 2), .fault_flip(TEST == 3),
        .bus_err_drop(bus_err_drop), .bus_active(bus_active),
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

    // 8 MB of model memory: ddr.S uses megabytes 0..2 and 15 (which wraps onto 7)
    axi4_mem_model #(.MEM_WORDS(2097152), .LAT(3)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(awaddr), .s_awlen(awlen), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wlast(wlast), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arlen(arlen), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready)
    );

    genvar gt;
    generate
        for (gt = 0; gt < 3; gt = gt + 1) begin : load
            initial begin
                if (TEST == 1) $readmemh({SW_DIR, "single_bus/sw/ddr.mem"}, dut.g_tile[gt].u_ni.mem);
                else           $readmemh({SW_DIR, "sw/alltoall.mem"},       dut.g_tile[gt].u_ni.mem);
            end
            assign mark[gt*32 +: 32] = dut.g_tile[gt].u_ni.mem[MARK_IX];
            assign nerr[gt*32 +: 32] = dut.g_tile[gt].u_ni.mem[ERR_IX];
            assign nchk[gt*32 +: 32] = dut.g_tile[gt].u_ni.mem[CHK_IX];
        end
    endgenerate
    wire [3*32-1:0] mark, nerr, nchk;
    wire all_done = (mark[0 +: 32] === 32'hC0DE) && (mark[32 +: 32] === 32'hC0DE) && (mark[64 +: 32] === 32'hC0DE);

    integer errors = 0, checks = 0, cyc = 0, act = 0, t, npass, nfail;
    always @(posedge clk) if (rst_n && bus_active && !all_done) act = act + 1;

    task check;
        input cond;
        input [8*72-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
            else             $display("PASS: %0s", msg);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        while (!all_done && cyc < 400000) begin @(posedge clk); cyc = cyc + 1; end
        repeat (20) @(posedge clk);
        $display("bus, TEST=%0d: programs finished after %0d cycles, bus busy %0d of them (%0d%%)",
                 TEST, cyc, act, 100 * act / cyc);

        npass = 0; nfail = 0;
        for (t = 0; t < 3; t = t + 1) begin
            if (tile_sw[t*32 +: 32] === (32'h600D0000 | CHECKS)) npass = npass + 1;
            if (tile_sw[t*32 + 16 +: 16] === 16'hFA11)           nfail = nfail + 1;
        end
        check(all_done, "all three cores completed (no hang)");
        check(tile_trap === {NT{1'b0}}, "no core trapped");

        if (TEST < 2) begin
            check(npass == 3, "every core passed with the expected check count");
            check(nerr === 96'b0 && nchk === {3{CHECKS[31:0]}}, "error and check counters agree");
            check(tile_err === {NT*5{1'b0}}, "no NI or memory-node error flags");
            check(bus_err_drop === {NT{1'b0}}, "the bus dropped nothing");
            check(u_ddr.protocol_errors == 0, "AXI4 single-beat rules kept");
            if (TEST == 1) begin
                check(u_ddr.mem[(32'h000000 >> 2) + 5] === 32'h005A_0005 &&
                      u_ddr.mem[(32'h100000 >> 2) + 5] === 32'h015A_0005 &&
                      u_ddr.mem[(32'h200000 >> 2) + 5] === 32'h025A_0005,
                      "each core's words are in its own megabyte of the DDR");
                check(u_ddr.mem[(32'h700000 >> 2) + 0] === 1 && u_ddr.mem[(32'h700000 >> 2) + 1] === 2 &&
                      u_ddr.mem[(32'h700000 >> 2) + 2] === 3, "the shared megabyte holds one slot per core");
            end
        end else begin
            check(npass == 0 && nfail == 3, "usable cores: 0 of 3 -- every core reports failure");
            check(tile_err[0*5] && tile_err[1*5] && tile_err[2*5], "every core's NI flags a timeout");
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
