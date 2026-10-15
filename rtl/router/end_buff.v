// end_buff.v
// Terminator for a mesh-edge port: stands in for the neighbour router that
// does not exist on that side.
//
// It plays BOTH halves of a neighbour, and the two halves are driven onto
// DIFFERENT router buses -- getting this wrong is what caused the earlier
// multi-driver bug, so it is spelled out here:
//
//   out_valid / out_flit      -> the router's in_valid[PORT] / in_flit[PORT]
//                                (a neighbour that never sends)
//   out_ready / out_room      -> the router's out_ready[PORT] / out_room[PORT]
//                                (a neighbour that absorbs, or refuses)
//
//   out_ready must NOT be tied to the router's in_ready[PORT], which is a
//   router OUTPUT. That is two drivers on one net.
//
// The router is also told the port does not exist (PORT_EXISTS), so in a
// healthy design nothing is ever routed here; a HEAD aimed at a missing port
// is dropped inside the router and flagged. MODE only matters if that mask
// is wrong or deliberately overridden in a test:
//   MODE_SINK (0)   absorbs anything routed at it.
//   MODE_SILENT (1) never accepts. Use this to provoke a stall on purpose.
// Internal faulted links are injected with link_buffer's FAULT parameter.

`timescale 1ns/1ps
`include "noc_defs.vh"

module end_buff #(
    parameter MODE = 0   // 0 = sink (healthy), 1 = silent (broken)
) (
    // -> router in_*[PORT]: this neighbour never transmits
    output wire                   out_valid,
    output wire [`NOC_FLIT_W-1:0] out_flit,

    // -> router out_ready[PORT] / out_room[PORT]
    output wire                   out_ready,
    output wire                   out_room
);

    // Constant values, never z. Internal tri-states do not exist on the target
    // FPGA fabric; driving z here is a simulation/synthesis mismatch.
    assign out_valid = 1'b0;
    assign out_flit  = {`NOC_FLIT_W{1'b0}};
    assign out_ready = (MODE == 0) ? 1'b1 : 1'b0;
    assign out_room  = (MODE == 0) ? 1'b1 : 1'b0;

endmodule
