// tb_four_router.v
// End-to-end baremetal test of the 2x2 tile mesh.
//
// Tile 0's core executes a real rv32i program that does a remote load from
// tile 3's status register. The path exercised is:
//
//   tile0 core -> NI initiator -> r00 -E-> link_buffer -> r10 -S-> link_buffer
//     -> r11 -L-> tile3 NI responder -> back the other way -> tile0 core
//
// Tile 3's core is only spinning: the responder lives in hardware, so a status
// read is served whether or not the remote core is doing anything. That is the
// property the availability scheme depends on.

`timescale 1ns/1ps
`include "rtl/integrated/four_router_config/four_router_top.v"

module tb_four_router;

    localparam DX_W=4, DY_W=4, DATA_W=32;

    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] tile_trap;
    always #5 clk = ~clk;

    four_router_top #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n), .tile_trap(tile_trap)
    );

    integer errors = 0;
    integer i;
    integer cyc = 0;

    // offset 0x100 is the first memory word -> array index 64
    localparam TEXT_BASE = 64;
    localparam RESULT_IX = 12'h200 >> 2;   // 128
    localparam MARKER_IX = 12'h204 >> 2;   // 129

    initial begin
        // Zero every tile's memory so nothing fetches X, then load images.
        for (i = 0; i < 1024; i = i + 1) begin
            dut.r00_ni.mem[i] = 32'h0;
            dut.r10_ni.mem[i] = 32'h0;
            dut.r01_ni.mem[i] = 32'h0;
            dut.r11_ni.mem[i] = 32'h0;
        end
        $readmemh("sw/tile0.hex", dut.r00_ni.mem, TEXT_BASE, TEXT_BASE+63);
        $readmemh("sw/spin.hex",  dut.r10_ni.mem, TEXT_BASE, TEXT_BASE+63);
        $readmemh("sw/spin.hex",  dut.r01_ni.mem, TEXT_BASE, TEXT_BASE+63);
        $readmemh("sw/spin.hex",  dut.r11_ni.mem, TEXT_BASE, TEXT_BASE+63);

        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("reset released; tile0 running a remote load from tile 3");

        // Run until tile 0 writes its completion marker, or give up.
        while (cyc < 4000 && dut.r00_ni.mem[MARKER_IX] !== 32'h0000C0DE) begin
            @(posedge clk);
            cyc = cyc + 1;
            if (|tile_trap) begin
                $display("FAIL: a core trapped (tile_trap=%b) at cycle %0d", tile_trap, cyc);
                errors = errors + 1;
                cyc = 4000;
            end
        end

        $display("");
        if (dut.r00_ni.mem[MARKER_IX] !== 32'h0000C0DE) begin
            $display("FAIL: program never completed (no marker after %0d cycles)", cyc);
            $display("      tile0 err flags: timeout=%b illegal=%b",
                     dut.r00_ni.err_timeout, dut.r00_ni.err_illegal);
            errors = errors + 1;
        end else begin
            $display("PASS: tile0 program completed in %0d cycles", cyc);

            if (dut.r00_ni.mem[RESULT_IX] !== 32'd3) begin
                $display("FAIL: remote read of tile3 status returned %0d, expected 3",
                         dut.r00_ni.mem[RESULT_IX]);
                errors = errors + 1;
            end else
                $display("PASS: remote read tile0 -> tile3 status register returned %0d",
                         dut.r00_ni.mem[RESULT_IX]);

            if (dut.r00_ni.mem[12'h208 >> 2] !== 32'hDEAD_BEEF) begin
                $display("FAIL: out-of-window read returned %h, expected POISON DEADBEEF",
                         dut.r00_ni.mem[12'h208 >> 2]);
                errors = errors + 1;
            end else
                $display("PASS: out-of-window read returned POISON instead of hanging");

            if (dut.r00_ni.mem[12'h20C >> 2] !== 32'd2) begin
                $display("FAIL: error CSR read back %0d, expected 2 (illegal set, timeout clear)",
                         dut.r00_ni.mem[12'h20C >> 2]);
                errors = errors + 1;
            end else
                $display("PASS: error CSR reports illegal=1 timeout=0");

            if (dut.r00_ni.err_timeout !== 1'b0) begin
                $display("FAIL: timeout flag set on a healthy path");
                errors = errors + 1;
            end else
                $display("PASS: no timeout on a healthy path");

            if (|tile_trap) begin
                $display("FAIL: tile_trap=%b", tile_trap);
                errors = errors + 1;
            end else
                $display("PASS: no core trapped");
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TOTAL: %0d errors", errors);
        $finish;
    end
endmodule
