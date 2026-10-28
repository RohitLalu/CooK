// gw_ni.v
// Gateway network interface: NoC <-> Xilinx AXI DMA (axi_dma, direct register
// mode, 32-bit). Replaces ni.v on the gateway tile, which has no core and no
// local RAM. Same flit/packet format, check bits, tags, retry and poison rules
// as ni.v -- only the "other side" differs.
//
// THREE JOBS
//   1. DMA register window. A core's write/read to the gateway tile at
//      0x200..0x2FF becomes an AXI4-Lite write/read on axi_dma S_AXI_LITE
//      (address = offset - 0x200). Reads answer with the register value.
//   2. MM2S -> NoC. Each word the DMA streams out (DDR -> stream) becomes a
//      posted write (HEAD+TAIL) to a tile's RAM, address auto-incrementing.
//   3. NoC -> S2MM. On command the NI reads N words from a tile's RAM, one
//      read request at a time, and streams them to the DMA (stream -> DDR).
//
// ADDRESS MAP within the gateway tile's 4KB window
//   0x000  tile ID (ro)              0x004  error flags, write 1 to clear
//   0x008  software status (rw)      0x00C  number of tiles (ro)
//   0x010  tile kind (ro) = 1: gateway. ni.v reads 0 here (reserved CSR), so
//          software can tell a gateway tile (no RAM, no core) from a core tile.
//   0x100  MM2S_DST  (rw) NoC address of the first destination word. Writing
//          it ARMS the MM2S path and clears the sticky done bit. Rewriting
//          while armed is an error (err_illegal) and is ignored.
//   0x104  S2MM_SRC  (rw) NoC address of the first source word
//   0x108  S2MM_CNT  (rw) write N (1..65535) to START an S2MM transfer of N
//          words; reads back the words still to deliver. Writing while busy
//          or with N = 0 is an error and is ignored.
//   0x10C  STATUS    [0] mm2s armed  [1] mm2s done (sticky)
//                    [2] s2mm busy   [3] s2mm done (sticky). Write 1 to clear
//                    bits 1 and 3.
//   0x110  MM2S_CNT  (ro) words sent since MM2S_DST was written
//   0x200..0x2FF  axi_dma register window (AXI4-Lite)
//   anything at 0x300 and above is illegal: reads return POISON, writes are
//   dropped, err_illegal is set.
//
// ORDER OF OPERATIONS for DDR -> tile memory:
//   write MM2S_DST (arms), then program the DMA (MM2S_DMACR.RS, SA, LENGTH).
//   For tile memory -> DDR: write S2MM_SRC, program the DMA S2MM side (RS, DA,
//   LENGTH), THEN write S2MM_CNT (the stream starts immediately).
//
// ERRORS (err_flags bits as in ni.v)
//   bit 0 timeout: an S2MM read exhausted its retries. The word delivered to
//         the DMA is POISON so the transfer still terminates.
//   bit 1 illegal: bad offset, bad MM2S/S2MM address (outside the window, this
//         tile itself, or an MM2S offset below 0x100 -- that would hit the
//         destination's CSRs), bad CSR use, or an AXI-Lite SLVERR/DECERR.
//   bit 2 poison TAIL received.   bit 3 stale/unexpected response.
//   bit 4 check-bit error on a received flit.
//
// LIMITS: MM2S writes are posted -- a lost one is not detected here (read back
// to confirm, as with ni.v). S2MM has one outstanding read.

`timescale 1ns/1ps
`include "noc_defs.vh"

module gw_ni #(
    parameter integer MY_ID          = 3,
    parameter integer TIMEOUT_CYCLES = 1024,
    parameter integer RETRY_MAX      = 2,
    parameter integer RSP_Q_DEPTH    = `NOC_NUM_TILES,
    parameter [31:0]  POISON         = `NOC_POISON_DATA
) (
    input  wire clk,
    input  wire rst_n,

    // ---- mesh side: router LOCAL port (same as ni.v) ----
    input  wire                   in_valid,
    output wire                   in_ready,
    output wire                   in_room,
    input  wire [`NOC_FLIT_W-1:0] in_flit,
    output reg                    out_valid,
    input  wire                   out_ready,
    output reg  [`NOC_FLIT_W-1:0] out_flit,

    // ---- AXI4-Lite master -> axi_dma S_AXI_LITE ----
    output reg  [9:0]  m_axil_awaddr,
    output reg         m_axil_awvalid,
    input  wire        m_axil_awready,
    output reg  [31:0] m_axil_wdata,
    output reg  [3:0]  m_axil_wstrb,
    output reg         m_axil_wvalid,
    input  wire        m_axil_wready,
    input  wire [1:0]  m_axil_bresp,
    input  wire        m_axil_bvalid,
    output wire        m_axil_bready,
    output reg  [9:0]  m_axil_araddr,
    output reg         m_axil_arvalid,
    input  wire        m_axil_arready,
    input  wire [31:0] m_axil_rdata,
    input  wire [1:0]  m_axil_rresp,
    input  wire        m_axil_rvalid,
    output wire        m_axil_rready,

    // ---- stream from axi_dma M_AXIS_MM2S (DDR -> NoC) ----
    input  wire [31:0] s_axis_mm2s_tdata,
    input  wire [3:0]  s_axis_mm2s_tkeep,
    input  wire        s_axis_mm2s_tlast,
    input  wire        s_axis_mm2s_tvalid,
    output wire        s_axis_mm2s_tready,

    // ---- stream to axi_dma S_AXIS_S2MM (NoC -> DDR) ----
    output wire [31:0] m_axis_s2mm_tdata,
    output wire [3:0]  m_axis_s2mm_tkeep,
    output wire        m_axis_s2mm_tlast,
    output wire        m_axis_s2mm_tvalid,
    input  wire        m_axis_s2mm_tready,

    // ---- status ----
    output wire [4:0]  err_flags,
    output wire [31:0] sw_status
);

`include "noc_funcs.vh"

    localparam FW  = `NOC_FLIT_W;
    localparam IW  = `NOC_ID_W;
    localparam XW  = `NOC_X_W;
    localparam YW  = `NOC_Y_W;
    localparam TW  = `NOC_TAG_W;
    localparam OB  = `NOC_OFFSET_BITS;
    localparam DW  = `NOC_DATA_W;
    localparam [OB-1:0] CSR_ID       = 'h000;
    localparam [OB-1:0] CSR_ERR      = 'h004;
    localparam [OB-1:0] CSR_SW       = 'h008;
    localparam [OB-1:0] CSR_NT       = 'h00C;
    localparam [OB-1:0] CSR_KIND     = 'h010;
    localparam [OB-1:0] G_MM2S_DST   = 'h100;
    localparam [OB-1:0] G_S2MM_SRC   = 'h104;
    localparam [OB-1:0] G_S2MM_CNT   = 'h108;
    localparam [OB-1:0] G_STATUS     = 'h10C;
    localparam [OB-1:0] G_MM2S_CNT   = 'h110;
    localparam [OB-1:0] DMA_BASE     = 'h200;
    localparam [OB-1:0] DMA_END      = 'h300;
    localparam [OB-1:0] TILE_MEM_MIN = 'h100;     // first RAM offset on a core tile
    localparam [1:0] T_BODY = `NOC_T_BODY, T_HEAD = `NOC_T_HEAD,
                     T_HEADTAIL = `NOC_T_HEADTAIL, T_TAIL = `NOC_T_TAIL;
    localparam [`NOC_LEN_W-1:0] LEN_2FLIT = 1;
    localparam QW  = `NOC_CLOG2_1(RSP_Q_DEPTH);
    localparam TOW = $clog2(TIMEOUT_CYCLES + 1);
    localparam RW  = `NOC_CLOG2_1(RETRY_MAX + 1);

    generate
        if (DW != 32) begin : gw_check_dw
            NOC_CONFIG_ERROR_gw_ni_assumes_32bit_data u_err ();
        end
        if (OB < 10) begin : gw_check_ob
            NOC_CONFIG_ERROR_gw_ni_needs_at_least_1KB_tile_window u_err ();
        end
        if (RSP_Q_DEPTH < 1) begin : gw_check_q
            NOC_CONFIG_ERROR_gw_ni_response_queue_depth_below_1 u_err ();
        end
    endgenerate

    function [DW-1:0] make_hdr;
        input [OB-1:0] off;
        input          is_write;
        input          is_resp;
        input [3:0]    wstrb;
        input [TW-1:0] tag;
        begin
            make_hdr = {DW{1'b0}};
            make_hdr[`NOC_H_OFF_LSB +: OB]          = off;
            make_hdr[`NOC_H_WR]                     = is_write;
            make_hdr[`NOC_H_RSP]                    = is_resp;
            make_hdr[`NOC_H_WSTRB_LSB +: 4]         = wstrb;
            make_hdr[`NOC_H_LEN_LSB +: `NOC_LEN_W]  = LEN_2FLIT;
            make_hdr[`NOC_H_TAG_LSB +: TW]          = tag;
        end
    endfunction

    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------
    reg        err_timeout, err_illegal, err_poison, err_stale, err_chk;
    reg [31:0] sw_reg;
    assign err_flags = {err_chk, err_stale, err_poison, err_illegal, err_timeout};
    assign sw_status = sw_reg;

    // MM2S path
    reg [31:0] mm2s_ptr;
    reg        mm2s_armed, mm2s_done;
    reg [31:0] mm2s_cnt;

    // S2MM path
    localparam [1:0] S2_IDLE = 2'd0, S2_REQ = 2'd1, S2_WAIT = 2'd2, S2_PUSH = 2'd3;
    reg [1:0]     s2_state;
    reg [31:0]    s2_ptr;
    reg [15:0]    s2_rem;
    reg           s2_busy, s2_done;
    reg [31:0]    s2_data;
    reg [TW-1:0]  s2_tag;
    reg [IW-1:0]  s2_tgt;
    reg [TOW-1:0] timeout_cnt;
    reg [RW-1:0]  retry_cnt;

    // address decode for the two stream pointers
    wire          m_loc, m_rem, m_ill;
    wire [IW-1:0] m_tile;
    wire [XW-1:0] m_x;
    wire [YW-1:0] m_y;
    wire [OB-1:0] m_off;
    address_decoder #(.MY_TILE_ID(MY_ID)) u_adec_m (
        .addr(mm2s_ptr), .is_local(m_loc), .is_remote(m_rem), .is_illegal(m_ill),
        .target_tile(m_tile), .target_x(m_x), .target_y(m_y), .local_offset(m_off));
    wire m_ok = m_rem && (m_off >= TILE_MEM_MIN);

    wire          s_loc, s_rem, s_ill;
    wire [IW-1:0] s_tile;
    wire [XW-1:0] s_x;
    wire [YW-1:0] s_y;
    wire [OB-1:0] s_off;
    address_decoder #(.MY_TILE_ID(MY_ID)) u_adec_s (
        .addr(s2_ptr), .is_local(s_loc), .is_remote(s_rem), .is_illegal(s_ill),
        .target_tile(s_tile), .target_x(s_x), .target_y(s_y), .local_offset(s_off));

    // CSR read value for an offset below DMA_BASE
    function [31:0] csr_read;
        input [OB-1:0] off;
        begin
            csr_read = (off == CSR_ID)     ? MY_ID :
                       (off == CSR_ERR)    ? {27'b0, err_flags} :
                       (off == CSR_SW)     ? sw_reg :
                       (off == CSR_NT)     ? `NOC_NUM_TILES :
                       (off == CSR_KIND)   ? 32'd1 :
                       (off == G_MM2S_DST) ? mm2s_ptr :
                       (off == G_S2MM_SRC) ? s2_ptr :
                       (off == G_S2MM_CNT) ? {16'b0, s2_rem} :
                       (off == G_STATUS)   ? {28'b0, s2_done, s2_busy, mm2s_done, mm2s_armed} :
                       (off == G_MM2S_CNT) ? mm2s_cnt : 32'b0;
        end
    endfunction

    // ---------------------------------------------------------------
    // Receive side (identical capture to ni.v)
    // ---------------------------------------------------------------
    reg           rx_have, rx_in_pkt;
    reg           rx_is_resp, rx_is_write;
    reg [3:0]     rx_wstrb;
    reg [OB-1:0]  rx_off;
    reg [IW-1:0]  rx_src;
    reg [TW-1:0]  rx_tag;
    reg [31:0]    rx_data;

    assign in_ready = !rx_have;
    assign in_room  = !rx_have;
    wire rx_fire = in_valid && in_ready;

    wire [1:0]    in_type = in_flit[`NOC_F_TYPE_LSB +: 2];
    wire          in_pois = in_flit[`NOC_F_POISON];
    wire [IW-1:0] in_src  = in_flit[`NOC_F_SRC_LSB +: IW];
    wire [DW-1:0] in_data = in_flit[`NOC_F_DATA_LSB +: DW];
    wire          in_ok   = noc_chk_ok(in_flit);

    wire rx_dma  = (rx_off >= DMA_BASE) && (rx_off < DMA_END);
    wire rsp_match = rx_have && rx_is_resp && (s2_state == S2_WAIT) &&
                     (rx_src == s2_tgt) && (rx_tag == s2_tag);

    // ---------------------------------------------------------------
    // Response queue: reads we owe to other tiles
    // ---------------------------------------------------------------
    reg [IW-1:0] rq_dst  [0:RSP_Q_DEPTH-1];
    reg [TW-1:0] rq_tag  [0:RSP_Q_DEPTH-1];
    reg [OB-1:0] rq_off  [0:RSP_Q_DEPTH-1];
    reg [31:0]   rq_data [0:RSP_Q_DEPTH-1];
    reg [QW-1:0] rq_wp, rq_rp;
    reg [QW:0]   rq_cnt;
    wire rq_empty = (rq_cnt == 0);
    wire rq_full  = (rq_cnt == RSP_Q_DEPTH);
    reg  rq_push, rq_pop;

    // at most one push per cycle: callers check rq_push first
    task rq_put;
        input [IW-1:0] d;
        input [TW-1:0] g;
        input [OB-1:0] o;
        input [31:0]   v;
        begin
            rq_dst[rq_wp]  <= d;
            rq_tag[rq_wp]  <= g;
            rq_off[rq_wp]  <= o;
            rq_data[rq_wp] <= v;
            rq_wp   <= (rq_wp == RSP_Q_DEPTH-1) ? {QW{1'b0}} : rq_wp + 1'b1;
            rq_push  = 1'b1;
        end
    endtask

    // ---------------------------------------------------------------
    // AXI4-Lite master: one transaction at a time
    // ---------------------------------------------------------------
    localparam [2:0] AX_IDLE = 3'd0, AX_W = 3'd1, AX_B = 3'd2, AX_AR = 3'd3, AX_R = 3'd4;
    reg [2:0]    ax_state;
    reg [IW-1:0] ax_dst;
    reg [TW-1:0] ax_tag;
    reg [OB-1:0] ax_off;

    assign m_axil_bready = (ax_state == AX_B);
    assign m_axil_rready = (ax_state == AX_R) && !rq_full;

    // ---------------------------------------------------------------
    // Stream handshakes
    // ---------------------------------------------------------------
    localparam [1:0] TX_IDLE = 2'd0, TX_HEAD = 2'd1, TX_TAIL = 2'd2;
    reg [1:0]    tx_state;
    reg [FW-1:0] tx_head, tx_tail;

    assign s_axis_mm2s_tready = mm2s_armed && (tx_state == TX_IDLE) && rq_empty &&
                                (s2_state != S2_REQ);
    wire mm2s_take = s_axis_mm2s_tvalid && s_axis_mm2s_tready;

    assign m_axis_s2mm_tdata  = s2_data;
    assign m_axis_s2mm_tkeep  = 4'hF;
    assign m_axis_s2mm_tlast  = (s2_rem == 16'd1);
    assign m_axis_s2mm_tvalid = (s2_state == S2_PUSH);

    // ---------------------------------------------------------------
    // Control
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;  out_flit <= {FW{1'b0}};
            rx_have <= 1'b0;  rx_in_pkt <= 1'b0;
            rx_src <= {IW{1'b0}};  rx_tag <= {TW{1'b0}};
            rx_is_resp <= 1'b0;  rx_is_write <= 1'b0;
            rx_wstrb <= 4'b0;  rx_off <= {OB{1'b0}};  rx_data <= 32'b0;
            rq_wp <= {QW{1'b0}};  rq_rp <= {QW{1'b0}};  rq_cnt <= {(QW+1){1'b0}};
            tx_state <= TX_IDLE;  tx_head <= {FW{1'b0}};  tx_tail <= {FW{1'b0}};
            err_timeout <= 1'b0;  err_illegal <= 1'b0;  err_poison <= 1'b0;
            err_stale <= 1'b0;  err_chk <= 1'b0;
            sw_reg <= 32'b0;
            mm2s_ptr <= 32'b0;  mm2s_armed <= 1'b0;  mm2s_done <= 1'b0;  mm2s_cnt <= 32'b0;
            s2_state <= S2_IDLE;  s2_ptr <= 32'b0;  s2_rem <= 16'b0;
            s2_busy <= 1'b0;  s2_done <= 1'b0;  s2_data <= 32'b0;
            s2_tag <= {TW{1'b0}};  s2_tgt <= {IW{1'b0}};
            timeout_cnt <= {TOW{1'b0}};  retry_cnt <= {RW{1'b0}};
            ax_state <= AX_IDLE;  ax_dst <= {IW{1'b0}};  ax_tag <= {TW{1'b0}};  ax_off <= {OB{1'b0}};
            m_axil_awaddr <= 10'b0;  m_axil_awvalid <= 1'b0;
            m_axil_wdata <= 32'b0;  m_axil_wstrb <= 4'b0;  m_axil_wvalid <= 1'b0;
            m_axil_araddr <= 10'b0;  m_axil_arvalid <= 1'b0;
        end else begin
            rq_push = 1'b0;
            rq_pop  = 1'b0;

            // ---------------- receive ----------------
            if (rx_fire) begin
                if (!in_ok) begin
                    err_chk   <= 1'b1;
                    rx_in_pkt <= 1'b0;
                end else begin
                    case (in_type)
                        T_HEAD, T_HEADTAIL: begin
                            rx_src      <= in_src;
                            rx_off      <= in_data[`NOC_H_OFF_LSB +: OB];
                            rx_is_write <= in_data[`NOC_H_WR];
                            rx_is_resp  <= in_data[`NOC_H_RSP];
                            rx_wstrb    <= in_data[`NOC_H_WSTRB_LSB +: 4];
                            rx_tag      <= in_data[`NOC_H_TAG_LSB +: TW];
                            if (in_type == T_HEADTAIL) begin
                                rx_data   <= 32'b0;
                                rx_have   <= 1'b1;
                                rx_in_pkt <= 1'b0;
                            end else begin
                                rx_in_pkt <= 1'b1;
                            end
                        end
                        T_TAIL: begin
                            if (in_pois) begin
                                err_poison <= 1'b1;
                                rx_in_pkt  <= 1'b0;
                            end else if (rx_in_pkt) begin
                                rx_data   <= in_data;
                                rx_have   <= 1'b1;
                                rx_in_pkt <= 1'b0;
                            end
                        end
                        default: ;
                    endcase
                end
            end

            // ---------------- AXI4-Lite engine ----------------
            case (ax_state)
                AX_W: begin
                    if (m_axil_awvalid && m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wvalid  && m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if ((!m_axil_awvalid || m_axil_awready) && (!m_axil_wvalid || m_axil_wready))
                        ax_state <= AX_B;
                end
                AX_B: begin
                    if (m_axil_bvalid) begin
                        if (m_axil_bresp != 2'b00) err_illegal <= 1'b1;
                        ax_state <= AX_IDLE;
                    end
                end
                AX_AR: begin
                    if (m_axil_arvalid && m_axil_arready) begin
                        m_axil_arvalid <= 1'b0;
                        ax_state       <= AX_R;
                    end
                end
                AX_R: begin
                    if (m_axil_rvalid && m_axil_rready) begin
                        if (m_axil_rresp != 2'b00) begin
                            err_illegal <= 1'b1;
                            rq_put(ax_dst, ax_tag, ax_off, POISON);
                        end else begin
                            rq_put(ax_dst, ax_tag, ax_off, m_axil_rdata);
                        end
                        ax_state <= AX_IDLE;
                    end
                end
                default: ;
            endcase

            // ---------------- consume a received packet ----------------
            if (rx_have) begin
                if (rx_is_resp) begin
                    // answer to our S2MM read
                    if (rsp_match) begin
                        s2_data  <= rx_data;
                        s2_state <= S2_PUSH;
                    end else begin
                        err_stale <= 1'b1;
                    end
                    rx_have <= 1'b0;
                end else if (rx_is_write) begin
                    if (rx_dma) begin
                        // stall (leave rx_have set) until the AXI engine is free
                        if (ax_state == AX_IDLE) begin
                            m_axil_awaddr  <= {{(10-8){1'b0}}, rx_off[7:0]};
                            m_axil_awvalid <= 1'b1;
                            m_axil_wdata   <= rx_data;
                            m_axil_wstrb   <= rx_wstrb;
                            m_axil_wvalid  <= 1'b1;
                            ax_state       <= AX_W;
                            rx_have        <= 1'b0;
                        end
                    end else begin
                        if (rx_off == CSR_ERR) begin
                            if (rx_data[0]) err_timeout <= 1'b0;
                            if (rx_data[1]) err_illegal <= 1'b0;
                            if (rx_data[2]) err_poison  <= 1'b0;
                            if (rx_data[3]) err_stale   <= 1'b0;
                            if (rx_data[4]) err_chk     <= 1'b0;
                        end else if (rx_off == CSR_SW) begin
                            if (rx_wstrb[0]) sw_reg[ 7: 0] <= rx_data[ 7: 0];
                            if (rx_wstrb[1]) sw_reg[15: 8] <= rx_data[15: 8];
                            if (rx_wstrb[2]) sw_reg[23:16] <= rx_data[23:16];
                            if (rx_wstrb[3]) sw_reg[31:24] <= rx_data[31:24];
                        end else if (rx_off == G_MM2S_DST) begin
                            if (mm2s_armed) begin
                                err_illegal <= 1'b1;
                            end else begin
                                mm2s_ptr   <= rx_data;
                                mm2s_cnt   <= 32'b0;
                                mm2s_armed <= 1'b1;
                                mm2s_done  <= 1'b0;
                            end
                        end else if (rx_off == G_S2MM_SRC) begin
                            if (s2_busy) err_illegal <= 1'b1;
                            else         s2_ptr <= rx_data;
                        end else if (rx_off == G_S2MM_CNT) begin
                            if (s2_busy || rx_data[15:0] == 16'b0) begin
                                err_illegal <= 1'b1;
                            end else begin
                                s2_rem    <= rx_data[15:0];
                                s2_busy   <= 1'b1;
                                s2_done   <= 1'b0;
                                retry_cnt <= {RW{1'b0}};
                                s2_state  <= S2_REQ;
                            end
                        end else if (rx_off == G_STATUS) begin
                            if (rx_data[1]) mm2s_done <= 1'b0;
                            if (rx_data[3]) s2_done   <= 1'b0;
                        end else if (rx_off >= DMA_END) begin
                            err_illegal <= 1'b1;
                        end
                        rx_have <= 1'b0;
                    end
                end else begin
                    // read request
                    if (rx_dma) begin
                        if (ax_state == AX_IDLE) begin
                            m_axil_araddr  <= {{(10-8){1'b0}}, rx_off[7:0]};
                            m_axil_arvalid <= 1'b1;
                            ax_dst         <= rx_src;
                            ax_tag         <= rx_tag;
                            ax_off         <= rx_off;
                            ax_state       <= AX_AR;
                            rx_have        <= 1'b0;
                        end
                    end else if (!rq_full && !rq_push) begin
                        if (rx_off >= DMA_END) begin
                            err_illegal <= 1'b1;
                            rq_put(rx_src, rx_tag, rx_off, POISON);
                        end else begin
                            rq_put(rx_src, rx_tag, rx_off, csr_read(rx_off));
                        end
                        rx_have <= 1'b0;
                    end
                end
            end

            // ---------------- S2MM sequencer ----------------
            case (s2_state)
                S2_WAIT: begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                    // a response arriving on the timeout cycle wins
                    if (!rsp_match && timeout_cnt >= TIMEOUT_CYCLES) begin
                        if (retry_cnt < RETRY_MAX) begin
                            retry_cnt <= retry_cnt + 1'b1;
                            s2_state  <= S2_REQ;        // resend with a new tag
                        end else begin
                            s2_data     <= POISON;
                            err_timeout <= 1'b1;
                            s2_state    <= S2_PUSH;
                        end
                    end
                end
                S2_PUSH: begin
                    if (m_axis_s2mm_tready) begin
                        s2_ptr    <= s2_ptr + 32'd4;
                        s2_rem    <= s2_rem - 1'b1;
                        retry_cnt <= {RW{1'b0}};
                        if (s2_rem == 16'd1) begin
                            s2_busy  <= 1'b0;
                            s2_done  <= 1'b1;
                            s2_state <= S2_IDLE;
                        end else begin
                            s2_state <= S2_REQ;
                        end
                    end
                end
                default: ;
            endcase

            // ---------------- transmit ----------------
            case (tx_state)
                TX_IDLE: begin
                    out_valid <= 1'b0;
                    if (!rq_empty) begin
                        // responses owed to others win over our own traffic
                        tx_head <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0],
                                                 noc_id_x(rq_dst[rq_rp]), noc_id_y(rq_dst[rq_rp]),
                                                 make_hdr(rq_off[rq_rp], 1'b0, 1'b1, 4'b0, rq_tag[rq_rp]));
                        tx_tail <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0],
                                                 noc_id_x(rq_dst[rq_rp]), noc_id_y(rq_dst[rq_rp]),
                                                 rq_data[rq_rp]);
                        rq_rp    <= (rq_rp == RSP_Q_DEPTH-1) ? {QW{1'b0}} : rq_rp + 1'b1;
                        rq_pop    = 1'b1;
                        tx_state <= TX_HEAD;
                    end else if (s2_state == S2_REQ) begin
                        if (s_rem) begin
                            s2_tag      <= s2_tag + 1'b1;
                            s2_tgt      <= s_tile;
                            timeout_cnt <= {TOW{1'b0}};
                            s2_state    <= S2_WAIT;
                            tx_head <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0], s_x, s_y,
                                                     make_hdr(s_off, 1'b0, 1'b0, 4'b0, s2_tag + 1'b1));
                            tx_tail <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0], s_x, s_y, 32'b0);
                            tx_state <= TX_HEAD;
                        end else begin
                            // bad source address: still feed the DMA so it terminates
                            err_illegal <= 1'b1;
                            s2_data     <= POISON;
                            s2_state    <= S2_PUSH;
                        end
                    end else if (mm2s_take) begin
                        if (m_ok) begin
                            tx_head <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0], m_x, m_y,
                                                     make_hdr(m_off, 1'b1, 1'b0, s_axis_mm2s_tkeep, {TW{1'b0}}));
                            tx_tail <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0], m_x, m_y,
                                                     s_axis_mm2s_tdata);
                            tx_state <= TX_HEAD;
                            mm2s_ptr <= mm2s_ptr + 32'd4;
                            mm2s_cnt <= mm2s_cnt + 1'b1;
                        end else begin
                            err_illegal <= 1'b1;        // drop the word, keep draining
                        end
                        if (s_axis_mm2s_tlast) begin
                            mm2s_armed <= 1'b0;
                            mm2s_done  <= 1'b1;
                        end
                    end
                end

                TX_HEAD: begin
                    out_valid <= 1'b1;
                    out_flit  <= tx_head;
                    if (out_valid && out_ready) begin
                        out_flit <= tx_tail;
                        tx_state <= TX_TAIL;
                    end
                end

                TX_TAIL: begin
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                        tx_state  <= TX_IDLE;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase

            if (rq_push && !rq_pop)
                rq_cnt <= rq_cnt + 1'b1;
            else if (rq_pop && !rq_push)
                rq_cnt <= rq_cnt - 1'b1;
        end
    end

endmodule
