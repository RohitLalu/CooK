// sb_axil_info.v
// The memory node's registers in the AXI baseline (node 3): an AXI4-Lite
// slave that answers the same identity CSRs as a tile, so software written
// for the NoC finds it the same way. The DDR itself is a separate slave on
// the interconnect, at 0x8000_0000 (sb_top.v).
//   0x000 node ID   0x00C number of nodes   0x010 node kind = 2 (memory)
//   0x120 availability = {1, 0..., all nodes}: a bus has no BIST, so every
//         node is reported usable (alltoall.S reads this)
// Every other offset reads 0; writes are accepted and ignored.

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_axil_info #(
    parameter integer MY_ID = `NOC_NUM_TILES - 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [31:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready
);
    localparam integer NT = `NOC_NUM_TILES;
    localparam integer OB = `NOC_OFFSET_BITS;
    reg aw_got, w_got;
    assign s_axil_awready = !aw_got && !s_axil_bvalid;
    assign s_axil_wready  = !w_got  && !s_axil_bvalid;
    assign s_axil_arready = !s_axil_rvalid;

    wire [OB-1:0] off = s_axil_araddr[OB-1:0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got <= 1'b0; w_got <= 1'b0; s_axil_bvalid <= 1'b0;
            s_axil_rvalid <= 1'b0; s_axil_rdata <= 32'b0;
        end else begin
            if (s_axil_awvalid && s_axil_awready) aw_got <= 1'b1;
            if (s_axil_wvalid && s_axil_wready)   w_got  <= 1'b1;
            if (aw_got && w_got) begin aw_got <= 1'b0; w_got <= 1'b0; s_axil_bvalid <= 1'b1; end
            if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 1'b0;
            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rdata  <= (off == 'h000) ? MY_ID :
                                 (off == 'h00C) ? NT :
                                 (off == 'h010) ? 32'd2 :
                                 (off == 'h120) ? {1'b1, {(31-NT){1'b0}}, {NT{1'b1}}} : 32'b0;
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end
endmodule
