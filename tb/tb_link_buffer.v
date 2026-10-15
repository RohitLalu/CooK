// tb_link_buffer.v
// Directed + randomized test for the multi-flit link FIFO.
//   1. reset state
//   2. fill to DEPTH, ready drops exactly at full, room tracks free slots
//   3. ready/room are registered: toggling out_ready alone never changes them
//      in the same cycle
//   4. randomized valid/ready stalls: every flit delivered once, in order
//   5. sustained throughput of one flit per cycle when downstream is ready
//   6. FAULT=1 silent link, FAULT=2 bit-flip breaks the check bits

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_link_buffer;

`include "noc_funcs.vh"

    localparam FW    = `NOC_FLIT_W;
    localparam DEPTH = `NOC_LB_DEPTH;
    localparam ROOM  = `NOC_MAX_PKT_FLITS;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg           in_valid = 0;
    reg  [FW-1:0] in_flit  = 0;
    reg           out_ready = 0;
    wire          in_ready, in_room, out_valid;
    wire [FW-1:0] out_flit;

    link_buffer #(.DEPTH(DEPTH), .ROOM(ROOM), .FAULT(0)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_room(in_room), .in_flit(in_flit),
        .out_valid(out_valid), .out_ready(out_ready), .out_flit(out_flit)
    );

    // fault-mode instances share the stimulus
    wire f1_in_ready, f1_in_room, f1_out_valid; wire [FW-1:0] f1_out_flit;
    wire f2_in_ready, f2_in_room, f2_out_valid; wire [FW-1:0] f2_out_flit;
    link_buffer #(.DEPTH(DEPTH), .ROOM(ROOM), .FAULT(1)) dut_silent (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(f1_in_ready), .in_room(f1_in_room), .in_flit(in_flit),
        .out_valid(f1_out_valid), .out_ready(out_ready), .out_flit(f1_out_flit)
    );
    link_buffer #(.DEPTH(DEPTH), .ROOM(ROOM), .FAULT(2)) dut_flip (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(f2_in_ready), .in_room(f2_in_room), .in_flit(in_flit),
        .out_valid(f2_out_valid), .out_ready(out_ready), .out_flit(f2_out_flit)
    );

    integer errors = 0;
    integer checks = 0;
    integer i, sent, recv, cyc, seed;
    reg [FW-1:0] expect_q [0:255];

    task check;
        input cond;
        input [8*64-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    function [FW-1:0] flit_n;
        input integer n;
        begin
            flit_n = noc_make_flit(`NOC_T_HEADTAIL, 1'b0, n[`NOC_ID_W-1:0], {`NOC_X_W{1'b0}},
                                   {`NOC_Y_W{1'b0}}, 32'hA500_0000 + n);
        end
    endfunction

    initial begin
        seed = 7;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        $display("=== reset state ===");
        check(!out_valid, "out_valid low after reset");
        check(in_ready,   "in_ready high after reset");
        check(in_room,    "in_room high after reset");

        $display("=== fill to DEPTH=%0d with downstream stalled ===", DEPTH);
        out_ready = 0;
        for (i = 0; i < DEPTH; i = i + 1) begin
            check(in_ready, "in_ready high while not full");
            check(in_room == ((DEPTH - i) >= ROOM), "in_room matches free slots");
            in_valid = 1; in_flit = flit_n(i);
            @(posedge clk); #1;
        end
        in_valid = 0;
        @(negedge clk);
        check(!in_ready, "in_ready low exactly at full");
        check(!in_room,  "in_room low at full");
        check(out_valid && out_flit == flit_n(0), "head of FIFO is the first flit");

        $display("=== ready is registered: out_ready alone does not raise it ===");
        out_ready = 1; #1;
        check(!in_ready, "in_ready stays low in the same cycle out_ready rises");
        @(posedge clk); #1;
        out_ready = 0;
        check(in_ready, "in_ready rises one cycle after a pop");
        // drain
        out_ready = 1;
        while (out_valid) @(posedge clk);
        #1; out_ready = 0;

        $display("=== randomized stalls: no loss, no duplication, in order ===");
        sent = 0; recv = 0; cyc = 0;
        for (i = 0; i < 200; i = i + 1) expect_q[i] = flit_n(i + 16);
        while (recv < 200 && cyc < 5000) begin
            @(negedge clk);
            in_valid  = (sent < 200) && ($random(seed) & 1);
            in_flit   = expect_q[sent];
            out_ready = ($random(seed) % 3) != 0;
            @(posedge clk);
            if (out_valid && out_ready) begin
                checks = checks + 1;
                if (out_flit !== expect_q[recv]) begin
                    errors = errors + 1;
                    $display("FAIL: flit %0d out of order or corrupted", recv);
                end
                recv = recv + 1;
            end
            if (in_valid && in_ready) sent = sent + 1;
            cyc = cyc + 1;
        end
        check(recv == 200, "all 200 flits delivered");
        @(negedge clk); in_valid = 0; out_ready = 1;
        @(posedge clk); #1;
        check(!out_valid, "nothing extra left behind");

        $display("=== full throughput with downstream always ready ===");
        sent = 0; recv = 0;
        out_ready = 1;
        for (i = 0; i < 20; i = i + 1) begin
            @(negedge clk);
            in_valid = 1; in_flit = flit_n(i);
            @(posedge clk);
            if (in_ready) sent = sent + 1;
            if (out_valid) recv = recv + 1;
        end
        @(negedge clk); in_valid = 0;
        check(sent == 20, "accepted one flit every cycle");
        check(recv == 19, "delivered one flit every cycle after one cycle of latency");
        repeat (3) @(posedge clk);

        $display("=== FAULT=1 silent link ===");
        check(!f1_in_ready && !f1_in_room && !f1_out_valid, "silent link never ready, never valid");

        $display("=== FAULT=2 bit-flip ===");
        @(negedge clk);
        out_ready = 0;
        in_valid = 1; in_flit = flit_n(99);
        @(posedge clk); #1;
        in_valid = 0;
        check(f2_out_valid, "bit-flip link still delivers");
        check(noc_chk_ok(in_flit), "sent flit has valid check bits");
        check(!noc_chk_ok(f2_out_flit), "delivered flit fails the check");
        check(noc_chk_ok(out_flit) || !out_valid, "healthy link output passes the check");

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
