// ni.v
// Network Interface: picorv32 (native memory interface) <-> NoC flits.
//
// PACKET FORMAT -- two flits, HEAD then TAIL, on every transaction.
//   HEAD  dx,dy = delta to destination (consumed hop by hop by the router)
//         rc    = MY_TILE_ID, i.e. the SOURCE tag; this is the return address
//         data  = { 14'b0, wstrb[3:0], is_resp, is_write, offset[11:0] }
//   TAIL  data  = write data (request) or read data (response)
//         dx,dy are zeroed by the router on non-HEAD flits and are not used.
//
// WHY is_resp IS AN EXPLICIT BIT, not inferred from rc:
//   Inferring "request vs response" from the source tag alone only works
//   while exactly one tile ever initiates. The roadmap already breaks that
//   twice: distributed BIST has every tile pinging its neighbours at once,
//   and the DMA gateway is a second initiator. The failure mode of getting it
//   wrong is a silent hang that no module can locally detect. One bit removes
//   the dependence on a global rule that nothing in hardware can check.
//
// WHY THERE IS A TIMEOUT:
//   picorv32 holds mem_valid until mem_ready. A response that never arrives
//   (faulted tile -- the exact case this project exists to handle) would hang
//   the core with no trap, no output, nothing to see on a board. On timeout we
//   return POISON, assert mem_ready, and latch a sticky bit software can read.
//
// ADDRESS MAP within a tile's 4KB region:
//   0x000..0x0FF  control/status registers (not memory)
//   0x100..0xFFF  local memory
//   PROGADDR_RESET for tile N must therefore be (N<<12) + 0x100.

module ni #(
    parameter DX_W            = 4,
    parameter DY_W            = 4,
    parameter DATA_W          = 32,
    parameter ROUTER_CODE     = 0,     // this tile's ID == router_code == bitmap index
    parameter TOTAL_ROUTERS   = 4,
    parameter MESH_X          = 2,
    parameter MESH_Y          = 2,
    parameter TIMEOUT_CYCLES  = 1024,
    parameter [31:0] POISON   = 32'hDEAD_BEEF
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
    input  wire [$clog2(TOTAL_ROUTERS):0] in_router_code_flit,
    input  wire                           in_valid,
    output wire                           in_ready,
    input  wire [1:0]                     in_type,
    input  wire [DX_W-1:0]                in_dx,    // unused: 0 at destination
    input  wire [DY_W-1:0]                in_dy,    // unused: 0 at destination
    input  wire [DATA_W-1:0]              in_data,

    output reg  [$clog2(TOTAL_ROUTERS):0] out_router_code_flit,
    output reg                            out_valid,
    input  wire                           out_ready,
    output reg  [1:0]                     out_type,
    output reg  signed [DX_W-1:0]         out_dx,
    output reg  signed [DY_W-1:0]         out_dy,
    output reg  [DATA_W-1:0]              out_data
);

    localparam RC_W = $clog2(TOTAL_ROUTERS) + 1;
    localparam [1:0] BODY = 2'b00, HEAD = 2'b01, HEADTAIL = 2'b10, TAIL = 2'b11;
    localparam MEM_WORDS = 1024;                 // 4KB; low 64 words shadowed by CSRs
    localparam CSR_LIMIT = 12'h100;

    // ---------------------------------------------------------------
    // Address decode for the core's current access
    // ---------------------------------------------------------------
    wire               ad_local, ad_remote, ad_illegal;
    wire [1:0]         ad_tile;
    wire signed [DX_W-1:0] ad_dx;
    wire signed [DY_W-1:0] ad_dy;
    wire [11:0]        ad_off;

    address_decoder #(
        .MESH_X(MESH_X), .MESH_Y(MESH_Y), .MY_TILE_ID(ROUTER_CODE),
        .DX_W(DX_W), .DY_W(DY_W)
    ) u_adec (
        .addr(mem_addr),
        .is_local(ad_local), .is_remote(ad_remote), .is_illegal(ad_illegal),
        .target_tile(ad_tile), .target_dx(ad_dx), .target_dy(ad_dy),
        .local_offset(ad_off)
    );

    // Return path to whoever sent us a request: same math, same module, fed a
    // synthetic address built from the requester's tile ID.
    reg [1:0] rx_src;      // source of the packet currently being received
    reg [1:0] rsp_dst;     // source of the read we still owe a response to
    wire signed [DX_W-1:0] rsp_dx;
    wire signed [DY_W-1:0] rsp_dy;

    address_decoder #(
        .MESH_X(MESH_X), .MESH_Y(MESH_Y), .MY_TILE_ID(ROUTER_CODE),
        .DX_W(DX_W), .DY_W(DY_W)
    ) u_adec_rsp (
        .addr({18'b0, rsp_dst, 12'h000}),
        .is_local(), .is_remote(), .is_illegal(), .target_tile(),
        .target_dx(rsp_dx), .target_dy(rsp_dy), .local_offset()
    );

    // ---------------------------------------------------------------
    // Local memory + CSRs
    // ---------------------------------------------------------------
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [31:0] loc_rdata;
    reg        err_timeout;     // sticky, write 1 to clear
    reg        err_illegal;     // sticky, write 1 to clear

    wire [9:0] core_widx = ad_off[11:2];

    // ---------------------------------------------------------------
    // Receive side: capture HEAD then TAIL into one pending packet
    // ---------------------------------------------------------------
    reg        rx_have;     // a complete packet is captured, not yet consumed
    reg        rx_in_pkt;   // HEAD seen, TAIL outstanding
    reg        rx_is_resp, rx_is_write;
    reg [3:0]  rx_wstrb;
    reg [11:0] rx_off;
    reg [31:0] rx_data;

    assign in_ready = !rx_have;
    wire rx_fire = in_valid && in_ready;

    // ---------------------------------------------------------------
    // Transmit side
    // ---------------------------------------------------------------
    localparam [1:0] TX_IDLE = 2'd0, TX_HEAD = 2'd1, TX_TAIL = 2'd2;
    reg [1:0]  tx_state;
    reg        tx_is_rsp;           // this packet is a response, not a request
    reg signed [DX_W-1:0] tx_dx;
    reg signed [DY_W-1:0] tx_dy;
    reg [31:0] tx_hdr, tx_payload;

    reg        rsp_pending;         // we owe someone a read response
    reg [31:0] rsp_data;

    // ---------------------------------------------------------------
    // Core-facing transaction state
    // ---------------------------------------------------------------
    localparam [1:0] C_IDLE = 2'd0, C_LOCAL = 2'd1, C_REQ = 2'd2, C_WAIT = 2'd3;
    reg [1:0]  c_state;
    reg [31:0] timeout_cnt;

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready    <= 1'b0;
            mem_rdata    <= 32'b0;
            out_valid    <= 1'b0;
            out_type     <= BODY;
            out_dx       <= {DX_W{1'b0}};
            out_dy       <= {DY_W{1'b0}};
            out_data     <= {DATA_W{1'b0}};
            out_router_code_flit <= ROUTER_CODE[RC_W-1:0];
            rx_have      <= 1'b0;
            rx_in_pkt    <= 1'b0;
            rx_src       <= 2'b0;
            rx_is_resp   <= 1'b0;
            rx_is_write  <= 1'b0;
            rx_wstrb     <= 4'b0;
            rx_off       <= 12'b0;
            rx_data      <= 32'b0;
            tx_state     <= TX_IDLE;
            tx_is_rsp    <= 1'b0;
            rsp_pending  <= 1'b0;
            rsp_data     <= 32'b0;
            rsp_dst      <= 2'b0;
            c_state      <= C_IDLE;
            timeout_cnt  <= 32'b0;
            err_timeout  <= 1'b0;
            err_illegal  <= 1'b0;
        end else begin
            mem_ready <= 1'b0;      // single-cycle ack by default

            // ---------------- receive ----------------
            if (rx_fire) begin
                if (in_type == HEAD) begin
                    rx_src      <= in_router_code_flit[1:0];
                    rx_off      <= in_data[11:0];
                    rx_is_write <= in_data[12];
                    rx_is_resp  <= in_data[13];
                    rx_wstrb    <= in_data[17:14];
                    rx_in_pkt   <= 1'b1;
                end else if (in_type == TAIL && rx_in_pkt) begin
                    rx_data   <= in_data;
                    rx_in_pkt <= 1'b0;
                    rx_have   <= 1'b1;
                end
            end

            // ---------------- consume a received packet ----------------
            if (rx_have) begin
                if (rx_is_resp) begin
                    // response to our outstanding read
                    if (c_state == C_WAIT) begin
                        mem_rdata <= rx_data;
                        mem_ready <= 1'b1;
                        c_state   <= C_IDLE;
                    end
                    rx_have <= 1'b0;
                end else if (rx_is_write) begin
                    // remote write into our memory (posted: no response owed)
                    if (rx_off >= CSR_LIMIT) begin
                        if (rx_wstrb[0]) mem[rx_off[11:2]][ 7: 0] <= rx_data[ 7: 0];
                        if (rx_wstrb[1]) mem[rx_off[11:2]][15: 8] <= rx_data[15: 8];
                        if (rx_wstrb[2]) mem[rx_off[11:2]][23:16] <= rx_data[23:16];
                        if (rx_wstrb[3]) mem[rx_off[11:2]][31:24] <= rx_data[31:24];
                    end else if (rx_off == 12'h004) begin
                        if (rx_data[0]) err_timeout <= 1'b0;
                        if (rx_data[1]) err_illegal <= 1'b0;
                    end
                    rx_have <= 1'b0;
                end else if (!rsp_pending) begin
                    // remote read: owe a response back to rx_src
                    rsp_dst  <= rx_src;
                    rsp_data <= (rx_off == 12'h000) ? {30'b0, ROUTER_CODE[1:0]} :
                                (rx_off == 12'h004) ? {30'b0, err_illegal, err_timeout} :
                                (rx_off >= CSR_LIMIT) ? mem[rx_off[11:2]] : 32'b0;
                    rsp_pending <= 1'b1;
                    rx_have     <= 1'b0;
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
                                end else if (ad_off == 12'h004) begin
                                    if (mem_wdata[0]) err_timeout <= 1'b0;
                                    if (mem_wdata[1]) err_illegal <= 1'b0;
                                end
                                mem_ready <= 1'b1;
                            end else begin
                                loc_rdata <= (ad_off == 12'h000) ? {30'b0, ROUTER_CODE[1:0]} :
                                             (ad_off == 12'h004) ? {30'b0, err_illegal, err_timeout} :
                                             (ad_off >= CSR_LIMIT) ? mem[core_widx] : 32'b0;
                                c_state   <= C_LOCAL;
                            end
                        end else begin
                            // remote
                            c_state <= C_REQ;
                        end
                    end
                end

                C_LOCAL: begin
                    mem_rdata <= loc_rdata;
                    mem_ready <= 1'b1;
                    c_state   <= C_IDLE;
                end

                C_REQ: begin
                    // wait until the TX engine has taken our request
                    if (tx_state == TX_IDLE && !rsp_pending) begin
                        if (|mem_wstrb) begin
                            // posted write: ack the core as soon as it is queued
                            mem_ready <= 1'b1;
                            c_state   <= C_IDLE;
                        end else begin
                            timeout_cnt <= 32'b0;
                            c_state     <= C_WAIT;
                        end
                    end
                end

                C_WAIT: begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                    if (timeout_cnt >= TIMEOUT_CYCLES) begin
                        mem_rdata   <= POISON;
                        mem_ready   <= 1'b1;
                        err_timeout <= 1'b1;
                        c_state     <= C_IDLE;
                    end
                end
                default: c_state <= C_IDLE;
            endcase

            // ---------------- transmit ----------------
            case (tx_state)
                TX_IDLE: begin
                    out_valid <= 1'b0;
                    if (rsp_pending) begin
                        // responses owed to others win: a starved status read
                        // is indistinguishable from an unreachable tile.
                        tx_is_rsp <= 1'b1;
                        tx_dx     <= rsp_dx;
                        tx_dy     <= rsp_dy;
                        tx_hdr    <= {18'b0, 1'b1, 1'b0, 12'h000};  // is_resp
                        tx_payload<= rsp_data;
                        tx_state  <= TX_HEAD;
                    end else if (c_state == C_REQ) begin
                        tx_is_rsp <= 1'b0;
                        tx_dx     <= ad_dx;
                        tx_dy     <= ad_dy;
                        tx_hdr    <= {14'b0, mem_wstrb, 1'b0, (|mem_wstrb), ad_off};
                        tx_payload<= mem_wdata;
                        tx_state  <= TX_HEAD;
                    end
                end

                TX_HEAD: begin
                    out_valid            <= 1'b1;
                    out_type             <= HEAD;
                    out_router_code_flit <= ROUTER_CODE[RC_W-1:0];
                    out_dx               <= tx_dx;
                    out_dy               <= tx_dy;
                    out_data             <= tx_hdr;
                    if (out_valid && out_ready) begin
                        out_type <= TAIL;
                        out_data <= tx_payload;
                        out_dx   <= {DX_W{1'b0}};
                        out_dy   <= {DY_W{1'b0}};
                        tx_state <= TX_TAIL;
                    end
                end

                TX_TAIL: begin
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                        tx_state  <= TX_IDLE;
                        if (tx_is_rsp) rsp_pending <= 1'b0;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule
