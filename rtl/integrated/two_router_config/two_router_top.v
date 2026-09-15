`include "end_buff.v"
`include "/Users/hello.welcometothisdevice/CooK/rtl/router/noc_router.v"
`include "/Users/hello.welcometothisdevice/CooK/rtl/router/link_buffer.v"


//TODO: NEED TO ADD NETWORK INTERFACE HERE

module two_router_top #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32
) (
    input clk,
    input rst_n
);

    // Considering N <-> S router attachment for now

    // Connecting r00
    wire [4:0] to_r00_in_valid;
    wire [4:0] to_r00_in_ready;
    wire [9:0] to_r00_in_type;
    wire [5*DX_W-1:0] to_r00_in_dx;
    wire [5*DY_W-1:0] to_r00_in_dy;
    wire [5*DATA_W-1:0] to_r00_in_data;

    wire [4:0] from_r00_out_valid;
    wire [4:0] from_r00_out_ready;
    wire [9:0] from_r00_out_type;
    wire [5*DX_W-1:0] from_r00_out_dx;
    wire [5*DY_W-1:0] from_r00_out_dy;
    wire [5*DATA_W-1:0] from_r00_out_data;

    // End buffers attachment to r00


    // N router (r00)
    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(to_r00_in_valid), .in_ready(to_r00_in_ready), .in_type(to_r00_in_type),
        .in_dx(to_r00_in_dx), .in_dy(to_r00_in_dy), .in_data(to_r00_in_data),
        .out_valid(from_r00_out_valid), .out_ready(from_r00_out_ready), .out_type(from_r00_out_type),
        .out_dx(from_r00_out_dx), .out_dy(from_r00_out_dy), .out_data(from_r00_out_data)
    );

    // S->N LB
        link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r01_out_valid[1]), .in_ready(from_r01_out_ready[1]), .in_type(from_r01_out_type[3:2]),
        .in_dx(from_r01_out_dx[2*DX_W-1:DX_W]), .in_dy(from_r01_out_dy[2*DY_W-1:DY_W]), .in_data(from_r01_out_data[2*DATA_W-1:DATA_W]),
        .out_valid(to_r00_in_valid[1]), .out_ready(to_r00_in_ready[1]), .out_type(to_r00_in_type[3:2]),
        .out_dx(to_r00_in_dx[2*DX_W-1:DX_W]), .out_dy(to_r00_in_dy[2*DY_W-1:DY_W]), .out_data(to_r00_in_data[2*DATA_W-1:DATA_W])
    );


end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_n(
    .clk(clk),
    .rst_n(rst_n),
    .out_valid(to_r00_in_valid[0]),
    .out_ready(to_r00_in_ready[0]),
    .out_type(to_r00_in_type[1:0]),
    .out_dx(to_r01_in_dx[DX_W-1:0]),
    .out_dy(to_r01_in_dy[DY_W-1:0]),
    .out_data(to_r01_in_data[DATA_W-1:0])

);

end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_e(
    .clk(clk),
    .rst_n(rst_n),
    .out_valid(to_r00_in_valid[2]),
    .out_ready(to_r00_in_ready[2]),
    .out_type(to_r00_in_type[5:4]),
    .out_dx(to_r01_in_dx[3*DX_W-1:2*DX_W]),
    .out_dy(to_r01_in_dy[3*DY_W-1:2*DY_W]),
    .out_data(to_r01_in_data[3*DATA_W-1:2*DATA_W])

);

end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_w(
    .clk(clk),
    .rst_n(rst_n),
    .out_valid(to_r00_in_valid[3]),
    .out_ready(to_r00_in_ready[3]),
    .out_type(to_r00_in_type[7:6]),
    .out_dx(to_r01_in_dx[4*DX_W-1:3*DX_W]),
    .out_dy(to_r01_in_dy[4*DY_W-1:3*DY_W]),
    .out_data(to_r01_in_data[4*DATA_W-1:3*DATA_W])

);


    // Connecting r01

    wire [4:0] to_r01_in_valid;
    wire [4:0] to_r01_in_ready;
    wire [9:0] to_r01_in_type;
    wire [5*DX_W-1:0] to_r01_in_dx;
    wire [5*DY_W-1:0] to_r01_in_dy;
    wire [5*DATA_W-1:0] to_r01_in_data;

    wire [4:0] from_r01_out_valid;
    wire [4:0] from_r01_out_ready;
    wire [9:0] from_r01_out_type;
    wire [5*DX_W-1:0] from_r01_out_dx;
    wire [5*DY_W-1:0] from_r01_out_dy;
    wire [5*DATA_W-1:0] from_r01_out_data;

    // S router (r01)
    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(to_r01_in_valid), .in_ready(to_r01_in_ready), .in_type(to_r01_in_type),
        .in_dx(to_r01_in_dx), .in_dy(to_r01_in_dy), .in_data(to_r01_in_data),
        .out_valid(from_r01_out_valid), .out_ready(from_r01_out_ready), .out_type(from_r01_out_type),
        .out_dx(from_r01_out_dx), .out_dy(from_r01_out_dy), .out_data(from_r01_out_data)
    );

        // N->S LB
        link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(from_r00_out_valid[1]), .in_ready(from_r00_out_ready[1]), .in_type(from_r00_out_type[3:2]),
        .in_dx(from_r00_out_dx[2*DX_W-1:DX_W]), .in_dy(from_r00_out_dy[2*DY_W-1:DY_W]), .in_data(from_r00_out_data[2*DATA_W-1:DATA_W]),
        .out_valid(to_r01_in_valid[1]), .out_ready(to_r01_in_ready[1]), .out_type(to_r01_in_type[3:2]),
        .out_dx(to_r01_in_dx[2*DX_W-1:DX_W]), .out_dy(to_r01_in_dy[2*DY_W-1:DY_W]), .out_data(to_r01_in_data[2*DATA_W-1:DATA_W])
    );

    end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_S(
    .clk(clk),
    .rst_n(rst_n),
    .out_valid(to_r00_in_valid[1]),
    .out_ready(to_r00_in_ready[1]),
    .out_type(to_r00_in_type[3:2]),
    .out_dx(to_r01_in_dx[2*DX_W-1:DX_W]),
    .out_dy(to_r01_in_dy[2*DY_W-1:DY_W]),
    .out_data(to_r01_in_data[2*DATA_W-1:DATA_W])

);

end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_e(
    .clk(clk),
    .rst_n(rst_n),
    .out_valid(to_r00_in_valid[2]),
    .out_ready(to_r00_in_ready[2]),
    .out_type(to_r00_in_type[5:4]),
    .out_dx(to_r01_in_dx[3*DX_W-1:2*DX_W]),
    .out_dy(to_r01_in_dy[3*DY_W-1:2*DY_W]),
    .out_data(to_r01_in_data[3*DATA_W-1:2*DATA_W])

);

end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_eb_w(
    .clk(clk),
    .rst_n(rst_n),
    .out_valid(to_r00_in_valid[3]),
    .out_ready(to_r00_in_ready[3]),
    .out_type(to_r00_in_type[7:6]),
    .out_dx(to_r01_in_dx[4*DX_W-1:3*DX_W]),
    .out_dy(to_r01_in_dy[4*DY_W-1:3*DY_W]),
    .out_data(to_r01_in_data[4*DATA_W-1:3*DATA_W])

);

endmodule