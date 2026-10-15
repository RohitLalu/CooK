// seven_seg.v
// Drives an 8-digit common-anode 7-segment display (Nexys4 DDR) with a
// 32-bit value as 8 hex digits, digit 7 = most significant, leftmost.
// Segments and anodes are active low. One digit is lit at a time; every digit
// gets REFRESH_CYCLES clock cycles in turn.

`timescale 1ns/1ps

module seven_seg #(
    parameter integer REFRESH_CYCLES = 50_000    // 1 ms per digit at 50 MHz
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] value,
    output reg  [6:0]  seg,     // {g,f,e,d,c,b,a}, active low
    output reg  [7:0]  an       // active low
);

    localparam integer RW = $clog2(REFRESH_CYCLES + 1);

    reg [RW-1:0] cnt;
    reg [2:0]    digit;

    function [6:0] hex7;   // active-high {g,f,e,d,c,b,a}
        input [3:0] h;
        begin
            case (h)
                4'h0: hex7 = 7'h3F; 4'h1: hex7 = 7'h06; 4'h2: hex7 = 7'h5B; 4'h3: hex7 = 7'h4F;
                4'h4: hex7 = 7'h66; 4'h5: hex7 = 7'h6D; 4'h6: hex7 = 7'h7D; 4'h7: hex7 = 7'h07;
                4'h8: hex7 = 7'h7F; 4'h9: hex7 = 7'h6F; 4'hA: hex7 = 7'h77; 4'hB: hex7 = 7'h7C;
                4'hC: hex7 = 7'h39; 4'hD: hex7 = 7'h5E; 4'hE: hex7 = 7'h79; default: hex7 = 7'h71;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt   <= {RW{1'b0}};
            digit <= 3'd0;
            seg   <= 7'h7F;
            an    <= 8'hFF;
        end else begin
            if (cnt == REFRESH_CYCLES - 1) begin
                cnt   <= {RW{1'b0}};
                digit <= digit + 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
            end
            seg <= ~hex7(value[digit*4 +: 4]);
            an  <= ~(8'b1 << digit);
        end
    end

endmodule
