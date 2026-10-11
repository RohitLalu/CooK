// end_buff.v
// Terminator for a mesh-edge port: stands in for the neighbour router that
// does not exist on that side.
//
// It plays BOTH halves of a neighbour, and the two halves are driven onto
// DIFFERENT router buses -- getting this wrong is what caused the earlier
// multi-driver bug, so it is spelled out here:
//
//   out_valid / out_type / out_dx / out_dy / out_data / out_router_code_flit
//       -> the router's  in_*[PORT]   bus   (a neighbour that never sends)
//   out_ready
//       -> the router's  out_ready[PORT] bit (a neighbour that absorbs)
//
//   out_ready must NOT be tied to the router's in_ready[PORT], which is a
//   router OUTPUT. That is two drivers on one net.
//
// MODE also makes this the fault-injection lever the roadmap asks for:
//   MODE_SINK (0)   healthy edge: silently absorbs anything routed at it.
//                   This is the default ON PURPOSE. A terminator that never
//                   asserts ready wedges the router's route-hold forever, and
//                   there is no timeout anywhere in the design to recover.
//   MODE_SILENT (1) broken link: never sends, never accepts. Use this to
//                   deliberately provoke the stall, not as the default.

module end_buff #(
    parameter DX_W          = 4,
    parameter DY_W          = 4,
    parameter DATA_W        = 32,
    parameter TOTAL_ROUTERS = 4,
    parameter MODE          = 0   // 0 = sink (healthy), 1 = silent (broken)
) (
    input  wire clk,
    input  wire rst_n,

    // -> router in_*[PORT]: this neighbour never transmits
    output wire [$clog2(TOTAL_ROUTERS):0] out_router_code_flit,
    output wire                           out_valid,
    output wire [1:0]                     out_type,
    output wire [DX_W-1:0]                out_dx,
    output wire [DY_W-1:0]                out_dy,
    output wire [DATA_W-1:0]              out_data,

    // -> router out_ready[PORT]: this neighbour absorbs (or refuses) traffic
    output wire                           out_ready
);

    localparam RC_W = $clog2(TOTAL_ROUTERS) + 1;

    // Constant 0, never z. Internal tri-state does not exist on the target
    // FPGA fabric; driving z here is a simulation/synthesis mismatch waiting
    // to happen, and comparisons against z behave differently in each.
    assign out_router_code_flit = {RC_W{1'b1}};   // "no valid source"
    assign out_valid            = 1'b0;
    assign out_type             = 2'b00;
    assign out_dx               = {DX_W{1'b0}};
    assign out_dy               = {DY_W{1'b0}};
    assign out_data             = {DATA_W{1'b0}};

    assign out_ready            = (MODE == 0) ? 1'b1 : 1'b0;

endmodule
