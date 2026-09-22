// link_buffer.v
// One-flit elastic register on a single (unidirectional) link.
// Breaks the combinational chain that would otherwise run straight
// through the router's crossbar into the next router's arbiter and out
// the far side -- without this, backpressure and routing decisions
// would need to settle across an unbounded number of hops within one
// clock cycle, which will not close timing beyond a trivial mesh size.
//
// This is deliberately NOT a multi-entry FIFO. A full FIFO solves a
// different problem (absorbing sustained bursts faster than the
// consumer drains them), which doesn't exist at this project's scale.
// A single elastic register solves the actual problem (breaking the
// combinational path) at full throughput: it never stalls unnecessarily
// as long as the downstream keeps consuming, and it never drops or
// duplicates a flit when the downstream stalls.
//
// One instance covers ONE direction of a link. A real bidirectional
// router-to-router link needs two instances, one each way -- same as
// the router's own ports already assume separate in_* and out_* buses
// per direction.

`timescale 1ns/1ps

module link_buffer #(
    parameter DX_W = 4,
    parameter DY_W = 4,
    parameter DATA_W = 32,
    parameter TOTAL_ROUTERS = 4

)(
    input  wire clk,
    input  wire rst_n,

    // Upstream (sender) side
    input wire [$clog2(TOTAL_ROUTERS):0] in_router_code_flit,
    input  wire in_valid,
    output wire in_ready,
    input  wire [1:0] in_type,
    input  wire signed [DX_W-1:0] in_dx,
    input  wire signed [DY_W-1:0] in_dy,
    input  wire [DATA_W-1:0] in_data,

    // Downstream (receiver) side
    output wire [$clog2(TOTAL_ROUTERS):0] out_router_code_flit,
    output wire out_valid,
    input  wire out_ready,
    output wire [1:0] out_type,
    output wire signed [DX_W-1:0] out_dx,
    output wire signed [DY_W-1:0] out_dy,
    output wire [DATA_W-1:0] out_data
);
    reg [$clog2(TOTAL_ROUTERS):0] out_router_code_flit_reg;
    reg out_valid_reg;
    reg [1:0] out_type_reg;
    reg signed [DX_W-1:0] out_dx_reg;
    reg signed [DY_W-1:0] out_dy_reg;
    reg [DATA_W-1:0] out_data_reg;

    // Accept a new flit if the register is empty, OR if the downstream
    // is consuming the one currently held (freeing it up this same cycle).
    assign in_ready = (!out_valid_reg) || out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_router_code_flit_reg <=$clog2(TOTAL_ROUTERS){1'b1};
            out_valid_reg <= 1'b0;
            out_type_reg  <= 2'b00;
            out_dx_reg    <= {DX_W{1'b0}};
            out_dy_reg    <= {DY_W{1'b0}};
            out_data_reg  <= {DATA_W{1'b0}};
        end else if (in_ready) begin
            out_valid_reg <= in_valid;
            if (in_valid) begin
                out_router_code_flit_reg <= in_router_code_flit;
                out_type_reg <= in_type;
                out_dx_reg   <= in_dx;
                out_dy_reg   <= in_dy;
                out_data_reg <= in_data;
            end
        end
        // else: in_ready is low (register full and downstream not
        // consuming) -- hold current contents unchanged.
    end
    assign out_router_code_flit = out_router_code_flit_reg;
    assign out_valid = out_valid_reg;
    assign out_type  = out_type_reg;
    assign out_dx    = out_dx_reg;
    assign out_dy    = out_dy_reg;
    assign out_data  = out_data_reg;

endmodule