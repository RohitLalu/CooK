// tb_status_panel.v
// Checks the board status panel: blink counts per code and tile, priority
// between simultaneous errors, display value and per-tile flags.
// Uses tiny timing parameters so a blink frame is a few dozen cycles.
// Assumes the default 2x2 knobs (4 tiles).

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_status_panel;

    localparam NT = `NOC_NUM_TILES;
    localparam UNIT = 4, GAP = 6;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg [NT-1:0]             tile_trap = 0;
    reg [NT*5-1:0]           tile_err  = 0;
    reg [NT*32-1:0]          tile_sw   = 0;
    reg [NT*5*`NOC_E_W-1:0]  rt_in_err = 0;
    reg [NT*5-1:0]           rt_out_dead = 0, rt_out_wd = 0;
    // healthy 2x2 BIST status: every existing port passes ({L,W,E,S,N} per tile)
    localparam [NT*10-1:0] BIST_OK = {{2{5'b11001}}, {2{5'b10101}}, {2{5'b11010}}, {2{5'b10110}}};
    reg [NT*10-1:0]          bist_status = BIST_OK;
    reg                      bist_done = 1;
    reg [2:0]                gw_flags = 0;
    reg [31:0]               gw_info = 0;
    wire code_led, tile_led, heartbeat;
    wire [NT-1:0] tile_bad, tile_pass, tile_fail;
    wire [31:0] display;

    status_panel #(.UNIT_CYCLES(UNIT), .GAP_UNITS(GAP), .HEART_CYCLES(10), .GW_TILE(3)) dut (
        .clk(clk), .rst_n(rst_n),
        .tile_trap(tile_trap), .tile_err(tile_err), .tile_sw(tile_sw),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead), .rt_out_wd(rt_out_wd),
        .bist_status(bist_status), .bist_done(bist_done), .gw_flags(gw_flags), .gw_info(gw_info),
        .code_led(code_led), .tile_led(tile_led), .heartbeat(heartbeat),
        .tile_bad(tile_bad), .tile_pass(tile_pass), .tile_fail(tile_fail),
        .display(display), .cur_code(), .cur_tile()
    );

    integer errors = 0, checks = 0;
    integer nc, nt, n, len;
    reg pc, pt;

    task check;
        input cond;
        input [8*72-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
        end
    endtask

    task wait_frame;   // until the first cycle of a new frame
        begin
            @(posedge clk);
            while (!(dut.unit_idx == 0 && dut.unit_cnt == 0)) @(posedge clk);
        end
    endtask

    // count blinks on both LEDs over one whole frame
    task measure;
        begin
            wait_frame;            // this frame may still show the old state
            wait_frame;            // this one shows the new state from its start
            // the LEDs are registered one cycle behind the frame counter, so
            // the frame's last cycle already shows the next frame's first blink
            len = dut.frame_len * UNIT - 1;
            nc = 0; nt = 0; pc = 0; pt = 0;
            for (n = 0; n < len; n = n + 1) begin
                @(posedge clk); #1;
                if (code_led && !pc) nc = nc + 1;
                if (tile_led && !pt) nt = nt + 1;
                pc = code_led; pt = tile_led;
            end
        end
    endtask

    task expect_code;
        input integer code, tile;
        input [8*40-1:0] what;
        begin
            measure;
            check(nc == code, what);
            check(nt == ((code == 0) ? 0 : tile + 1), what);
            check(display[31:28] == code && display[27:20] == ((code == 0) ? 0 : tile), what);
            if (nc != code || nt != ((code == 0) ? 0 : tile + 1))
                $display("      %0s: code blinks %0d (want %0d), tile blinks %0d", what, nc, code, nt);
        end
    endtask

    task clear_all;
        begin
            tile_trap = 0; tile_err = 0; tile_sw = 0; rt_in_err = 0; rt_out_dead = 0; rt_out_wd = 0;
            bist_status = BIST_OK; gw_flags = 0; gw_info = 0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;

        expect_code(0, 0, "healthy: both LEDs dark");

        clear_all; tile_trap[2] = 1;
        expect_code(1, 2, "trap on tile 2");

        tile_err[1*5 + 0] = 1;       // timeout on tile 1, trap still on tile 2
        expect_code(1, 2, "trap outranks timeout");

        clear_all; tile_err[1*5 + 0] = 1;
        expect_code(2, 1, "timeout on tile 1");

        clear_all; tile_err[0*5 + 4] = 1;
        expect_code(3, 0, "check-bit error on tile 0");

        clear_all; rt_out_dead[3*5 + 1] = 1;
        expect_code(6, 3, "dead router output on tile 3");

        clear_all; rt_in_err[2*5*`NOC_E_W + 7] = 1;
        expect_code(8, 2, "router input error on tile 2");

        clear_all; tile_sw[1*32 +: 32] = 32'hFA11_0007;
        expect_code(9, 1, "software failure on tile 1");
        check(display[15:0] == 16'h0007, "display shows that tile's status low half");
        check(tile_fail == 4'b0010 && tile_bad == 4'b0010, "fail and bad flags on tile 1");

        clear_all; tile_err[0*5 + 1] = 1;
        expect_code(10, 0, "illegal address on tile 0 (lowest priority)");

        $display("--- new codes B-E ---");
        clear_all; bist_status[1*10 + `NOC_P_S] = 1'b0;          // router 1 outlink S failed
        tile_err[0*5 + 0] = 1;                                   // ...and the timeout it causes
        expect_code(14, 1, "BIST fault outranks the timeout it causes");
        check(display[15:0] == {6'b0, bist_status[1*10 +: 10]}, "display shows router 1's in/out bits");
        clear_all; bist_status[0*10 + `NOC_P_N] = 1'b0;          // absent port (edge): not a fault
        expect_code(0, 0, "absent edge port at 0 is not a BIST fault");
        clear_all; gw_flags = 3'b100; gw_info = 32'h0050_0000;
        expect_code(11, 3, "DMA engine error on the gateway tile");
        check(display[15:0] == 16'h0005, "display shows the DMA error bits");
        clear_all; gw_flags = 3'b001; gw_info = 32'h0000_0012;   // tile 1, reason 2 (zone)
        expect_code(12, 3, "DMA request refused");
        check(display[15:0] == 16'h0102, "display shows refused tile 1, reason 2");
        clear_all; gw_flags = 3'b010; gw_info = 32'h0000_2000;   // tile 2 lost the lock
        expect_code(13, 3, "lock lease expired");
        check(display[15:0] == 16'h0200, "display shows the tile that lost the lock");
        clear_all; gw_flags = 3'b001; tile_sw[0*32 +: 32] = 32'hFA11_0001;
        expect_code(9, 0, "software failure outranks a refused request");

        clear_all; tile_sw = {4{32'h600D_00DE}};
        expect_code(0, 0, "all tiles passing: dark");
        check(tile_pass == 4'b1111 && tile_bad == 0, "pass flags on every tile");
        check(display == 32'h0000_00DE, "display shows tile 0's check count");

        check(heartbeat === 1'b0 || heartbeat === 1'b1, "heartbeat driven");

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
