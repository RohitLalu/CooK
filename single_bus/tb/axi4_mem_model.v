// axi4_mem_model.v
// Behavioural AXI4 slave memory standing in for the DDR2 controller (MIG) in
// simulation. Single-beat transfers only, which is all sb_mem_ni issues.
// The index wraps modulo MEM_WORDS, so any DDR address lands somewhere.
// LAT = cycles between accepting an address and answering, to model a
// controller that is slower than the bus. An address at or above ERR_ADDR
// answers SLVERR.

`timescale 1ns/1ps

module axi4_mem_model #(
    parameter integer MEM_WORDS = 4096,
    parameter integer LAT       = 2,
    parameter [31:0]  ERR_ADDR  = 32'hFFFF_FFFF
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    output reg  [1:0]  s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire        s_arvalid,
    output wire        s_arready,
    output reg  [31:0] s_rdata,
    output reg  [1:0]  s_rresp,
    output wire        s_rlast,
    output reg         s_rvalid,
    input  wire        s_rready
);

    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;
    initial for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'b0;

    // write: take AW and W in either order, then answer after LAT cycles
    reg        aw_got, w_got;
    reg [31:0] aw_q, w_q;
    reg [3:0]  ws_q;
    integer    wcnt, rcnt;
    reg        r_busy;
    reg [31:0] ar_q;
    integer    protocol_errors = 0;

    assign s_awready = !aw_got && !s_bvalid;
    assign s_wready  = !w_got  && !s_bvalid;
    assign s_arready = !r_busy && !s_rvalid;
    assign s_rlast   = 1'b1;

    wire [31:0] widx = (aw_q >> 2) % MEM_WORDS;
    wire [31:0] ridx = (ar_q >> 2) % MEM_WORDS;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got <= 0; w_got <= 0; aw_q <= 0; w_q <= 0; ws_q <= 0; wcnt <= 0;
            s_bvalid <= 0; s_bresp <= 0;
            r_busy <= 0; ar_q <= 0; rcnt <= 0; s_rvalid <= 0; s_rdata <= 0; s_rresp <= 0;
        end else begin
            if (s_awvalid && s_awready) begin
                aw_got <= 1; aw_q <= s_awaddr;
                if (s_awlen != 0) protocol_errors = protocol_errors + 1;
            end
            if (s_wvalid && s_wready) begin
                w_got <= 1; w_q <= s_wdata; ws_q <= s_wstrb;
                if (!s_wlast) protocol_errors = protocol_errors + 1;
            end
            if (aw_got && w_got) begin
                if (wcnt >= LAT) begin
                    if (aw_q < ERR_ADDR) begin
                        if (ws_q[0]) mem[widx][ 7: 0] <= w_q[ 7: 0];
                        if (ws_q[1]) mem[widx][15: 8] <= w_q[15: 8];
                        if (ws_q[2]) mem[widx][23:16] <= w_q[23:16];
                        if (ws_q[3]) mem[widx][31:24] <= w_q[31:24];
                    end
                    s_bresp  <= (aw_q < ERR_ADDR) ? 2'b00 : 2'b10;
                    s_bvalid <= 1; aw_got <= 0; w_got <= 0; wcnt <= 0;
                end else wcnt <= wcnt + 1;
            end
            if (s_bvalid && s_bready) s_bvalid <= 0;

            if (s_arvalid && s_arready) begin
                r_busy <= 1; ar_q <= s_araddr; rcnt <= 0;
                if (s_arlen != 0) protocol_errors = protocol_errors + 1;
            end
            if (r_busy) begin
                if (rcnt >= LAT) begin
                    s_rdata  <= mem[ridx];
                    s_rresp  <= (ar_q < ERR_ADDR) ? 2'b00 : 2'b10;
                    s_rvalid <= 1; r_busy <= 0;
                end else rcnt <= rcnt + 1;
            end
            if (s_rvalid && s_rready) s_rvalid <= 0;
        end
    end

endmodule
