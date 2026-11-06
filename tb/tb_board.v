// tb_board.v
// Simulates the whole Nexys4 DDR top exactly as it will be built for the
// board: programs come from the tileNN.mem init files (not testbench
// loading), reset goes through reset_sync, and the result is read only from
// the LEDs and the 7-segment display. In simulation the MMCM is bypassed.
// Every tile runs alltoall.S (sw/build.sh FPGA_PROG default).

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_board;

    // FAULT_SW = 0: healthy. Otherwise the value on the slide switches, e.g.
    // 16'h1005 = SW[12] on, silent, link 5 (tile 1 south).
    parameter [15:0] FAULT_SW = 16'h0000;

    reg  CLK100MHZ = 0;
    reg  CPU_RESETN = 0;
    reg  BTNC = 0;
    wire [15:0] SW = FAULT_SW;
    wire LED17_R;
    wire [15:0] LED;
    wire [6:0]  SEG;
    wire        DP;
    wire [7:0]  AN;
    always #5 CLK100MHZ = ~CLK100MHZ;

`ifdef XILINX_SIMULATOR
    localparam PREFIX = "../../../../../sw/tile";
`else
    localparam PREFIX = "sw/tile";
`endif

    nexys4ddr_top #(
        .MEM_PREFIX(PREFIX),
        .UNIT_CYCLES(8), .HEART_CYCLES(20), .REFRESH_CYCLES(4),
        .GATEWAY(0)     // the MIG has no simulation model; see tb_gw_dma_ip.v
    ) dut (
        .CLK100MHZ(CLK100MHZ), .CPU_RESETN(CPU_RESETN), .BTNC(BTNC), .SW(SW), .LED17_R(LED17_R),
        .LED(LED), .SEG(SEG), .DP(DP), .AN(AN)
    );

    integer errors = 0, checks = 0, cyc = 0, k;
    reg [6:0] digit7;
    reg       hb0, hb_toggled;

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
        repeat (10) @(posedge CLK100MHZ);
        CPU_RESETN = 1;
        repeat (20) @(posedge CLK100MHZ);
        check(LED[13] == 1'b0, "system-ready LED off while the link BIST runs");
        while (!LED[13] && cyc < 2000) begin @(posedge CLK100MHZ); cyc = cyc + 1; end
        check(LED[13] == 1'b1, "system ready after BIST");
        $display("      BIST done %0d cycles after reset", cyc + 20);

        if (FAULT_SW == 16'h0) begin
        cyc = 0;
        while (LED[7:4] != 4'hF && cyc < 300000) begin
            @(posedge CLK100MHZ);
            cyc = cyc + 1;
        end
        $display("      pass LEDs after %0d cycles", cyc);
        check(LED[7:4] == 4'hF, "all four tiles report pass on LED[7:4]");
        check(LED[3:0] == 4'h0, "no tile shows an error on LED[3:0]");
        check(LED[11:8] == 4'h0, "no tile reports failure on LED[11:8]");
        check(LED17_R == 1'b0, "BIST fault LED off");
        check(dut.u_panel.display == 32'h0000_00DE, "display 000000DE (docs/hardware_test.md stage A)");

        // blink-code LEDs stay dark over a few frames
        k = 0;
        repeat (400) begin @(posedge CLK100MHZ); if (LED[15] || LED[14]) k = k + 1; end
        check(k == 0, "blink-code LEDs dark when healthy");

        // heartbeat toggles
        hb0 = LED[12]; hb_toggled = 0;
        repeat (100) begin @(posedge CLK100MHZ); if (LED[12] != hb0) hb_toggled = 1; end
        check(hb_toggled, "heartbeat LED toggles");

        // leftmost digit (code) reads 0
        while (AN !== 8'b0111_1111) @(posedge CLK100MHZ);
        #1 digit7 = SEG;
        check(digit7 == ~7'h3F, "7-segment code digit shows 0");
        check(DP == 1'b1, "decimal points off");
        end else begin
        // switch-injected fault: BIST must catch it at start-up
        check(LED17_R == 1'b1, "BIST fault LED on");
        repeat (200) @(posedge CLK100MHZ);
        check(dut.u_panel.cur_code == 4'd14 && dut.u_panel.cur_tile == 1,
              "panel reports code E on router 1 (the faulted link's sender)");
        while (AN !== 8'b0111_1111) @(posedge CLK100MHZ);
        #1 digit7 = SEG;
        check(digit7 == ~7'h79, "7-segment code digit shows E");
        check(dut.u_sys.u_mesh.g_row[0].g_col[1].u_router.port_disable[`NOC_P_S] === 1'b1,
              "router 1 does not use the broken link");
        cyc = 0;
        while (LED[7:4] != 4'hF && cyc < 300000) begin @(posedge CLK100MHZ); cyc = cyc + 1; end
        check(LED[7:4] == 4'hF, "every tile still passes: traffic routed around the link");
        check(LED[11:8] == 4'h0, "no tile reports failure");
        if (FAULT_SW == 16'h1005)
            check(dut.u_panel.display == 32'hE010_0358, "display E0100358 (docs/hardware_test.md stage B)");
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
