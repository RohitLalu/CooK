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
//          it ARMS the MM2S path and clears the sticky done bit. It can be
//          rewritten until the transfer starts; after that it is refused (busy).
//   0x104  S2MM_SRC  (rw) NoC address of the first source word
//   0x108  S2MM_CNT  (rw) write N (1..65535) to START an S2MM transfer of N
//          words; reads back the words still to deliver. N must equal the
//          S2MM length already accepted, divided by 4 (else refused, reason 5).
//   0x10C  STATUS    [0] mm2s armed  [1] mm2s done (sticky)
//                    [2] s2mm busy   [3] s2mm done (sticky). Write 1 to clear
//                    bits 1 and 3.
//   0x110  MM2S_CNT  (ro) words sent since MM2S_DST was written
//   0x200..0x2FF  axi_dma register window (AXI4-Lite)
//   anything at 0x300 and above is illegal: reads return POISON, writes are
//   dropped, err_illegal is set.
//
// ORDER OF OPERATIONS (claim the lock first: read 0x114 until bit 31 is set)
//   DDR -> tile memory: write MM2S_DST (arms), then program the DMA
//   (MM2S_DMACR.RS, SA, LENGTH). The LENGTH write is checked and starts it.
//   Tile memory -> DDR: write S2MM_SRC, program the DMA S2MM side (RS, DA,
//   LENGTH, checked), THEN write S2MM_CNT (the stream starts immediately).
//   Wait for the done bit in STATUS, then write 0x114 to release the lock.
//
// ERRORS (err_flags bits as in ni.v)
//   bit 0 timeout: an S2MM read exhausted its retries. The word delivered to
//         the DMA is POISON so the transfer still terminates.
//   bit 1 illegal: offset 0x300 or above, an AXI-Lite SLVERR/DECERR, or a bad
//         stream address that slipped past the checks (defence in depth).
//         Misprogrammed requests are refused instead -- see DMA_REJECT.
//   bit 2 poison TAIL received.   bit 3 stale/unexpected response.
//   bit 4 check-bit error on a received flit.
//
// LIMITS: MM2S writes are posted -- a lost one is not detected here (read back
// to confirm, as with ni.v). S2MM has one outstanding read.
//
// ---------------------------------------------------------------------------
// BIST CONTROL POINT
//   After a total system reset the routers run their link ping-pong
//   (bist_node). When bist_mesh_done rises, this NI reads every other tile's
//   BIST status CSR (0x014) over the network, with the usual timeout and
//   retries. A tile is AVAILABLE only if that read came back and its two
//   halves are complements. A successful round trip proves both X-Y paths
//   (gateway to tile and back) are usable, because every router has already
//   disabled the outlinks it could not verify. Then sys_ready rises: the
//   cores leave reset, the DMA lock can be granted, and avail[] gates DMA.
//     0x014  this tile's own router status (same format as ni.v)
//     0x120  [31] sys_ready  [15:0] avail bitmap (bit t = tile t)
//     0x130 + 4t  stored status of tile t (0 if it could not be read)
//
// DMA LOCK (mutex for the single DMA engine)
//     0x114  DMA_LOCK  read = claim:  free -> it is yours; yours -> yours again
//            (so an NI retry of a lost reply is harmless); someone else's ->
//            you are queued. Reply: [31] granted to you  [30] held
//            [7:0] owner. Writing (owner) releases it; refused while a
//            transfer is moving. Writing (anyone else) withdraws your queued
//            request. A release hands the lock to the next queued tile in
//            round-robin order, so no core can be starved.
//            Lease: if the owner sends nothing for LEASE_CYCLES while no
//            transfer is moving, the lock is taken back (error "lease").
//   Only the owner may write 0x100-0x10C or the DMA window. Reads stay open.
//
// CHECKS AT THE "GO" WRITE (the DMA LENGTH registers start a transfer)
//   The LENGTH write is forwarded to the DMA only if every check passes:
//     owner's tile available (BIST), length and addresses 4-byte aligned and
//     non-zero, MM2S destination armed / no transfer already moving, the tile
//     address is the OWNER's own tile, at 0x100 or above, and the transfer
//     stays inside that 4KB window, and the DDR range [addr, addr+len) lies
//     inside one region the owner may use (DDR zones below).
//   S2MM_CNT must then equal the S2MM length / 4. DMA control-register
//   writes are refused while data is moving; only the eight direct-mode
//   registers can be written at all.
//   A refused write never reaches the DMA; the reason is recorded:
//     0x118  DMA_REJECT  [31] valid (write 1 to clear)  [23:16] tile
//            [3:0] reason: 1 no lock  2 DDR zone  3 tile range  4 alignment
//            5 S2MM count/length  6 register not writable  7 busy
//            8 tile not available / BIST not done  9 MM2S destination not armed
//
// DDR ZONES (parameters RG_*), default for the 128 MB DDR2:
//     Z0 0x0000_0000 40 MB tile 0     B0 0x0280_0000 4 MB tiles 0, 2
//     Z1 0x02C0_0000 40 MB tile 1     B1 0x0540_0000 4 MB tiles 0, 1
//     Z2 0x0580_0000 40 MB tile 2
//   B0 and B1 are shared windows, not guard bands: the range check above
//   already stops a transfer exactly at a region boundary.
//
// ERROR FLAGS: CSR 0x004 bits 0-4 as in ni.v, plus [5] request rejected,
//   [6] lock lease expired, [7] DMA reported an error (seen when its status
//   register is read). err_flags carries bits 0-4, gw_flags bits 5-7.

`timescale 1ns/1ps
`include "noc_defs.vh"

module gw_ni #(
    parameter integer MY_ID          = 3,
    parameter integer TIMEOUT_CYCLES = 1024,
    parameter integer RETRY_MAX      = 2,
    parameter integer RSP_Q_DEPTH    = `NOC_NUM_TILES,
    parameter [31:0]  POISON         = `NOC_POISON_DATA,
    // must outlast a core's whole NI retry sequence ((RETRY_MAX+1) x
    // TIMEOUT_CYCLES), or an owner whose replies are lost can lose the lock
    // between its own retries
    parameter integer LEASE_CYCLES   = 16384,
    parameter integer ZONE_EN        = 1,
    // DDR regions r = 0..4: [RG_LO, RG_HI), usable by the tiles set in RG_MASK
    parameter [5*32-1:0] RG_LO   = {32'h0580_0000, 32'h0540_0000, 32'h02C0_0000,
                                    32'h0280_0000, 32'h0000_0000},
    parameter [5*32-1:0] RG_HI   = {32'h0800_0000, 32'h0580_0000, 32'h0540_0000,
                                    32'h02C0_0000, 32'h0280_0000},
    parameter [5*16-1:0] RG_MASK = {16'h0004, 16'h0003, 16'h0002, 16'h0005, 16'h0001}
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
    output wire [31:0] sw_status,
    output wire [2:0]  gw_flags,     // {DMA error, lease expired, request rejected}
    // [3:0] reject reason, [11:4] rejected tile, [19:12] tile whose lease
    // expired, [22:20] DMA status error bits
    output wire [31:0] gw_info,

    // ---- BIST ----
    input  wire        bist_mesh_done,
    input  wire [9:0]  bist_own_status,
    output wire        sys_ready,
    output wire [`NOC_NUM_TILES-1:0] avail
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
    localparam [OB-1:0] G_LOCK       = 'h114;
    localparam [OB-1:0] G_REJECT     = 'h118;
    localparam [OB-1:0] G_BIST       = 'h120;
    localparam [OB-1:0] G_BIST_T     = 'h130;
    localparam [OB-1:0] CSR_BIST     = 'h014;
    // direct-mode axi_dma registers (offset inside the DMA window)
    localparam [7:0] D_MM2S_CR = 8'h00, D_MM2S_SR = 8'h04, D_MM2S_SA = 8'h18, D_MM2S_LEN = 8'h28,
                     D_S2MM_CR = 8'h30, D_S2MM_SR = 8'h34, D_S2MM_DA = 8'h48, D_S2MM_LEN = 8'h58;
    // reject reasons
    localparam [3:0] R_LOCK = 4'd1, R_ZONE = 4'd2, R_TILE = 4'd3, R_ALIGN = 4'd4, R_COUNT = 4'd5,
                     R_REG = 4'd6, R_BUSY = 4'd7, R_UNAVAIL = 4'd8, R_NOARM = 4'd9;
    localparam integer LW = $clog2(LEASE_CYCLES + 1);
    localparam integer NT = `NOC_NUM_TILES;
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
        if (`NOC_NUM_TILES > 16) begin : gw_check_nt
            NOC_CONFIG_ERROR_gw_ni_zone_masks_and_bitmap_assume_at_most_16_tiles u_err ();
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
    reg        err_rej, err_lease, err_dma;
    reg [3:0]  rej_reason;
    reg [7:0]  rej_tile, lease_tile;
    reg [2:0]  dma_bits;
    reg [31:0] sw_reg;
    assign err_flags = {err_chk, err_stale, err_poison, err_illegal, err_timeout};
    assign sw_status = sw_reg;
    assign gw_flags  = {err_dma, err_lease, err_rej};
    assign gw_info   = {9'b0, dma_bits, lease_tile, rej_tile, rej_reason};

    // DMA lock
    reg          lk_held;
    reg [IW-1:0] lk_owner;
    reg [NT-1:0] lk_req;
    reg [LW-1:0] lease_cnt;

    // transfer state used by the checks
    reg          mm2s_go;        // MM2S LENGTH accepted, stream not finished
    reg          s2_len_ok;      // S2MM LENGTH accepted, waiting for / running S2MM_CNT
    reg [15:0]   s2_len_w;       // that length in words
    reg [31:0]   sh_mm2s_sa, sh_s2mm_da;   // shadows of the DMA address registers

    // BIST collection
    localparam [2:0] BC_WAIT = 3'd0, BC_SEL = 3'd1, BC_REQ = 3'd2, BC_RSP = 3'd3,
                     BC_NEXT = 3'd4, BC_DONE = 3'd5;
    reg [2:0]     bc_state;
    reg [IW:0]    bc_idx;
    reg [TW-1:0]  bc_tag;
    reg [TOW-1:0] bc_to;
    reg [RW-1:0]  bc_retry;
    reg [9:0]     bc_st [0:NT-1];
    reg [NT-1:0]  avail_r;
    reg           ready_r;
    assign sys_ready = ready_r;
    assign avail     = avail_r;

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
                       (off == CSR_ERR)    ? {24'b0, err_dma, err_lease, err_rej, err_flags} :
                       (off == CSR_SW)     ? sw_reg :
                       (off == CSR_NT)     ? `NOC_NUM_TILES :
                       (off == CSR_KIND)   ? 32'd1 :
                       (off == G_MM2S_DST) ? mm2s_ptr :
                       (off == G_S2MM_SRC) ? s2_ptr :
                       (off == G_S2MM_CNT) ? {16'b0, s2_rem} :
                       (off == G_STATUS)   ? {28'b0, s2_done, s2_busy, mm2s_done, mm2s_armed} :
                       (off == G_MM2S_CNT) ? mm2s_cnt :
                       (off == G_REJECT)   ? {err_rej, 7'b0, rej_tile, 12'b0, rej_reason} :
                       (off == G_BIST)     ? {ready_r, 15'b0, {(16-NT){1'b0}}, avail_r} :
                       (off == CSR_BIST)   ? {6'b0, ~bist_own_status, 6'b0, bist_own_status} :
                       (off >= G_BIST_T && off < G_BIST_T + 4*NT && off[1:0] == 2'b00)
                                           ? {6'b0, ~bc_st[(off - G_BIST_T) >> 2], 6'b0,
                                              bc_st[(off - G_BIST_T) >> 2]} : 32'b0;
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
    // DMA lock and request checks
    // ---------------------------------------------------------------
    // DDR range [a, a + len) inside one region `who` may use
    function zone_ok;
        input [IW-1:0] who;
        input [31:0]   a;
        input [31:0]   len;
        reg   [32:0]   e;
        integer        r;
        begin
            e = {1'b0, a} + {1'b0, len};
            zone_ok = (ZONE_EN == 0);
            for (r = 0; r < 5; r = r + 1)
                if (RG_MASK[r*16 + who] && a >= RG_LO[r*32 +: 32] && e <= {1'b0, RG_HI[r*32 +: 32]})
                    zone_ok = 1'b1;
        end
    endfunction

    wire       is_owner   = lk_held && (rx_src == lk_owner);
    wire       need_owner = (rx_off == G_MM2S_DST) || (rx_off == G_S2MM_SRC) ||
                            (rx_off == G_S2MM_CNT) || (rx_off == G_STATUS);
    wire [7:0] rel        = rx_off[7:0];                  // offset inside the DMA window
    wire       rel_ok     = (rel == D_MM2S_CR) || (rel == D_MM2S_SR) || (rel == D_MM2S_SA) ||
                            (rel == D_MM2S_LEN) || (rel == D_S2MM_CR) || (rel == D_S2MM_SR) ||
                            (rel == D_S2MM_DA) || (rel == D_S2MM_LEN);
    wire       moving     = mm2s_go || s2_busy;
    wire       len_bad    = (rx_data == 32'b0) || (rx_data[1:0] != 2'b00);
    wire [32:0] mm_end    = {21'b0, m_off} + {1'b0, rx_data};
    wire [32:0] s2_end    = {21'b0, s_off} + {1'b0, rx_data};
    wire       mm_tile_bad = !m_rem || (m_tile != lk_owner) || (m_off < TILE_MEM_MIN) ||
                             (m_off[1:0] != 2'b00) || (mm_end > (33'd1 << OB));
    wire       s2_tile_bad = !s_rem || (s_tile != lk_owner) || (s_off < TILE_MEM_MIN) ||
                             (s_off[1:0] != 2'b00) || (s2_end > (33'd1 << OB));
    wire [3:0] mm_code = !avail_r[lk_owner]                     ? R_UNAVAIL :
                         (len_bad || sh_mm2s_sa[1:0] != 2'b00)  ? R_ALIGN :
                         !mm2s_armed                            ? R_NOARM :
                         mm2s_go                                ? R_BUSY :
                         mm_tile_bad                            ? R_TILE :
                         !zone_ok(lk_owner, sh_mm2s_sa, rx_data) ? R_ZONE : 4'd0;
    wire [3:0] s2_code = !avail_r[lk_owner]                     ? R_UNAVAIL :
                         (len_bad || sh_s2mm_da[1:0] != 2'b00)  ? R_ALIGN :
                         (s2_busy || s2_len_ok)                 ? R_BUSY :
                         s2_tile_bad                            ? R_TILE :
                         !zone_ok(lk_owner, sh_s2mm_da, rx_data) ? R_ZONE : 4'd0;

    // lock: a claim is granted when the lock is free or already yours
    wire        lk_grant_now = ready_r && (is_owner || !lk_held);
    wire [7:0]  lk_who       = lk_grant_now ? {{(8-IW){1'b0}}, rx_src} : {{(8-IW){1'b0}}, lk_owner};
    wire [31:0] lock_resp    = {lk_grant_now, lk_held || lk_grant_now, 22'b0, lk_who};

    // next queued tile after the owner, round robin
    reg          nx_v;
    reg [IW-1:0] nx;
    integer      ki, kt;
    always @(*) begin
        nx_v = 1'b0;
        nx   = {IW{1'b0}};
        for (ki = 1; ki <= NT; ki = ki + 1) begin
            kt = (lk_owner + ki) % NT;
            if (!nx_v && lk_req[kt]) begin
                nx_v = 1'b1;
                nx   = kt;
            end
        end
    end

    wire bc_match = rx_have && rx_is_resp && (bc_state == BC_RSP) &&
                    (rx_src == bc_idx[IW-1:0]) && (rx_tag == bc_tag);

    task reject;
        input [3:0] why;
        begin
            err_rej    <= 1'b1;
            rej_reason <= why;
            rej_tile   <= {{(8-IW){1'b0}}, rx_src};
            rx_have    <= 1'b0;
        end
    endtask

    task lock_handoff;   // give the lock to the next queued tile, or free it
        begin
            if (nx_v) begin
                lk_owner   <= nx;
                lk_req[nx] <= 1'b0;
                lease_cnt  <= {LW{1'b0}};
            end else begin
                lk_held <= 1'b0;
            end
        end
    endtask

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
            err_rej <= 1'b0;  err_lease <= 1'b0;  err_dma <= 1'b0;
            rej_reason <= 4'b0;  rej_tile <= 8'b0;  lease_tile <= 8'b0;  dma_bits <= 3'b0;
            lk_held <= 1'b0;  lk_owner <= {IW{1'b0}};  lk_req <= {NT{1'b0}};  lease_cnt <= {LW{1'b0}};
            mm2s_go <= 1'b0;  s2_len_ok <= 1'b0;  s2_len_w <= 16'b0;
            sh_mm2s_sa <= 32'b0;  sh_s2mm_da <= 32'b0;
            bc_state <= BC_WAIT;  bc_idx <= {(IW+1){1'b0}};  bc_tag <= {TW{1'b0}};
            bc_to <= {TOW{1'b0}};  bc_retry <= {RW{1'b0}};
            avail_r <= {NT{1'b0}};  ready_r <= 1'b0;
            for (ki = 0; ki < NT; ki = ki + 1) bc_st[ki] <= 10'b0;
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
                        // DMA status registers: bits 6:4 are its error flags
                        if ((ax_off == DMA_BASE + D_MM2S_SR || ax_off == DMA_BASE + D_S2MM_SR) &&
                            m_axil_rdata[6:4] != 3'b000) begin
                            err_dma  <= 1'b1;
                            dma_bits <= m_axil_rdata[6:4];
                        end
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
                // any request from the lock owner renews its lease
                if (!rx_is_resp && is_owner) lease_cnt <= {LW{1'b0}};

                if (rx_is_resp) begin
                    if (bc_match) begin
                        // BIST status of tile bc_idx: accept only complementary halves
                        if (rx_data[25:16] == ~rx_data[9:0]) begin
                            bc_st[bc_idx[IW-1:0]]   <= rx_data[9:0];
                            avail_r[bc_idx[IW-1:0]] <= 1'b1;
                        end
                        bc_state <= BC_NEXT;
                    end else if (rsp_match) begin
                        // answer to our S2MM read
                        s2_data  <= rx_data;
                        s2_state <= S2_PUSH;
                    end else begin
                        err_stale <= 1'b1;
                    end
                    rx_have <= 1'b0;
                end else if (rx_is_write) begin
                    if (rx_dma || need_owner) begin
                        // DMA control: owner only, checked, then applied
                        if (!is_owner) begin
                            reject(ready_r ? R_LOCK : R_UNAVAIL);
                        end else if (rx_dma) begin
                            if (!rel_ok)
                                reject(R_REG);
                            else if (rel == D_MM2S_LEN && mm_code != 4'd0)
                                reject(mm_code);
                            else if (rel == D_S2MM_LEN && s2_code != 4'd0)
                                reject(s2_code);
                            else if ((rel == D_MM2S_CR || rel == D_S2MM_CR) && moving)
                                reject(R_BUSY);
                            else if (ax_state == AX_IDLE) begin
                                // checks passed: forward to the DMA
                                m_axil_awaddr  <= {{(10-8){1'b0}}, rel};
                                m_axil_awvalid <= 1'b1;
                                m_axil_wdata   <= rx_data;
                                m_axil_wstrb   <= rx_wstrb;
                                m_axil_wvalid  <= 1'b1;
                                ax_state       <= AX_W;
                                if (rel == D_MM2S_SA)  sh_mm2s_sa <= rx_data;
                                if (rel == D_S2MM_DA)  sh_s2mm_da <= rx_data;
                                if (rel == D_MM2S_LEN) mm2s_go    <= 1'b1;
                                if (rel == D_S2MM_LEN) begin
                                    s2_len_ok <= 1'b1;
                                    s2_len_w  <= rx_data[17:2];
                                end
                                rx_have <= 1'b0;
                            end
                            // else: stall (leave rx_have set) until the AXI engine is free
                        end else if (rx_off == G_MM2S_DST) begin
                            if (mm2s_go) begin
                                reject(R_BUSY);
                            end else begin
                                mm2s_ptr   <= rx_data;
                                mm2s_cnt   <= 32'b0;
                                mm2s_armed <= 1'b1;
                                mm2s_done  <= 1'b0;
                                rx_have    <= 1'b0;
                            end
                        end else if (rx_off == G_S2MM_SRC) begin
                            if (s2_busy) reject(R_BUSY);
                            else begin
                                s2_ptr  <= rx_data;
                                rx_have <= 1'b0;
                            end
                        end else if (rx_off == G_S2MM_CNT) begin
                            if (s2_busy)
                                reject(R_BUSY);
                            else if (!s2_len_ok || rx_data[15:0] == 16'b0 || rx_data[15:0] != s2_len_w)
                                reject(R_COUNT);
                            else begin
                                s2_rem    <= rx_data[15:0];
                                s2_busy   <= 1'b1;
                                s2_done   <= 1'b0;
                                retry_cnt <= {RW{1'b0}};
                                s2_state  <= S2_REQ;
                                rx_have   <= 1'b0;
                            end
                        end else begin   // G_STATUS: clear sticky done bits
                            if (rx_data[1]) mm2s_done <= 1'b0;
                            if (rx_data[3]) s2_done   <= 1'b0;
                            rx_have <= 1'b0;
                        end
                    end else begin
                        // CSRs open to every tile
                        if (rx_off == CSR_ERR) begin
                            if (rx_data[0]) err_timeout <= 1'b0;
                            if (rx_data[1]) err_illegal <= 1'b0;
                            if (rx_data[2]) err_poison  <= 1'b0;
                            if (rx_data[3]) err_stale   <= 1'b0;
                            if (rx_data[4]) err_chk     <= 1'b0;
                            if (rx_data[5]) err_rej     <= 1'b0;
                            if (rx_data[6]) err_lease   <= 1'b0;
                            if (rx_data[7]) err_dma     <= 1'b0;
                        end else if (rx_off == CSR_SW) begin
                            if (rx_wstrb[0]) sw_reg[ 7: 0] <= rx_data[ 7: 0];
                            if (rx_wstrb[1]) sw_reg[15: 8] <= rx_data[15: 8];
                            if (rx_wstrb[2]) sw_reg[23:16] <= rx_data[23:16];
                            if (rx_wstrb[3]) sw_reg[31:24] <= rx_data[31:24];
                        end else if (rx_off == G_LOCK) begin
                            if (is_owner) begin
                                // release: refused while a transfer is set up or moving
                                if (moving || s2_len_ok) begin
                                    err_rej    <= 1'b1;
                                    rej_reason <= R_BUSY;
                                    rej_tile   <= {{(8-IW){1'b0}}, rx_src};
                                end else begin
                                    lock_handoff;
                                end
                            end else begin
                                lk_req[rx_src] <= 1'b0;      // withdraw a queued request
                            end
                        end else if (rx_off == G_REJECT) begin
                            if (rx_data[31]) err_rej <= 1'b0;
                        end else if (rx_off >= DMA_END) begin
                            err_illegal <= 1'b1;
                        end
                        rx_have <= 1'b0;
                    end
                end else begin
                    // read request: open to every tile
                    if (rx_dma) begin
                        if (ax_state == AX_IDLE) begin
                            m_axil_araddr  <= {{(10-8){1'b0}}, rel};
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
                        end else if (rx_off == G_LOCK) begin
                            // claim: the reply and the state change are one indivisible step
                            rq_put(rx_src, rx_tag, rx_off, lock_resp);
                            if (ready_r) begin
                                if (!lk_held) begin
                                    lk_held        <= 1'b1;
                                    lk_owner       <= rx_src;
                                    lk_req[rx_src] <= 1'b0;
                                    lease_cnt      <= {LW{1'b0}};
                                end else if (!is_owner) begin
                                    lk_req[rx_src] <= 1'b1;
                                end
                            end
                        end else begin
                            rq_put(rx_src, rx_tag, rx_off, csr_read(rx_off));
                        end
                        rx_have <= 1'b0;
                    end
                end
            end else begin
                // lock lease (only on cycles with no packet, so it never races a claim)
                if (lk_held && !moving) begin
                    if (lease_cnt >= LEASE_CYCLES) begin
                        err_lease  <= 1'b1;
                        lease_tile <= {{(8-IW){1'b0}}, lk_owner};
                        s2_len_ok  <= 1'b0;
                        lock_handoff;
                    end else begin
                        lease_cnt <= lease_cnt + 1'b1;
                    end
                end
            end

            // ---------------- BIST collection ----------------
            case (bc_state)
                BC_WAIT: if (bist_mesh_done) bc_state <= BC_SEL;
                BC_SEL: begin
                    if (bc_idx == NT) begin
                        bc_st[MY_ID]   <= bist_own_status;
                        avail_r[MY_ID] <= bist_own_status[9] && bist_own_status[4];   // own L links
                        ready_r        <= 1'b1;
                        bc_state       <= BC_DONE;
                    end else if (bc_idx == MY_ID) begin
                        bc_idx <= bc_idx + 1'b1;
                    end else begin
                        bc_retry <= {RW{1'b0}};
                        bc_state <= BC_REQ;
                    end
                end
                BC_RSP: begin
                    bc_to <= bc_to + 1'b1;
                    if (!bc_match && bc_to >= TIMEOUT_CYCLES) begin
                        if (bc_retry < RETRY_MAX) begin
                            bc_retry <= bc_retry + 1'b1;
                            bc_state <= BC_REQ;
                        end else begin
                            bc_state <= BC_NEXT;          // unreachable: stays unavailable
                        end
                    end
                end
                BC_NEXT: begin
                    bc_idx   <= bc_idx + 1'b1;
                    bc_state <= BC_SEL;
                end
                default: ;
            endcase

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
                            s2_busy   <= 1'b0;
                            s2_done   <= 1'b1;
                            s2_len_ok <= 1'b0;
                            s2_state  <= S2_IDLE;
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
                    end else if (bc_state == BC_REQ) begin
                        // BIST: read tile bc_idx's router status
                        bc_tag   <= bc_tag + 1'b1;
                        bc_to    <= {TOW{1'b0}};
                        bc_state <= BC_RSP;
                        tx_head  <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0],
                                                  noc_id_x(bc_idx[IW-1:0]), noc_id_y(bc_idx[IW-1:0]),
                                                  make_hdr(CSR_BIST, 1'b0, 1'b0, 4'b0, bc_tag + 1'b1));
                        tx_tail  <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0],
                                                  noc_id_x(bc_idx[IW-1:0]), noc_id_y(bc_idx[IW-1:0]), 32'b0);
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
                            mm2s_go    <= 1'b0;
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
