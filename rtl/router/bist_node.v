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
// ROUTER SELF-TEST, after the local phase (the router is still cut off from
// its links, so this node can drive its inputs and watch its outputs)
//   Path test: for every input port i and every other output port o that
//   both exist, a two-flit packet addressed so that X-Y routing sends it to
//   o is put on input i. Exactly those two flits must come out of o, in
//   order and unchanged, and nothing may come out anywhere else. That walks
//   every path of the crossbar and the route computation for each direction.
//   Arbitration test: two inputs offer a packet for the local output on the
//   same cycle. Both packets must come out whole, one after the other.
//   A failed test marks the input and the output it involved in
//   rt_status = {in_bad[4:0], out_bad[4:0]} (1 = failed; note the sense is
//   the opposite of the link status). A router with any bit set is not
//   trusted with anything: all its ports are reported dead and all its links
//   go into the dead-link mask, so the rest of the mesh routes around it and
//   its tile is cut off. The test takes the same number of cycles in every
//   node, so the nodes stay in step for the gossip that follows.
//   Not covered: the watchdog and the error-drop paths of the router.
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
    output wire [9:0]               rt_status,  // router self-test {in_bad, out_bad}, 1 = failed
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

    localparam [1:0] ST_WAIT = 2'd0, ST_RUN = 2'd1, ST_DONE = 2'd2, ST_RTR = 2'd3;
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
                own_dead[noc_link_bit(MY_ID, lb)] = rt_fail || !(st_in[lb] && st_out[lb]);
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
    assign port_dead  = {PORT_EXISTS[L] && (!st_out[L] || rt_fail),
                         mask_port | ({4{rt_fail}} & PORT_EXISTS[3:0])};

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
    assign r_in_valid  = rtr ? rt_valid : active ? 5'b0       : l_in_valid;
    assign r_in_flit   = rtr ? rt_in_flit                     : l_in_flit;
    assign r_out_ready = rtr ? 5'b11111 : active ? 5'b0       : l_out_ready;
    assign r_out_room  = rtr ? 5'b11111 : active ? 5'b0       : l_out_room;

    // ---------------------------------------------------------------
    // router self-test (state ST_RTR)
    // ---------------------------------------------------------------
    localparam integer RT_SLOT  = 8;                  // cycles per test
    localparam integer RT_PATHS = 25;                 // (input, output) pairs, slot k: i = k/5, o = k%5
    localparam integer RT_SLOTS = RT_PATHS + 2;       // + the arbitration test (two slots long)
    localparam integer MY_X = MY_ID % `NOC_MESH_X, MY_Y = MY_ID / `NOC_MESH_X;
    localparam [1:0] T_HEAD = `NOC_T_HEAD, T_TAIL = `NOC_T_TAIL;

    // the two lowest-numbered link ports that exist: the arbitration test's inputs
    function integer nth_port;
        input integer n;
        integer q, c;
        begin
            nth_port = -1; c = 0;
            for (q = 0; q < 4; q = q + 1)
                if (PORT_EXISTS[q]) begin
                    if (c == n) nth_port = q;
                    c = c + 1;
                end
        end
    endfunction
    localparam integer ARB_A = nth_port(0), ARB_B = nth_port(1);
    localparam ARB_EN = (ARB_B >= 0) && PORT_EXISTS[L];

    // a test flit that X-Y routing sends out of port `o`
    function [FW-1:0] rt_make;
        input [1:0]  ftype;
        input [2:0]  o;
        input [31:0] data;
        integer x, y;
        begin
            x = MY_X + ((o == E) ? 1 : 0) - ((o == W) ? 1 : 0);
            y = MY_Y + ((o == S) ? 1 : 0) - ((o == N) ? 1 : 0);
            rt_make = noc_make_flit(ftype, 1'b0, MY_ID[`NOC_ID_W-1:0], x[`NOC_X_W-1:0], y[`NOC_Y_W-1:0], data);
        end
    endfunction

    wire         rtr = (state == ST_RTR);
    reg  [4:0]   rt_slot;                    // which test
    reg  [3:0]   rt_c;                       // cycle inside the test
    reg  [1:0]   sa, sb;                     // flits sent by sender A / B (0, 1, done)
    reg  [2:0]   seen;                       // flits seen on the expected output
    reg          rt_bad;
    reg  [1:0]   arb_first;                  // arbitration test: 1 = A's packet came out first, 2 = B's
    reg  [4:0]   rt_in_bad, rt_out_bad;
    wire         rt_fail = |{rt_in_bad, rt_out_bad};
    assign rt_status = {rt_in_bad, rt_out_bad};

    wire         arb    = (rt_slot >= RT_PATHS);
    wire [2:0]   pi     = rt_slot / 5;
    wire [2:0]   po     = arb ? L : rt_slot % 5;
    wire         pair   = !arb && (pi != po) && PORT_EXISTS[pi] && PORT_EXISTS[po];
    wire [2:0]   ia     = arb ? ARB_A[2:0] : pi;                 // sender A's input port
    wire [2:0]   ib     = ARB_B[2:0];                            // sender B's (arbitration only)
    wire [31:0]  da     = {16'hB157, 3'b0, rt_slot, 8'hA5};      // payloads: recognisably different
    wire [31:0]  db     = {16'hB157, 3'b0, rt_slot, 8'h5B};
    wire [FW-1:0] fa    = rt_make(sa == 0 ? T_HEAD : T_TAIL, po, sa == 0 ? da : ~da);
    wire [FW-1:0] fb    = rt_make(sb == 0 ? T_HEAD : T_TAIL, po, sb == 0 ? db : ~db);
    wire         a_on   = rtr && (pair || (arb && ARB_EN)) && (sa < 2);
    wire         b_on   = rtr && arb && ARB_EN && (sb < 2);

    reg  [4:0]      rt_valid;
    reg  [5*FW-1:0] rt_in_flit;
    always @(*) begin
        rt_valid   = 5'b0;
        rt_in_flit = {5*FW{1'b0}};
        if (a_on) begin rt_valid[ia] = 1'b1; rt_in_flit[ia*FW +: FW] = fa; end
        if (b_on) begin rt_valid[ib] = 1'b1; rt_in_flit[ib*FW +: FW] = fb; end
    end

    // what comes out of the router this cycle
    wire [FW-1:0] of = r_out_flit[po*FW +: FW];
    wire          ov = r_out_valid[po];
    wire          stray = |(r_out_valid & ~(5'b1 << po));        // a flit on any other output
    // path test: the two flits, in order. Arbitration: a HEAD picks which packet is first.
    wire exp_path = (seen == 0) ? (of == rt_make(T_HEAD, po, da)) : (of == rt_make(T_TAIL, po, ~da));
    wire is_ha = (of == rt_make(T_HEAD, L, da)),  is_ta = (of == rt_make(T_TAIL, L, ~da));
    wire is_hb = (of == rt_make(T_HEAD, L, db)),  is_tb = (of == rt_make(T_TAIL, L, ~db));
    wire exp_arb  = (seen == 0) ? (is_ha || is_hb) :
                    (seen == 1) ? ((arb_first == 1) ? is_ta : is_tb) :
                    (seen == 2) ? ((arb_first == 1) ? is_hb : is_ha) :
                                  ((arb_first == 1) ? is_tb : is_ta);
    wire [3:0] rt_last = arb ? 2*RT_SLOT - 1 : RT_SLOT - 1;

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
            rt_slot   <= 5'd0;  rt_c <= 4'd0;  sa <= 2'd0;  sb <= 2'd0;  seen <= 3'd0;
            rt_bad    <= 1'b0;  arb_first <= 2'd0;  rt_in_bad <= 5'b0;  rt_out_bad <= 5'b0;
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
                        if (in_local) state <= ST_RTR;       // router self-test before the drain phase
                    end else begin
                        cyc <= cyc + 1'b1;
                    end
                end

                ST_RTR: begin
                    if (a_on && r_in_ready[ia]) sa <= sa + 1'b1;
                    if (b_on && r_in_ready[ib]) sb <= sb + 1'b1;
                    if (stray) rt_bad <= 1'b1;
                    if (ov) begin
                        if (seen != 3'd7) seen <= seen + 1'b1;
                        if (!(pair || (arb && ARB_EN)) || !(arb ? (seen < 4 && exp_arb) : (seen < 2 && exp_path)))
                            rt_bad <= 1'b1;
                        if (arb && seen == 0) arb_first <= is_ha ? 2'd1 : 2'd2;
                    end

                    if (rt_c == rt_last) begin
                        // close the test: anything but the expected flits fails it
                        if (pair && (rt_bad || seen != 2)) begin
                            rt_in_bad[pi]  <= 1'b1;
                            rt_out_bad[po] <= 1'b1;
                        end
                        if (!arb && !pair && rt_bad) rt_out_bad <= rt_out_bad | r_out_valid;   // output with nothing sent
                        if (arb && ARB_EN && (rt_bad || seen != 4)) begin
                            rt_in_bad[ia]  <= 1'b1;
                            rt_in_bad[ib]  <= 1'b1;
                            rt_out_bad[L]  <= 1'b1;
                        end
                        rt_c <= 4'd0;  sa <= 2'd0;  sb <= 2'd0;  seen <= 3'd0;  rt_bad <= 1'b0;  arb_first <= 2'd0;
                        if (arb) state <= ST_RUN;            // on to the drain phase and the gossip
                        else     rt_slot <= rt_slot + 1'b1;
                    end else begin
                        rt_c <= rt_c + 1'b1;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
