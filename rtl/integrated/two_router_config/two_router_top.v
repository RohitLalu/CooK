// `include "end_buff.v"
// `include "/Users/hello.welcometothisdevice/CooK/rtl/router/noc_router.v"
// `include "/Users/hello.welcometothisdevice/CooK/rtl/router/link_buffer.v"


// //TODO: NEED TO ADD NETWORK INTERFACE HERE

// module two_router_top #(
//     parameter DX_W   = 4,
//     parameter DY_W   = 4,
//     parameter DATA_W = 32
// ) (
//     input clk,
//     input rst_n
// );

//     // Considering N <-> S router attachment for now

//     // Connecting r00
//     wire [4:0] to_r00_in_valid;
//     wire [4:0] to_r00_in_ready;
//     wire [9:0] to_r00_in_type;
//     wire [5*DX_W-1:0] to_r00_in_dx;
//     wire [5*DY_W-1:0] to_r00_in_dy;
//     wire [5*DATA_W-1:0] to_r00_in_data;

//     wire [4:0] from_r00_out_valid;
//     wire [4:0] from_r00_out_ready;
//     wire [9:0] from_r00_out_type;
//     wire [5*DX_W-1:0] from_r00_out_dx;
//     wire [5*DY_W-1:0] from_r00_out_dy;
//     wire [5*DATA_W-1:0] from_r00_out_data;

//     // End buffers attachment to r00


//     // N router (r00)
//     noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00 (
//         .clk(clk), .rst_n(rst_n),
//         .in_valid(to_r00_in_valid), .in_ready(to_r00_in_ready), .in_type(to_r00_in_type),
//         .in_dx(to_r00_in_dx), .in_dy(to_r00_in_dy), .in_data(to_r00_in_data),
//         .out_valid(from_r00_out_valid), .out_ready(from_r00_out_ready), .out_type(from_r00_out_type),
//         .out_dx(from_r00_out_dx), .out_dy(from_r00_out_dy), .out_data(from_r00_out_data)
//     );

//     // S->N LB
//         link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00 (
//         .clk(clk), .rst_n(rst_n),
//         .in_valid(from_r01_out_valid[1]), .in_ready(from_r01_out_ready[1]), .in_type(from_r01_out_type[3:2]),
//         .in_dx(from_r01_out_dx[2*DX_W-1:DX_W]), .in_dy(from_r01_out_dy[2*DY_W-1:DY_W]), .in_data(from_r01_out_data[2*DATA_W-1:DATA_W]),
//         .out_valid(to_r00_in_valid[1]), .out_ready(to_r00_in_ready[1]), .out_type(to_r00_in_type[3:2]),
//         .out_dx(to_r00_in_dx[2*DX_W-1:DX_W]), .out_dy(to_r00_in_dy[2*DY_W-1:DY_W]), .out_data(to_r00_in_data[2*DATA_W-1:DATA_W])
//     );


// end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_n(
//     .clk(clk),
//     .rst_n(rst_n),
//     .out_valid(to_r00_in_valid[0]),
//     .out_ready(to_r00_in_ready[0]),
//     .out_type(to_r00_in_type[1:0]),
//     .out_dx(to_r01_in_dx[DX_W-1:0]),
//     .out_dy(to_r01_in_dy[DY_W-1:0]),
//     .out_data(to_r01_in_data[DATA_W-1:0])

// );

// end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_e(
//     .clk(clk),
//     .rst_n(rst_n),
//     .out_valid(to_r00_in_valid[2]),
//     .out_ready(to_r00_in_ready[2]),
//     .out_type(to_r00_in_type[5:4]),
//     .out_dx(to_r01_in_dx[3*DX_W-1:2*DX_W]),
//     .out_dy(to_r01_in_dy[3*DY_W-1:2*DY_W]),
//     .out_data(to_r01_in_data[3*DATA_W-1:2*DATA_W])

// );

// end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_w(
//     .clk(clk),
//     .rst_n(rst_n),
//     .out_valid(to_r00_in_valid[3]),
//     .out_ready(to_r00_in_ready[3]),
//     .out_type(to_r00_in_type[7:6]),
//     .out_dx(to_r01_in_dx[4*DX_W-1:3*DX_W]),
//     .out_dy(to_r01_in_dy[4*DY_W-1:3*DY_W]),
//     .out_data(to_r01_in_data[4*DATA_W-1:3*DATA_W])

// );


//     // Connecting r01

//     wire [4:0] to_r01_in_valid;
//     wire [4:0] to_r01_in_ready;
//     wire [9:0] to_r01_in_type;
//     wire [5*DX_W-1:0] to_r01_in_dx;
//     wire [5*DY_W-1:0] to_r01_in_dy;
//     wire [5*DATA_W-1:0] to_r01_in_data;

//     wire [4:0] from_r01_out_valid;
//     wire [4:0] from_r01_out_ready;
//     wire [9:0] from_r01_out_type;
//     wire [5*DX_W-1:0] from_r01_out_dx;
//     wire [5*DY_W-1:0] from_r01_out_dy;
//     wire [5*DATA_W-1:0] from_r01_out_data;

//     // S router (r01)
//     noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01 (
//         .clk(clk), .rst_n(rst_n),
//         .in_valid(to_r01_in_valid), .in_ready(to_r01_in_ready), .in_type(to_r01_in_type),
//         .in_dx(to_r01_in_dx), .in_dy(to_r01_in_dy), .in_data(to_r01_in_data),
//         .out_valid(from_r01_out_valid), .out_ready(from_r01_out_ready), .out_type(from_r01_out_type),
//         .out_dx(from_r01_out_dx), .out_dy(from_r01_out_dy), .out_data(from_r01_out_data)
//     );

//         // N->S LB
//         link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01 (
//         .clk(clk), .rst_n(rst_n),
//         .in_valid(from_r00_out_valid[1]), .in_ready(from_r00_out_ready[1]), .in_type(from_r00_out_type[3:2]),
//         .in_dx(from_r00_out_dx[2*DX_W-1:DX_W]), .in_dy(from_r00_out_dy[2*DY_W-1:DY_W]), .in_data(from_r00_out_data[2*DATA_W-1:DATA_W]),
//         .out_valid(to_r01_in_valid[1]), .out_ready(to_r01_in_ready[1]), .out_type(to_r01_in_type[3:2]),
//         .out_dx(to_r01_in_dx[2*DX_W-1:DX_W]), .out_dy(to_r01_in_dy[2*DY_W-1:DY_W]), .out_data(to_r01_in_data[2*DATA_W-1:DATA_W])
//     );

//     end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_S(
//     .clk(clk),
//     .rst_n(rst_n),
//     .out_valid(to_r00_in_valid[1]),
//     .out_ready(to_r00_in_ready[1]),
//     .out_type(to_r00_in_type[3:2]),
//     .out_dx(to_r01_in_dx[2*DX_W-1:DX_W]),
//     .out_dy(to_r01_in_dy[2*DY_W-1:DY_W]),
//     .out_data(to_r01_in_data[2*DATA_W-1:DATA_W])

// );

// end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_e(
//     .clk(clk),
//     .rst_n(rst_n),
//     .out_valid(to_r00_in_valid[2]),
//     .out_ready(to_r00_in_ready[2]),
//     .out_type(to_r00_in_type[5:4]),
//     .out_dx(to_r01_in_dx[3*DX_W-1:2*DX_W]),
//     .out_dy(to_r01_in_dy[3*DY_W-1:2*DY_W]),
//     .out_data(to_r01_in_data[3*DATA_W-1:2*DATA_W])

// );

// end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_w(
//     .clk(clk),
//     .rst_n(rst_n),
//     .out_valid(to_r00_in_valid[3]),
//     .out_ready(to_r00_in_ready[3]),
//     .out_type(to_r00_in_type[7:6]),
//     .out_dx(to_r01_in_dx[4*DX_W-1:3*DX_W]),
//     .out_dy(to_r01_in_dy[4*DY_W-1:3*DY_W]),
//     .out_data(to_r01_in_data[4*DATA_W-1:3*DATA_W])

// );

// endmodule

// two_router_top.v
// Two routers (r00, r01) connected by one real bidirectional link,
// every other port terminated by end_buff. This is the first point in
// the project where a flit actually crosses a real inter-router link,
// through a real link_buffer, rather than staying inside one router.
//
// NOTE ON THE LINK'S PORT INDEX -- a deliberate question, not a silent
// fix: this connects r00's index-1 port to r01's index-1 port (both
// "S" under the N=0,S=1,E=2,W=3,L=4 convention). In a real mesh, two
// adjacent routers connect via COMPLEMENTARY indices -- one router's S
// to the other's N -- not matching indices on both ends. If r00/r01
// are meant to represent a real north/south pair, this should likely
// be r00 index 1 (S) <-> r01 index 0 (N) instead. Left exactly as
// originally chosen here (index 1 on both ends) since it may be
// intentional for a first protocol smoke test where real geometry
// doesn't matter yet -- worth a deliberate yes/no, not something to
// change without knowing which was intended.
//
// No `include` directives here on purpose: this file must be compiled
// by passing noc_router.v, link_buffer.v, end_buff.v, and this file
// together as separate sources (see the accompanying cocotb Makefile).
// Self-including the same modules a build already lists explicitly is
// what caused the machine-specific path failure and the duplicate-
// instance-name errors in the version this replaces.

module two_router_top #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32
)(
    input clk,
    input rst_n
);

    localparam N = 0, S = 1, E = 2, W = 3, L = 4;

    // ---- r00 ----
    wire [4:0] to_r00_in_valid, to_r00_in_ready;
    wire [9:0] to_r00_in_type;
    wire [5*DX_W-1:0] to_r00_in_dx;
    wire [5*DY_W-1:0] to_r00_in_dy;
    wire [5*DATA_W-1:0] to_r00_in_data;

    wire [4:0] from_r00_out_valid, from_r00_out_ready;
    wire [9:0] from_r00_out_type;
    wire [5*DX_W-1:0] from_r00_out_dx;
    wire [5*DY_W-1:0] from_r00_out_dy;
    wire [5*DATA_W-1:0] from_r00_out_data;

    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(to_r00_in_valid), .in_ready(to_r00_in_ready), .in_type(to_r00_in_type),
        .in_dx(to_r00_in_dx), .in_dy(to_r00_in_dy), .in_data(to_r00_in_data),
        .out_valid(from_r00_out_valid), .out_ready(from_r00_out_ready), .out_type(from_r00_out_type),
        .out_dx(from_r00_out_dx), .out_dy(from_r00_out_dy), .out_data(from_r00_out_data)
    );

    // ---- r01 ----
    wire [4:0] to_r01_in_valid, to_r01_in_ready;
    wire [9:0] to_r01_in_type;
    wire [5*DX_W-1:0] to_r01_in_dx;
    wire [5*DY_W-1:0] to_r01_in_dy;
    wire [5*DATA_W-1:0] to_r01_in_data;

    wire [4:0] from_r01_out_valid, from_r01_out_ready;
    wire [9:0] from_r01_out_type;
    wire [5*DX_W-1:0] from_r01_out_dx;
    wire [5*DY_W-1:0] from_r01_out_dy;
    wire [5*DATA_W-1:0] from_r01_out_data;

    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(to_r01_in_valid), .in_ready(to_r01_in_ready), .in_type(to_r01_in_type),
        .in_dx(to_r01_in_dx), .in_dy(to_r01_in_dy), .in_data(to_r01_in_data),
        .out_valid(from_r01_out_valid), .out_ready(from_r01_out_ready), .out_type(from_r01_out_type),
        .out_dx(from_r01_out_dx), .out_dy(from_r01_out_dy), .out_data(from_r01_out_data)
    );

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r00_out_valid[S]), .in_ready(from_r00_out_ready[S]), .in_type(from_r00_out_type[2*S+1:2*S]),
        .in_dx(from_r00_out_dx[(S+1)*DX_W-1:S*DX_W]), .in_dy(from_r00_out_dy[(S+1)*DY_W-1:S*DY_W]), .in_data(from_r00_out_data[(S+1)*DATA_W-1:S*DATA_W]),
        .out_valid(to_r01_in_valid[S]), .out_ready(to_r01_in_ready[S]), .out_type(to_r01_in_type[2*S+1:2*S]),
        .out_dx(to_r01_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r01_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r01_in_data[(S+1)*DATA_W-1:S*DATA_W])
    );

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r01_out_valid[N]), .in_ready(from_r01_out_ready[N]), .in_type(from_r01_out_type[2*N+1:2*N]),
        .in_dx(from_r01_out_dx[(N+1)*DX_W-1:N*DX_W]), .in_dy(from_r01_out_dy[(N+1)*DY_W-1:N*DY_W]), .in_data(from_r01_out_data[(N+1)*DATA_W-1:N*DATA_W]),
        .out_valid(to_r00_in_valid[N]), .out_ready(to_r00_in_ready[N]), .out_type(to_r00_in_type[2*N+1:2*N]),
        .out_dx(to_r00_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r00_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r00_in_data[(N+1)*DATA_W-1:N*DATA_W])
    );

    // ---- Terminate every other port on both routers ----
    // A generate loop instead of hand-copied instances: this is exactly
    // the repetitive, direction-indexed wiring where copy-paste breaks
    // silently, which is what produced the duplicate instance names and
    // cross-wired dx/dy/data in the version this replaces. Skips index S
    // on each router since that's the one real link above.
    genvar g;
    generate
        for (g = 0; g < 5; g = g + 1) begin : term_r00
            if (g != S) begin : eb
                end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) u (
                    .clk(clk), .rst_n(rst_n),
                    .out_valid(to_r00_in_valid[g]),
                    .out_ready(from_r00_out_ready[g]),
                    .out_type(to_r00_in_type[2*g+1:2*g]),
                    .out_dx(to_r00_in_dx[(g+1)*DX_W-1:g*DX_W]),
                    .out_dy(to_r00_in_dy[(g+1)*DY_W-1:g*DY_W]),
                    .out_data(to_r00_in_data[(g+1)*DATA_W-1:g*DATA_W])
                );
            end
        end
        for (g = 0; g < 5; g = g + 1) begin : term_r01
            if (g != N) begin : eb
                end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) u (
                    .clk(clk), .rst_n(rst_n),
                    .out_valid(to_r01_in_valid[g]),
                    .out_ready(from_r01_out_ready[g]),
                    .out_type(to_r01_in_type[2*g+1:2*g]),
                    .out_dx(to_r01_in_dx[(g+1)*DX_W-1:g*DX_W]),
                    .out_dy(to_r01_in_dy[(g+1)*DY_W-1:g*DY_W]),
                    .out_data(to_r01_in_data[(g+1)*DATA_W-1:g*DATA_W])
                );
            end
        end
    endgenerate

endmodule