// link_buffer.v
// Multi-flit FIFO on one unidirectional router-to-router link.
//
// WHAT IT DOES
//   * Stores up to DEPTH flits. This is the network's only flit storage
//     between routers: the router itself is a storage-free crossbar, so this
//     FIFO is logically the downstream router's input buffer, placed on the
//     wire instead of inside the router. That style is known as elastic-buffer
//     flow control (Michelogiannakis, Balfour, Dally, HPCA 2009).
//   * Applies backpressure: in_ready drops when the FIFO is full.
//
// WHY READY IS REGISTERED
//   in_ready and in_room depend ONLY on the occupancy register, never on
//   out_ready. The previous single-slot version computed
//   in_ready = !full || out_ready, which chained ready combinationally through
//   every router and link and formed a structural loop around the mesh ring.
//   With two or more slots, a registered ready still sustains one flit per
//   cycle, so nothing is lost by breaking that chain.
//
// WHY in_room EXISTS (whole-packet admission)
//   in_room is high when at least ROOM slots are free. The upstream router
//   admits a HEAD onto this link only when in_room is high, and then locks the
//   output to that packet until its TAIL. Because nothing else can write into
//   this FIFO while the lock is held, the rest of the packet is guaranteed to
//   fit. Two consequences the fault logic relies on:
//     1. A blocked packet ends up wholly inside one FIFO instead of being
//        smeared across several links (virtual cut-through behaviour).
//     2. In a healthy network, in_ready never drops while a packet is in
//        flight on this link. A locked output that sees ready low is
//        therefore a fault, not congestion -- see the router watchdog.
//
// FAULT (simulation fault injection; keep 0 for hardware)
//   0  healthy
//   1  silent link: never accepts, never delivers
//   2  bit-flip: inverts DATA bit 0 of every flit written, so the check bits
//      no longer match and the downstream router must catch it
//
// One instance covers ONE direction. A bidirectional link needs two.

`timescale 1ns/1ps
`include "noc_defs.vh"

module link_buffer #(
    parameter DEPTH = `NOC_LB_DEPTH,
    parameter ROOM  = `NOC_MAX_PKT_FLITS,
    parameter FAULT = 0
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // upstream (sending router) side
    input  wire                   in_valid,
    output wire                   in_ready,
    output wire                   in_room,
    input  wire [`NOC_FLIT_W-1:0] in_flit,

    // downstream (receiving router) side
    output wire                   out_valid,
    input  wire                   out_ready,
    output wire [`NOC_FLIT_W-1:0] out_flit
);

`include "noc_funcs.vh"

    localparam FW  = `NOC_FLIT_W;
    localparam PW  = `NOC_CLOG2_1(DEPTH);
    localparam CW  = $clog2(DEPTH + 1);

    generate
        if (DEPTH < 2) begin : lb_check_depth
            NOC_CONFIG_ERROR_link_buffer_depth_below_2 u_err ();
        end
        if (DEPTH < ROOM) begin : lb_check_room
            NOC_CONFIG_ERROR_link_buffer_cannot_hold_a_whole_packet u_err ();
        end
    endgenerate

    reg [FW-1:0] mem [0:DEPTH-1];
    reg [PW-1:0] wr_ptr, rd_ptr;
    reg [CW-1:0] count;

    wire full    = (count == DEPTH);
    wire empty   = (count == 0);

    wire rdy_int  = (FAULT == 1) ? 1'b0 : !full;
    wire room_int = (FAULT == 1) ? 1'b0 : ((DEPTH - count) >= ROOM);

    assign in_ready  = rdy_int;
    assign in_room   = room_int;
    assign out_valid = (FAULT == 1) ? 1'b0 : !empty;
    // Drive a defined value when empty so X never leaks into router decode.
    assign out_flit  = empty ? {FW{1'b0}} : mem[rd_ptr];

    wire push = in_valid && rdy_int;
    wire pop  = out_valid && out_ready;

    wire [FW-1:0] wr_flit = (FAULT == 2) ? (in_flit ^ {{(FW-1){1'b0}}, 1'b1}) : in_flit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {PW{1'b0}};
            rd_ptr <= {PW{1'b0}};
            count  <= {CW{1'b0}};
        end else begin
            if (push) begin
                mem[wr_ptr] <= wr_flit;
                wr_ptr      <= (wr_ptr == DEPTH-1) ? {PW{1'b0}} : wr_ptr + 1'b1;
            end
            if (pop)
                rd_ptr <= (rd_ptr == DEPTH-1) ? {PW{1'b0}} : rd_ptr + 1'b1;
            if (push && !pop)
                count <= count + 1'b1;
            else if (pop && !push)
                count <= count - 1'b1;
        end
    end

endmodule
