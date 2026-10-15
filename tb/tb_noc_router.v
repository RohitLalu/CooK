// tb_noc_router.v
// Directed tests for noc_router. Compile with a mesh of at least 3x3
// (-DNOC_MESH_X=3 -DNOC_MESH_Y=3, the Makefile does this) so the DUT at
// (1,1) has a real neighbour on all four sides.
//
// Each input port has a flit queue driven with valid/ready; each output has
// a log of every flit that left it. Tests reset the DUT and queues first.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_noc_router;

`include "noc_funcs.vh"

    localparam FW = `NOC_FLIT_W;
    localparam N = 0, S = 1, E = 2, W = 3, L = 4;
    localparam [1:0] BODY = `NOC_T_BODY, HEAD = `NOC_T_HEAD,
                     HEADTAIL = `NOC_T_HEADTAIL, TAIL = `NOC_T_TAIL;
    localparam QD = 32;          // queue depth per input
    localparam LD = 64;          // log depth per output
    localparam PRESC_W = 2, LOCK_LIM = 8, STARVE_LIM = 64;
    localparam LOCK_CYC   = (LOCK_LIM + 2) << PRESC_W;     // comfortably past the limit
    localparam STARVE_CYC = (STARVE_LIM + 2) << PRESC_W;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- DUT ----------------
    wire [4:0]      in_valid, in_ready;
    wire [5*FW-1:0] in_flit;
    wire [4:0]      out_valid;
    reg  [4:0]      out_ready = 5'b11111;
    reg  [4:0]      out_room  = 5'b11111;
    wire [5*FW-1:0] out_flit;
    reg  [4:0]      port_disable = 5'b0;
    reg             err_clear = 1'b0;
    wire [5*`NOC_E_W-1:0] in_err;
    wire [4:0]      out_dead, out_wd;
    wire [7:0]      drop_cnt;
    wire            cap_valid;
    wire [2:0]      cap_port;
    wire [FW-1:0]   cap_flit;

    noc_router #(
        .MY_X(1), .MY_Y(1), .PORT_EXISTS(5'b11111),
        .WD_PRESCALE_W(PRESC_W), .WD_LOCK_LIMIT(LOCK_LIM), .WD_STARVE_LIMIT(STARVE_LIM)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_flit(in_flit),
        .out_valid(out_valid), .out_ready(out_ready), .out_room(out_room), .out_flit(out_flit),
        .port_disable(port_disable), .err_clear(err_clear),
        .in_err(in_err), .out_dead(out_dead), .out_wd(out_wd), .drop_cnt(drop_cnt),
        .cap_valid(cap_valid), .cap_port(cap_port), .cap_flit(cap_flit)
    );

    // ---------------- input queues ----------------
    reg [FW-1:0] q   [0:5*QD-1];
    reg [5:0]    qh  [0:4];
    reg [5:0]    qt  [0:4];
    reg [4:0]    hold = 5'b0;          // freeze a driver (models an upstream stall)

    genvar g;
    generate
        for (g = 0; g < 5; g = g + 1) begin : drv
            assign in_valid[g]          = (qh[g] != qt[g]) && !hold[g];
            assign in_flit[g*FW +: FW]  = q[g*QD + qh[g]];
            always @(posedge clk)
                if (rst_n && in_valid[g] && in_ready[g]) qh[g] <= qh[g] + 1'b1;
        end
    endgenerate

    // ---------------- output logs ----------------
    reg [FW-1:0] lg [0:5*LD-1];
    integer      lc [0:4];
    integer      mo;
    always @(posedge clk) begin
        if (rst_n)
            for (mo = 0; mo < 5; mo = mo + 1)
                if (out_valid[mo] && out_ready[mo]) begin
                    lg[mo*LD + lc[mo]] <= out_flit[mo*FW +: FW];
                    lc[mo] = lc[mo] + 1;
                end
    end

    integer errors = 0;
    integer checks = 0;
    integer tnum = 0;
    integer i, j, k;

    task check;
        input cond;
        input [8*72-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL [test %0d]: %0s", tnum, msg);
            end
        end
    endtask

    integer r;
    task reset_all;
        begin
            @(negedge clk);
            rst_n = 0;
            hold = 5'b0; out_ready = 5'b11111; out_room = 5'b11111; port_disable = 5'b0;
            for (r = 0; r < 5; r = r + 1) begin qh[r] = 0; qt[r] = 0; lc[r] = 0; end
            repeat (2) @(negedge clk);
            rst_n = 1;
        end
    endtask

    task push;
        input [2:0]    port;
        input [FW-1:0] f;
        begin
            q[port*QD + qt[port]] = f;
            qt[port] = qt[port] + 1;
        end
    endtask

    task run;
        input integer cycles;
        begin
            repeat (cycles) @(negedge clk);
        end
    endtask

    // flit builders. dst given as an output direction from (1,1).
    function [`NOC_X_W-1:0] dx_of; input [2:0] o;
        begin dx_of = (o == E) ? 2 : (o == W) ? 0 : 1; end endfunction
    function [`NOC_Y_W-1:0] dy_of; input [2:0] o;
        begin dy_of = (o == S) ? 2 : (o == N) ? 0 : 1; end endfunction

    function [FW-1:0] mk;
        input [1:0]  t;
        input [3:0]  src;
        input [2:0]  to;
        input [31:0] data;
        begin
            mk = noc_make_flit(t, 1'b0, src[`NOC_ID_W-1:0], dx_of(to), dy_of(to), data);
        end
    endfunction

    function [FW-1:0] poison_of;
        input [3:0] src;
        input [2:0] to;
        begin
            poison_of = noc_make_flit(TAIL, 1'b1, src[`NOC_ID_W-1:0], dx_of(to), dy_of(to),
                                      `NOC_POISON_DATA);
        end
    endfunction

    function err_bit;
        input [2:0] port;
        input integer bitn;
        begin
            err_bit = in_err[port*`NOC_E_W + bitn];
        end
    endfunction

    reg [FW-1:0] fa, fb;

    initial begin
        for (i = 0; i < 5; i = i + 1) begin qh[i] = 0; qt[i] = 0; lc[i] = 0; end

        // ------------------------------------------------------------
        tnum = 1;
        $display("=== 1. X-Y routing on absolute coordinates, all 20 port pairs ===");
        for (i = 0; i < 5; i = i + 1) begin
            for (j = 0; j < 5; j = j + 1) begin
                if (i != j) begin
                    reset_all;
                    fa = mk(HEADTAIL, i, j, 32'hC000_0000 + i*16 + j);
                    push(i, fa);
                    run(3);
                    check(lc[j] == 1 && lg[j*LD] == fa, "HEADTAIL left on the X-Y output, unmodified");
                    for (k = 0; k < 5; k = k + 1)
                        if (k != j) check(lc[k] == 0, "no other output fired");
                end
            end
        end

        // ------------------------------------------------------------
        tnum = 2;
        $display("=== 2. output lock: two packets to one output never interleave ===");
        reset_all;
        push(W, mk(HEAD, 1, E, 32'h1111_0000)); push(W, mk(TAIL, 1, E, 32'h1111_0001));
        push(L, mk(HEAD, 2, E, 32'h2222_0000)); push(L, mk(TAIL, 2, E, 32'h2222_0001));
        run(8);
        check(lc[E] == 4, "four flits left E");
        check(lg[E*LD+0][`NOC_F_TYPE_LSB +: 2] == HEAD && lg[E*LD+1][`NOC_F_TYPE_LSB +: 2] == TAIL &&
              lg[E*LD+2][`NOC_F_TYPE_LSB +: 2] == HEAD && lg[E*LD+3][`NOC_F_TYPE_LSB +: 2] == TAIL,
              "E carried HEAD,TAIL,HEAD,TAIL");
        check(lg[E*LD+0][`NOC_F_SRC_LSB +: `NOC_ID_W] == lg[E*LD+1][`NOC_F_SRC_LSB +: `NOC_ID_W] &&
              lg[E*LD+2][`NOC_F_SRC_LSB +: `NOC_ID_W] == lg[E*LD+3][`NOC_F_SRC_LSB +: `NOC_ID_W],
              "each TAIL follows its own HEAD");

        $display("=== 2b. four 4-flit packets from four inputs into one output ===");
        reset_all;
        for (i = 0; i < 4; i = i + 1) begin
            k = (i == 0) ? N : (i == 1) ? S : (i == 2) ? W : L;
            push(k, mk(HEAD, k, E, 32'h0));
            push(k, mk(BODY, k, E, 32'h1));
            push(k, mk(BODY, k, E, 32'h2));
            push(k, mk(TAIL, k, E, 32'h3));
        end
        run(30);
        check(lc[E] == 16, "all 16 flits left E");
        for (i = 0; i < 4; i = i + 1) begin
            check(lg[E*LD+4*i][`NOC_F_TYPE_LSB +: 2] == HEAD, "packet starts with HEAD");
            check(lg[E*LD+4*i+3][`NOC_F_TYPE_LSB +: 2] == TAIL, "packet ends with TAIL");
            for (j = 1; j < 4; j = j + 1)
                check(lg[E*LD+4*i+j][`NOC_F_SRC_LSB +: `NOC_ID_W] ==
                      lg[E*LD+4*i][`NOC_F_SRC_LSB +: `NOC_ID_W], "no foreign flit inside a packet");
        end

        $display("=== 2c. other outputs keep flowing while one is locked ===");
        reset_all;
        hold[W] = 1'b0;
        push(W, mk(HEAD, 1, E, 32'h0));            // TAIL withheld below
        run(2);
        hold[W] = 1'b1;
        push(W, mk(TAIL, 1, E, 32'h1));
        push(L, mk(HEADTAIL, 2, N, 32'h5));
        push(S, mk(HEADTAIL, 3, E, 32'h6));        // must wait: E is locked
        run(4);
        check(lc[N] == 1, "N served while E is locked");
        check(lc[E] == 1, "E still holds only the first HEAD");
        hold[W] = 1'b0;
        run(4);
        check(lc[E] == 3 && lg[E*LD+1][`NOC_F_TYPE_LSB +: 2] == TAIL &&
              lg[E*LD+2][`NOC_F_DATA_LSB +: 32] == 32'h6, "waiting HEADTAIL goes after the TAIL");

        // ------------------------------------------------------------
        tnum = 3;
        $display("=== 3. whole-packet admission: no room, no HEAD ===");
        reset_all;
        out_room[E] = 1'b0;
        push(W, mk(HEAD, 1, E, 32'h0)); push(W, mk(TAIL, 1, E, 32'h1));
        run(5);
        check(lc[E] == 0, "HEAD held while downstream lacks room");
        out_room[E] = 1'b1;
        run(4);
        check(lc[E] == 2, "packet admitted once room appears");
        reset_all;
        push(W, mk(HEAD, 1, E, 32'h0)); push(W, mk(TAIL, 1, E, 32'h1));
        run(1);
        out_room[E] = 1'b0;      // room drops after the HEAD: the TAIL must still pass
        run(4);
        check(lc[E] == 2, "room only gates HEADs, not the rest of an admitted packet");

        // ------------------------------------------------------------
        tnum = 4;
        $display("=== 4. same-cycle drops: U-turn, orphan, bad check bits ===");
        reset_all;
        push(E, mk(HEADTAIL, 1, E, 32'h0));       // came from E, wants E
        run(3);
        check(lc[E] == 0 && err_bit(E, `NOC_E_ROUTE), "U-turn dropped, E_ROUTE set on E");
        reset_all;
        push(S, mk(TAIL, 1, N, 32'h0));
        push(S, mk(BODY, 1, N, 32'h0));
        run(3);
        check(lc[N] == 0 && err_bit(S, `NOC_E_ORPHAN), "orphan TAIL/BODY dropped, E_ORPHAN set");
        check(qh[S] == qt[S], "orphans were consumed, not left blocking");
        reset_all;
        fa = mk(HEAD, 1, E, 32'h0);
        fa[3] = ~fa[3];                           // corrupt a data bit
        push(W, fa); push(W, mk(TAIL, 1, E, 32'h1));
        push(W, mk(HEADTAIL, 1, E, 32'h77));      // next packet must still get through
        run(5);
        check(err_bit(W, `NOC_E_CHK), "corrupted HEAD flagged E_CHK");
        check(err_bit(W, `NOC_E_ORPHAN), "its TAIL drained as an orphan");
        check(lc[E] == 1 && lg[E*LD][`NOC_F_DATA_LSB +: 32] == 32'h77, "only the clean packet left E");
        check(cap_valid && cap_port == W && cap_flit == fa, "capture register holds the bad HEAD");
        check(drop_cnt == 2, "two drop events counted");

        // ------------------------------------------------------------
        tnum = 5;
        $display("=== 5. mid-packet faults become poison TAILs ===");
        reset_all;
        fb = mk(TAIL, 1, E, 32'h1);
        fb[5] = ~fb[5];
        push(W, mk(HEAD, 1, E, 32'h0)); push(W, fb);
        push(W, mk(HEADTAIL, 1, E, 32'h88));
        run(6);
        check(lc[E] == 3, "HEAD, poison TAIL, next packet");
        check(lg[E*LD+1] == poison_of(1, E), "bad TAIL replaced by a sealed poison TAIL");
        check(noc_chk_ok(lg[E*LD+1]), "poison TAIL has valid check bits");
        check(err_bit(W, `NOC_E_CHK), "E_CHK set");
        check(lg[E*LD+2][`NOC_F_DATA_LSB +: 32] == 32'h88, "route released after the poison TAIL");

        reset_all;
        push(W, mk(HEAD, 1, E, 32'h0));
        push(W, mk(BODY, 2, E, 32'h1));           // source tag changed mid-packet
        push(W, mk(TAIL, 1, E, 32'h2));
        run(6);
        check(lc[E] == 2 && lg[E*LD+1] == poison_of(1, E), "source change closed the packet with poison");
        check(err_bit(W, `NOC_E_PROTO) && err_bit(W, `NOC_E_ORPHAN), "E_PROTO, then the rest drained");

        reset_all;
        push(W, mk(HEAD, 1, E, 32'h0));
        push(W, mk(HEAD, 1, N, 32'h10));          // previous TAIL lost
        push(W, mk(TAIL, 1, N, 32'h11));
        run(6);
        check(lc[E] == 2 && lg[E*LD+1] == poison_of(1, E), "old packet closed with poison on E");
        check(lc[N] == 2 && lg[N*LD][`NOC_F_DATA_LSB +: 32] == 32'h10, "new packet kept and routed to N");
        check(err_bit(W, `NOC_E_PROTO), "E_PROTO set");

        // ------------------------------------------------------------
        tnum = 6;
        $display("=== 6. watchdog: upstream stalls mid-packet -> poison TAIL ===");
        reset_all;
        push(W, mk(HEAD, 1, E, 32'h0));
        run(2);
        hold[W] = 1'b1;
        push(W, mk(TAIL, 1, E, 32'h1));
        run(LOCK_CYC);
        check(lc[E] == 2 && lg[E*LD+1] == poison_of(1, E), "watchdog emitted a poison TAIL");
        check(out_wd[E] && !out_dead[E], "out_wd set, output not dead (downstream was fine)");
        hold[W] = 1'b0;
        run(3);
        check(lc[E] == 2 && err_bit(W, `NOC_E_ORPHAN), "late TAIL drained as orphan");

        tnum = 7;
        $display("=== 7. watchdog: downstream stuck while locked -> output dead ===");
        reset_all;
        push(W, mk(HEAD, 1, N, 32'h0)); push(W, mk(TAIL, 1, N, 32'h1));
        @(posedge clk); #1;
        out_ready[N] = 1'b0;                      // HEAD went, TAIL now stuck
        run(LOCK_CYC);
        check(out_dead[N] && out_wd[N], "N declared dead");
        out_ready[N] = 1'b1;
        push(L, mk(HEADTAIL, 2, N, 32'h0));
        run(3);
        check(err_bit(L, `NOC_E_ROUTE), "new HEAD to dead N dropped with E_ROUTE");

        tnum = 8;
        $display("=== 8. watchdog: HEAD never admitted -> output dead ===");
        reset_all;
        out_room[S] = 1'b0;
        push(E, mk(HEAD, 1, S, 32'h0)); push(E, mk(TAIL, 1, S, 32'h1));
        run(STARVE_CYC);
        check(out_dead[S], "S declared dead after starvation limit");
        run(3);
        check(qh[E] == qt[E] && err_bit(E, `NOC_E_ROUTE) && lc[S] == 0, "waiting packet dropped, nothing sent");
        reset_all;
        out_room[S] = 1'b0;
        push(E, mk(HEAD, 1, S, 32'h0));
        run(STARVE_CYC / 2);
        out_room[S] = 1'b1;
        run(3);
        check(!out_dead[S] && lc[S] == 1, "shorter congestion is not a fault");

        // ------------------------------------------------------------
        tnum = 9;
        $display("=== 9. port_disable and err_clear ===");
        reset_all;
        port_disable[E] = 1'b1;
        push(W, mk(HEADTAIL, 1, E, 32'h0));
        run(3);
        check(lc[E] == 0 && err_bit(W, `NOC_E_ROUTE), "disabled port refuses traffic");
        port_disable[E] = 1'b0;
        @(negedge clk); err_clear = 1'b1;
        @(negedge clk); err_clear = 1'b0;
        check(in_err == 0 && drop_cnt == 0 && !cap_valid, "err_clear wipes sticky state");
        push(W, mk(HEADTAIL, 1, E, 32'h1));
        run(3);
        check(lc[E] == 1, "re-enabled port carries traffic");

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
