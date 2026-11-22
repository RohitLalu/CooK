// tb_coverage.v
// One fault of the BIST fault-coverage campaign (benchmarks/run_coverage.py
// compiles this once per fault). The fault is a compile-time parameter of
// noc_mesh, off by default and never in a bitstream:
//   SITE 0  none (a healthy run must flag nothing)
//   SITE 1  one wire of the flit entering link (TILE, PORT) stuck: bit BIT = VAL
//   SITE 2  that link's input valid stuck at VAL
//   SITE 3  that link's ready towards the sender stuck at VAL
//   SITE 4  one wire of router TILE's output PORT stuck: bit BIT = VAL
//   SITE 5  that router output's valid stuck at VAL
// BIST runs once and the result is printed:
//   COV <site> <tile> <port> <bit> <val> <hit> <false alarms>
// hit = the faulty link is in the dead-link mask (sites 1 to 3), or the
// faulty router's self-test failed (sites 4, 5). A false alarm is any other
// link or router flagged.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_coverage;

`include "noc_funcs.vh"

    parameter integer SITE = 0, TILE = 0, PORT = 0, BIT = 0;
    parameter [0:0]   VAL  = 1'b0;

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer FW = `NOC_FLIT_W;
    localparam integer LW = `NOC_LINKS_W;
    localparam LINK = (SITE >= 1 && SITE <= 3);
    localparam RTR  = (SITE >= 4);

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [NT*10-1:0] st, rts;
    wire             done;

    noc_mesh #(
        .LINK_FAULT_MASK(LINK ? ({{(4*NT-1){1'b0}}, 1'b1} << (TILE*4 + PORT)) : {4*NT{1'b0}}),
        .LINK_FAULT_MODE(SITE + 2), .LINK_FAULT_BIT(BIT), .LINK_FAULT_VAL(VAL),
        .RT_FAULT_TILE(RTR ? TILE : -1), .RT_FAULT_PORT(PORT),
        .RT_FAULT_BIT(SITE == 5 ? -1 : BIT), .RT_FAULT_VAL(VAL)
    ) u_m (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid({NT{1'b0}}), .loc_in_ready(), .loc_in_flit({NT*FW{1'b0}}),
        .loc_out_valid(), .loc_out_ready({NT{1'b1}}), .loc_out_room({NT{1'b1}}), .loc_out_flit(),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(),
        .fault_rt_mask({4*NT{1'b0}}), .fault_rt_flip(1'b0), .fault_router({NT{1'b0}}),
        .bist_status(st), .rt_status(rts), .bist_done(done)
    );

    wire [LW-1:0] mask0 = u_m.dead_links[LW-1:0];    // every router holds the same mask
    integer i, falses, n;
    reg hit;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        n = 0;
        while (!done && n < 5000) begin @(posedge clk); n = n + 1; end
        repeat (2) @(posedge clk);
        falses = 0; hit = 1'b0;
        if (!done) begin
            falses = 99;                                          // BIST never finished
        end else if (LINK) begin
            hit = mask0[noc_link_bit(TILE, PORT)];
            for (i = 0; i < LW; i = i + 1) if (i != noc_link_bit(TILE, PORT) && mask0[i]) falses = falses + 1;
            for (i = 0; i < NT; i = i + 1) if (rts[i*10 +: 10] != 0) falses = falses + 1;
        end else if (RTR) begin
            hit = (rts[TILE*10 +: 10] != 0);
            for (i = 0; i < NT; i = i + 1) if (i != TILE && rts[i*10 +: 10] != 0) falses = falses + 1;
        end else begin
            for (i = 0; i < LW; i = i + 1) if (mask0[i]) falses = falses + 1;
            for (i = 0; i < NT; i = i + 1) if (rts[i*10 +: 10] != 0) falses = falses + 1;
        end
        $display("COV %0d %0d %0d %0d %0d %0d %0d", SITE, TILE, PORT, BIT, VAL, hit, falses);
        $finish;
    end
endmodule
