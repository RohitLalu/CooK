// seven_seg_text.v
// Shows 8 ASCII characters on the Nexys4 DDR's 7-segment display, character 0
// (bits 7:0) leftmost. Same pins and timing as rtl/board/seven_seg.v; the
// board top selects this one while the live demo has text to show.
// Digits, upper- and lower-case letters (shown the same) and a few signs; a
// 7-segment digit cannot draw every letter well (K, M, V, W, X are rough)
// and anything else shows blank.

`timescale 1ns/1ps

module seven_seg_text #(
    parameter integer REFRESH_CYCLES = 50_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [63:0] text,
    output reg  [6:0]  seg,     // {g,f,e,d,c,b,a}, active low
    output reg  [7:0]  an       // active low; an[7] is the leftmost digit
);

    localparam integer RW = $clog2(REFRESH_CYCLES + 1);
    reg [RW-1:0] cnt;
    reg [2:0]    digit;

    function [6:0] font;        // active-high {g,f,e,d,c,b,a}
        input [7:0] ch;
        reg   [7:0] c;
        begin
            c = (ch >= "a" && ch <= "z") ? ch - 8'd32 : ch;
            case (c)
                "0": font = 7'h3F; "1": font = 7'h06; "2": font = 7'h5B; "3": font = 7'h4F;
                "4": font = 7'h66; "5": font = 7'h6D; "6": font = 7'h7D; "7": font = 7'h07;
                "8": font = 7'h7F; "9": font = 7'h6F;
                "A": font = 7'h77; "B": font = 7'h7C; "C": font = 7'h39; "D": font = 7'h5E;
                "E": font = 7'h79; "F": font = 7'h71; "G": font = 7'h3D; "H": font = 7'h76;
                "I": font = 7'h30; "J": font = 7'h1E; "K": font = 7'h75; "L": font = 7'h38;
                "M": font = 7'h37; "N": font = 7'h54; "O": font = 7'h5C; "P": font = 7'h73;
                "Q": font = 7'h67; "R": font = 7'h50; "S": font = 7'h6D; "T": font = 7'h78;
                "U": font = 7'h3E; "V": font = 7'h1C; "W": font = 7'h7E; "X": font = 7'h64;
                "Y": font = 7'h6E; "Z": font = 7'h5B;
                "-": font = 7'h40; "_": font = 7'h08; "=": font = 7'h48;
                default: font = 7'h00;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= {RW{1'b0}};  digit <= 3'd0;  seg <= 7'h7F;  an <= 8'hFF;
        end else begin
            if (cnt == REFRESH_CYCLES - 1) begin
                cnt   <= {RW{1'b0}};
                digit <= digit + 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
            end
            seg <= ~font(text[digit*8 +: 8]);
            an  <= ~(8'h80 >> digit);            // character 0 on the leftmost digit
        end
    end

endmodule
