// sb_axil_tile.v
// One core tile of the AXI baseline: the core's memory interface, the tile's
// block RAM and CSRs, and two AXI4-Lite ports on the shared interconnect.
// It replaces ni.v in the baseline and has the same core-side ports and the
// same RAM (instance name u_ni, array mem), so the same programs,
// testbenches and images run on both systems; only the interconnect differs.
//
//   core -> local address     block RAM port A, or a CSR; no bus traffic
//   core -> any other address AXI4-Lite master (m_axil_*): another tile, the
//                             memory node, or the DDR. The interconnect
//                             answers an address that belongs to nobody with
//                             DECERR.
//   other masters -> this tile  AXI4-Lite slave (s_axil_*): block RAM port B
//                             and the CSRs
//
// ADDRESS MAP within the tile, as in ni.v: 0x000 tile ID, 0x004 error flags
// (write 1 to clear), 0x008 software status, 0x00C number of tiles, 0x010
// tile kind (0 = core), 0x018 core control (read: trapped; write 1: restart).
// RAM from 0x100.
//
// WRITES are posted, as in the NoC: the core is released when the
// interconnect has accepted the address and the data, and the response is
// collected in the background. A new bus access waits for it, so accesses
// from one tile stay in order.
//
// PROTECTION, as in ni.v: another master may write this tile's RAM only in
// the mailbox window [WIN_LO, WIN_HI); a DMA engine marks its accesses
// privileged (AxPROT[0] = 1) and may write anywhere from 0x100. With
// RD_PROTECT = 1 reads are limited the same way. A refused access gets
// SLVERR and sets the illegal flag here.
//
// TIMEOUT. AXI has none: a master whose transaction is never answered waits
// for ever. To match the NoC's network interface, which gives up after
// TIMEOUT_CYCLES x (RETRY_MAX + 1) cycles, this master gives up after the
// same time, returns POISON to the core and sets the timeout flag, so a
// broken bus is reported instead of hanging the core. Giving up withdraws a
// valid signal, which AXI does not allow; it only happens when the
// interconnect has already failed to answer for thousands of cycles.
// There are no check bits on AXI4-Lite: a corrupted data wire is not
// detected here, only by the software's own checks.
// Error flags: bit 0 timeout, bit 1 illegal (DECERR, SLVERR, refused access).

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_axil_tile #(
    parameter integer MY_ID          = 0,
    parameter integer TIMEOUT_CYCLES = 1024,
    parameter integer RETRY_MAX      = 2,
    parameter [31:0]  POISON         = `NOC_POISON_DATA,
    parameter         INIT_FILE      = "none",
    parameter [11:0]  WIN_LO         = 12'h800,
    parameter [11:0]  WIN_HI         = 12'hF00,
    parameter integer RD_PROTECT     = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    // core side: picorv32 native memory interface (as ni.v)
    input  wire        mem_valid,
    input  wire        mem_instr,
    output reg         mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wstrb,
    output reg  [31:0] mem_rdata,

    // AXI4-Lite master: this core's accesses to the rest of the system
    output reg  [31:0] m_axil_awaddr,
    output wire [2:0]  m_axil_awprot,
    output reg         m_axil_awvalid,
    input  wire        m_axil_awready,
    output reg  [31:0] m_axil_wdata,
    output reg  [3:0]  m_axil_wstrb,
    output reg         m_axil_wvalid,
    input  wire        m_axil_wready,
    input  wire [1:0]  m_axil_bresp,
    input  wire        m_axil_bvalid,
    output wire        m_axil_bready,
    output reg  [31:0] m_axil_araddr,
    output wire [2:0]  m_axil_arprot,
    output reg         m_axil_arvalid,
    input  wire        m_axil_arready,
    input  wire [31:0] m_axil_rdata,
    input  wire [1:0]  m_axil_rresp,
    input  wire        m_axil_rvalid,
    output wire        m_axil_rready,

    // AXI4-Lite slave: other masters' accesses to this tile
    input  wire [31:0] s_axil_awaddr,
    input  wire [2:0]  s_axil_awprot,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [31:0] s_axil_araddr,
    input  wire [2:0]  s_axil_arprot,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    // status, as ni.v
    output wire [4:0]  err_flags,
    output wire [31:0] sw_status,
    input  wire [9:0]  bist_status,     // unused: a bus has no link BIST
    input  wire        core_trap,
    output wire        core_restart
);

    localparam integer OB = `NOC_OFFSET_BITS;
    localparam integer AW = OB - 2;
    localparam integer MEM_WORDS = 1 << AW;
    localparam [OB-1:0] CSR_LIMIT = 'h100;
    localparam [OB-1:0] CSR_ID = 'h000, CSR_ERR = 'h004, CSR_SW = 'h008, CSR_NT = 'h00C,
                        CSR_KIND = 'h010, CSR_CORE = 'h018;
    localparam integer TMO = TIMEOUT_CYCLES * (RETRY_MAX + 1);
    localparam integer TW  = $clog2(TMO + 2);

    assign m_axil_awprot = 3'b000;
    assign m_axil_arprot = 3'b000;

    // ---------------------------------------------------------------
    // CSRs
    // ---------------------------------------------------------------
    reg        err_timeout, err_illegal;
    reg [31:0] sw_reg;
    reg [3:0]  restart_cnt;
    assign err_flags    = {3'b000, err_illegal, err_timeout};
    assign sw_status    = sw_reg;
    assign core_restart = |restart_cnt;

    function [31:0] csr_read;
        input [OB-1:0] off;
        begin
            csr_read = (off == CSR_ID)   ? MY_ID :
                       (off == CSR_ERR)  ? {27'b0, err_flags} :
                       (off == CSR_SW)   ? sw_reg :
                       (off == CSR_NT)   ? `NOC_NUM_TILES :
                       (off == CSR_CORE) ? {31'b0, core_trap} : 32'b0;
        end
    endfunction

    // ---------------------------------------------------------------
    // block RAM, true dual port (the same template as ni.v)
    // ---------------------------------------------------------------
    reg [31:0] mem [0:MEM_WORDS-1];
    generate
        if (INIT_FILE != "none") begin : g_init
            initial $readmemh(INIT_FILE, mem);
        end
    endgenerate

    wire          is_local = (mem_addr[31:OB] == MY_ID);
    wire [OB-1:0] l_off    = mem_addr[OB-1:0];

    localparam [2:0] C_IDLE = 3'd0, C_LOCAL = 3'd1, C_RD = 3'd2, C_RDATA = 3'd3, C_WR = 3'd4;
    reg [2:0]    c_state;
    wire         core_new = (c_state == C_IDLE) && mem_valid && !mem_ready;
    wire         lmem     = core_new && is_local && (l_off >= CSR_LIMIT);

    wire          a_en    = lmem;
    wire [3:0]    a_we    = lmem ? mem_wstrb : 4'b0;
    wire [AW-1:0] a_addr  = l_off[OB-1:2];
    reg  [31:0]   a_rdata;
    always @(posedge clk) begin
        if (a_en) begin
            if (a_we[0]) mem[a_addr][ 7: 0] <= mem_wdata[ 7: 0];
            if (a_we[1]) mem[a_addr][15: 8] <= mem_wdata[15: 8];
            if (a_we[2]) mem[a_addr][23:16] <= mem_wdata[23:16];
            if (a_we[3]) mem[a_addr][31:24] <= mem_wdata[31:24];
            a_rdata <= mem[a_addr];
        end
    end

    // slave side, port B
    localparam [1:0] S_IDLE = 2'd0, S_RRESP = 2'd1, S_BRESP = 2'd2;
    reg  [1:0]    s_state;
    reg           aw_got, w_got;
    reg  [31:0]   sw_addr, sw_data;
    reg  [3:0]    sw_strb;
    reg           sw_priv;
    reg           rd_mem;          // the read in progress returns RAM data
    reg  [31:0]   rd_csr;          // ... or this
    reg  [1:0]    rd_resp;

    assign s_axil_arready = (s_state == S_IDLE) && !aw_got && !w_got;
    assign s_axil_awready = (s_state == S_IDLE) && !aw_got && !s_axil_arvalid;
    assign s_axil_wready  = (s_state == S_IDLE) && !w_got  && !s_axil_arvalid;

    wire          ar_fire  = s_axil_arvalid && s_axil_arready;
    wire [OB-1:0] ar_off   = s_axil_araddr[OB-1:0];
    wire          ar_win   = (ar_off >= WIN_LO) && (ar_off < WIN_HI);
    wire          ar_deny  = (RD_PROTECT != 0) && (ar_off >= CSR_LIMIT) && !s_axil_arprot[0] && !ar_win;
    wire          wr_now   = (s_state == S_IDLE) && aw_got && w_got;
    wire [OB-1:0] w_off    = sw_addr[OB-1:0];
    wire          w_win    = (w_off >= WIN_LO) && (w_off < WIN_HI);
    wire          w_ram_ok = (w_off >= CSR_LIMIT) && (sw_priv || w_win);
    wire          w_ram_no = (w_off >= CSR_LIMIT) && !(sw_priv || w_win);

    wire          b_en   = (ar_fire && ar_off >= CSR_LIMIT && !ar_deny) || (wr_now && w_ram_ok);
    wire [3:0]    b_we   = (wr_now && w_ram_ok) ? sw_strb : 4'b0;
    wire [AW-1:0] b_addr = wr_now ? w_off[OB-1:2] : ar_off[OB-1:2];
    reg  [31:0]   b_rdata;
    always @(posedge clk) begin
        if (b_en) begin
            if (b_we[0]) mem[b_addr][ 7: 0] <= sw_data[ 7: 0];
            if (b_we[1]) mem[b_addr][15: 8] <= sw_data[15: 8];
            if (b_we[2]) mem[b_addr][23:16] <= sw_data[23:16];
            if (b_we[3]) mem[b_addr][31:24] <= sw_data[31:24];
            b_rdata <= mem[b_addr];
        end
    end

    // ---------------------------------------------------------------
    // master side
    // ---------------------------------------------------------------
    reg          b_pending;        // a posted write's response is outstanding
    reg          r_orphan, b_orphan;   // drop a response that arrives after a timeout
    reg [TW-1:0] tmo;
    reg          loc_mem;
    reg [31:0]   loc_csr;
    reg          aw_done, w_done;

    assign m_axil_rready = (c_state == C_RDATA) || r_orphan;
    assign m_axil_bready = b_pending || b_orphan;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready <= 1'b0; mem_rdata <= 32'b0; c_state <= C_IDLE;
            loc_mem <= 1'b0; loc_csr <= 32'b0;
            m_axil_awaddr <= 32'b0; m_axil_awvalid <= 1'b0; m_axil_wdata <= 32'b0;
            m_axil_wstrb <= 4'b0; m_axil_wvalid <= 1'b0; m_axil_araddr <= 32'b0; m_axil_arvalid <= 1'b0;
            aw_done <= 1'b0; w_done <= 1'b0; b_pending <= 1'b0; r_orphan <= 1'b0; b_orphan <= 1'b0;
            tmo <= {TW{1'b0}};
            err_timeout <= 1'b0; err_illegal <= 1'b0; sw_reg <= 32'b0; restart_cnt <= 4'd0;
            s_state <= S_IDLE; aw_got <= 1'b0; w_got <= 1'b0;
            sw_addr <= 32'b0; sw_data <= 32'b0; sw_strb <= 4'b0; sw_priv <= 1'b0;
            rd_mem <= 1'b0; rd_csr <= 32'b0; rd_resp <= 2'b00;
            s_axil_bvalid <= 1'b0; s_axil_bresp <= 2'b00;
            s_axil_rvalid <= 1'b0; s_axil_rresp <= 2'b00; s_axil_rdata <= 32'b0;
        end else begin
            mem_ready <= 1'b0;
            if (restart_cnt != 0) restart_cnt <= restart_cnt - 1'b1;

            // ---------------- the posted write's response ----------------
            if (b_pending) begin
                if (m_axil_bvalid) begin
                    if (m_axil_bresp[1]) err_illegal <= 1'b1;
                    b_pending <= 1'b0;
                end else if (tmo == TMO) begin
                    b_pending <= 1'b0; b_orphan <= 1'b1; err_timeout <= 1'b1;
                end
            end else if (b_orphan && m_axil_bvalid) begin
                b_orphan <= 1'b0;
            end
            if (r_orphan && m_axil_rvalid && c_state != C_RDATA) r_orphan <= 1'b0;

            // ---------------- core side ----------------
            case (c_state)
                C_IDLE: if (core_new) begin
                    if (is_local) begin
                        if (|mem_wstrb) begin
                            if (l_off == CSR_ERR) begin
                                if (mem_wdata[0]) err_timeout <= 1'b0;
                                if (mem_wdata[1]) err_illegal <= 1'b0;
                            end else if (l_off == CSR_SW) begin
                                if (mem_wstrb[0]) sw_reg[ 7: 0] <= mem_wdata[ 7: 0];
                                if (mem_wstrb[1]) sw_reg[15: 8] <= mem_wdata[15: 8];
                                if (mem_wstrb[2]) sw_reg[23:16] <= mem_wdata[23:16];
                                if (mem_wstrb[3]) sw_reg[31:24] <= mem_wdata[31:24];
                            end
                            mem_ready <= 1'b1;
                        end else begin
                            loc_mem <= (l_off >= CSR_LIMIT);
                            loc_csr <= csr_read(l_off);
                            c_state <= C_LOCAL;
                        end
                    end else if (!b_pending) begin           // keep this tile's bus accesses in order
                        tmo <= {TW{1'b0}};
                        if (|mem_wstrb) begin
                            m_axil_awaddr <= {mem_addr[31:2], 2'b00}; m_axil_awvalid <= 1'b1;
                            m_axil_wdata <= mem_wdata; m_axil_wstrb <= mem_wstrb; m_axil_wvalid <= 1'b1;
                            aw_done <= 1'b0; w_done <= 1'b0;
                            c_state <= C_WR;
                        end else begin
                            m_axil_araddr <= {mem_addr[31:2], 2'b00}; m_axil_arvalid <= 1'b1;
                            c_state <= C_RD;
                        end
                    end
                end
                C_LOCAL: begin
                    mem_rdata <= loc_mem ? a_rdata : loc_csr;
                    mem_ready <= 1'b1;
                    c_state   <= C_IDLE;
                end
                C_RD: begin
                    tmo <= tmo + 1'b1;
                    if (m_axil_arready) begin
                        m_axil_arvalid <= 1'b0;
                        c_state <= C_RDATA;
                    end else if (tmo == TMO) begin
                        m_axil_arvalid <= 1'b0;              // the bus never took it
                        mem_rdata <= POISON; mem_ready <= 1'b1; err_timeout <= 1'b1;
                        c_state <= C_IDLE;
                    end
                end
                C_RDATA: begin
                    tmo <= tmo + 1'b1;
                    if (m_axil_rvalid) begin
                        if (m_axil_rresp[1]) err_illegal <= 1'b1;
                        mem_rdata <= m_axil_rresp[1] ? POISON : m_axil_rdata;
                        mem_ready <= 1'b1;
                        c_state   <= C_IDLE;
                    end else if (tmo == TMO) begin
                        r_orphan <= 1'b1;                    // the answer may still come: drop it
                        mem_rdata <= POISON; mem_ready <= 1'b1; err_timeout <= 1'b1;
                        c_state <= C_IDLE;
                    end
                end
                C_WR: begin
                    tmo <= tmo + 1'b1;
                    if (m_axil_awvalid && m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wvalid  && m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if ((!m_axil_awvalid || m_axil_awready) && (!m_axil_wvalid || m_axil_wready)) begin
                        mem_ready <= 1'b1;                   // posted: release the core
                        b_pending <= 1'b1;
                        tmo       <= {TW{1'b0}};
                        c_state   <= C_IDLE;
                    end else if (tmo == TMO) begin
                        m_axil_awvalid <= 1'b0; m_axil_wvalid <= 1'b0;
                        mem_ready <= 1'b1; err_timeout <= 1'b1;
                        c_state <= C_IDLE;
                    end
                end
                default: c_state <= C_IDLE;
            endcase
            if (b_pending && c_state == C_IDLE && !(core_new && !is_local)) tmo <= tmo + 1'b1;

            // ---------------- slave side ----------------
            if (s_axil_awvalid && s_axil_awready) begin
                aw_got <= 1'b1; sw_addr <= s_axil_awaddr; sw_priv <= s_axil_awprot[0];
            end
            if (s_axil_wvalid && s_axil_wready) begin
                w_got <= 1'b1; sw_data <= s_axil_wdata; sw_strb <= s_axil_wstrb;
            end
            case (s_state)
                S_IDLE: begin
                    if (ar_fire) begin
                        rd_mem  <= (ar_off >= CSR_LIMIT) && !ar_deny;
                        rd_csr  <= ar_deny ? POISON : csr_read(ar_off);
                        rd_resp <= ar_deny ? 2'b10 : 2'b00;
                        if (ar_deny) err_illegal <= 1'b1;
                        s_state <= S_RRESP;
                    end else if (wr_now) begin
                        if (w_ram_no) err_illegal <= 1'b1;
                        else if (w_off == CSR_ERR) begin
                            if (sw_data[0]) err_timeout <= 1'b0;
                            if (sw_data[1]) err_illegal <= 1'b0;
                        end else if (w_off == CSR_SW) begin
                            if (sw_strb[0]) sw_reg[ 7: 0] <= sw_data[ 7: 0];
                            if (sw_strb[1]) sw_reg[15: 8] <= sw_data[15: 8];
                            if (sw_strb[2]) sw_reg[23:16] <= sw_data[23:16];
                            if (sw_strb[3]) sw_reg[31:24] <= sw_data[31:24];
                        end else if (w_off == CSR_CORE) begin
                            if (sw_data[0]) restart_cnt <= 4'hF;
                        end
                        s_axil_bresp  <= w_ram_no ? 2'b10 : 2'b00;
                        s_axil_bvalid <= 1'b1;
                        aw_got <= 1'b0; w_got <= 1'b0;
                        s_state <= S_BRESP;
                    end
                end
                S_RRESP: begin
                    if (!s_axil_rvalid) begin                // RAM data is out one cycle after the address
                        s_axil_rdata  <= rd_mem ? b_rdata : rd_csr;
                        s_axil_rresp  <= rd_resp;
                        s_axil_rvalid <= 1'b1;
                    end else if (s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        s_state <= S_IDLE;
                    end
                end
                S_BRESP: if (s_axil_bready) begin
                    s_axil_bvalid <= 1'b0;
                    s_state <= S_IDLE;
                end
                default: s_state <= S_IDLE;
            endcase
        end
    end

endmodule
