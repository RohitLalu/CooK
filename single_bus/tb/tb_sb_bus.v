// tb_sb_bus.v
// Directed tests for sb_bus with four nodes. Each node has a queue of flits
// to send (driven with valid/ready) and a log of every flit it received;
// the receive side's ready and room are under test control.
//   1  one packet reaches its destination only, unchanged
//   2  three nodes send to one destination at once: no interleaving,
//      round-robin order, nothing lost
//   3  a busy destination is skipped, traffic between other nodes goes on
//   4  packets to a missing node or to the sender itself are dropped, flagged
//   5  back-to-back packets use every bus cycle
//   6  fault_grant: nothing moves; fault_flip: check bits fail at the receiver
//   7  watchdog: a packet whose TAIL never comes loses the bus, others go on

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_sb_bus;

`include "noc_funcs.vh"

    localparam N  = 4;
    localparam FW = `NOC_FLIT_W;
    localparam QD = 32, LD = 64;
    localparam [1:0] HEAD = `NOC_T_HEAD, TAIL = `NOC_T_TAIL;

    generate
        if (`NOC_NUM_TILES != 4) begin : tb_check_nt
            TB_ERROR_tb_sb_bus_assumes_four_node_ids u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [N-1:0]    in_valid, in_ready, out_valid;
    wire [N*FW-1:0] in_flit, out_flit;
    reg  [N-1:0]    out_ready = {N{1'b1}}, out_room = {N{1'b1}};
    reg             fault_grant = 0, fault_flip = 0;
    wire [N-1:0]    err_drop;
    wire            bus_active;

    sb_bus #(.N(N), .WD_CYCLES(16)) dut (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(in_valid), .loc_in_ready(in_ready), .loc_in_flit(in_flit),
        .loc_out_valid(out_valid), .loc_out_ready(out_ready), .loc_out_room(out_room),
        .loc_out_flit(out_flit),
        .fault_grant(fault_grant), .fault_flip(fault_flip),
        .err_drop(err_drop), .bus_active(bus_active)
    );

    // ---------------- send queues ----------------
    reg [FW-1:0] q  [0:N*QD-1];
    reg [5:0]    qh [0:N-1];
    reg [5:0]    qt [0:N-1];
    reg          hold = 0;              // keep every queue from sending (to line packets up)
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : drv
            assign in_valid[g]         = (qh[g] != qt[g]) && !hold;
            assign in_flit[g*FW +: FW] = q[g*QD + qh[g][4:0]];
            always @(posedge clk)
                if (rst_n && in_valid[g] && in_ready[g]) qh[g] <= qh[g] + 1'b1;
        end
    endgenerate

    // ---------------- receive logs ----------------
    reg [FW-1:0] lg [0:N*LD-1];
    integer      lc [0:N-1];
    integer      order [0:LD-1];        // source of each HEAD seen anywhere, in time order
    integer      oc, act;
    integer      m;
    always @(posedge clk) begin
        if (rst_n) begin
            if (bus_active) act = act + 1;
            for (m = 0; m < N; m = m + 1)
                if (out_valid[m] && out_ready[m]) begin
                    lg[m*LD + lc[m]] = out_flit[m*FW +: FW];
                    lc[m] = lc[m] + 1;
                    if (out_flit[m*FW + `NOC_F_TYPE_LSB +: 2] == HEAD) begin
                        order[oc] = out_flit[m*FW + `NOC_F_SRC_LSB +: `NOC_ID_W];
                        oc = oc + 1;
                    end
                end
        end
    end

    integer errors = 0, checks = 0;
    task check;
        input cond;
        input [8*72-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
            else             $display("PASS: %0s", msg);
        end
    endtask

    task restart;
        integer i;
        begin
            rst_n = 0; hold = 0; fault_grant = 0; fault_flip = 0;
            out_ready = {N{1'b1}}; out_room = {N{1'b1}};
            for (i = 0; i < N; i = i + 1) begin qh[i] = 0; qt[i] = 0; lc[i] = 0; end
            oc = 0; act = 0;
            repeat (2) @(posedge clk);
            #1 rst_n = 1;
        end
    endtask

    // queue one HEAD+TAIL packet; the TAIL's data is `d`, the HEAD's is ~d
    task send;
        input integer src, dst;
        input [31:0]  d;
        begin
            q[src*QD + qt[src][4:0]] = noc_make_flit(HEAD, 1'b0, src[`NOC_ID_W-1:0], dst % `NOC_MESH_X,
                                                     dst / `NOC_MESH_X, ~d);
            qt[src] = qt[src] + 1;
            q[src*QD + qt[src][4:0]] = noc_make_flit(TAIL, 1'b0, src[`NOC_ID_W-1:0], dst % `NOC_MESH_X,
                                                     dst / `NOC_MESH_X, d);
            qt[src] = qt[src] + 1;
        end
    endtask

    // every packet logged at node `m`: HEAD and TAIL from the same source, adjacent
    function whole_packets;
        input integer node;
        integer i;
        reg [FW-1:0] h, t;
        begin
            whole_packets = (lc[node] % 2 == 0);
            for (i = 0; i + 1 < lc[node]; i = i + 2) begin
                h = lg[node*LD + i];  t = lg[node*LD + i + 1];
                if (h[`NOC_F_TYPE_LSB +: 2] != HEAD || t[`NOC_F_TYPE_LSB +: 2] != TAIL ||
                    h[`NOC_F_SRC_LSB +: `NOC_ID_W] != t[`NOC_F_SRC_LSB +: `NOC_ID_W] ||
                    h[`NOC_F_DATA_LSB +: 32] != ~t[`NOC_F_DATA_LSB +: 32] ||
                    !noc_chk_ok(h) || !noc_chk_ok(t))
                    whole_packets = 1'b0;
            end
        end
    endfunction

    integer i, t0;
    initial begin
        // ---- 1 ----
        restart;
        send(0, 2, 32'hCAFE_0001);
        repeat (12) @(posedge clk);
        check(lc[2] == 2 && lc[0] == 0 && lc[1] == 0 && lc[3] == 0, "1: packet 0->2 reached node 2 only");
        check(whole_packets(2) && lg[2*LD + 1][`NOC_F_DATA_LSB +: 32] == 32'hCAFE_0001,
              "1: HEAD then TAIL, unchanged, check bits good");

        // ---- 2 ----
        restart;
        hold = 1;
        for (i = 0; i < 2; i = i + 1) begin
            send(0, 2, 32'hA000_0000 + i);
            send(1, 2, 32'hB000_0000 + i);
            send(3, 2, 32'hC000_0000 + i);
        end
        @(posedge clk); #1 hold = 0;
        repeat (40) @(posedge clk);
        check(lc[2] == 12, "2: all six packets arrived at node 2");
        check(whole_packets(2), "2: no interleaving: every HEAD is followed by its own TAIL");
        check(order[0] == 0 && order[1] == 1 && order[2] == 3 &&
              order[3] == 0 && order[4] == 1 && order[5] == 3, "2: round-robin order 0,1,3,0,1,3");
        check(err_drop == 0, "2: nothing dropped");

        // ---- 3 ----
        restart;
        out_room[2] = 0;
        send(0, 2, 32'h1111_1111);
        repeat (6) @(posedge clk);
        send(1, 3, 32'h2222_2222);
        repeat (12) @(posedge clk);
        check(lc[3] == 2 && lc[2] == 0, "3: 1->3 delivered while 0->2 waits for room");
        #1 out_room[2] = 1;
        repeat (8) @(posedge clk);
        check(lc[2] == 2 && whole_packets(2), "3: 0->2 delivered once node 2 has room");

        // ---- 4 ----
        restart;
        send(1, 1, 32'h3333_3333);          // to itself
        send(1, 0, 32'h4444_4444);
        repeat (16) @(posedge clk);
        check(err_drop == 4'b0010, "4: packet to its own sender dropped and flagged");
        check(lc[0] == 2 && lc[1] == 0 && whole_packets(0), "4: the next packet from that node still arrives");

        // ---- 5 ----
        restart;
        hold = 1;
        for (i = 0; i < 4; i = i + 1) send(0, 1, 32'h5000_0000 + i);
        @(posedge clk); #1 hold = 0; act = 0;
        t0 = 0;
        while (lc[1] < 8 && t0 < 40) begin @(posedge clk); t0 = t0 + 1; end
        $display("      8 flits in %0d cycles from the first push", t0);
        check(lc[1] == 8 && whole_packets(1) && t0 <= 12, "5: four back-to-back packets, no idle bus cycles");

        // ---- 6 ----
        restart;
        fault_grant = 1;
        send(0, 1, 32'h6666_6666);
        repeat (50) @(posedge clk);
        check(lc[1] == 0 && act == 0, "6: stuck arbiter: nothing crosses the bus");
        #1 fault_grant = 0; fault_flip = 1;
        repeat (10) @(posedge clk);
        check(lc[1] == 2 && !noc_chk_ok(lg[1*LD]) && !noc_chk_ok(lg[1*LD + 1]),
              "6: flipped data wire: both flits arrive with bad check bits");

        // ---- 7 ----
        restart;
        q[0*QD + qt[0][4:0]] = noc_make_flit(HEAD, 1'b0, 2'd0, 1'b1, 1'b0, 32'h7777_7777);   // 0 -> 1, HEAD only
        qt[0] = qt[0] + 1;
        repeat (6) @(posedge clk);
        send(2, 3, 32'h8888_8888);
        repeat (8) @(posedge clk);
        check(lc[3] == 0 && err_drop == 0, "7: bus held by the unfinished packet, 2->3 waits");
        repeat (20) @(posedge clk);
        check(err_drop == 4'b0001, "7: watchdog released the bus and flagged node 0");
        check(lc[3] == 2 && whole_packets(3), "7: 2->3 delivered afterwards");

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
