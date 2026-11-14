// uart_port.v
// Optional serial port for one core: the laptop link of the live demo. It
// sits on the core's memory bus IN FRONT of the network interface and claims
// one page of addresses that is not a tile address (0xFFFFF000..0xFFFFFFFF);
// every other access passes straight through to the NI, unchanged and with
// no added delay. Nothing else in the system knows it exists: mesh_top only
// instantiates it when UART_EN = 1, and without it this file is not needed.
//
// REGISTERS (byte offsets in the page)
//   0x0  DATA    read: next received byte (and remove it); write: send a byte
//   0x4  STATUS  bit 0 a received byte is waiting   bit 1 the sender is free
//                bit 2 a received byte was lost (queue full), cleared by reading STATUS
//   0x8  TEXT_LO characters 0..3 for the board's display, ASCII, character 0
//                in bits 7:0 (leftmost on the display)
//   0xC  TEXT_HI characters 4..7. Writing either TEXT register switches the
//                display to text; writing 0 to both switches it back.
//
// SERIAL FORMAT 8 data bits, no parity, 1 stop bit, CLKS_PER_BIT clock cycles
// per bit (50 MHz / 115200 baud = 434). 64 received bytes are queued, so a
// short message can arrive while the core is busy.

`timescale 1ns/1ps

module uart_port #(
    parameter integer CLKS_PER_BIT = 434,
    parameter integer RX_DEPTH     = 64          // power of two
) (
    input  wire        clk,
    input  wire        rst_n,

    // core side (picorv32 native memory interface)
    input  wire        c_valid,
    input  wire        c_instr,
    output wire        c_ready,
    input  wire [31:0] c_addr,
    input  wire [31:0] c_wdata,
    input  wire [ 3:0] c_wstrb,
    output wire [31:0] c_rdata,
    // NI side: the same interface, for everything that is not the UART page
    output wire        n_valid,
    output wire        n_instr,
    input  wire        n_ready,
    output wire [31:0] n_addr,
    output wire [31:0] n_wdata,
    output wire [ 3:0] n_wstrb,
    input  wire [31:0] n_rdata,

    input  wire        rx,
    output reg         tx,
    output wire [63:0] text,        // 8 ASCII characters, character 0 in [7:0]
    output wire        text_en
);

    localparam integer BW = $clog2(CLKS_PER_BIT + 1);
    localparam integer QW = $clog2(RX_DEPTH);

    wire sel = c_valid && (c_addr[31:12] == 20'hFFFFF);

    // ---------------- pass-through ----------------
    reg         u_ready;
    reg  [31:0] u_rdata;
    assign n_valid = c_valid && !sel;
    assign n_instr = c_instr;
    assign n_addr  = c_addr;
    assign n_wdata = c_wdata;
    assign n_wstrb = c_wstrb;
    assign c_ready = sel ? u_ready : n_ready;
    assign c_rdata = sel ? u_rdata : n_rdata;

    // ---------------- receiver ----------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] rx_s;
    reg [BW-1:0] rx_cnt;
    reg [3:0]    rx_bit;          // 0 idle, 1 start, 2..9 data, 10 stop
    reg [7:0]    rx_sh;
    reg [7:0]    q [0:RX_DEPTH-1];
    reg [QW:0]   q_wp, q_rp;
    reg          lost;
    wire         q_empty = (q_wp == q_rp);
    wire         q_full  = (q_wp[QW-1:0] == q_rp[QW-1:0]) && (q_wp[QW] != q_rp[QW]);

    // ---------------- sender ----------------
    reg [BW-1:0] tx_cnt;
    reg [3:0]    tx_bit;          // 0 idle, 1..10 = start, 8 data, stop
    reg [8:0]    tx_sh;
    wire         tx_free = (tx_bit == 0);

    reg [31:0] text_lo, text_hi;
    assign text    = {text_hi, text_lo};
    assign text_en = |{text_hi, text_lo};

    wire acc    = sel && !u_ready;                    // one register access, answered next cycle
    wire wr     = acc && |c_wstrb;
    wire rd     = acc && !(|c_wstrb);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_ready <= 1'b0;  u_rdata <= 32'b0;
            rx_s <= 2'b11;  rx_cnt <= 0;  rx_bit <= 0;  rx_sh <= 8'b0;
            q_wp <= 0;  q_rp <= 0;  lost <= 1'b0;
            tx <= 1'b1;  tx_cnt <= 0;  tx_bit <= 0;  tx_sh <= 9'h1FF;
            text_lo <= 32'b0;  text_hi <= 32'b0;
        end else begin
            // ---- registers ----
            u_ready <= acc;
            if (rd) begin
                case (c_addr[3:2])
                    2'd0: begin
                        u_rdata <= {24'b0, q[q_rp[QW-1:0]]};
                        if (!q_empty) q_rp <= q_rp + 1'b1;
                    end
                    2'd1: begin
                        u_rdata <= {29'b0, lost, tx_free, !q_empty};
                        lost    <= 1'b0;
                    end
                    2'd2:    u_rdata <= text_lo;
                    default: u_rdata <= text_hi;
                endcase
            end
            if (wr) begin
                case (c_addr[3:2])
                    2'd0: if (tx_free) begin
                        tx_sh  <= {c_wdata[7:0], 1'b0};      // start bit first
                        tx_bit <= 4'd1;
                        tx_cnt <= 0;
                    end
                    2'd2:    text_lo <= c_wdata;
                    2'd3:    text_hi <= c_wdata;
                    default: ;
                endcase
            end

            // ---- sender: one bit every CLKS_PER_BIT cycles ----
            if (!tx_free) begin
                tx <= (tx_bit == 4'd10) ? 1'b1 : tx_sh[0];
                if (tx_cnt == CLKS_PER_BIT - 1) begin
                    tx_cnt <= 0;
                    tx_sh  <= {1'b1, tx_sh[8:1]};
                    tx_bit <= (tx_bit == 4'd10) ? 4'd0 : tx_bit + 1'b1;
                end else begin
                    tx_cnt <= tx_cnt + 1'b1;
                end
            end else begin
                tx <= 1'b1;
            end

            // ---- receiver: sample each bit in its middle ----
            rx_s <= {rx_s[0], rx};
            if (rx_bit == 0) begin
                if (!rx_s[1]) begin                          // start bit begins
                    rx_bit <= 4'd1;
                    rx_cnt <= CLKS_PER_BIT / 2;
                end
            end else if (rx_cnt == CLKS_PER_BIT - 1) begin
                rx_cnt <= 0;
                if (rx_bit == 4'd1) begin
                    rx_bit <= rx_s[1] ? 4'd0 : 4'd2;         // a glitch, not a start bit
                end else if (rx_bit == 4'd10) begin
                    rx_bit <= 4'd0;
                    if (rx_s[1]) begin                       // valid stop bit: keep the byte
                        if (q_full) lost <= 1'b1;
                        else begin
                            q[q_wp[QW-1:0]] <= rx_sh;
                            q_wp <= q_wp + 1'b1;
                        end
                    end
                end else begin
                    rx_sh  <= {rx_s[1], rx_sh[7:1]};         // least significant bit first
                    rx_bit <= rx_bit + 1'b1;
                end
            end else begin
                rx_cnt <= rx_cnt + 1'b1;
            end
        end
    end

endmodule
