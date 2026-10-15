// status_panel.v
// Turns the mesh's status signals into something readable on a dev board:
// two slow blink codes, per-tile flags and an 8-digit hex display value.
//
// It only OBSERVES. It never drives or clears anything in the mesh, so it
// can sit beside the BIST module (which will read the same signals) without
// interfering.
//
// ERROR CODES, highest priority first. The panel reports the highest-priority
// code present on any tile, and the lowest tile that has it.
//    1  core trapped                         (tile_trap)
//    2  NI timeout: retries exhausted        (NI flag bit 0)
//    3  NI check-bit error                   (NI flag bit 4)
//    4  NI poison TAIL received              (NI flag bit 2)
//    5  NI stale response discarded          (NI flag bit 3)
//    6  router output declared dead          (that tile's router)
//    7  router watchdog fired                (that tile's router)
//    8  router input error: check/orphan/route/protocol
//    9  software reported failure            (status CSR upper half = 0xFA11)
//   10  NI illegal address                   (NI flag bit 1)
// Illegal address is last on purpose: tile0.S triggers it deliberately to
// prove the decoder poisons instead of hanging.
//
// BLINK CODES (slow, readable by eye)
//   code_led blinks CODE times, tile_led blinks TILE+1 times, both in the same
//   frame: one blink = UNIT on + UNIT off, then a gap of GAP_UNITS dark units.
//   Both stay dark when nothing is wrong. With UNIT = 0.25 s, code 6 on tile 2
//   is six blinks on one LED and three on the other, then a 1.5 s pause.
//
// DISPLAY VALUE (8 hex digits, left to right)
//   [31:28] code   [27:20] tile   [19:16] 0   [15:0] that tile's status CSR
//   low half (tile 0 when nothing is wrong). For alltoall.S a passing tile
//   shows its check count there.
//
// SOFTWARE STATUS CONVENTION (CSR 0x008, upper half)
//   0x600D pass, 0xFA11 fail, anything else = still running.

`timescale 1ns/1ps
`include "noc_defs.vh"

module status_panel #(
    parameter integer UNIT_CYCLES   = 12_500_000,   // 0.25 s at 50 MHz
    parameter integer GAP_UNITS     = 6,
    parameter integer HEART_CYCLES  = 25_000_000    // heartbeat half period
) (
    input  wire clk,
    input  wire rst_n,

    input  wire [`NOC_NUM_TILES-1:0]            tile_trap,
    input  wire [`NOC_NUM_TILES*5-1:0]          tile_err,
    input  wire [`NOC_NUM_TILES*32-1:0]         tile_sw,
    input  wire [`NOC_NUM_TILES*5*`NOC_E_W-1:0] rt_in_err,
    input  wire [`NOC_NUM_TILES*5-1:0]          rt_out_dead,
    input  wire [`NOC_NUM_TILES*5-1:0]          rt_out_wd,

    output reg                                  code_led,
    output reg                                  tile_led,
    output reg                                  heartbeat,
    output wire [`NOC_NUM_TILES-1:0]            tile_bad,    // any error on this tile
    output wire [`NOC_NUM_TILES-1:0]            tile_pass,   // software says pass
    output wire [`NOC_NUM_TILES-1:0]            tile_fail,   // software says fail
    output wire [31:0]                          display,
    output wire [3:0]                           cur_code,
    output wire [7:0]                           cur_tile
);

    localparam integer NT    = `NOC_NUM_TILES;
    localparam integer NCODE = 10;
    localparam integer EW    = 5 * `NOC_E_W;

    // ---------------------------------------------------------------
    // per-tile, per-code event matrix: ev[c*NT + t], c = code-1
    // ---------------------------------------------------------------
    wire [NCODE*NT-1:0] ev;
    genvar t;
    generate
        for (t = 0; t < NT; t = t + 1) begin : g_ev
            wire [15:0] sw_hi = tile_sw[t*32+16 +: 16];
            assign ev[0*NT + t] = tile_trap[t];
            assign ev[1*NT + t] = tile_err[t*5 + 0];
            assign ev[2*NT + t] = tile_err[t*5 + 4];
            assign ev[3*NT + t] = tile_err[t*5 + 2];
            assign ev[4*NT + t] = tile_err[t*5 + 3];
            assign ev[5*NT + t] = |rt_out_dead[t*5 +: 5];
            assign ev[6*NT + t] = |rt_out_wd[t*5 +: 5];
            assign ev[7*NT + t] = |rt_in_err[t*EW +: EW];
            assign ev[8*NT + t] = (sw_hi == 16'hFA11);
            assign ev[9*NT + t] = tile_err[t*5 + 1];

            assign tile_pass[t] = (sw_hi == 16'h600D);
            assign tile_fail[t] = (sw_hi == 16'hFA11);
            assign tile_bad[t]  = ev[0*NT+t] | ev[1*NT+t] | ev[2*NT+t] | ev[3*NT+t] | ev[4*NT+t] |
                                  ev[5*NT+t] | ev[6*NT+t] | ev[7*NT+t] | ev[8*NT+t] | ev[9*NT+t];
        end
    endgenerate

    // highest-priority code, lowest tile
    reg [3:0] sel_code;
    reg [7:0] sel_tile;
    reg       sel_found;
    integer   ci, ti;
    always @(*) begin
        sel_found = 1'b0;
        sel_code  = 4'd0;
        sel_tile  = 8'd0;
        for (ci = 0; ci < NCODE; ci = ci + 1)
            for (ti = 0; ti < NT; ti = ti + 1)
                if (!sel_found && ev[ci*NT + ti]) begin
                    sel_found = 1'b1;
                    sel_code  = ci + 1;
                    sel_tile  = ti;
                end
    end

    // ---------------------------------------------------------------
    // blink engine: the reported code/tile only change at a frame start,
    // so a sequence is never cut halfway
    // ---------------------------------------------------------------
    localparam integer UW = $clog2(UNIT_CYCLES + 1);
    localparam integer HW = $clog2(HEART_CYCLES + 1);

    reg [UW-1:0] unit_cnt;
    reg [7:0]    unit_idx;      // unit number inside the frame
    reg [7:0]    frame_len;
    reg [3:0]    f_code;
    reg [7:0]    f_tile;
    reg [HW-1:0] heart_cnt;

    wire [8:0] code_blinks = f_code;
    wire [8:0] tile_blinks = (f_code == 0) ? 9'd0 : f_tile + 9'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            unit_cnt  <= {UW{1'b0}};
            unit_idx  <= 8'd0;
            frame_len <= GAP_UNITS;
            f_code    <= 4'd0;
            f_tile    <= 8'd0;
            code_led  <= 1'b0;
            tile_led  <= 1'b0;
            heart_cnt <= {HW{1'b0}};
            heartbeat <= 1'b0;
        end else begin
            if (heart_cnt == HEART_CYCLES - 1) begin
                heart_cnt <= {HW{1'b0}};
                heartbeat <= ~heartbeat;
            end else begin
                heart_cnt <= heart_cnt + 1'b1;
            end

            if (unit_cnt == UNIT_CYCLES - 1) begin
                unit_cnt <= {UW{1'b0}};
                if (unit_idx + 1 >= frame_len) begin
                    // new frame: latch what to show for its whole length
                    unit_idx  <= 8'd0;
                    f_code    <= sel_code;
                    f_tile    <= sel_tile;
                    frame_len <= 2 * (((sel_code > sel_tile + 1) ? sel_code : sel_tile + 1)) + GAP_UNITS;
                end else begin
                    unit_idx <= unit_idx + 1'b1;
                end
            end else begin
                unit_cnt <= unit_cnt + 1'b1;
            end

            code_led <= (unit_idx[0] == 1'b0) && ({1'b0, unit_idx} < 2 * code_blinks);
            tile_led <= (unit_idx[0] == 1'b0) && ({1'b0, unit_idx} < 2 * tile_blinks);
        end
    end

    // ---------------------------------------------------------------
    // display value (live, not frame-latched)
    // ---------------------------------------------------------------
    wire [15:0] sel_sw_lo = tile_sw[sel_tile*32 +: 16];
    assign display  = {sel_code, sel_tile, 4'h0, sel_sw_lo};
    assign cur_code = sel_code;
    assign cur_tile = sel_tile;

endmodule
