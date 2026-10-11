module address_decoder #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32,
    parameter ROUTER_CODE = 1,
    parameter TOTAL_ROUTERS = 4
) (
    input clk,
    input rst_n,

    input wire [$clog2(TOTAL_ROUTERS)-1:0] in_router_code_flit,
    input wire in_valid,
    output wire in_ready,
    input wire [1:0] in_type,
    input wire [DX_W-1:0] in_dx,
    input wire [DY_W-1:0] in_dy,
    input wire [DATA_W-1:0] in_data,

    output reg [$clog2(TOTAL_ROUTERS)-1:0] out_router_code_flit,
    output reg out_valid,
    input wire out_ready,
    output reg [1:0] out_type,
    output reg [DX_W-1:0] out_dx,
    output reg [DY_W-1:0] out_dy,
    output reg [DATA_W-1:0] out_data
);

//TODO: THE BELOW LOGIC IS WRONG

always@(*) begin
    if (in_valid && (in_router_code_flit == ROUTER_CODE)) begin
        out_router_code_flit = in_router_code_flit;
        out_valid = in_valid;
        out_type = in_type;
        out_dx = in_dx;
        out_dy = in_dy;
        out_data = in_data;
    end else begin
        out_router_code_flit = {($clog2(TOTAL_ROUTERS)){1'b1}};
        out_valid = 1'b0;
        out_type = 2'b00;
        out_dx = {DX_W{1'b0}};
        out_dy = {DY_W{1'b0}};
        out_data = {DATA_W{1'b0}};
    end
end