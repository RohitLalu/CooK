// reset_sync.v
// Asynchronous assert, synchronous de-assert reset.
//
// arst_n may drop at any time (button, clock not yet locked) and rst_n drops
// with it immediately. rst_n only rises STAGES clock edges after arst_n has
// risen, and always on a clock edge, so every flip-flop in the design leaves
// reset in the same cycle. Without this, a raw button released close to a
// clock edge can release half the design one cycle before the other half --
// the thesis's own reason for rejecting a raw global reset (README 6.10).

`timescale 1ns/1ps

module reset_sync #(
    parameter integer STAGES = 3
) (
    input  wire clk,
    input  wire arst_n,
    output wire rst_n
);

    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            sync <= {STAGES{1'b0}};
        else
            sync <= {sync[STAGES-2:0], 1'b1};
    end

    assign rst_n = sync[STAGES-1];

endmodule
