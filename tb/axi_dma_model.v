// axi_dma_model.v
// SIMULATION ONLY. Behavioural stand-in for Xilinx axi_dma (direct register
// mode, 32-bit) plus the DDR behind it, so gw_ni can be tested without Vivado
// IP. Models only what gw_ni exercises:
//   AXI4-Lite regs  0x00 MM2S_DMACR (bit0 RS)   0x04 MM2S_DMASR (bit0 halted, bit1 idle)
//                   0x18 MM2S_SA   0x28 MM2S_LENGTH (write starts the transfer)
//                   0x30 S2MM_DMACR 0x34 S2MM_DMASR 0x48 S2MM_DA
//                   0x58 S2MM_LENGTH (write arms; read = bytes received)
//   anything at 0x5C and above answers SLVERR, like the real IP.
// mem[] is the DDR: word index = byte address / 4.

`timescale 1ns/1ps

module axi_dma_model #(
    parameter integer MEM_WORDS = 1024
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [9:0]  s_awaddr,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,
    output reg  [1:0]  s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,
    input  wire [9:0]  s_araddr,
    input  wire        s_arvalid,
    output wire        s_arready,
    output reg  [31:0] s_rdata,
    output reg  [1:0]  s_rresp,
    output reg         s_rvalid,
    input  wire        s_rready,

    output reg  [31:0] mm2s_tdata,
    output wire [3:0]  mm2s_tkeep,
    output reg         mm2s_tlast,
    output reg         mm2s_tvalid,
    input  wire        mm2s_tready,

    input  wire [31:0] s2mm_tdata,
    input  wire [3:0]  s2mm_tkeep,
    input  wire        s2mm_tlast,
    input  wire        s2mm_tvalid,
    output wire        s2mm_tready
);

    reg [31:0] mem [0:MEM_WORDS-1];
    integer k;
    initial for (k = 0; k < MEM_WORDS; k = k + 1) mem[k] = 32'b0;

    reg [31:0] mm2s_cr, mm2s_sa, mm2s_len, s2mm_cr, s2mm_da, s2mm_len, s2mm_rx_bytes;
    reg        mm2s_busy, s2mm_busy;
    reg [31:0] mm2s_idx, mm2s_nw, s2mm_idx;

    assign mm2s_tkeep  = 4'hF;
    assign s2mm_tready = s2mm_busy;

    wire wr_fire = s_awvalid && s_wvalid && !s_bvalid;
    wire rd_fire = s_arvalid && !s_rvalid;
    assign s_awready = wr_fire;
    assign s_wready  = wr_fire;
    assign s_arready = rd_fire;

    function [31:0] reg_read;
        input [9:0] a;
        begin
            case (a)
                10'h00: reg_read = mm2s_cr;
                10'h04: reg_read = {30'b0, !mm2s_busy && mm2s_cr[0], !mm2s_cr[0]};
                10'h18: reg_read = mm2s_sa;
                10'h28: reg_read = mm2s_len;
                10'h30: reg_read = s2mm_cr;
                10'h34: reg_read = {30'b0, !s2mm_busy && s2mm_cr[0], !s2mm_cr[0]};
                10'h48: reg_read = s2mm_da;
                10'h58: reg_read = s2mm_busy ? s2mm_len : s2mm_rx_bytes;
                default: reg_read = 32'b0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_bvalid <= 1'b0;  s_bresp <= 2'b00;
            s_rvalid <= 1'b0;  s_rresp <= 2'b00;  s_rdata <= 32'b0;
            mm2s_cr <= 32'b0;  mm2s_sa <= 32'b0;  mm2s_len <= 32'b0;
            s2mm_cr <= 32'b0;  s2mm_da <= 32'b0;  s2mm_len <= 32'b0;  s2mm_rx_bytes <= 32'b0;
            mm2s_busy <= 1'b0;  s2mm_busy <= 1'b0;
            mm2s_idx <= 32'b0;  mm2s_nw <= 32'b0;  s2mm_idx <= 32'b0;
            mm2s_tdata <= 32'b0;  mm2s_tlast <= 1'b0;  mm2s_tvalid <= 1'b0;
        end else begin
            // ---- AXI4-Lite ----
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;

            if (wr_fire) begin
                s_bvalid <= 1'b1;
                s_bresp  <= (s_awaddr >= 10'h5C) ? 2'b10 : 2'b00;
                case (s_awaddr)
                    10'h00: mm2s_cr <= s_wdata;
                    10'h18: mm2s_sa <= s_wdata;
                    10'h28: begin
                        mm2s_len <= s_wdata;
                        if (mm2s_cr[0] && s_wdata != 0) begin
                            mm2s_busy <= 1'b1;
                            mm2s_idx  <= 32'b0;
                            mm2s_nw   <= s_wdata >> 2;
                        end
                    end
                    10'h30: s2mm_cr <= s_wdata;
                    10'h48: s2mm_da <= s_wdata;
                    10'h58: begin
                        s2mm_len <= s_wdata;
                        if (s2mm_cr[0] && s_wdata != 0) begin
                            s2mm_busy     <= 1'b1;
                            s2mm_idx      <= 32'b0;
                            s2mm_rx_bytes <= 32'b0;
                        end
                    end
                    default: ;
                endcase
            end

            if (rd_fire) begin
                s_rvalid <= 1'b1;
                s_rresp  <= (s_araddr >= 10'h5C) ? 2'b10 : 2'b00;
                s_rdata  <= reg_read(s_araddr);
            end

            // ---- MM2S: memory -> stream ----
            if (mm2s_busy && (!mm2s_tvalid || mm2s_tready)) begin
                if (mm2s_idx < mm2s_nw) begin
                    mm2s_tdata  <= mem[(mm2s_sa >> 2) + mm2s_idx];
                    mm2s_tvalid <= 1'b1;
                    mm2s_tlast  <= (mm2s_idx == mm2s_nw - 1);
                    mm2s_idx    <= mm2s_idx + 1;
                end else begin
                    mm2s_tvalid <= 1'b0;
                    mm2s_tlast  <= 1'b0;
                    mm2s_busy   <= 1'b0;
                end
            end

            // ---- S2MM: stream -> memory ----
            if (s2mm_busy && s2mm_tvalid) begin
                mem[(s2mm_da >> 2) + s2mm_idx] <= s2mm_tdata;
                s2mm_idx      <= s2mm_idx + 1;
                s2mm_rx_bytes <= s2mm_rx_bytes + 4;
                if (s2mm_tlast) s2mm_busy <= 1'b0;
            end
        end
    end

endmodule
