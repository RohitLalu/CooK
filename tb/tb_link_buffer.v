`timescale 1ns/1ps

module tb_link_buffer;

    localparam DX_W = 4, DY_W = 4, DATA_W = 8;

    reg clk = 0;
    reg rst_n = 0;

    reg              in_valid = 0;
    wire             in_ready;
    reg  [1:0]       in_type = 0;
    reg  signed [DX_W-1:0] in_dx = 0;
    reg  signed [DY_W-1:0] in_dy = 0;
    reg  [DATA_W-1:0] in_data = 0;

    wire             out_valid;
    reg              out_ready = 1;
    wire [1:0]       out_type;
    wire signed [DX_W-1:0] out_dx;
    wire signed [DY_W-1:0] out_dy;
    wire [DATA_W-1:0] out_data;

    integer errors = 0;
    integer tests  = 0;

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_type(in_type),
        .in_dx(in_dx), .in_dy(in_dy), .in_data(in_data),
        .out_valid(out_valid), .out_ready(out_ready), .out_type(out_type),
        .out_dx(out_dx), .out_dy(out_dy), .out_data(out_data)
    );

    always #5 clk = ~clk;

    task check;
        input cond;
        input [639:0] msg; // wide enough for the longer test descriptions below
        begin
            tests = tests + 1;
            if (cond) $display("PASS: %0s", msg);
            else begin
                $display("FAIL: %0s", msg);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (3) @(posedge clk);

        // ---- Reset behavior ----
        #1;
        check(out_valid === 1'b0, "out_valid is low immediately after reset");

        rst_n = 1;
        @(posedge clk); #1;

        // ---- Basic pass-through, downstream always ready ----
        out_ready = 1'b1;
        in_valid = 1'b1; in_type = 2'b01; in_dx = 2; in_dy = -1; in_data = 8'hAA;
        #1;
        check(in_ready === 1'b1, "empty buffer accepts immediately");
        @(posedge clk); #1;
        in_valid = 1'b0;
        check(out_valid === 1'b1 && out_data === 8'hAA && out_dx === 2 && out_dy === -1,
              "flit appears on output one cycle later, fields intact");
        @(posedge clk); #1;
        check(out_valid === 1'b0, "output empties once consumed and nothing new sent");

        // ---- Back-to-back full throughput: no bubble while downstream keeps up ----
        out_ready = 1'b1;
        in_valid = 1'b1; in_data = 8'h01;
        #1; check(in_ready, "back-to-back: accepts flit 1");
        @(posedge clk); #1;
        check(out_valid && out_data === 8'h01, "back-to-back: flit 1 appears");
        in_data = 8'h02; // send flit 2 immediately, same cycle flit 1 is being read out
        #1; check(in_ready, "back-to-back: still accepting while flit 1 is being consumed -- no bubble");
        @(posedge clk); #1;
        check(out_valid && out_data === 8'h02, "back-to-back: flit 2 appears next cycle, no gap");
        in_valid = 1'b0;
        @(posedge clk); #1;
        check(out_valid === 1'b0, "drains cleanly once input stops");

        // ---- Backpressure: downstream not ready, buffer must hold data intact ----
        out_ready = 1'b0;
        in_valid = 1'b1; in_data = 8'hBB; in_dx = -3; in_dy = 0;
        #1;
        check(in_ready === 1'b1, "empty buffer still accepts even though downstream isn't ready yet");
        @(posedge clk); #1;
        in_valid = 1'b0; // stop sending -- buffer is now full and downstream is stalled
        check(out_valid === 1'b1 && out_data === 8'hBB,
              "buffer holds the flit once downstream stalls");
        check(in_ready === 1'b0, "buffer correctly refuses new input while full and stalled");

        // Hold for a few more cycles under backpressure; data must not drift
        repeat (3) begin
            @(posedge clk); #1;
            check(out_data === 8'hBB && out_dx === -3 && out_dy === 0,
                  "held flit's fields stay exactly intact across multiple stalled cycles");
            check(in_ready === 1'b0, "still refusing new input every cycle downstream stays not-ready");
        end

        // Try to sneak a second flit in while stalled -- must be rejected, not silently accepted
        in_valid = 1'b1; in_data = 8'hCC;
        #1;
        check(in_ready === 1'b0, "attempted second flit while full+stalled is correctly rejected");
        @(posedge clk); #1;
        check(out_data === 8'hBB, "rejected flit did NOT overwrite the one already held");

        // Now release backpressure -- the held flit must be delivered, and
        // the rejected one (still being offered) accepted right after
        out_ready = 1'b1;
        #1;
        check(out_valid === 1'b1 && out_data === 8'hBB && in_ready === 1'b1,
              "downstream ready again: held flit delivered, buffer accepts the waiting one too");
        @(posedge clk); #1;
        in_valid = 1'b0;
        check(out_valid === 1'b1 && out_data === 8'hCC,
              "previously-rejected flit now correctly delivered, nothing lost or duplicated");
        @(posedge clk); #1;
        check(out_valid === 1'b0, "drains to empty cleanly");

        $display("----------------------------------------");
        $display("TOTAL: %0d tests, %0d errors", tests, errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end

endmodule