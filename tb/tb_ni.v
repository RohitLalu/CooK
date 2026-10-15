// tb_ni.v
// Unit test for the network interface, with the core side and the network
// side both driven by the testbench. Covers the paths the mesh tests cannot
// reach on demand: tag matching, stale responses, retry that succeeds,
// retries exhausted, poison TAILs, check-bit errors, response-queue fill and
// backpressure, response priority, remote CSR access and byte strobes.
// Assumes the default 2x2 knobs. DUT is tile 1 = (1,0).

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_ni;

`include "noc_funcs.vh"

    localparam FW = `NOC_FLIT_W;
    localparam IW = `NOC_ID_W;
    localparam TW = `NOC_TAG_W;
    localparam [1:0] HEAD = `NOC_T_HEAD, TAIL = `NOC_T_TAIL, HEADTAIL = `NOC_T_HEADTAIL;
    localparam MY = 1;
    localparam TMO = 40, RETRIES = 2, QD = 4;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- core side ----------------
    reg         mem_valid = 0;
    reg  [31:0] mem_addr = 0, mem_wdata = 0;
    reg  [3:0]  mem_wstrb = 0;
    wire        mem_ready;
    wire [31:0] mem_rdata;
    reg         core_done = 0;
    reg  [31:0] core_rdata = 0;

    // ---------------- network side ----------------
    reg           in_valid_r = 0;
    wire          in_valid;
    wire          in_ready, in_room;
    wire [FW-1:0] in_flit;
    wire          out_valid;
    reg           out_ready = 1;
    wire [FW-1:0] out_flit;
    wire [4:0]    err_flags;
    wire [31:0]   sw_status;

    ni #(.MY_ID(MY), .TIMEOUT_CYCLES(TMO), .RETRY_MAX(RETRIES), .RSP_Q_DEPTH(QD)) dut (
        .clk(clk), .rst_n(rst_n),
        .mem_valid(mem_valid), .mem_instr(1'b0), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .in_valid(in_valid), .in_ready(in_ready), .in_room(in_room), .in_flit(in_flit),
        .out_valid(out_valid), .out_ready(out_ready), .out_flit(out_flit),
        .err_flags(err_flags), .sw_status(sw_status)
    );

    // core model: like picorv32, hold mem_valid until mem_ready
    always @(posedge clk)
        if (mem_valid && mem_ready) begin
            mem_valid  <= 1'b0;
            core_rdata <= mem_rdata;
            core_done  <= 1'b1;
        end

    // network input queue
    reg [FW-1:0] iq [0:63];
    integer      ih = 0, it = 0;
    assign in_valid = (ih != it);
    assign in_flit  = iq[ih];
    always @(posedge clk)
        if (rst_n && in_valid && in_ready) ih <= ih + 1;

    // network output log
    reg [FW-1:0] oq [0:63];
    integer      oc = 0;
    always @(posedge clk)
        if (rst_n && out_valid && out_ready) begin
            oq[oc] <= out_flit;
            oc = oc + 1;
        end

    integer errors = 0, checks = 0, tnum = 0;
    integer i, base;

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

    task reset_all;
        begin
            @(negedge clk);
            rst_n = 0; mem_valid = 0; out_ready = 1; ih = 0; it = 0; oc = 0;
            repeat (2) @(negedge clk);
            rst_n = 1;
            @(negedge clk);
        end
    endtask

    task run;
        input integer n;
        begin repeat (n) @(negedge clk); end
    endtask

    task core_start;
        input [31:0] a, d;
        input [3:0]  s;
        begin
            @(negedge clk);
            mem_addr = a; mem_wdata = d; mem_wstrb = s;
            core_done = 0; mem_valid = 1;
        end
    endtask

    task core_wait;
        input integer limit;
        integer n;
        begin
            n = 0;
            while (!core_done && n < limit) begin @(negedge clk); n = n + 1; end
        end
    endtask

    task core_rd;      // blocking local/remote read
        input [31:0] a;
        begin core_start(a, 0, 4'b0); core_wait(5000); end
    endtask

    task core_wr;
        input [31:0] a, d;
        input [3:0]  s;
        begin core_start(a, d, s); core_wait(5000); end
    endtask

    function [31:0] hdr;
        input [11:0] off;
        input        wr, rsp;
        input [3:0]  strb;
        input [TW-1:0] tag;
        begin
            hdr = 32'b0;
            hdr[`NOC_H_OFF_LSB +: 12]        = off;
            hdr[`NOC_H_WR]                   = wr;
            hdr[`NOC_H_RSP]                  = rsp;
            hdr[`NOC_H_WSTRB_LSB +: 4]       = strb;
            hdr[`NOC_H_LEN_LSB +: `NOC_LEN_W] = 1;
            hdr[`NOC_H_TAG_LSB +: TW]        = tag;
        end
    endfunction

    // queue a two-flit packet from tile `src` to the DUT
    task send_pkt;
        input [IW-1:0] src;
        input [31:0]   h, d;
        input          poison_tail;
        begin
            iq[it] = noc_make_flit(HEAD, 1'b0, src, noc_id_x(MY), noc_id_y(MY), h); it = it + 1;
            iq[it] = noc_make_flit(TAIL, poison_tail, src, noc_id_x(MY), noc_id_y(MY), d); it = it + 1;
        end
    endtask

    // field accessors for logged output flits
    function [1:0]    f_type; input [FW-1:0] f; f_type = f[`NOC_F_TYPE_LSB +: 2]; endfunction
    function [IW-1:0] f_src;  input [FW-1:0] f; f_src  = f[`NOC_F_SRC_LSB +: IW]; endfunction
    function [31:0]   f_data; input [FW-1:0] f; f_data = f[`NOC_F_DATA_LSB +: 32]; endfunction
    function [`NOC_X_W-1:0] f_dx; input [FW-1:0] f; f_dx = f[`NOC_F_DSTX_LSB +: `NOC_X_W]; endfunction
    function [`NOC_Y_W-1:0] f_dy; input [FW-1:0] f; f_dy = f[`NOC_F_DSTY_LSB +: `NOC_Y_W]; endfunction
    function [TW-1:0] h_tag;  input [FW-1:0] f; h_tag  = f[`NOC_F_DATA_LSB + `NOC_H_TAG_LSB +: TW]; endfunction

    reg [TW-1:0] tg;

    initial begin
        // ------------------------------------------------------------
        tnum = 1;
        $display("=== 1. local CSRs and local memory with byte strobes ===");
        reset_all;
        core_rd(32'h0000_1000); check(core_rdata == MY, "tile ID CSR");
        core_rd(32'h0000_100C); check(core_rdata == `NOC_NUM_TILES, "tile-count CSR");
        core_rd(32'h0000_1004); check(core_rdata == 0, "error CSR clear after reset");
        core_wr(32'h0000_1008, 32'h1234_5678, 4'b1111);
        core_wr(32'h0000_1008, 32'h0000_AB00, 4'b0010);
        core_rd(32'h0000_1008); check(core_rdata == 32'h1234_AB78 && sw_status == 32'h1234_AB78,
                                      "software status CSR honours byte strobes");
        core_wr(32'h0000_1200, 32'hDEAD_BEEF, 4'b1111);
        core_wr(32'h0000_1200, 32'h0011_0000, 4'b0100);
        core_rd(32'h0000_1200); check(core_rdata == 32'hDE11_BEEF, "local RAM byte write");
        check(oc == 0, "local accesses never touch the network");
        core_rd(32'hFFFF_F000); check(core_rdata == `NOC_POISON_DATA && err_flags[1], "illegal address: POISON + flag");
        core_wr(32'h0000_1004, 32'h2, 4'b1111);
        check(err_flags == 0, "error flag cleared by write-1");

        // ------------------------------------------------------------
        tnum = 2;
        $display("=== 2. remote read: request format and matching response ===");
        reset_all;
        core_start(32'h0000_3010, 0, 4'b0);
        run(6);
        check(oc == 2, "request sent as two flits");
        check(f_type(oq[0]) == HEAD && f_type(oq[1]) == TAIL, "HEAD then TAIL");
        check(noc_chk_ok(oq[0]) && noc_chk_ok(oq[1]), "check bits valid");
        check(f_src(oq[0]) == MY && f_dx(oq[0]) == 1 && f_dy(oq[0]) == 1, "src = me, dst = tile 3 (1,1)");
        check(f_data(oq[0]) == hdr(12'h010, 0, 0, 4'b0, 1), "header: offset, read, tag 1");
        send_pkt(3, hdr(12'h010, 0, 1, 4'b0, 1), 32'hCAFE_F00D, 1'b0);
        core_wait(50);
        check(core_done && core_rdata == 32'hCAFE_F00D, "core received the response data");
        check(err_flags == 0, "no errors");

        // ------------------------------------------------------------
        tnum = 3;
        $display("=== 3. stale tag, wrong source and poison are rejected ===");
        reset_all;
        core_start(32'h0000_3010, 0, 4'b0);
        run(6);
        tg = h_tag(oq[0]);
        send_pkt(3, hdr(12'h010, 0, 1, 4'b0, tg + 1'b1), 32'h1111_1111, 1'b0);  // wrong tag
        send_pkt(2, hdr(12'h010, 0, 1, 4'b0, tg), 32'h2222_2222, 1'b0);         // wrong source
        run(10);
        check(!core_done && err_flags[3], "wrong tag / wrong source discarded as stale");
        send_pkt(3, hdr(12'h010, 0, 1, 4'b0, tg), 32'h3333_3333, 1'b1);         // poison TAIL
        run(6);
        check(!core_done && err_flags[2], "poison TAIL discarded and flagged");
        send_pkt(3, hdr(12'h010, 0, 1, 4'b0, tg), 32'h4444_4444, 1'b0);
        core_wait(20);
        check(core_done && core_rdata == 32'h4444_4444, "correct response still accepted afterwards");

        // ------------------------------------------------------------
        tnum = 4;
        $display("=== 4. check-bit error on a received flit ===");
        reset_all;
        iq[it] = noc_make_flit(HEAD, 1'b0, 2, noc_id_x(MY), noc_id_y(MY), hdr(12'h200, 1, 0, 4'hF, 0));
        iq[it][7] = ~iq[it][7]; it = it + 1;
        iq[it] = noc_make_flit(TAIL, 1'b0, 2, noc_id_x(MY), noc_id_y(MY), 32'h5555_5555); it = it + 1;
        run(6);
        check(err_flags[4], "check-bit error flagged");
        core_rd(32'h0000_1200);
        check(core_rdata !== 32'h5555_5555, "corrupted write did not land");

        // ------------------------------------------------------------
        tnum = 5;
        $display("=== 5. retry succeeds after a lost request ===");
        reset_all;
        core_start(32'h0000_2020, 0, 4'b0);
        run(TMO + 10);
        check(oc == 4, "first attempt timed out and was resent");
        check(h_tag(oq[2]) == h_tag(oq[0]) + 1'b1, "resend carries a new tag");
        send_pkt(2, hdr(12'h020, 0, 1, 4'b0, h_tag(oq[0])), 32'hBAD0_BAD0, 1'b0);  // late answer, old tag
        run(6);
        check(!core_done && err_flags[3], "answer to the abandoned attempt is stale");
        send_pkt(2, hdr(12'h020, 0, 1, 4'b0, h_tag(oq[2])), 32'h600D_600D, 1'b0);
        core_wait(20);
        check(core_done && core_rdata == 32'h600D_600D, "retry's answer accepted");
        check(!err_flags[0], "no timeout flag when a retry succeeds");

        // ------------------------------------------------------------
        tnum = 6;
        $display("=== 6. retries exhausted -> POISON ===");
        reset_all;
        core_start(32'h0000_2020, 0, 4'b0);
        core_wait((RETRIES + 1) * (TMO + 10) + 20);
        check(core_done && core_rdata == `NOC_POISON_DATA, "core got POISON");
        check(err_flags[0], "timeout flag set");
        check(oc == 2 * (RETRIES + 1), "one request plus RETRY_MAX resends");

        // ------------------------------------------------------------
        tnum = 7;
        $display("=== 7. remote write with byte strobes, remote reads of RAM and CSRs ===");
        reset_all;
        send_pkt(0, hdr(12'h300, 1, 0, 4'b1111, 0), 32'hA1B2_C3D4, 1'b0);
        send_pkt(2, hdr(12'h300, 1, 0, 4'b0101, 0), 32'h00EE_00FF, 1'b0);
        send_pkt(3, hdr(12'h008, 1, 0, 4'b1111, 0), 32'h0000_0042, 1'b0);   // remote sw status
        run(12);
        core_rd(32'h0000_1300);
        check(core_rdata == 32'hA1EE_C3FF, "remote byte-strobed writes merged");
        check(sw_status == 32'h42, "remote write reached the software status CSR");
        base = oc;
        send_pkt(0, hdr(12'h300, 0, 0, 4'b0, 2), 32'h0, 1'b0);
        send_pkt(3, hdr(12'h000, 0, 0, 4'b0, 3), 32'h0, 1'b0);
        run(20);
        check(oc == base + 4, "two responses sent");
        check(f_data(oq[base]) == hdr(12'h300, 0, 1, 4'b0, 2) && f_dx(oq[base]) == 0 && f_dy(oq[base]) == 0,
              "RAM response: to tile 0, is_resp, offset and tag echoed");
        check(f_data(oq[base+1]) == 32'hA1EE_C3FF, "RAM response data");
        check(f_dx(oq[base+2]) == 1 && f_dy(oq[base+2]) == 1 && h_tag(oq[base+2]) == 3 &&
              f_data(oq[base+3]) == MY, "CSR response to tile 3 carries my ID");

        // ------------------------------------------------------------
        tnum = 8;
        $display("=== 8. response queue fills, then backpressure, nothing lost ===");
        reset_all;
        out_ready = 0;
        // capacity = QD queued + 1 held by the TX engine + 1 in the receive
        // register; one more request must be refused
        for (i = 0; i < QD + 3; i = i + 1)
            send_pkt(i % 4, hdr(12'h000, 0, 0, 4'b0, i), 32'h0, 1'b0);
        run(40);
        check(oc == 0, "nothing sent while the network refuses");
        check(it - ih == 2, "receive side stopped accepting once the queue was full");
        check(!in_ready && !in_room, "in_ready and in_room low under backpressure");
        out_ready = 1;
        run(60);
        check(oc == 2 * (QD + 3), "every queued and held request answered");
        for (i = 0; i < QD + 3; i = i + 1)
            check(h_tag(oq[2*i]) == i[TW-1:0], "responses leave in arrival order");

        // ------------------------------------------------------------
        tnum = 9;
        $display("=== 9. owed responses go out before the core's own request ===");
        reset_all;
        out_ready = 0;
        send_pkt(3, hdr(12'h000, 0, 0, 4'b0, 1), 32'h0, 1'b0);
        run(6);
        core_start(32'h0000_0010, 0, 4'b0);
        run(4);
        out_ready = 1;
        run(10);
        check(oc >= 4 && oq[0][`NOC_F_DATA_LSB + `NOC_H_RSP] == 1'b1 &&
              oq[2][`NOC_F_DATA_LSB + `NOC_H_RSP] == 1'b0, "response first, then the request");

        // ------------------------------------------------------------
        tnum = 10;
        $display("=== 10. posted remote write: core is released at once ===");
        reset_all;
        core_start(32'h0000_0204, 32'h7777_7777, 4'b1111);
        core_wait(10);
        check(core_done, "core acked without waiting for the network");
        run(4);
        check(oc == 2 && oq[0][`NOC_F_DATA_LSB + `NOC_H_WR] && f_data(oq[1]) == 32'h7777_7777,
              "write request sent with data");

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
