// tb_m3.v
// Metric M3 (README section 5): cores still usable after an injected fault.
//
// The board system in simulation: mesh_top with the gateway on tile 3 and
// real picorv32 cores on tiles 0..2, all running alltoall.mem, which reads
// the gateway's BIST bitmap and tests only the tiles marked available. The
// fault goes in through fault_rt_mask (what the board's switches drive), set
// before reset so the start-up BIST sees it. Cases:
//   healthy
//   every directed link (8), silent and bit-flip         -> 16 single faults
//   both links of tile 0 (tile 0 cut off)                 -> double fault
//   links 0-1 and 2-3 (the mesh splits in two)            -> double fault
// A core counts as usable when its status CSR reads pass with exactly the
// checks expected for the tiles marked available (74 per other core, 2 for
// the gateway). Every case must give the expected bitmap and usable count,
// and single faults must drop nothing (no route crosses a dead link).
// The bus baseline is 0 usable cores for every fault: one shared resource.
// Assumes the default 2x2 knobs.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_m3;

`ifdef XILINX_SIMULATOR
    parameter SW_DIR = "../../../../../sw/";
`else
    parameter SW_DIR = "sw/";
`endif

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer GW = NT - 1;
    localparam integer MARK_IX = 32'hF04 >> 2;   // alltoall.S completion marker
    localparam integer N = `NOC_P_N, S = `NOC_P_S, E = `NOC_P_E, W = `NOC_P_W;

    generate
        if (NT != 4) begin : tb_check_nt
            TB_ERROR_tb_m3_assumes_a_2x2_mesh u_err ();
        end
    endgenerate

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg  [4*NT-1:0]  fmask = 0;
    reg              fflip = 0;
    wire [NT-1:0]    tile_trap;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire [NT*8-1:0]  rt_drop_cnt;
    wire             sys_ready;
    wire [NT-1:0]    avail;

    mesh_top #(.GW_EN(1), .GW_TILE(GW)) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(rt_drop_cnt),
        .fault_rt_mask(fmask), .fault_rt_flip(fflip),
        .bist_status(), .sys_ready(sys_ready), .avail(avail), .gw_flags(), .gw_info(),
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

    integer fails = 0, checks = 0;
    integer n_single = 0, sum_single = 0, min_single = 99;

    function [4*NT-1:0] lnk;     // one directed link: leaving tile t in direction d
        input integer t, d;
        begin
            lnk = {{(4*NT-1){1'b0}}, 1'b1} << (t*4 + d);
        end
    endfunction

    // pass value a core's status CSR must show when the bitmap is av
    function [31:0] pass_word;
        input integer me;
        input [NT-1:0] av;
        integer t, n;
        begin
            n = 0;
            for (t = 0; t < NT; t = t + 1)
                if (t != me && av[t]) n = n + ((t == GW) ? 2 : 74);
            pass_word = 32'h600D0000 | n;
        end
    endfunction

    task run_case;
        input [4*NT-1:0] m;
        input            flip;
        input [NT-1:0]   exp_av;
        input integer    exp_use;
        input            single;
        input [8*28-1:0] name;
        integer cyc, t, nuse;
        reg ok;
        begin
            rst_n = 0;
            fmask = m;
            fflip = flip;
            dut.g_tile[0].g_ni.u_ni.mem[MARK_IX] = 0;
            dut.g_tile[1].g_ni.u_ni.mem[MARK_IX] = 0;
            dut.g_tile[2].g_ni.u_ni.mem[MARK_IX] = 0;
            repeat (5) @(posedge clk);
            rst_n = 1;
            cyc = 0;
            while (!all_done && cyc < 200000) begin @(posedge clk); cyc = cyc + 1; end
            repeat (20) @(posedge clk);

            nuse = 0;
            for (t = 0; t < GW; t = t + 1)
                if (tile_sw[t*32 +: 32] === pass_word(t, avail)) nuse = nuse + 1;
            ok = all_done && sys_ready && avail === exp_av && nuse == exp_use &&
                 tile_trap === {NT{1'b0}} && (!single || rt_drop_cnt === {NT*8{1'b0}});
            checks = checks + 1;
            if (!ok) fails = fails + 1;
            $display("%0s  %0s  avail %b  usable %0d/3  bus 0/3  (%0d cycles)",
                     ok ? "PASS:" : "FAIL:", name, avail, nuse, cyc);
            if (!ok)
                $display("       expected avail %b usable %0d; status %h %h %h, drops %h",
                         exp_av, exp_use, tile_sw[0 +: 32], tile_sw[32 +: 32], tile_sw[64 +: 32], rt_drop_cnt);
            if (single) begin
                n_single = n_single + 1;
                sum_single = sum_single + nuse;
                if (nuse < min_single) min_single = nuse;
            end
        end
    endtask

    integer md;
    initial begin
        run_case(0, 0, 4'b1111, 3, 0, "healthy");
        for (md = 0; md < 2; md = md + 1) begin
            run_case(lnk(0, E), md, 4'b1111, 3, 1, md ? "flip   0->E (link 0-1)" : "silent 0->E (link 0-1)");
            run_case(lnk(1, W), md, 4'b1111, 3, 1, md ? "flip   1->W (link 0-1)" : "silent 1->W (link 0-1)");
            run_case(lnk(0, S), md, 4'b1111, 3, 1, md ? "flip   0->S (link 0-2)" : "silent 0->S (link 0-2)");
            run_case(lnk(2, N), md, 4'b1111, 3, 1, md ? "flip   2->N (link 0-2)" : "silent 2->N (link 0-2)");
            run_case(lnk(1, S), md, 4'b1111, 3, 1, md ? "flip   1->S (link 1-3)" : "silent 1->S (link 1-3)");
            run_case(lnk(3, N), md, 4'b1111, 3, 1, md ? "flip   3->N (link 1-3)" : "silent 3->N (link 1-3)");
            run_case(lnk(2, E), md, 4'b1111, 3, 1, md ? "flip   2->E (link 2-3)" : "silent 2->E (link 2-3)");
            run_case(lnk(3, W), md, 4'b1111, 3, 1, md ? "flip   3->W (link 2-3)" : "silent 3->W (link 2-3)");
        end
        run_case(lnk(0, E) | lnk(0, S), 0, 4'b1110, 2, 0, "double: tile 0 cut off");
        run_case(lnk(0, E) | lnk(2, E), 0, 4'b1010, 1, 0, "double: mesh split 0-2 / 1-3");

        $display("M3 single link faults: %0d cases, usable cores min %0d / avg %0d.%0d of 3 (bus: 0 of 3)",
                 n_single, min_single, sum_single / n_single, (10 * sum_single / n_single) % 10);
        $display("----------------------------------------");
        if (fails == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else            $display("TOTAL: %0d of %0d checks failed", fails, checks);
        $finish;
    end

endmodule
