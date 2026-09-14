`include ""
`include "/Users/hello.welcometothisdevice/CooK/rtl/router/noc_router.v"
`include "/Users/hello.welcometothisdevice/CooK/rtl/router/link_buffer.v"

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
    wire [1:0] lb_to_r00_in_valid;
    wire [1:0] lb_to_r00_in_ready;
    wire [3:0] lb_to_r00_in_type;
    wire [2*DX_W-1:0] lb_to_r00_in_dx;
    wire [2*DY_W-1:0] lb_to_r00_in_dy;
    wire [2*DATA_W-1:0] lb_to_r00_in_data;

    wire [1:0] r00_to_lb_out_valid;
    wire [1:0] r00_to_lb_out_ready;
    wire [3:0] r00_to_lb_out_type;
    wire [2*DX_W-1:0] r00_to_lb_out_dx;
    wire [2*DY_W-1:0] r00_to_lb_out_dy;
    wire [2*DATA_W-1:0] r00_to_lb_out_data;

    // N router (r00)
    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(lb_to_r00_in_valid), .in_ready(lb_to_r00_in_ready), .in_type(lb_to_r00_in_type),
        .in_dx(lb_to_r00_in_dx), .in_dy(lb_to_r00_in_dy), .in_data(lb_to_r00_in_data),
        .out_valid(r00_to_lb_out_valid), .out_ready(r00_to_lb_out_ready), .out_type(r00_to_lb_out_type),
        .out_dx(r00_to_lb_out_dx), .out_dy(r00_to_lb_out_dy), .out_data(r00_to_lb_out_data)
    );

    // S->N LB
        link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01_to_r00 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(r01_to_lb_out_valid), .in_ready(r01_to_lb_out_ready), .in_type(r01_to_lb_out_type),
        .in_dx(r01_to_lb_out_dx), .in_dy(r01_to_lb_out_dy), .in_data(r01_to_lb_out_data),
        .out_valid(lb_to_r00_in_valid), .out_ready(lb_to_r00_in_ready), .out_type(lb_to_r00_in_type),
        .out_dx(lb_to_r00_in_dx), .out_dy(lb_to_r00_in_dy), .out_data(lb_to_r00_in_data)
    );

        // N->S LB
        link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r00_to_r01 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(r00_to_lb_out_valid), .in_ready(r00_to_lb_out_ready), .in_type(r00_to_lb_out_type),
        .in_dx(r00_to_lb_out_dx), .in_dy(r00_to_lb_out_dy), .in_data(r00_to_lb_out_data),
        .out_valid(lb_to_r01_in_valid), .out_ready(lb_to_r01_in_ready), .out_type(lb_to_r01_in_type),
        .out_dx(lb_to_r01_in_dx), .out_dy(lb_to_r01_in_dy), .out_data(lb_to_r01_in_data)
    );


    // Connecting r01

    wire [1:0] lb_to_r01_in_valid;
    wire [1:0] lb_to_r01_in_ready;
    wire [3:0] lb_to_r01_in_type;
    wire [2*DX_W-1:0] lb_to_r01_in_dx;
    wire [2*DY_W-1:0] lb_to_r01_in_dy;
    wire [2*DATA_W-1:0] lb_to_r01_in_data;

    wire [1:0] r01_to_lb_out_valid;
    wire [1:0] r01_to_lb_out_ready;
    wire [3:0] r01_to_lb_out_type;
    wire [2*DX_W-1:0] r01_to_lb_out_dx;
    wire [2*DY_W-1:0] r01_to_lb_out_dy;
    wire [2*DATA_W-1:0] r01_to_lb_out_data;

    // S router (r01)
    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) r01 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(lb_to_r01_in_valid), .in_ready(lb_to_r01_in_ready), .in_type(lb_to_r01_in_type),
        .in_dx(lb_to_r01_in_dx), .in_dy(lb_to_r01_in_dy), .in_data(lb_to_r01_in_data),
        .out_valid(r01_to_lb_out_valid), .out_ready(r01_to_lb_out_ready), .out_type(r01_to_lb_out_type),
        .out_dx(r01_to_lb_out_dx), .out_dy(r01_to_lb_out_dy), .out_data(r01_to_lb_out_data)
    );

    always @(*) begin
        
    end

endmodule