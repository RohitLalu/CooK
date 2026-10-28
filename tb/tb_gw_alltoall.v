// tb_gw_alltoall.v
// The board's software with the gateway in place: mesh_top with GW_EN = 1
// (tile 3 = gw_ni, no core), real picorv32 cores on tiles 0..2 all running
// alltoall.mem at once. Each core must recognise tile 3 as the gateway
// (tile-kind CSR 0x010 = 1), give it only the ID and tile-count checks, and
// fully test the two other core tiles:
//   checks per core = 2 x 74 + 2 = 150, errors = 0, status CSR 0x600D0096.
// alltoall never touches the DMA, so the gateway's AXI side is tied idle.
// Assumes the default 2x2 knobs.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_gw_alltoall;

    // Where the baremetal images live, relative to the simulator's run
    // directory (same convention as tb_mesh_top.v).
`ifdef XILINX_SIMULATOR
    parameter SW_DIR = "../../../../../sw/";
`else
    parameter SW_DIR = "sw/";
`endif

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer GW = NT - 1;
    localparam integer CHECKS = 2 * 74 + 2;
    // alltoall.S result words (byte offsets 0xF00, 0xF04, 0xF08)
    localparam integer ERR_IX = 32'hF00 >> 2, MARK_IX = 32'hF04 >> 2, CHK_IX = 32'hF08 >> 2;

    generate
        if (NT != 4) begin : tb_check_nt
            TB_ERROR_tb_gw_alltoall_assumes_a_2x2_mesh u_err ();
        end
    endgenerate

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]    tile_trap;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire [NT*5*`NOC_E_W-1:0] rt_in_err;
    wire [NT*5-1:0]  rt_out_dead, rt_out_wd;
    wire [NT*8-1:0]  rt_drop_cnt;

    mesh_top #(.GW_EN(1), .GW_TILE(GW)) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt),
        // DMA side idle: alltoall only reads the gateway's CSRs
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

    initial begin
        $readmemh({SW_DIR, "alltoall.mem"}, dut.g_tile[0].g_ni.u_ni.mem);
        $readmemh({SW_DIR, "alltoall.mem"}, dut.g_tile[1].g_ni.u_ni.mem);
        $readmemh({SW_DIR, "alltoall.mem"}, dut.g_tile[2].g_ni.u_ni.mem);
    end

    wire [31:0] mark0 = dut.g_tile[0].g_ni.u_ni.mem[MARK_IX];
    wire [31:0] mark1 = dut.g_tile[1].g_ni.u_ni.mem[MARK_IX];
    wire [31:0] mark2 = dut.g_tile[2].g_ni.u_ni.mem[MARK_IX];
    wire all_done = (mark0 === 32'hC0DE) && (mark1 === 32'hC0DE) && (mark2 === 32'hC0DE);

    integer fails = 0;
    integer checks = 0;
    task check;
        input        cond;
        input [8*56-1:0] name;
        begin
            checks = checks + 1;
            if (cond) $display("PASS: %0s", name);
            else begin $display("FAIL: %0s", name); fails = fails + 1; end
        end
    endtask

    integer cyc;
    reg ok_err, ok_chk, ok_sw;

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        cyc = 0;
        while (!all_done && cyc < 400000) begin @(posedge clk); cyc = cyc + 1; end
        repeat (20) @(posedge clk);
        $display("      programs finished after %0d cycles", cyc);

        check(all_done, "all three cores completed (no hang)");
        ok_err = (dut.g_tile[0].g_ni.u_ni.mem[ERR_IX] === 0) &&
                 (dut.g_tile[1].g_ni.u_ni.mem[ERR_IX] === 0) &&
                 (dut.g_tile[2].g_ni.u_ni.mem[ERR_IX] === 0);
        check(ok_err, "no core reported an error");
        ok_chk = (dut.g_tile[0].g_ni.u_ni.mem[CHK_IX] === CHECKS) &&
                 (dut.g_tile[1].g_ni.u_ni.mem[CHK_IX] === CHECKS) &&
                 (dut.g_tile[2].g_ni.u_ni.mem[CHK_IX] === CHECKS);
        check(ok_chk, "each core ran 150 checks (gateway: 2, cores: 74 each)");
        ok_sw = (tile_sw[0*32 +: 32] === (32'h600D0000 | CHECKS)) &&
                (tile_sw[1*32 +: 32] === (32'h600D0000 | CHECKS)) &&
                (tile_sw[2*32 +: 32] === (32'h600D0000 | CHECKS));
        check(ok_sw, "status CSRs read 0x600D0096 (board pass LEDs)");
        check(tile_sw[GW*32 +: 32] === 32'b0, "gateway status CSR untouched");
        check(tile_trap === {NT{1'b0}}, "no core trapped");
        check(tile_err === {NT*5{1'b0}}, "no NI or gateway error flags");
        check(rt_in_err === {NT*5*`NOC_E_W{1'b0}}, "no router error flags");
        check(rt_drop_cnt === {NT*8{1'b0}}, "no router dropped anything");

        if (fails == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else            $display("TESTS FAILED (%0d of %0d)", fails, checks);
        $finish;
    end

endmodule
