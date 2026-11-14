// sb_bus.v
// Single shared bus for the baseline system: N nodes, ONE channel, one flit
// per cycle for the whole system. It takes the place of noc_mesh and has the
// same node-facing ports, so the same network interfaces (ni.v) and the same
// software run on both architectures and only the interconnect differs.
//
// PACKETS are the NoC's: HEAD then TAIL flits, same layout and check bits
// (noc_defs.vh). The bus never changes a flit.
//
// BUFFERING. Every node has a transmit queue (a link_buffer FIFO, one whole
// packet plus slack). A node hands its packet to the queue and gets on with
// its work; the queue waits for the bus. That is where contention is
// absorbed: a node that loses arbitration is not stalled, its packet is.
//
// ARBITRATION. Round robin over the queues whose head-of-line flit is a
// HEAD. The winner owns the channel until its TAIL has passed, so packets
// never interleave. A HEAD is granted only when its destination has room for
// a whole packet (loc_out_room), so the channel never stalls in the middle
// of a packet; a queue whose destination is busy is skipped, not waited for,
// so one slow node cannot hold up traffic between the others. The pointer
// moves past the winner, which bounds every queue's wait to N-1 packets.
//
// DROPS. A HEAD addressed to a node that does not exist, or to its own
// sender, and any non-HEAD flit at the head of a queue while the channel is
// free (the rest of a dropped packet) are consumed and flagged in err_drop.
//
// WATCHDOG. A sender that was granted the channel and then delivers no flit
// for WD_CYCLES cycles (its TAIL never comes, or the receiver stopped taking
// flits) loses the channel and is flagged in err_drop. The rest of its
// packet, if it ever arrives, is dropped by the rule above. Without this one
// broken node would hold the only channel forever.
//
// FAULTS (run-time fault injection for metric M3; tie both to 0 otherwise)
//   fault_grant  the arbiter is stuck: nothing is ever granted
//   fault_flip   one data wire of the shared channel is inverted, so every
//                flit arrives with bad check bits
// Either one takes out the whole system, which is the baseline's M3 result:
// one shared resource, no other path.

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_bus #(
    parameter integer N        = `NOC_NUM_TILES,
    parameter integer TX_DEPTH = `NOC_LB_DEPTH,
    parameter integer WD_CYCLES = 256
) (
    input  wire clk,
    input  wire rst_n,

    // node -> bus
    input  wire [N-1:0]             loc_in_valid,
    output wire [N-1:0]             loc_in_ready,
    input  wire [N*`NOC_FLIT_W-1:0] loc_in_flit,
    // bus -> node
    output wire [N-1:0]             loc_out_valid,
    input  wire [N-1:0]             loc_out_ready,
    input  wire [N-1:0]             loc_out_room,
    output wire [N*`NOC_FLIT_W-1:0] loc_out_flit,

    input  wire                     fault_grant,
    input  wire                     fault_flip,
    output reg  [N-1:0]             err_drop,     // sticky, per sending node
    output wire                     bus_active    // a flit crosses the channel this cycle
);

    localparam integer FW = `NOC_FLIT_W;
    localparam integer SW = `NOC_CLOG2_1(N);
    localparam [1:0] T_HEAD = `NOC_T_HEAD, T_HEADTAIL = `NOC_T_HEADTAIL, T_TAIL = `NOC_T_TAIL;

    generate
        if (N > `NOC_NUM_TILES) begin : sb_check_n
            NOC_CONFIG_ERROR_bus_has_more_nodes_than_tile_ids u_err ();
        end
    endgenerate

    // ---------------------------------------------------------------
    // transmit queues
    // ---------------------------------------------------------------
    wire [N-1:0]    q_valid;
    reg  [N-1:0]    q_ready;
    wire [N*FW-1:0] q_flit;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_txq
            link_buffer #(.DEPTH(TX_DEPTH)) u_txq (
                .clk(clk), .rst_n(rst_n), .rt_silent(1'b0), .rt_flip(1'b0),
                .in_valid(loc_in_valid[g]), .in_ready(loc_in_ready[g]), .in_room(),
                .in_flit(loc_in_flit[g*FW +: FW]),
                .out_valid(q_valid[g]), .out_ready(q_ready[g]),
                .out_flit(q_flit[g*FW +: FW])
            );
        end
    endgenerate

    // ---------------------------------------------------------------
    // arbiter and channel
    // ---------------------------------------------------------------
    reg          busy;       // a packet owns the channel
    reg [SW-1:0] owner;      // sending node
    reg [SW-1:0] dest;       // receiving node
    reg [SW-1:0] rr;         // next node to be asked first
    reg [$clog2(WD_CYCLES + 1)-1:0] wd;   // cycles the owner has made no progress

    reg          sel_v;      // a queue is served this cycle
    reg          sel_drop;   // ... by discarding its flit
    reg [SW-1:0] sel;
    reg [SW-1:0] sel_dst;

    integer k, c;
    reg [FW-1:0] hf;
    reg [1:0]    ht;
    integer      hd;

    always @(*) begin
        sel_v = 1'b0; sel_drop = 1'b0; sel = {SW{1'b0}}; sel_dst = {SW{1'b0}};
        c = 0; hf = {FW{1'b0}}; ht = 2'b0; hd = 0; k = 0;   // loop temporaries: no latches
        if (busy) begin
            sel_v   = q_valid[owner] && loc_out_ready[dest];
            sel     = owner;
            sel_dst = dest;
        end else if (!fault_grant) begin
            for (k = 0; k < N; k = k + 1) begin
                c  = (rr + k) % N;
                hf = q_flit[c*FW +: FW];
                ht = hf[`NOC_F_TYPE_LSB +: 2];
                hd = hf[`NOC_F_DSTY_LSB +: `NOC_Y_W] * `NOC_MESH_X + hf[`NOC_F_DSTX_LSB +: `NOC_X_W];
                if (!sel_v && q_valid[c]) begin
                    if ((ht != T_HEAD && ht != T_HEADTAIL) || hd >= N || hd == c) begin
                        sel_v = 1'b1; sel_drop = 1'b1; sel = c;
                    end else if (loc_out_room[hd] && loc_out_ready[hd]) begin
                        sel_v = 1'b1; sel = c; sel_dst = hd;
                    end
                end
            end
        end
    end

    wire [FW-1:0] sel_flit = q_flit[sel*FW +: FW];
    wire [1:0]    sel_type = sel_flit[`NOC_F_TYPE_LSB +: 2];
    // the one shared channel
    wire          ch_valid = sel_v && !sel_drop;
    wire [FW-1:0] ch_flit  = sel_flit ^ {{(FW-1){1'b0}}, fault_flip};

    assign bus_active = ch_valid;

    always @(*) begin
        q_ready = {N{1'b0}};
        if (sel_v) q_ready[sel] = 1'b1;
    end

    generate
        for (g = 0; g < N; g = g + 1) begin : g_rx
            assign loc_out_valid[g]         = ch_valid && (sel_dst == g);
            assign loc_out_flit[g*FW +: FW] = ch_flit;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            owner    <= {SW{1'b0}};
            dest     <= {SW{1'b0}};
            rr       <= {SW{1'b0}};
            err_drop <= {N{1'b0}};
            wd       <= 0;
        end else if (busy && !sel_v) begin
            // the owner is stalled: give up on its packet after WD_CYCLES
            if (wd == WD_CYCLES) begin
                busy            <= 1'b0;
                err_drop[owner] <= 1'b1;
                wd              <= 0;
            end else begin
                wd <= wd + 1'b1;
            end
        end else if (sel_v) begin
            wd <= 0;
            if (sel_drop) begin
                err_drop[sel] <= 1'b1;
            end else if (!busy) begin
                // a HEAD was granted: hold the channel until its TAIL
                owner <= sel;
                dest  <= sel_dst;
                rr    <= (sel == N - 1) ? {SW{1'b0}} : sel + 1'b1;
                busy  <= (sel_type == T_HEAD);
            end else if (sel_type == T_TAIL) begin
                busy <= 1'b0;
            end
        end
    end

endmodule
