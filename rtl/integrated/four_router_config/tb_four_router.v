`timescale 1ns/1ps
module tb_two_router;
    localparam DX_W=4, DY_W=4, DATA_W=32;
    localparam N=0, S=1, E=2, W=3, L=4;
    localparam [1:0] HEADTAIL = 2'b10;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    two_router_top #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n)
    );

    integer errors = 0;

    initial begin
        rst_n = 0;
        // Drive R00's Local input to a known idle value before reset lifts
        force dut.to_r00_in_valid[L] = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // Inject at R00's Local port: dx=0, dy=+1 (needs one hop south).
        // Expect: R00 routes it out its South port, next_dy decrements
        // to 0, it crosses r00_to_r01 (the real link_buffer), and
        // arrives at R01's North input with dy now 0 and data intact.
        force dut.to_r00_in_valid[L]              = 1'b1;
        force dut.to_r00_in_type[2*L+1:2*L]        = HEADTAIL;
        force dut.to_r00_in_dx[(L+1)*DX_W-1:L*DX_W] = 4'sd0;
        force dut.to_r00_in_dy[(L+1)*DY_W-1:L*DY_W] = 4'sd1;
        force dut.to_r00_in_data[(L+1)*DATA_W-1:L*DATA_W] = 32'hCAFEF00D;
        #1;

        if (!dut.to_r00_in_ready[L]) begin
            $display("FAIL: R00 did not accept the injected flit at its Local port");
            errors = errors + 1;
        end else
            $display("PASS: R00 accepted the flit at its Local port (wants South)");

        @(posedge clk); #1;
        force dut.to_r00_in_valid[L] = 1'b0;

        // One cycle later, the link_buffer between r00 and r01 should be
        // presenting the flit at r01's North input.
        @(posedge clk); #1;

        if (dut.to_r01_in_valid[N] &&
            dut.to_r01_in_dx[(N+1)*DX_W-1:N*DX_W] === 4'sd0 &&
            dut.to_r01_in_dy[(N+1)*DY_W-1:N*DY_W] === 4'sd0 &&
            dut.to_r01_in_data[(N+1)*DATA_W-1:N*DATA_W] === 32'hCAFEF00D) begin
            $display("PASS: flit crossed the real link -- arrived at r01's North input, dy correctly decremented 1->0, data intact");
        end else begin
            $display("FAIL: flit did not correctly arrive at r01 North (valid=%b dx=%0d dy=%0d data=%h)",
                      dut.to_r01_in_valid[N],
                      dut.to_r01_in_dx[(N+1)*DX_W-1:N*DX_W],
                      dut.to_r01_in_dy[(N+1)*DY_W-1:N*DY_W],
                      dut.to_r01_in_data[(N+1)*DATA_W-1:N*DATA_W]);
            errors = errors + 1;
        end

        // Confirm r01 internally recognizes this as "destination reached"
        // (dx=0,dy=0 -> wants its own Local port), even though nothing
        // real is attached there yet to actually consume it.
        if (dut.r01.want_out[N] === L && dut.r01.want_valid[N] === 1'b1)
            $display("PASS: r01 correctly computes this flit now wants its own Local port (destination reached)");
        else begin
            $display("FAIL: r01 did not correctly recompute the route on arrival");
            errors = errors + 1;
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", 3);
        else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule