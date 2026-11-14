// tb_sb_board.v
// sb_nexys4ddr_top as it is built for the board, DDR = 0 (the MIG has no
// simulation model): programs come from the tileNN.mem init files and the
// result is read from the LEDs only. The cores run alltoall.S.
// FAULT_SW = 0: healthy. Otherwise the slide-switch value, e.g. 16'h1000
// (stuck arbiter) or 16'h1800 (flipped data wire).

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_sb_board;

    parameter [15:0] FAULT_SW = 16'h0000;

    reg  CLK100MHZ = 0, CPU_RESETN = 0;
    wire [15:0] LED;
    wire [6:0]  SEG;
    wire        DP, LED16_G, LED17_B, LED17_R;
    wire [7:0]  AN;
    always #5 CLK100MHZ = ~CLK100MHZ;

`ifdef XILINX_SIMULATOR
    localparam PREFIX = "../../../../../sw/tile";
`else
    localparam PREFIX = "../sw/tile";
`endif

    sb_nexys4ddr_top #(
        .MEM_PREFIX(PREFIX), .UNIT_CYCLES(8), .HEART_CYCLES(20), .REFRESH_CYCLES(4), .DDR(0)
    ) dut (
        .CLK100MHZ(CLK100MHZ), .CPU_RESETN(CPU_RESETN), .BTNC(1'b0), .SW(FAULT_SW),
        .LED(LED), .SEG(SEG), .DP(DP), .AN(AN),
        .LED16_G(LED16_G), .LED17_B(LED17_B), .LED17_R(LED17_R)
    );

    integer errors = 0, checks = 0, cyc = 0;
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
        while (LED[6:4] != 3'b111 && LED[10:8] != 3'b111 && cyc < 300000) begin
            @(posedge CLK100MHZ);
            cyc = cyc + 1;
        end
        $display("      result LEDs after %0d cycles", cyc);
        check(LED[13] == 1'b1, "system-ready LED on");
        if (FAULT_SW == 16'h0) begin
            check(LED[6:4] == 3'b111, "all three cores report pass on LED[6:4]");
            check(LED[3:0] == 4'h0 && LED[11:8] == 4'h0, "no error and no failure LEDs");
            check(LED17_R == 1'b0, "fault LED off");
            check(dut.u_panel.display == 32'h0000_0096, "display 00000096: 150 checks on core 0");
        end else begin
            check(LED[10:8] == 3'b111 && LED[6:4] == 3'b000, "all three cores report failure, none passes");
            check(LED17_R == 1'b1, "fault LED on");
            check(dut.u_panel.cur_code == 4'd2 && dut.u_panel.cur_tile == 0,
                  "panel reports code 2 (NI timeout) on tile 0");
        end

        $display("----------------------------------------");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TOTAL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
