// tb_mesh_top.v
// End-to-end baremetal test of the generated mesh, real picorv32 cores.
//
// TEST = 0  healthy, with contention
//           tile 0 runs tile0.S (remote read of tile 3, out-of-window read,
//           error CSR read); tiles 1 and 2 run hammer.S at the same time, so
//           packets from several sources share outputs on the way to and from
//           tile 3. Works for any mesh with at least 4 tiles.
// TEST = 1  silent link fault on the link leaving tile 1 southward (2x2 only).
//           Tile 0's read of tile 3 must come back as POISON after the NI's
//           retries, with the timeout flag set, and router 1 must declare its
//           S output dead -- no hang anywhere.
// TEST = 2  bit-flip fault on the same link (2x2 only). Router 3 must flag a
//           check-bit error on its N input; tile 0 again gets POISON.
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
    localparam [4*NT-1:0] FAULT_MASK = (TEST == 0) ? {4*NT{1'b0}} : ({{(4*NT-1){1'b0}}, 1'b1} << (1*4 + 1));
    localparam integer    FAULT_MODE = (TEST == 2) ? 2 : 1;

    generate
        if (NT < 4) begin : tb_check_nt
            TB_ERROR_mesh_test_needs_at_least_4_tiles u_err ();
        end
        if (TEST != 0 && (`NOC_MESH_X != 2 || `NOC_MESH_Y != 2)) begin : tb_check_fault
            TB_ERROR_fault_tests_assume_a_2x2_mesh u_err ();
        end
    endgenerate

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]   tile_trap;
    wire [NT*5-1:0] tile_err;

    mesh_top #(
        .LINK_FAULT_MASK(FAULT_MASK),
        .LINK_FAULT_MODE(FAULT_MODE)
    ) dut (
        .clk(clk), .rst_n(rst_n), .tile_trap(tile_trap), .tile_err(tile_err)
    );

    // offset 0x100 is the first memory word -> array index 64
    localparam TEXT_BASE = 64;
    localparam RESULT_IX = 12'h200 >> 2;
    localparam MARKER_IX = 12'h204 >> 2;
    localparam POISON_IX = 12'h208 >> 2;
    localparam ERRCSR_IX = 12'h20C >> 2;
    localparam SLOT_IX   = 12'h300 >> 2;

    // ---- load images ----
    genvar gt;
    generate
        for (gt = 0; gt < NT; gt = gt + 1) begin : load
            integer w;
            initial begin
                for (w = 0; w < (1 << (`NOC_OFFSET_BITS - 2)); w = w + 1)
                    dut.g_tile[gt].u_ni.mem[w] = 32'h0;
                if (gt == 0)
                    $readmemh({SW_DIR, "tile0.hex"}, dut.g_tile[gt].u_ni.mem, TEXT_BASE, TEXT_BASE+63);
                else if ((gt == 1 || gt == 2) && TEST == 0)
                    $readmemh({SW_DIR, "hammer.hex"}, dut.g_tile[gt].u_ni.mem, TEXT_BASE, TEXT_BASE+63);
                else
                    $readmemh({SW_DIR, "spin.hex"}, dut.g_tile[gt].u_ni.mem, TEXT_BASE, TEXT_BASE+63);
            end
        end
    endgenerate

    integer errors = 0;
    integer checks = 0;
    integer cyc = 0;
    integer limit = 20000;
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
            done = (dut.g_tile[0].u_ni.mem[MARKER_IX] === 32'h0000C0DE);
            if (TEST == 0)
                done = done && (dut.g_tile[1].u_ni.mem[MARKER_IX] === 32'h0000C0DE)
                            && (dut.g_tile[2].u_ni.mem[MARKER_IX] === 32'h0000C0DE);
            if (|tile_trap) begin
                $display("FAIL: a core trapped (tile_trap=%b) at cycle %0d", tile_trap, cyc);
                errors = errors + 1;
                cyc = limit;
            end
        end

        check(done, "all programs completed (no hang)");
        $display("      finished after %0d cycles", cyc);
        check(dut.g_tile[0].u_ni.mem[POISON_IX] === `NOC_POISON_DATA,
              "out-of-window read returned POISON instead of hanging");

        if (TEST == 0) begin
            check(dut.g_tile[0].u_ni.mem[RESULT_IX] === 32'd3, "tile0 remote read of tile3 ID returned 3");
            check(dut.g_tile[0].u_ni.mem[ERRCSR_IX] === 32'd2, "tile0 error CSR: illegal only");
            check(dut.g_tile[1].u_ni.mem[RESULT_IX] === 32'd48, "tile1 hammer sum = 48");
            check(dut.g_tile[2].u_ni.mem[RESULT_IX] === 32'd48, "tile2 hammer sum = 48");
            check(dut.g_tile[3].u_ni.mem[SLOT_IX+1] === 32'd48, "tile1's posted writes landed in tile3");
            check(dut.g_tile[3].u_ni.mem[SLOT_IX+2] === 32'd48, "tile2's posted writes landed in tile3");
            check(tile_err[0*5 +: 5] === 5'b00010, "tile0 NI flags: illegal only");
            check(tile_err[5*NT-1:5] === {5*(NT-1){1'b0}}, "no NI errors on other tiles");
            check(dut.u_mesh.rt_drop_cnt === {8*NT{1'b0}}, "no router dropped anything");
            check(dut.u_mesh.rt_out_dead === {5*NT{1'b0}}, "no output declared dead");
            check(dut.u_mesh.rt_in_err === {5*NT*`NOC_E_W{1'b0}}, "no router error flags");
        end else begin
            check(dut.g_tile[0].u_ni.mem[RESULT_IX] === `NOC_POISON_DATA,
                  "read across the faulted link returned POISON");
            check(dut.g_tile[0].u_ni.mem[ERRCSR_IX] === 32'd3, "tile0 error CSR: illegal and timeout");
            if (TEST == 1)
                check(dut.u_mesh.rt_out_dead[1*5 + `NOC_P_S] === 1'b1,
                      "router 1 declared its S output dead");
            else
                check(dut.u_mesh.rt_in_err[(3*5 + `NOC_P_N)*`NOC_E_W + `NOC_E_CHK] === 1'b1,
                      "router 3 flagged a check-bit error on its N input");
            check(dut.u_mesh.rt_drop_cnt != {8*NT{1'b0}}, "router drop counter recorded the loss");
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
