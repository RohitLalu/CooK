// noc_mesh.v
// The network fabric for an NOC_MESH_X x NOC_MESH_Y mesh, generated from the
// mesh-size knobs in noc_defs.vh: one router per node, two link_buffers per
// internal edge (one each way), one end_buff per mesh-edge port.
//
// Nothing here is hand-wired per direction. Every connection is computed from
// (x, y, direction) by the same few lines, which is the point: the earlier
// hand-copied four_router_top accumulated a long list of swapped and
// duplicated wires.
//
// Flattened buses, tile id = y*MESH_X + x:
//   loc_*         one router L port per tile, tile t at bit t / slice t
//   router buses  router t, port p at index t*5 + p
//   link faults   bit t*4 + d = the link LEAVING tile t in direction d
//                 (d: 0=N 1=S 2=E 3=W), see link_buffer FAULT

`timescale 1ns/1ps
`include "noc_defs.vh"

module noc_mesh #(
    parameter [4*`NOC_NUM_TILES-1:0] LINK_FAULT_MASK = {4*`NOC_NUM_TILES{1'b0}},
    parameter integer LINK_FAULT_MODE = 1,
    parameter integer LB_DEPTH        = `NOC_LB_DEPTH,
    parameter integer WD_PRESCALE_W   = 2,
    parameter integer WD_LOCK_LIMIT   = 8,
    parameter integer WD_STARVE_LIMIT = 64
) (
    input  wire clk,
    input  wire rst_n,

    // tile -> router L input
    input  wire [`NOC_NUM_TILES-1:0]             loc_in_valid,
    output wire [`NOC_NUM_TILES-1:0]             loc_in_ready,
    input  wire [`NOC_NUM_TILES*`NOC_FLIT_W-1:0] loc_in_flit,
    // router L output -> tile
    output wire [`NOC_NUM_TILES-1:0]             loc_out_valid,
    input  wire [`NOC_NUM_TILES-1:0]             loc_out_ready,
    input  wire [`NOC_NUM_TILES-1:0]             loc_out_room,
    output wire [`NOC_NUM_TILES*`NOC_FLIT_W-1:0] loc_out_flit,

    // BIST / debug, router t at slice t
    input  wire [`NOC_NUM_TILES*5-1:0]           port_disable,
    input  wire                                  err_clear,
    output wire [`NOC_NUM_TILES*5*`NOC_E_W-1:0]  rt_in_err,
    output wire [`NOC_NUM_TILES*5-1:0]           rt_out_dead,
    output wire [`NOC_NUM_TILES*5-1:0]           rt_out_wd,
    output wire [`NOC_NUM_TILES*8-1:0]           rt_drop_cnt
);

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer MX = `NOC_MESH_X;
    localparam integer MY = `NOC_MESH_Y;
    localparam integer FW = `NOC_FLIT_W;
    localparam integer PN = `NOC_P_N, PS = `NOC_P_S, PE = `NOC_P_E,
                       PW = `NOC_P_W, PL = `NOC_P_L;

    // all router ports, router t port p at index t*5+p
    wire [NT*5-1:0]    r_in_valid,  r_in_ready;
    wire [NT*5*FW-1:0] r_in_flit;
    wire [NT*5-1:0]    r_out_valid, r_out_ready, r_out_room;
    wire [NT*5*FW-1:0] r_out_flit;

    genvar gx, gy, gd;
    generate
        for (gy = 0; gy < MY; gy = gy + 1) begin : g_row
            for (gx = 0; gx < MX; gx = gx + 1) begin : g_col
                localparam integer ID = gy*MX + gx;
                // {L, W, E, S, N}
                localparam [4:0] PORTS = {1'b1, (gx > 0), (gx < MX-1), (gy < MY-1), (gy > 0)};

                noc_router #(
                    .MY_X(gx), .MY_Y(gy), .PORT_EXISTS(PORTS),
                    .WD_PRESCALE_W(WD_PRESCALE_W),
                    .WD_LOCK_LIMIT(WD_LOCK_LIMIT),
                    .WD_STARVE_LIMIT(WD_STARVE_LIMIT)
                ) u_router (
                    .clk(clk), .rst_n(rst_n),
                    .in_valid (r_in_valid [ID*5 +: 5]),
                    .in_ready (r_in_ready [ID*5 +: 5]),
                    .in_flit  (r_in_flit  [ID*5*FW +: 5*FW]),
                    .out_valid(r_out_valid[ID*5 +: 5]),
                    .out_ready(r_out_ready[ID*5 +: 5]),
                    .out_room (r_out_room [ID*5 +: 5]),
                    .out_flit (r_out_flit [ID*5*FW +: 5*FW]),
                    .port_disable(port_disable[ID*5 +: 5]),
                    .err_clear(err_clear),
                    .in_err   (rt_in_err  [ID*5*`NOC_E_W +: 5*`NOC_E_W]),
                    .out_dead (rt_out_dead[ID*5 +: 5]),
                    .out_wd   (rt_out_wd  [ID*5 +: 5]),
                    .drop_cnt (rt_drop_cnt[ID*8 +: 8]),
                    .cap_valid(), .cap_port(), .cap_flit()
                );

                // local port straight to the tile
                assign r_in_valid[ID*5+PL]            = loc_in_valid[ID];
                assign loc_in_ready[ID]               = r_in_ready[ID*5+PL];
                assign r_in_flit[(ID*5+PL)*FW +: FW]  = loc_in_flit[ID*FW +: FW];
                assign loc_out_valid[ID]              = r_out_valid[ID*5+PL];
                assign r_out_ready[ID*5+PL]           = loc_out_ready[ID];
                assign r_out_room[ID*5+PL]            = loc_out_room[ID];
                assign loc_out_flit[ID*FW +: FW]      = r_out_flit[(ID*5+PL)*FW +: FW];

                for (gd = 0; gd < 4; gd = gd + 1) begin : g_dir
                    localparam integer NX  = gx + ((gd == PE) ? 1 : 0) - ((gd == PW) ? 1 : 0);
                    localparam integer NY  = gy + ((gd == PS) ? 1 : 0) - ((gd == PN) ? 1 : 0);
                    localparam integer HAS = (NX >= 0) && (NX < MX) && (NY >= 0) && (NY < MY);
                    localparam integer NID = NY*MX + NX;
                    localparam integer OPP = (gd == PN) ? PS : (gd == PS) ? PN :
                                             (gd == PE) ? PW : PE;
                    localparam integer FLT = LINK_FAULT_MASK[ID*4+gd] ? LINK_FAULT_MODE : 0;

                    if (HAS) begin : g_link
                        // our output gd -> neighbour's input OPP
                        link_buffer #(.DEPTH(LB_DEPTH), .FAULT(FLT)) u_lb (
                            .clk(clk), .rst_n(rst_n),
                            .in_valid (r_out_valid[ID*5+gd]),
                            .in_ready (r_out_ready[ID*5+gd]),
                            .in_room  (r_out_room [ID*5+gd]),
                            .in_flit  (r_out_flit [(ID*5+gd)*FW +: FW]),
                            .out_valid(r_in_valid [NID*5+OPP]),
                            .out_ready(r_in_ready [NID*5+OPP]),
                            .out_flit (r_in_flit  [(NID*5+OPP)*FW +: FW])
                        );
                    end else begin : g_edge
                        end_buff #(.MODE(0)) u_eb (
                            .out_valid(r_in_valid [ID*5+gd]),
                            .out_flit (r_in_flit  [(ID*5+gd)*FW +: FW]),
                            .out_ready(r_out_ready[ID*5+gd]),
                            .out_room (r_out_room [ID*5+gd])
                        );
                    end
                end
            end
        end
    endgenerate

endmodule
