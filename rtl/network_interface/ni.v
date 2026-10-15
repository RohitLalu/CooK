// ni.v
// Network Interface: picorv32 (native memory interface) <-> NoC flits.
//
// PACKET FORMAT -- two flits, HEAD then TAIL, on every transaction.
// Field positions are defined once in noc_defs.vh.
//   HEAD  dst_x,dst_y = absolute destination; src = MY_ID (the return address)
//         data = { class, tag, length-1, wstrb, is_resp, is_write, offset }
//   TAIL  data = write data (request) or read data (response)
//   Both flits carry check bits, generated here and verified at every router
//   and at the receiving NI.
//
// WHY is_resp IS AN EXPLICIT BIT, not inferred from the source tag:
//   Inferring "request vs response" from the source tag alone only works
//   while exactly one tile ever initiates. Distributed BIST has every tile
//   pinging its neighbours at once, and the DMA gateway is a second
//   initiator. Getting it wrong is a silent hang no module can detect.
//
// WHY THE RESPONSE QUEUE (request/response deadlock)
//   Requests and responses share one network. If the NI refused new input
//   while its own response was blocked, two tiles could each hold a request
//   the other's response is stuck behind: a protocol deadlock that X-Y routing
//   does not prevent. Here a read request is moved out of the receive
//   register into a response queue at once, so the receive side keeps
//   draining. Every initiator has at most one outstanding read, so a queue of
//   RSP_Q_DEPTH = number of tiles cannot overflow in normal operation. If it
//   ever fills, the NI applies backpressure instead of dropping.
//
// TIMEOUT, RETRY AND TAGS
//   picorv32 holds mem_valid until mem_ready. A response that never arrives
//   (faulted path -- the case this project exists to handle) would hang the
//   core. After TIMEOUT_CYCLES the NI resends the read, up to RETRY_MAX
//   times, each attempt with a new tag. Only a response whose source and tag
//   match the CURRENT attempt is accepted; a late response to an abandoned
//   attempt is discarded and flagged. When retries run out the core gets
//   POISON and the sticky timeout bit is set.
//   Posted writes have no response, so a dropped write cannot be detected or
//   retried here. Use a read-back where a write must be confirmed.
//
// POISON TAIL
//   A router that has to cut a packet short sends a TAIL with the POISON bit
//   set. The NI discards the partial packet and sets a sticky flag; the
//   requester's timeout then retries.
//
// ADDRESS MAP within a tile's region:
//   0x000         tile ID (read-only)
//   0x004         error flags, write 1 to clear:
//                   bit 0 timeout (retries exhausted)
//                   bit 1 illegal address
//                   bit 2 poison TAIL received
//                   bit 3 stale or unexpected response discarded
//                   bit 4 check-bit error on a received flit
//   0x008..0x0FF  reserved CSRs (read 0)
//   0x100..       local memory
//   PROGADDR_RESET for tile N must therefore be (N << NOC_OFFSET_BITS) + 0x100.

`timescale 1ns/1ps
`include "noc_defs.vh"

module ni #(
    parameter integer MY_ID          = 0,     // tile ID == source tag == bitmap index
    parameter integer TIMEOUT_CYCLES = 1024,
    parameter integer RETRY_MAX      = 2,
    parameter integer RSP_Q_DEPTH    = `NOC_NUM_TILES,
    parameter [31:0]  POISON         = `NOC_POISON_DATA
) (
    input  wire clk,
    input  wire rst_n,

    // ---- core side: picorv32 native memory interface ----
    input  wire        mem_valid,
    input  wire        mem_instr,
    output reg         mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wstrb,
    output reg  [31:0] mem_rdata,

    // ---- mesh side: router LOCAL port ----
    // router L output -> NI
    input  wire                   in_valid,
    output wire                   in_ready,
    output wire                   in_room,
    input  wire [`NOC_FLIT_W-1:0] in_flit,
    // NI -> router L input
    output reg                    out_valid,
    input  wire                   out_ready,
    output reg  [`NOC_FLIT_W-1:0] out_flit,

    // ---- status, same bits as CSR 0x004 ----
    output wire [4:0]             err_flags
);

`include "noc_funcs.vh"

    localparam FW  = `NOC_FLIT_W;
    localparam IW  = `NOC_ID_W;
    localparam XW  = `NOC_X_W;
    localparam YW  = `NOC_Y_W;
    localparam TW  = `NOC_TAG_W;
    localparam OB  = `NOC_OFFSET_BITS;
    localparam DW  = `NOC_DATA_W;
    localparam MEM_WORDS = 1 << (OB - 2);
    localparam [OB-1:0] CSR_LIMIT = 'h100;
    localparam [OB-1:0] CSR_ID    = 'h000;
    localparam [OB-1:0] CSR_ERR   = 'h004;
    localparam [1:0] T_BODY = `NOC_T_BODY, T_HEAD = `NOC_T_HEAD,
                     T_HEADTAIL = `NOC_T_HEADTAIL, T_TAIL = `NOC_T_TAIL;
    localparam [`NOC_LEN_W-1:0] LEN_2FLIT = 1;    // length-1 for HEAD+TAIL
    localparam QW  = `NOC_CLOG2_1(RSP_Q_DEPTH);
    localparam TOW = $clog2(TIMEOUT_CYCLES + 1);
    localparam RW  = `NOC_CLOG2_1(RETRY_MAX + 1);

    generate
        if (DW != 32) begin : ni_check_dw
            NOC_CONFIG_ERROR_ni_assumes_32bit_data u_err ();
        end
        if (RSP_Q_DEPTH < 1) begin : ni_check_q
            NOC_CONFIG_ERROR_ni_response_queue_depth_below_1 u_err ();
        end
    endgenerate

    // HEAD payload builder
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
    // Address decode for the core's current access
    // ---------------------------------------------------------------
    wire           ad_local, ad_remote, ad_illegal;
    wire [IW-1:0]  ad_tile;
    wire [XW-1:0]  ad_x;
    wire [YW-1:0]  ad_y;
    wire [OB-1:0]  ad_off;

    address_decoder #(.MY_TILE_ID(MY_ID)) u_adec (
        .addr(mem_addr),
        .is_local(ad_local), .is_remote(ad_remote), .is_illegal(ad_illegal),
        .target_tile(ad_tile), .target_x(ad_x), .target_y(ad_y),
        .local_offset(ad_off)
    );

    // ---------------------------------------------------------------
    // Local memory + CSRs
    // ---------------------------------------------------------------
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [31:0] loc_rdata;
    reg        err_timeout, err_illegal, err_poison, err_stale, err_chk;
    wire [4:0] err_vec = {err_chk, err_stale, err_poison, err_illegal, err_timeout};
    assign err_flags = err_vec;

    wire [OB-3:0] core_widx = ad_off[OB-1:2];

    // ---------------------------------------------------------------
    // Receive side: capture HEAD then TAIL into one pending packet
    // ---------------------------------------------------------------
    reg           rx_have;     // a complete packet is captured, not yet consumed
    reg           rx_in_pkt;   // HEAD seen, TAIL outstanding
    reg           rx_is_resp, rx_is_write;
    reg [3:0]     rx_wstrb;
    reg [OB-1:0]  rx_off;
    reg [IW-1:0]  rx_src;
    reg [TW-1:0]  rx_tag;
    reg [31:0]    rx_data;

    assign in_ready = !rx_have;
    assign in_room  = !rx_have;      // one whole packet fits whenever idle
    wire rx_fire = in_valid && in_ready;

    wire [1:0]    in_type = in_flit[`NOC_F_TYPE_LSB +: 2];
    wire          in_pois = in_flit[`NOC_F_POISON];
    wire [IW-1:0] in_src  = in_flit[`NOC_F_SRC_LSB +: IW];
    wire [DW-1:0] in_data = in_flit[`NOC_F_DATA_LSB +: DW];
    wire          in_ok   = noc_chk_ok(in_flit);

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

    // ---------------------------------------------------------------
    // Transmit side
    // ---------------------------------------------------------------
    localparam [1:0] TX_IDLE = 2'd0, TX_HEAD = 2'd1, TX_TAIL = 2'd2;
    reg [1:0]    tx_state;
    reg [FW-1:0] tx_head, tx_tail;

    // ---------------------------------------------------------------
    // Core-facing transaction state
    // ---------------------------------------------------------------
    localparam [1:0] C_IDLE = 2'd0, C_LOCAL = 2'd1, C_REQ = 2'd2, C_WAIT = 2'd3;
    reg [1:0]     c_state;
    reg [TOW-1:0] timeout_cnt;
    reg [RW-1:0]  retry_cnt;
    reg [TW-1:0]  cur_tag;      // tag of the attempt currently in flight
    reg [IW-1:0]  req_tgt;      // tile that attempt was sent to

    wire tx_take_req = (tx_state == TX_IDLE) && rq_empty && (c_state == C_REQ);
    // the response we are waiting for is in the receive register this cycle
    wire rsp_match   = rx_have && rx_is_resp && (c_state == C_WAIT) &&
                       (rx_src == req_tgt) && (rx_tag == cur_tag);

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready   <= 1'b0;
            mem_rdata   <= 32'b0;
            loc_rdata   <= 32'b0;
            out_valid   <= 1'b0;
            out_flit    <= {FW{1'b0}};
            rx_have     <= 1'b0;
            rx_in_pkt   <= 1'b0;
            rx_src      <= {IW{1'b0}};
            rx_tag      <= {TW{1'b0}};
            rx_is_resp  <= 1'b0;
            rx_is_write <= 1'b0;
            rx_wstrb    <= 4'b0;
            rx_off      <= {OB{1'b0}};
            rx_data     <= 32'b0;
            rq_wp       <= {QW{1'b0}};
            rq_rp       <= {QW{1'b0}};
            rq_cnt      <= {(QW+1){1'b0}};
            tx_state    <= TX_IDLE;
            tx_head     <= {FW{1'b0}};
            tx_tail     <= {FW{1'b0}};
            c_state     <= C_IDLE;
            timeout_cnt <= {TOW{1'b0}};
            retry_cnt   <= {RW{1'b0}};
            cur_tag     <= {TW{1'b0}};
            req_tgt     <= {IW{1'b0}};
            err_timeout <= 1'b0;
            err_illegal <= 1'b0;
            err_poison  <= 1'b0;
            err_stale   <= 1'b0;
            err_chk     <= 1'b0;
        end else begin
            mem_ready <= 1'b0;      // single-cycle ack by default
            rq_push    = 1'b0;
            rq_pop     = 1'b0;

            // ---------------- receive ----------------
            if (rx_fire) begin
                if (!in_ok) begin
                    // corrupted flit: whatever packet it belonged to is lost
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
                        default: ;  // BODY: reserved for packets longer than two flits
                    endcase
                end
            end

            // ---------------- consume a received packet ----------------
            if (rx_have) begin
                if (rx_is_resp) begin
                    if (rsp_match) begin
                        mem_rdata <= rx_data;
                        mem_ready <= 1'b1;
                        c_state   <= C_IDLE;
                    end else begin
                        err_stale <= 1'b1;   // late answer to an abandoned attempt
                    end
                    rx_have <= 1'b0;
                end else if (rx_is_write) begin
                    // remote write into our memory (posted: no response owed)
                    if (rx_off >= CSR_LIMIT) begin
                        if (rx_wstrb[0]) mem[rx_off[OB-1:2]][ 7: 0] <= rx_data[ 7: 0];
                        if (rx_wstrb[1]) mem[rx_off[OB-1:2]][15: 8] <= rx_data[15: 8];
                        if (rx_wstrb[2]) mem[rx_off[OB-1:2]][23:16] <= rx_data[23:16];
                        if (rx_wstrb[3]) mem[rx_off[OB-1:2]][31:24] <= rx_data[31:24];
                    end else if (rx_off == CSR_ERR) begin
                        if (rx_data[0]) err_timeout <= 1'b0;
                        if (rx_data[1]) err_illegal <= 1'b0;
                        if (rx_data[2]) err_poison  <= 1'b0;
                        if (rx_data[3]) err_stale   <= 1'b0;
                        if (rx_data[4]) err_chk     <= 1'b0;
                    end
                    rx_have <= 1'b0;
                end else if (!rq_full) begin
                    // remote read: queue the response, keep the receive side free
                    rq_dst[rq_wp]  <= rx_src;
                    rq_tag[rq_wp]  <= rx_tag;
                    rq_off[rq_wp]  <= rx_off;
                    rq_data[rq_wp] <= (rx_off == CSR_ID)  ? MY_ID :
                                      (rx_off == CSR_ERR) ? {27'b0, err_vec} :
                                      (rx_off >= CSR_LIMIT) ? mem[rx_off[OB-1:2]] : 32'b0;
                    rq_wp   <= (rq_wp == RSP_Q_DEPTH-1) ? {QW{1'b0}} : rq_wp + 1'b1;
                    rq_push  = 1'b1;
                    rx_have <= 1'b0;
                end
            end

            // ---------------- core-facing ----------------
            case (c_state)
                C_IDLE: begin
                    if (mem_valid && !mem_ready) begin
                        if (ad_illegal) begin
                            // never hang on a bad address -- poison and flag it
                            mem_rdata   <= POISON;
                            mem_ready   <= 1'b1;
                            err_illegal <= 1'b1;
                        end else if (ad_local) begin
                            if (|mem_wstrb) begin
                                if (ad_off >= CSR_LIMIT) begin
                                    if (mem_wstrb[0]) mem[core_widx][ 7: 0] <= mem_wdata[ 7: 0];
                                    if (mem_wstrb[1]) mem[core_widx][15: 8] <= mem_wdata[15: 8];
                                    if (mem_wstrb[2]) mem[core_widx][23:16] <= mem_wdata[23:16];
                                    if (mem_wstrb[3]) mem[core_widx][31:24] <= mem_wdata[31:24];
                                end else if (ad_off == CSR_ERR) begin
                                    if (mem_wdata[0]) err_timeout <= 1'b0;
                                    if (mem_wdata[1]) err_illegal <= 1'b0;
                                    if (mem_wdata[2]) err_poison  <= 1'b0;
                                    if (mem_wdata[3]) err_stale   <= 1'b0;
                                    if (mem_wdata[4]) err_chk     <= 1'b0;
                                end
                                mem_ready <= 1'b1;
                            end else begin
                                loc_rdata <= (ad_off == CSR_ID)  ? MY_ID :
                                             (ad_off == CSR_ERR) ? {27'b0, err_vec} :
                                             (ad_off >= CSR_LIMIT) ? mem[core_widx] : 32'b0;
                                c_state   <= C_LOCAL;
                            end
                        end else begin
                            // remote: a fresh transaction starts with no retries used
                            retry_cnt <= {RW{1'b0}};
                            c_state   <= C_REQ;
                        end
                    end
                end

                C_LOCAL: begin
                    mem_rdata <= loc_rdata;
                    mem_ready <= 1'b1;
                    c_state   <= C_IDLE;
                end

                C_REQ: begin
                    // the TX engine takes the request this cycle (see tx_take_req)
                    if (tx_take_req) begin
                        if (|mem_wstrb) begin
                            // posted write: ack the core as soon as it is queued
                            mem_ready <= 1'b1;
                            c_state   <= C_IDLE;
                        end else begin
                            timeout_cnt <= {TOW{1'b0}};
                            c_state     <= C_WAIT;
                        end
                    end
                end

                C_WAIT: begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                    // a response arriving on the same cycle as the timeout wins
                    if (!rsp_match && timeout_cnt >= TIMEOUT_CYCLES) begin
                        if (retry_cnt < RETRY_MAX) begin
                            retry_cnt <= retry_cnt + 1'b1;
                            c_state   <= C_REQ;          // resend with a new tag
                        end else begin
                            mem_rdata   <= POISON;
                            mem_ready   <= 1'b1;
                            err_timeout <= 1'b1;
                            c_state     <= C_IDLE;
                        end
                    end
                end
                default: c_state <= C_IDLE;
            endcase

            // ---------------- transmit ----------------
            case (tx_state)
                TX_IDLE: begin
                    out_valid <= 1'b0;
                    if (!rq_empty) begin
                        // responses owed to others win: a starved status read
                        // is indistinguishable from an unreachable tile.
                        tx_head <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0],
                                                 noc_id_x(rq_dst[rq_rp]), noc_id_y(rq_dst[rq_rp]),
                                                 make_hdr(rq_off[rq_rp], 1'b0, 1'b1, 4'b0, rq_tag[rq_rp]));
                        tx_tail <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0],
                                                 noc_id_x(rq_dst[rq_rp]), noc_id_y(rq_dst[rq_rp]),
                                                 rq_data[rq_rp]);
                        rq_rp    <= (rq_rp == RSP_Q_DEPTH-1) ? {QW{1'b0}} : rq_rp + 1'b1;
                        rq_pop    = 1'b1;
                        tx_state <= TX_HEAD;
                    end else if (tx_take_req) begin
                        cur_tag <= cur_tag + 1'b1;
                        req_tgt <= ad_tile;
                        tx_head <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0], ad_x, ad_y,
                                                 make_hdr(ad_off, |mem_wstrb, 1'b0, mem_wstrb,
                                                          cur_tag + 1'b1));
                        tx_tail <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0], ad_x, ad_y,
                                                 mem_wdata);
                        tx_state <= TX_HEAD;
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
