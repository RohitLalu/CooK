// tb_bist.v
// Link BIST (bist_node in noc_mesh) on the default 2x2 mesh, NIs idle.
// Five meshes run side by side, each with a different fault, and every
// router's 10-bit status is compared with the expected value:
//   A healthy                       every existing port passes, edges stay 0
//   B silent link tile1 -> south    r1 out S = 0, r3 in N = 0, and r3 out N = 0
//     although r3 -> r1 is healthy: the thesis's known limitation -- r3's pong
//     has to come back over the broken link, so r3 cannot verify its outlink
//   C bit-flip on the same link     same result: vectors mismatch, no pong
//   D run-time silent tile0 -> east (fault_rt_mask, as the board switches do):
//     r0 out E, r1 in W, and r1 out W by the same limitation
//   E silent link tile3 -> north    the mirror image of B
// Also checks that bist_done rises, at the same cycle in every mesh, that
// every router ends with the same dead-link mask (gossip), and that both
// ends of a dead link stop using it.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_bist;

    localparam NT = `NOC_NUM_TILES;
    localparam FW = `NOC_FLIT_W;
    localparam N = 0, S = 1, E = 2, W = 3, L = 4;

    generate
        if (NT != 4) begin : tb_check_nt
            TB_ERROR_tb_bist_assumes_a_2x2_mesh u_err ();
        end
    endgenerate

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // existing ports per tile, {L,W,E,S,N}
    localparam [4:0] X0 = 5'b10110, X1 = 5'b11010, X2 = 5'b10101, X3 = 5'b11001;
    localparam [4*10-1:0] HEALTHY = {X3, X3, X2, X2, X1, X1, X0, X0};

    // faults: bit t*4+d = link leaving tile t in direction d
    localparam [15:0] F_T1_S = 16'b1 << (1*4 + S);
    localparam [15:0] F_T0_E = 16'b1 << (0*4 + E);
    localparam [15:0] F_T3_N = 16'b1 << (3*4 + N);

    wire [NT*10-1:0] st [0:4];
    wire [4:0]       done;
    reg  [15:0]      rt_mask_d = 16'b0;

    // NI side idle: nothing injected, everything accepted
    `define MESH(idx, MASK, MODE, RTMASK) \
        noc_mesh #(.LINK_FAULT_MASK(MASK), .LINK_FAULT_MODE(MODE)) u_m``idx ( \
            .clk(clk), .rst_n(rst_n), \
            .loc_in_valid({NT{1'b0}}), .loc_in_ready(), .loc_in_flit({NT*FW{1'b0}}), \
            .loc_out_valid(), .loc_out_ready({NT{1'b1}}), .loc_out_room({NT{1'b1}}), .loc_out_flit(), \
            .port_disable({NT*5{1'b0}}), .err_clear(1'b0), \
            .rt_in_err(), .rt_out_dead(), .rt_out_wd(), .rt_drop_cnt(), \
            .fault_rt_mask(RTMASK), .fault_rt_flip(1'b0), \
            .bist_status(st[idx]), .bist_done(done[idx]));

    `MESH(0, 16'b0,  1, 16'b0)
    `MESH(1, F_T1_S, 1, 16'b0)
    `MESH(2, F_T1_S, 2, 16'b0)
    `MESH(3, 16'b0,  1, rt_mask_d)
    `MESH(4, F_T3_N, 1, 16'b0)

    integer errors = 0, checks = 0, cyc = 0;
    integer m, t;

    function [9:0] clr;   // clear one status bit: inlink if is_in, else outlink
        input [9:0] v;
        input       is_in;
        input [2:0] port;
        begin
            clr = v;
            if (is_in) clr[5 + port] = 1'b0;
            else       clr[port]     = 1'b0;
        end
    endfunction

    reg [NT*10-1:0] exp_st [0:4];

    task check;
        input cond;
        input [8*72-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
            else             $display("PASS: %0s", msg);
        end
    endtask

    initial begin
        exp_st[0] = HEALTHY;
        exp_st[1] = HEALTHY;
        exp_st[1][1*10 +: 10] = clr(HEALTHY[1*10 +: 10], 0, S);
        exp_st[1][3*10 +: 10] = clr(clr(HEALTHY[3*10 +: 10], 1, N), 0, N);
        exp_st[2] = exp_st[1];
        exp_st[3] = HEALTHY;
        exp_st[3][0*10 +: 10] = clr(HEALTHY[0*10 +: 10], 0, E);
        exp_st[3][1*10 +: 10] = clr(clr(HEALTHY[1*10 +: 10], 1, W), 0, W);
        exp_st[4] = HEALTHY;
        exp_st[4][3*10 +: 10] = clr(HEALTHY[3*10 +: 10], 0, N);
        exp_st[4][1*10 +: 10] = clr(clr(HEALTHY[1*10 +: 10], 1, S), 0, S);

        rt_mask_d = F_T0_E;          // switch set before reset, as on the board
        repeat (3) @(posedge clk);
        rst_n = 1;
        while (done == 5'b0 && cyc < 2000) begin @(posedge clk); cyc = cyc + 1; end
        $display("      bist_done after %0d cycles", cyc);
        check(done == 5'b11111, "bist_done rose in all five meshes on the same cycle");

        for (m = 0; m < 5; m = m + 1)
            for (t = 0; t < NT; t = t + 1)
                if (st[m][t*10 +: 10] !== exp_st[m][t*10 +: 10])
                    $display("      mesh %0d router %0d: got in=%b out=%b, want in=%b out=%b", m, t,
                             st[m][t*10+5 +: 5], st[m][t*10 +: 5],
                             exp_st[m][t*10+5 +: 5], exp_st[m][t*10 +: 5]);
        check(st[0] === exp_st[0], "A healthy: every existing port passes, edge ports stay 0");
        check(st[1] === exp_st[1], "B silent tile1->S: r1 out S, r3 in N (+ r3 out N, limitation)");
        check(st[2] === exp_st[2], "C bit-flip tile1->S: same localisation");
        check(st[3] === exp_st[3], "D run-time silent tile0->E: r0 out E, r1 in W (+ r1 out W)");
        check(st[4] === exp_st[4], "E silent tile3->N: mirror of B");

        // gossip: one mask everywhere (bit 2t = t<->east, 2t+1 = t<->south)
        check(u_m0.dead_links === {NT{8'h00}}, "A: every router's dead-link mask is empty");
        check(u_m1.dead_links === {NT{8'h08}} && u_m2.dead_links === {NT{8'h08}},
              "B, C: every router knows link 1-3 is dead");
        check(u_m3.dead_links === {NT{8'h01}}, "D: every router knows link 0-1 is dead");
        check(u_m4.dead_links === {NT{8'h08}}, "E: every router knows link 1-3 is dead");

        // neither end may use a dead link
        check(u_m1.g_row[0].g_col[1].u_router.port_disable[S] === 1'b1 &&
              u_m1.g_row[1].g_col[1].u_router.port_disable[N] === 1'b1,
              "B: routers 1 and 3 both disable link 1-3");
        check(u_m0.g_row[0].g_col[1].u_router.port_disable === 5'b0,
              "A: no port disabled in the healthy mesh");

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
