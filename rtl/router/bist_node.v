// bist_node.v
// Per-router link BIST: the distributed ping-pong stage of the thesis BIST
// (Shashank V, 2018, section 3.1), adapted to this NoC.
//
// PLACEMENT
//   Sits between one router and its five links (noc_mesh instantiates one per
//   router). While BIST runs it owns the links and the router is isolated
//   (no input valid, no output ready). Once done it is a pass-through and
//   only its status register remains.
//
// WHEN
//   Once per total system reset. Every node leaves reset on the same clock
//   edge (reset_sync on the board), waits START_DELAY cycles, then all nodes
//   run the same fixed schedule in lockstep. Each phase lasts PHASE_CYCLES,
//   far longer than a ping and pong need, so a few cycles of skew between
//   neighbours cannot cause a false result.
//
// PING-PONG, phases East, South, West, North (the thesis order), then Local
//   In phase d, every router sends a ping on output d: NVEC raw words,
//   alternating all-0s and all-1s across the full flit width (data, header,
//   check bits). All-0s exposes a wire stuck at 1, all-1s a wire stuck at 0,
//   and NVEC = the link FIFO depth so every FIFO slot carries a vector.
//   The link FIFO does not care about flit types, so -- unlike the thesis --
//   no HEAD flit is needed to steer the ping.
//   The neighbour receives on its input opp(d). If exactly NVEC words arrive
//   and all match, it marks that INLINK healthy and sends one pong word back
//   on output opp(d). A correct pong marks the sender's OUTLINK d healthy.
//   During phase d, links d carry only pings and links opp(d) only pongs.
//   Local phase: the ping goes out on L and is reflected straight back by a
//   register inside this node (the far end on the FPGA is plain wiring to the
//   NI, which the fault model does not cover). A clean echo marks both L bits.
//
// STATUS  {in[4:0], out[4:0]}, port order N, S, E, W, L.
//   Every bit starts at 0 (faulty) and only a passed test sets it, so a
//   missing or garbled answer can never produce a false "healthy". Ports that
//   do not exist (mesh edge) stay 0.
//   Known limitation, inherited from the thesis: a broken INLINK d also
//   leaves OUTLINK d at 0, because the pong cannot get back.
//
// DEAD-LINK GOSSIP, NOC_NUM_TILES rounds after the ping-pong
//   A link is dead when either of its two status bits here is 0; by the
//   limitation above, both ends of a broken link then see it. Each router
//   starts from the dead links it measured itself, and in every round sends
//   its mask once on each verified outlink and ORs in the masks arriving on
//   its verified inlinks. N-1 rounds reach every router of a connected mesh;
//   the spare round absorbs one round of start skew. Unverified links carry
//   nothing, so a mask only ever gains bits from links that passed.
//   dead_links  the final mask (layout NOC_LINKS_W in noc_defs.vh), which the
//               router uses to route around dead links
//   port_dead   outputs this router must not use: its own failed ports plus
//               any port whose link is in the mask

`timescale 1ns/1ps
`include "noc_defs.vh"

module bist_node #(
    parameter [4:0]   PORT_EXISTS  = 5'b11111,      // {L, W, E, S, N}
    parameter integer MY_ID        = 0,
    parameter integer START_DELAY  = 8,
    parameter integer PHASE_CYCLES = 32,
    parameter integer NVEC         = `NOC_LB_DEPTH
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // router side
    input  wire [4:0]               r_out_valid,
    output wire [4:0]               r_out_ready,
    output wire [4:0]               r_out_room,
    input  wire [5*`NOC_FLIT_W-1:0] r_out_flit,
    output wire [4:0]               r_in_valid,
    input  wire [4:0]               r_in_ready,
    output wire [5*`NOC_FLIT_W-1:0] r_in_flit,

    // link side
    output wire [4:0]               l_out_valid,
    input  wire [4:0]               l_out_ready,
    input  wire [4:0]               l_out_room,
    output wire [5*`NOC_FLIT_W-1:0] l_out_flit,
    input  wire [4:0]               l_in_valid,
    output wire [4:0]               l_in_ready,
    input  wire [5*`NOC_FLIT_W-1:0] l_in_flit,

    output wire [9:0]               status,     // {in[4:0], out[4:0]}
    output wire [`NOC_LINKS_W-1:0]  dead_links,
    output wire [4:0]               port_dead,
    output wire                     done
);

`include "noc_funcs.vh"

    localparam FW = `NOC_FLIT_W;
    localparam N = `NOC_P_N, S = `NOC_P_S, E = `NOC_P_E, W = `NOC_P_W, L = `NOC_P_L;
    localparam [FW-1:0] ZEROS = {FW{1'b0}};
    localparam [FW-1:0] ONES  = {FW{1'b1}};
    localparam [FW+1:0] PONG_W = {((FW+2)/2){2'b10}};
    localparam [FW-1:0] PONG  = PONG_W[FW-1:0];   // ...1010: neither all-0s nor all-1s
    localparam integer CW = $clog2(NVEC + 2);
    localparam integer PW = $clog2(PHASE_CYCLES + 1);
    localparam integer DW = $clog2(START_DELAY + 1);
    localparam integer LW = `NOC_LINKS_W;
    localparam integer NPHASE = 6 + `NOC_NUM_TILES;  // E, S, W, N, L, drain, gossip rounds
    localparam integer HW = $clog2(NPHASE);

    generate
        if (NVEC < 2) begin : bn_check_nvec
            NOC_CONFIG_ERROR_bist_needs_at_least_two_vectors u_err ();
        end
        if (PHASE_CYCLES < NVEC + 16) begin : bn_check_phase
            NOC_CONFIG_ERROR_bist_phase_too_short_for_ping_and_pong u_err ();
        end
        if (`NOC_LINKS_W > FW) begin : bn_check_mask
            NOC_CONFIG_ERROR_dead_link_mask_wider_than_a_flit u_err ();
        end
    endgenerate

    // phase -> ping direction (phase 4 = local, 5 = drain, 6.. = gossip)
    function [2:0] ping_dir;
        input [HW-1:0] ph;
        begin
            case (ph)
                0: ping_dir = E;
                1: ping_dir = S;
                2: ping_dir = W;
                3: ping_dir = N;
                default: ping_dir = L;
            endcase
        end
    endfunction

    function [2:0] opp;
        input [2:0] d;
        begin
            case (d)
                N: opp = S;
                S: opp = N;
                E: opp = W;
                W: opp = E;
                default: opp = L;
            endcase
        end
    endfunction

    localparam [1:0] ST_WAIT = 2'd0, ST_RUN = 2'd1, ST_DONE = 2'd2;
    reg [1:0]    state;
    reg [DW-1:0] wait_cnt;
    reg [HW-1:0] ph;
    reg [PW-1:0] cyc;
    reg [CW-1:0] sent;       // ping vectors sent this phase
    reg [CW-1:0] rcvd;       // ping vectors received this phase
    reg          rx_bad;     // a received ping vector was wrong
    reg          pong_sent;
    reg          pong_ok;
    reg [4:0]    st_in, st_out;
    reg          refl_v;     // local-port reflector
    reg [FW-1:0] refl_f;
    reg [LW-1:0] mask;       // dead links known so far
    reg [3:0]    g_sent;     // gossip word sent on this port this round

    wire active = (state != ST_DONE);
    wire run    = (state == ST_RUN);
    wire in_local = (ph == 4);
    wire drain  = (ph == 5);
    wire gossip = (ph >= 6);
    wire [2:0] d_ping = ping_dir(ph);          // output carrying pings
    wire [2:0] d_back = opp(d_ping);           // input receiving pings, output carrying pongs
    wire ping_ok  = (rcvd == NVEC) && !rx_bad;
    wire [FW-1:0] vec_tx = sent[0] ? ONES : ZEROS;
    wire [FW-1:0] vec_rx = rcvd[0] ? ONES : ZEROS;

    // ---------------------------------------------------------------
    // dead links: measured here, and the mask's view of this router's ports
    // ---------------------------------------------------------------
    integer lb;
    reg [LW-1:0] own_dead;
    reg [3:0]    mask_port;
    always @(*) begin
        own_dead  = {LW{1'b0}};
        mask_port = 4'b0;
        for (lb = 0; lb < 4; lb = lb + 1)
            if (PORT_EXISTS[lb]) begin
                own_dead[noc_link_bit(MY_ID, lb)] = !(st_in[lb] && st_out[lb]);
                mask_port[lb] = mask[noc_link_bit(MY_ID, lb)];
            end
    end

    // masks arriving on verified inlinks this cycle
    reg [LW-1:0] g_rx;
    integer gi;
    always @(*) begin
        g_rx = {LW{1'b0}};
        for (gi = 0; gi < 4; gi = gi + 1)
            if (run && gossip && st_in[gi] && l_in_valid[gi])
                g_rx = g_rx | l_in_flit[gi*FW +: LW];
    end

    assign dead_links = mask;
    assign port_dead  = {PORT_EXISTS[L] && !st_out[L], mask_port};

    // ---------------------------------------------------------------
    // link side during BIST
    // ---------------------------------------------------------------
    reg  [4:0]    t_valid;
    reg  [5*FW-1:0] t_flit;
    integer p;
    always @(*) begin
        t_valid = 5'b0;
        t_flit  = {5*FW{1'b0}};
        p       = 0;            // loop temporary: assigned on every path, no latch
        if (run && gossip) begin
            for (p = 0; p < 4; p = p + 1)
                if (st_out[p] && !g_sent[p]) begin
                    t_valid[p] = 1'b1;
                    t_flit[p*FW +: FW] = {{(FW-LW){1'b0}}, mask};
                end
        end else if (run && !drain && !in_local) begin
            if (PORT_EXISTS[d_ping] && sent < NVEC) begin
                t_valid[d_ping] = 1'b1;
                t_flit[d_ping*FW +: FW] = vec_tx;
            end
            if (PORT_EXISTS[d_back] && ping_ok && !pong_sent) begin
                t_valid[d_back] = 1'b1;
                t_flit[d_back*FW +: FW] = PONG;
            end
        end
    end

    // local-port ping goes to the reflector, not to the NI
    wire tx_local = run && in_local && PORT_EXISTS[L] && (sent < NVEC);

    // received word per port during BIST (the local port reads the reflector)
    wire [4:0]      rx_valid = {refl_v, l_in_valid[3:0]};
    wire [5*FW-1:0] rx_flit  = {refl_f, l_in_flit[4*FW-1:0]};

    assign l_out_valid = active ? t_valid                     : r_out_valid;
    assign l_out_flit  = active ? t_flit                      : r_out_flit;
    assign l_in_ready  = active ? 5'b01111                    : r_in_ready;   // drain the four links
    assign r_in_valid  = active ? 5'b0                        : l_in_valid;
    assign r_in_flit   = l_in_flit;
    assign r_out_ready = active ? 5'b0                        : l_out_ready;
    assign r_out_room  = active ? 5'b0                        : l_out_room;

    assign status = {st_in, st_out};
    assign done   = (state == ST_DONE);

    // ---------------------------------------------------------------
    // sequencer
    // ---------------------------------------------------------------
    wire ping_push = !gossip && (in_local ? tx_local : (t_valid[d_ping] && l_out_ready[d_ping]));
    wire pong_push = !gossip && !in_local && t_valid[d_back] && l_out_ready[d_back];
    wire ping_rx   = run && !drain && !gossip && rx_valid[d_back];
    wire pong_rx   = run && !drain && !gossip && !in_local && rx_valid[d_ping];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_WAIT;
            wait_cnt  <= {DW{1'b0}};
            ph        <= {HW{1'b0}};
            cyc       <= {PW{1'b0}};
            sent      <= {CW{1'b0}};
            rcvd      <= {CW{1'b0}};
            rx_bad    <= 1'b0;
            pong_sent <= 1'b0;
            pong_ok   <= 1'b0;
            st_in     <= 5'b0;
            st_out    <= 5'b0;
            refl_v    <= 1'b0;
            refl_f    <= {FW{1'b0}};
            mask      <= {LW{1'b0}};
            g_sent    <= 4'b0;
        end else begin
            // reflector: one-cycle echo of the local-port ping
            refl_v <= tx_local;
            refl_f <= vec_tx;

            case (state)
                ST_WAIT: begin
                    if (wait_cnt == START_DELAY) state <= ST_RUN;
                    else                         wait_cnt <= wait_cnt + 1'b1;
                end

                ST_RUN: begin
                    if (ping_push) sent <= sent + 1'b1;
                    if (pong_push) pong_sent <= 1'b1;
                    if (ping_rx) begin
                        if (rcvd != NVEC + 1) rcvd <= rcvd + 1'b1;   // saturate: extras fail the test
                        if (rcvd >= NVEC || rx_flit[d_back*FW +: FW] != vec_rx) rx_bad <= 1'b1;
                    end
                    if (pong_rx && rx_flit[d_ping*FW +: FW] == PONG) pong_ok <= 1'b1;
                    if (gossip) begin
                        g_sent <= g_sent | (t_valid[3:0] & l_out_ready[3:0]);
                        mask   <= mask | g_rx;
                    end

                    if (cyc == PHASE_CYCLES - 1) begin
                        // close the phase: record, then start the next one
                        if (drain) begin
                            mask <= own_dead;    // all status bits are final now
                        end else if (!gossip) begin
                            if (in_local) begin
                                st_in[L]  <= PORT_EXISTS[L] && ping_ok;
                                st_out[L] <= PORT_EXISTS[L] && ping_ok;
                            end else begin
                                st_in[d_back]  <= PORT_EXISTS[d_back] && ping_ok;
                                st_out[d_ping] <= PORT_EXISTS[d_ping] && pong_ok;
                            end
                        end
                        cyc       <= {PW{1'b0}};
                        sent      <= {CW{1'b0}};
                        rcvd      <= {CW{1'b0}};
                        rx_bad    <= 1'b0;
                        pong_sent <= 1'b0;
                        pong_ok   <= 1'b0;
                        g_sent    <= 4'b0;
                        if (ph == NPHASE - 1) state <= ST_DONE;
                        else                  ph <= ph + 1'b1;
                    end else begin
                        cyc <= cyc + 1'b1;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
