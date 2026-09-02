`timescale 1ns/1ps

module tb_noc_router;

    localparam DX_W = 4, DY_W = 4, DATA_W = 8;
    localparam N=0, S=1, E=2, W=3, L=4;
    localparam [1:0] BODY=2'b00, HEAD=2'b01, HEADTAIL=2'b10, TAIL=2'b11;

    reg clk = 0;
    reg rst_n = 0;

    reg [4:0] in_valid = 5'b0;
    wire [4:0] in_ready;
    reg [9:0] in_type = 10'b0;
    reg [5*DX_W-1:0] in_dx = 0;
    reg [5*DY_W-1:0] in_dy = 0;
    reg [5*DATA_W-1:0] in_data = 0;

    wire [4:0] out_valid;
    reg  [4:0] out_ready = 5'b11111;
    wire [9:0] out_type;
    wire [5*DX_W-1:0] out_dx;
    wire [5*DY_W-1:0] out_dy;
    wire [5*DATA_W-1:0] out_data;

    integer errors = 0;
    integer tests  = 0;

    noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_type(in_type),
        .in_dx(in_dx), .in_dy(in_dy), .in_data(in_data),
        .out_valid(out_valid), .out_ready(out_ready), .out_type(out_type),
        .out_dx(out_dx), .out_dy(out_dy), .out_data(out_data)
    );

    always #5 clk = ~clk;

    // Drives one HEADTAIL flit into `port` aimed at `exp_out`, checks the
    // COMBINATIONAL result before the clock edge that commits it (this is
    // the correct way to check "will this be accepted", since the
    // registered state itself can change ON that edge).
    task send_and_check;
        input [2:0] port;
        input signed [DX_W-1:0] dx;
        input signed [DY_W-1:0] dy;
        input [DATA_W-1:0] data;
        input [2:0] exp_out;
        integer k;
        begin
            tests = tests + 1;
            in_valid[port] = 1'b1;
            in_type[2*port +: 2] = HEADTAIL;
            in_dx[DX_W*port +: DX_W] = dx;
            in_dy[DY_W*port +: DY_W] = dy;
            in_data[DATA_W*port +: DATA_W] = data;
            #1;

            if (!in_ready[port]) begin
                $display("FAIL test %0d: port %0d dx=%0d dy=%0d not granted", tests, port, dx, dy);
                errors = errors + 1;
            end else if (!out_valid[exp_out]) begin
                $display("FAIL test %0d: port %0d dx=%0d dy=%0d expected out %0d but out_valid[%0d]=0",
                          tests, port, dx, dy, exp_out, exp_out);
                errors = errors + 1;
            end else if (out_data[DATA_W*exp_out +: DATA_W] !== data) begin
                $display("FAIL test %0d: data mismatch on out %0d: got %0h expected %0h",
                          tests, exp_out, out_data[DATA_W*exp_out +: DATA_W], data);
                errors = errors + 1;
            end else begin
                for (k = 0; k < 5; k = k + 1) begin
                    if (k != exp_out && out_valid[k]) begin
                        $display("FAIL test %0d: unexpected out_valid[%0d] also high", tests, k);
                        errors = errors + 1;
                    end
                end
                $display("PASS test %0d: port %0d (dx=%0d,dy=%0d) -> out %0d, data=%0h",
                          tests, port, dx, dy, exp_out, data);
            end

            @(posedge clk); #1;
            in_valid[port] = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Want output N: dx=0, dy=-1. Legal sources: S,E,W,L
        send_and_check(S, 0, -1, 8'hA1, N);
        send_and_check(E, 0, -1, 8'hA2, N);
        send_and_check(W, 0, -1, 8'hA3, N);
        send_and_check(L, 0, -1, 8'hA4, N);

        // Want output S: dx=0, dy=+1. Legal sources: N,E,W,L
        send_and_check(N, 0, 1, 8'hB1, S);
        send_and_check(E, 0, 1, 8'hB2, S);
        send_and_check(W, 0, 1, 8'hB3, S);
        send_and_check(L, 0, 1, 8'hB4, S);

        // Want output E: dx=+1. Legal sources: N,S,W,L
        send_and_check(N, 1, 0, 8'hC1, E);
        send_and_check(S, 1, 0, 8'hC2, E);
        send_and_check(W, 1, 0, 8'hC3, E);
        send_and_check(L, 1, 0, 8'hC4, E);

        // Want output W: dx=-1. Legal sources: N,S,E,L
        send_and_check(N, -1, 0, 8'hD1, W);
        send_and_check(S, -1, 0, 8'hD2, W);
        send_and_check(E, -1, 0, 8'hD3, W);
        send_and_check(L, -1, 0, 8'hD4, W);

        // Want output L (destination reached): dx=0, dy=0. Legal sources: N,S,E,W
        send_and_check(N, 0, 0, 8'hE1, L);
        send_and_check(S, 0, 0, 8'hE2, L);
        send_and_check(E, 0, 0, 8'hE3, L);
        send_and_check(W, 0, 0, 8'hE4, L);

        // Multi-flit packet: Head/Body/Tail from S toward N -- checks
        // wormhole route-holding (Body carries no routing info at all,
        // yet still follows the route established by Head) and that the
        // route genuinely releases after Tail, not just "looks released".
        begin : multi_flit_test
            tests = tests + 1;
            in_valid[S] = 1'b1;
            in_type[2*S +: 2] = HEAD;
            in_dx[DX_W*S +: DX_W] = 0;
            in_dy[DY_W*S +: DY_W] = -1;
            in_data[DATA_W*S +: DATA_W] = 8'h11;
            #1;
            if (!in_ready[S] || !out_valid[N]) begin
                $display("FAIL multi-flit: Head not accepted/routed to N");
                errors = errors + 1;
            end else
                $display("PASS multi-flit: Head routed to N");
            @(posedge clk); #1;

            in_type[2*S +: 2] = BODY;
            in_data[DATA_W*S +: DATA_W] = 8'h22;
            #1;
            if (!in_ready[S] || !out_valid[N] || out_data[DATA_W*N +: DATA_W] !== 8'h22) begin
                $display("FAIL multi-flit: Body not held on route to N");
                errors = errors + 1;
            end else
                $display("PASS multi-flit: Body followed held route to N");
            @(posedge clk); #1;

            in_type[2*S +: 2] = TAIL;
            in_data[DATA_W*S +: DATA_W] = 8'h33;
            #1;
            if (!in_ready[S] || !out_valid[N] || out_data[DATA_W*N +: DATA_W] !== 8'h33) begin
                $display("FAIL multi-flit: Tail not routed to N");
                errors = errors + 1;
            end else
                $display("PASS multi-flit: Tail routed to N, route released");
            @(posedge clk); #1;
            in_valid[S] = 1'b0;

            // Prove the route is genuinely released: S should now be free
            // to start a brand new packet toward a DIFFERENT output (E),
            // not still stuck holding a route to N.
            tests = tests + 1;
            in_valid[S] = 1'b1;
            in_type[2*S +: 2] = HEADTAIL;
            in_dx[DX_W*S +: DX_W] = 1;
            in_dy[DY_W*S +: DY_W] = 0;
            in_data[DATA_W*S +: DATA_W] = 8'h44;
            #1;
            if (!in_ready[S] || !out_valid[E] || out_data[DATA_W*E +: DATA_W] !== 8'h44) begin
                $display("FAIL: route not released after Tail (S still stuck routing to N)");
                errors = errors + 1;
            end else
                $display("PASS: route correctly released, S free to route elsewhere after Tail");
            @(posedge clk); #1;
            in_valid[S] = 1'b0;
            @(posedge clk); #1;
        end

        // Genuine contention: two inputs want the SAME output at the SAME
        // time. This is the one thing the tests above never exercise --
        // everything so far had exactly one flit active, so a fixed-
        // priority arbiter would have passed every test above too.
        //
        // Note: by this point in the test, output N's round-robin pointer
        // has already been advanced repeatedly by earlier tests (every
        // send_and_check aimed at N, plus the multi-flit Head/Body/Tail,
        // all granted N). So this checks the ROTATION INVARIANT -- whoever
        // loses round 1 must win round 2 -- rather than assuming a specific
        // winner, which would be fragile and wrong given that history.
        begin : contention_test
            reg first_winner_is_S;

            tests = tests + 1;
            in_valid[S] = 1'b1;
            in_type[2*S +: 2] = HEADTAIL;
            in_dx[DX_W*S +: DX_W] = 0; in_dy[DY_W*S +: DY_W] = -1;
            in_data[DATA_W*S +: DATA_W] = 8'h55;

            in_valid[E] = 1'b1;
            in_type[2*E +: 2] = HEADTAIL;
            in_dx[DX_W*E +: DX_W] = 0; in_dy[DY_W*E +: DY_W] = -1;
            in_data[DATA_W*E +: DATA_W] = 8'h66;
            #1;
            if (in_ready[S] && !in_ready[E] && out_valid[N] && out_data[DATA_W*N +: DATA_W] === 8'h55) begin
                first_winner_is_S = 1'b1;
                $display("PASS contention round 1: S and E both want N; arbiter picks exactly one (S)");
            end else if (!in_ready[S] && in_ready[E] && out_valid[N] && out_data[DATA_W*N +: DATA_W] === 8'h66) begin
                first_winner_is_S = 1'b0;
                $display("PASS contention round 1: S and E both want N; arbiter picks exactly one (E)");
            end else begin
                $display("FAIL contention round 1: expected exactly one winner, got in_ready[S]=%b in_ready[E]=%b",
                          in_ready[S], in_ready[E]);
                errors = errors + 1;
                first_winner_is_S = 1'b1;
            end
            @(posedge clk); #1;

            // Round 2: the LOSER's original flit is still pending -- it
            // never got in_ready, so a real sender would keep holding it.
            // The WINNER asks again with a brand-new flit at the same
            // moment. A fixed-priority arbiter would let the same input
            // win again; true round-robin must let the previous loser
            // through instead.
            tests = tests + 1;
            if (first_winner_is_S) begin
                in_valid[S] = 1'b0;
                in_valid[S] = 1'b1;
                in_type[2*S +: 2] = HEADTAIL;
                in_dx[DX_W*S +: DX_W] = 0; in_dy[DY_W*S +: DY_W] = -1;
                in_data[DATA_W*S +: DATA_W] = 8'h77;
                #1;
                if (in_ready[E] && !in_ready[S])
                    $display("PASS contention round 2: round-robin rotated to E, no starvation");
                else begin
                    $display("FAIL contention round 2: expected E (previous loser) to win, in_ready[S]=%b in_ready[E]=%b",
                              in_ready[S], in_ready[E]);
                    errors = errors + 1;
                end
            end else begin
                in_valid[E] = 1'b0;
                in_valid[E] = 1'b1;
                in_type[2*E +: 2] = HEADTAIL;
                in_dx[DX_W*E +: DX_W] = 0; in_dy[DY_W*E +: DY_W] = -1;
                in_data[DATA_W*E +: DATA_W] = 8'h77;
                #1;
                if (in_ready[S] && !in_ready[E])
                    $display("PASS contention round 2: round-robin rotated to S, no starvation");
                else begin
                    $display("FAIL contention round 2: expected S (previous loser) to win, in_ready[S]=%b in_ready[E]=%b",
                              in_ready[S], in_ready[E]);
                    errors = errors + 1;
                end
            end
            @(posedge clk); #1;
            in_valid[S] = 1'b0;
            in_valid[E] = 1'b0;
            @(posedge clk); #1;
        end

        $display("----------------------------------------");
        $display("TOTAL: %0d tests, %0d errors", tests, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule