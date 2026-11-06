// tb_mesh_top.v
// End-to-end baremetal test of the generated mesh, real picorv32 cores.
//
// TEST = 0  healthy, with contention
//           tile 0 runs tile0.S (remote read of tile 3, out-of-window read,
//           error CSR read); tiles 1 and 2 run hammer.S at the same time, so
//           packets from several sources share outputs on the way to and from
//           tile 3. Works for any mesh with at least 4 tiles.
// TEST = 1  silent link fault on the link leaving tile 1 southward (2x2 only).
//           The start-up link BIST must localise it (router 1 outlink S and
//           router 3 inlink N fail), both ends must drop link 1-3, and tile
//           0's read of tile 3, whose X-Y path crosses it, must still return
//           the right value by the detour 0-2-3, with nothing dropped.
// TEST = 2  bit-flip fault on the same link (2x2 only): same localisation,
//           because the test vectors arrive corrupted and no pong is sent.
// TEST = 4  the same silent link, but it fails only AFTER the start-up BIST
//           (fault_rt_mask set as the cores start), so nothing routes around
//           it: tile 0's read of tile 3 comes back as POISON after the NI's
//           retries, with the timeout flag set -- no hang anywhere.
// TEST = 3  all-to-all self-check: every tile runs alltoall.S at once and
//           tests every other tile (byte lanes, read-after-write, walking
//           ones/zeros, remote instruction fetch). Any mesh size.
//
// Run with e.g.  iverilog -Ptb_mesh_top.TEST=1 ...

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_mesh_top;

    parameter integer TEST = 0;

    // Where the baremetal images live, relative to the simulator's run
    // directory. Icarus runs from the repo root (Makefile). Vivado's XSim runs
    // from cook_vivado/cook_vivado.sim/<simset>/behav/xsim, five levels down,
    // and predefines XILINX_SIMULATOR.
`ifdef XILINX_SIMULATOR
    parameter SW_DIR = "../../../../../sw/";
`else
    parameter SW_DIR = "sw/";
`endif

    localparam integer NT = `NOC_NUM_TILES;
    localparam [4*NT-1:0] FAULT_MASK = (TEST != 1 && TEST != 2) ? {4*NT{1'b0}} : ({{(4*NT-1){1'b0}}, 1'b1} << (1*4 + 1));
    localparam integer    FAULT_MODE = (TEST == 2) ? 2 : 1;

    generate
        if (NT < 4) begin : tb_check_nt
            TB_ERROR_mesh_test_needs_at_least_4_tiles u_err ();
        end
        if ((TEST == 1 || TEST == 2 || TEST == 4) && (`NOC_MESH_X != 2 || `NOC_MESH_Y != 2)) begin : tb_check_fault
            TB_ERROR_fault_tests_assume_a_2x2_mesh u_err ();
        end
    endgenerate

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]    tile_trap;
    wire [NT*5-1:0]  tile_err;
    wire [NT*32-1:0] tile_sw;
    wire [NT*10-1:0] bist_status;
    wire             sys_ready;

    // TEST 4: link tile1 -> south goes silent the moment the cores start
    reg [4*NT-1:0] fault_rt_mask = {4*NT{1'b0}};
    initial if (TEST == 4) begin
        @(posedge sys_ready);
        fault_rt_mask = {{(4*NT-1){1'b0}}, 1'b1} << (1*4 + 1);
    end


    mesh_top #(
        .LINK_FAULT_MASK(FAULT_MASK),
        .LINK_FAULT_MODE(FAULT_MODE)
    ) dut (
        .clk(clk), .rst_n(rst_n), .tile_trap(tile_trap), .tile_err(tile_err),
        .tile_sw(tile_sw),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(),
        .fault_rt_mask(fault_rt_mask), .fault_rt_flip(1'b0),
        .bist_status(bist_status), .sys_ready(sys_ready), .avail(),
        .gw_flags(), .gw_info()
    );

    // expected BIST status of a healthy mesh: every existing port passes
    reg  [NT*10-1:0] bist_healthy;
    integer bx, by;
    initial begin
        for (by = 0; by < `NOC_MESH_Y; by = by + 1)
            for (bx = 0; bx < `NOC_MESH_X; bx = bx + 1) begin
                // {L, W, E, S, N}, the same rule noc_mesh uses for PORT_EXISTS
                bist_healthy[(by*`NOC_MESH_X+bx)*10 +: 10] =
                    {2{1'b1, (bx > 0), (bx < `NOC_MESH_X-1), (by < `NOC_MESH_Y-1), (by > 0)}};
            end
    end

    localparam RESULT_IX = 12'h200 >> 2;
    localparam MARKER_IX = 12'h204 >> 2;
    localparam POISON_IX = 12'h208 >> 2;
    localparam ERRCSR_IX = 12'h20C >> 2;
    localparam SLOT_IX   = 12'h800 >> 2;     // hammer.S slots, in the remote write window
    // alltoall.S result block
    localparam A2A_ERR_IX    = 12'hF00 >> 2;
    localparam A2A_MARK_IX   = 12'hF04 >> 2;
    localparam A2A_CHECKS_IX = 12'hF08 >> 2;
    localparam A2A_PER_TILE  = 74;

    // ---- load images (full-memory .mem files from sw/build.sh) ----
    genvar gt;
    generate
        for (gt = 0; gt < NT; gt = gt + 1) begin : load
            initial begin
                if (TEST == 3)
                    $readmemh({SW_DIR, "alltoall.mem"}, dut.g_tile[gt].g_ni.u_ni.mem);
                else if (gt == 0)
                    $readmemh({SW_DIR, "tile0.mem"}, dut.g_tile[gt].g_ni.u_ni.mem);
                else if ((gt == 1 || gt == 2) && TEST == 0)
                    $readmemh({SW_DIR, "hammer.mem"}, dut.g_tile[gt].g_ni.u_ni.mem);
                else
                    $readmemh({SW_DIR, "spin.mem"}, dut.g_tile[gt].g_ni.u_ni.mem);
            end
            // per-tile alltoall.S results, flattened so the checker can loop
            assign a2a_mark[gt*32 +: 32] = dut.g_tile[gt].g_ni.u_ni.mem[A2A_MARK_IX];
            assign a2a_err [gt*32 +: 32] = dut.g_tile[gt].g_ni.u_ni.mem[A2A_ERR_IX];
            assign a2a_chk [gt*32 +: 32] = dut.g_tile[gt].g_ni.u_ni.mem[A2A_CHECKS_IX];
        end
    endgenerate

    wire [NT*32-1:0] a2a_mark, a2a_err, a2a_chk;
    integer ti;
    reg     a2a_done;
    always @(*) begin
        a2a_done = 1'b1;
        for (ti = 0; ti < NT; ti = ti + 1)
            if (a2a_mark[ti*32 +: 32] !== 32'h0000C0DE) a2a_done = 1'b0;
    end

    integer errors = 0;
    integer checks = 0;
    integer cyc = 0;
    integer limit = 200000;
    reg     done;

    task check;
        input cond;
        input [8*80-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s", msg);
            end else
                $display("PASS: %0s", msg);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("mesh %0dx%0d, TEST=%0d, flit width %0d bits", `NOC_MESH_X, `NOC_MESH_Y, TEST, `NOC_FLIT_W);

        done = 0;
        while (!done && cyc < limit) begin
            @(posedge clk);
            cyc = cyc + 1;
            done = (TEST == 3) ? a2a_done : (dut.g_tile[0].g_ni.u_ni.mem[MARKER_IX] === 32'h0000C0DE);
            if (TEST == 0)
                done = done && (dut.g_tile[1].g_ni.u_ni.mem[MARKER_IX] === 32'h0000C0DE)
                            && (dut.g_tile[2].g_ni.u_ni.mem[MARKER_IX] === 32'h0000C0DE);
            if (|tile_trap) begin
                $display("FAIL: a core trapped (tile_trap=%b) at cycle %0d", tile_trap, cyc);
                errors = errors + 1;
                cyc = limit;
            end
        end

        check(done, "all programs completed (no hang)");
        $display("      finished after %0d cycles", cyc);
        if (TEST != 3)
            check(dut.g_tile[0].g_ni.u_ni.mem[POISON_IX] === `NOC_POISON_DATA,
                  "out-of-window read returned POISON instead of hanging");

        if (TEST == 3) begin
            for (ti = 0; ti < NT; ti = ti + 1) begin
                checks = checks + 1;
                if (a2a_err[ti*32 +: 32] !== 0 ||
                    a2a_chk[ti*32 +: 32] !== A2A_PER_TILE*(NT-1) ||
                    tile_sw[ti*32 +: 32] !== (32'h600D0000 | A2A_PER_TILE*(NT-1))) begin
                    errors = errors + 1;
                    $display("FAIL: tile %0d: %0d errors, %0d checks, status %h",
                             ti, a2a_err[ti*32 +: 32], a2a_chk[ti*32 +: 32], tile_sw[ti*32 +: 32]);
                end
            end
            $display("%0s: every tile passed %0d checks against %0d other tiles",
                     (errors == 0) ? "PASS" : "FAIL", A2A_PER_TILE, NT-1);
            check(tile_err === {5*NT{1'b0}}, "no NI error flags on any tile");
            check(bist_status === bist_healthy, "link BIST passed every existing port");
            check(dut.u_mesh.rt_drop_cnt === {8*NT{1'b0}}, "no router dropped anything");
            check(dut.u_mesh.rt_out_dead === {5*NT{1'b0}}, "no output declared dead");
            check(dut.u_mesh.rt_in_err === {5*NT*`NOC_E_W{1'b0}}, "no router error flags");
        end else if (TEST == 0) begin
            check(dut.g_tile[0].g_ni.u_ni.mem[RESULT_IX] === 32'd3, "tile0 remote read of tile3 ID returned 3");
            check(dut.g_tile[0].g_ni.u_ni.mem[ERRCSR_IX] === 32'd2, "tile0 error CSR: illegal only");
            check(dut.g_tile[1].g_ni.u_ni.mem[RESULT_IX] === 32'd48, "tile1 hammer sum = 48");
            check(dut.g_tile[2].g_ni.u_ni.mem[RESULT_IX] === 32'd48, "tile2 hammer sum = 48");
            check(dut.g_tile[3].g_ni.u_ni.mem[SLOT_IX+1] === 32'd48, "tile1's posted writes landed in tile3");
            check(dut.g_tile[3].g_ni.u_ni.mem[SLOT_IX+2] === 32'd48, "tile2's posted writes landed in tile3");
            check(tile_err[0*5 +: 5] === 5'b00010, "tile0 NI flags: illegal only");
            check(tile_err[5*NT-1:5] === {5*(NT-1){1'b0}}, "no NI errors on other tiles");
            check(dut.u_mesh.rt_drop_cnt === {8*NT{1'b0}}, "no router dropped anything");
            check(dut.u_mesh.rt_out_dead === {5*NT{1'b0}}, "no output declared dead");
            check(dut.u_mesh.rt_in_err === {5*NT*`NOC_E_W{1'b0}}, "no router error flags");
            check(bist_status === bist_healthy, "link BIST passed every existing port");
        end else if (TEST == 4) begin
            check(bist_status === bist_healthy, "link BIST passed every port (the fault came later)");
            check(dut.g_tile[0].g_ni.u_ni.mem[RESULT_IX] === `NOC_POISON_DATA,
                  "read across the link that failed after BIST returned POISON");
            check(dut.g_tile[0].g_ni.u_ni.mem[ERRCSR_IX] === 32'd3, "tile0 error CSR: illegal and timeout");
            check(dut.u_mesh.rt_drop_cnt != {8*NT{1'b0}}, "router drop counter recorded the loss");
        end else begin
            check(dut.g_tile[0].g_ni.u_ni.mem[RESULT_IX] === 32'd3,
                  "read of tile3 whose X-Y path crosses the dead link: rerouted, returned 3");
            check(dut.g_tile[0].g_ni.u_ni.mem[ERRCSR_IX] === 32'd2, "tile0 error CSR: illegal only (no timeout)");
            check(bist_status[1*10 + `NOC_P_S] === 1'b0 && bist_status[3*10 + 5 + `NOC_P_N] === 1'b0,
                  "BIST localised the link: router 1 outlink S and router 3 inlink N failed");
            check(bist_status[0*10 +: 10] === bist_healthy[0*10 +: 10] &&
                  bist_status[2*10 +: 10] === bist_healthy[2*10 +: 10],
                  "routers 0 and 2 (not on that link) passed every port");
            check(dut.u_mesh.g_row[0].g_col[1].u_router.port_disable[`NOC_P_S] === 1'b1 &&
                  dut.u_mesh.g_row[1].g_col[1].u_router.port_disable[`NOC_P_N] === 1'b1,
                  "routers 1 and 3 both refuse to use the dead link");
            check(dut.u_mesh.rt_drop_cnt === {8*NT{1'b0}}, "nothing dropped: no route crosses the dead link");
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
