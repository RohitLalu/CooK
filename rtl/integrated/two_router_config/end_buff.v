

module end_buff #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32,
    parameter ROUTER_CODE = 1,
    parameter TOTAL_ROUTERS = 4
) (
    input clk,
    input rst_n,
    output reg [$clog2(TOTAL_ROUTERS):0] out_router_code_flit,
    output reg  out_valid,
    output reg  out_ready,
    output reg [1:0] out_type,
    output reg [DX_W-1:0] out_dx,
    output reg [DY_W-1:0] out_dy,
    output reg [DATA_W-1:0] out_data

);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_router_code_flit <= 3'd7;
        out_valid <= 0;
        out_ready <= 0;
        out_type <= 0;
        out_dx <= 0;
        out_dy <= 0;
        out_data <= 0;
    end
    else begin
        out_router_code_flit <= 3'd1;
        out_valid <= 0;
        out_ready <= 0;
        out_type <= 2'bzz;
        out_dx <= 4'bzzzz;
        out_dy <= 4'bzzzz;
        out_data <= 32'hzzzzzzzz;
    end

end



endmodule