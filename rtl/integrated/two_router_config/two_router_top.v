// TODO: REMOVE THE INCLUDE LINES WHEN NOT RUNNING IN YOUR MACHINE. I AM HARDCODING PATH FOR MYSLEF

`include "/Users/hello.welcometothisdevice/CooK/rtl/router/noc_router.v"
`include "/Users/hello.welcometothisdevice/CooK/rtl/router/link_buffer.v"
`include "/Users/hello.welcometothisdevice/CooK/rtl/network_interface/ni.v"

// TODO: need to add BIST module later once the single tile seems to work fine
module two_router_top #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32
)(
    input clk,
    input rst_n
);

    localparam N = 0, S = 1, E = 2, W = 3, L = 4;

    // r00 
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

    // r01 
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


    // considering full toroidal structure for better understanding its working

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01_n_s (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r00_out_valid[S]), .in_ready(from_r00_out_ready[S]), .in_type(from_r00_out_type[2*S+1:2*S]),
        .in_dx(from_r00_out_dx[(S+1)*DX_W-1:S*DX_W]), .in_dy(from_r00_out_dy[(S+1)*DY_W-1:S*DY_W]), .in_data(from_r00_out_data[(S+1)*DATA_W-1:S*DATA_W]),
        .out_valid(to_r01_in_valid[S]), .out_ready(to_r01_in_ready[S]), .out_type(to_r01_in_type[2*S+1:2*S]),
        .out_dx(to_r01_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r01_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r01_in_data[(S+1)*DATA_W-1:S*DATA_W])
    );

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00_n_s (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r01_out_valid[N]), .in_ready(from_r01_out_ready[N]), .in_type(from_r01_out_type[2*N+1:2*N]),
        .in_dx(from_r01_out_dx[(N+1)*DX_W-1:N*DX_W]), .in_dy(from_r01_out_dy[(N+1)*DY_W-1:N*DY_W]), .in_data(from_r01_out_data[(N+1)*DATA_W-1:N*DATA_W]),
        .out_valid(to_r00_in_valid[N]), .out_ready(to_r00_in_ready[N]), .out_type(to_r00_in_type[2*N+1:2*N]),
        .out_dx(to_r00_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r00_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r00_in_data[(N+1)*DATA_W-1:N*DATA_W])
    );

        link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01_s_n (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r00_out_valid[N]), .in_ready(from_r00_out_ready[N]), .in_type(from_r00_out_type[2*N+1:2*N]),
        .in_dx(from_r00_out_dx[(N+1)*DX_W-1:N*DX_W]), .in_dy(from_r00_out_dy[(N+1)*DY_W-1:N*DY_W]), .in_data(from_r00_out_data[(N+1)*DATA_W-1:N*DATA_W]),
        .out_valid(to_r01_in_valid[N]), .out_ready(to_r01_in_ready[N]), .out_type(to_r01_in_type[2*N+1:2*N]),
        .out_dx(to_r01_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r01_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r01_in_data[(N+1)*DATA_W-1:N*DATA_W])
    );

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00_s_n (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r01_out_valid[S]), .in_ready(from_r01_out_ready[S]), .in_type(from_r01_out_type[2*S+1:2*S]),
        .in_dx(from_r01_out_dx[(S+1)*DX_W-1:S*DX_W]), .in_dy(from_r01_out_dy[(S+1)*DY_W-1:S*DY_W]), .in_data(from_r01_out_data[(S+1)*DATA_W-1:S*DATA_W]),
        .out_valid(to_r00_in_valid[S]), .out_ready(to_r00_in_ready[S]), .out_type(to_r00_in_type[2*S+1:2*S]),
        .out_dx(to_r00_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r00_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r00_in_data[(S+1)*DATA_W-1:S*DATA_W])
    );

        link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01_e_w (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r00_out_valid[W]), .in_ready(from_r00_out_ready[W]), .in_type(from_r00_out_type[2*W+1:2*W]),
        .in_dx(from_r00_out_dx[(W+1)*DX_W-1:W*DX_W]), .in_dy(from_r00_out_dy[(W+1)*DY_W-1:W*DY_W]), .in_data(from_r00_out_data[(W+1)*DATA_W-1:W*DATA_W]),
        .out_valid(to_r01_in_valid[W]), .out_ready(to_r01_in_ready[W]), .out_type(to_r01_in_type[2*W+1:2*W]),
        .out_dx(to_r01_in_dx[(W+1)*DX_W-1:W*DX_W]), .out_dy(to_r01_in_dy[(W+1)*DY_W-1:W*DY_W]), .out_data(to_r01_in_data[(W+1)*DATA_W-1:W*DATA_W])
    );


    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00_e_w (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r01_out_valid[E]), .in_ready(from_r01_out_ready[E]), .in_type(from_r01_out_type[2*E+1:2*E]),
        .in_dx(from_r01_out_dx[(E+1)*DX_W-1:E*DX_W]), .in_dy(from_r01_out_dy[(E+1)*DY_W-1:E*DY_W]), .in_data(from_r01_out_data[(E+1)*DATA_W-1:E*DATA_W]),
        .out_valid(to_r00_in_valid[E]), .out_ready(to_r00_in_ready[E]), .out_type(to_r00_in_type[2*E+1:2*E]),
        .out_dx(to_r00_in_dx[(E+1)*DX_W-1:E*DX_W]), .out_dy(to_r00_in_dy[(E+1)*DY_W-1:E*DY_W]), .out_data(to_r00_in_data[(E+1)*DATA_W-1:E*DATA_W])
    );


    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01_w_e (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r00_out_valid[E]), .in_ready(from_r00_out_ready[E]), .in_type(from_r00_out_type[2*E+1:2*E]),
        .in_dx(from_r00_out_dx[(E+1)*DX_W-1:E*DX_W]), .in_dy(from_r00_out_dy[(E+1)*DY_W-1:E*DY_W]), .in_data(from_r00_out_data[(E+1)*DATA_W-1:E*DATA_W]),
        .out_valid(to_r01_in_valid[E]), .out_ready(to_r01_in_ready[E]), .out_type(to_r01_in_type[2*E+1:2*E]),
        .out_dx(to_r01_in_dx[(E+1)*DX_W-1:E*DX_W]), .out_dy(to_r01_in_dy[(E+1)*DY_W-1:E*DY_W]), .out_data(to_r01_in_data[(E+1)*DATA_W-1:E*DATA_W])
    );

    link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00_w_e (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r01_out_valid[W]), .in_ready(from_r01_out_ready[W]), .in_type(from_r01_out_type[2*W+1:2*W]),
        .in_dx(from_r01_out_dx[(W+1)*DX_W-1:W*DX_W]), .in_dy(from_r01_out_dy[(W+1)*DY_W-1:W*DY_W]), .in_data(from_r01_out_data[(W+1)*DATA_W-1:W*DATA_W]),
        .out_valid(to_r00_in_valid[W]), .out_ready(to_r00_in_ready[W]), .out_type(to_r00_in_type[2*W+1:2*W]),
        .out_dx(to_r00_in_dx[(W+1)*DX_W-1:W*DX_W]), .out_dy(to_r00_in_dy[(W+1)*DY_W-1:W*DY_W]), .out_data(to_r00_in_data[(W+1)*DATA_W-1:W*DATA_W])
    );




endmodule