// sb_mem_ni.v
// Memory node of the single-bus baseline: bus packets <-> one AXI4 master.
// The AXI4 side goes to the DDR2 controller (MIG, through a SmartConnect for
// the clock crossing: single_bus/rtl/create_sb_mem.tcl) or, in simulation, to
// tb/axi4_mem_model.v. Same packet format, check bits and tag rules as ni.v;
// it sits on the bus exactly like a tile and has no core and no local RAM.
//
// ADDRESS MAP within this node's window (offsets, as on every tile)
//   0x000  node ID (ro)             0x004  error flags, write 1 to clear:
//                                          bit 1 illegal / AXI error
//                                          bit 2 poison TAIL received
//                                          bit 4 check-bit error
//   0x00C  number of nodes (ro)     0x010  node kind (ro) = 2: memory
//   0x020  DDR_BASE (rw) byte address in the DDR that offset 0x200 maps to.
//          ONE REGISTER PER REQUESTING NODE: a read or write of 0x020 acts
//          on the caller's own base, so the cores cannot disturb each other.
//          Word aligned; resets to 0.
//   0x120  availability (ro) = {1, 15'b0, all nodes}: the bus has no BIST,
//          so every node is reported usable. Lets software written for the
//          NoC gateway's bitmap run here unchanged.
//   0x200..(window end)  DDR word at DDR_BASE + (offset - 0x200)
//   other offsets below 0x200 read 0 and ignore writes.
//   shortcut: a paged window, because a packet carries only NOC_OFFSET_BITS
//   of address; raise NOC_OFFSET_BITS (up to 20) for a wider direct window.
//
// AXI4: single-beat INCR transfers (AxLEN = 0, AxSIZE = 4 bytes), one
// transaction at a time, address and data channels raised together. Writes
// are posted on the bus (no response packet) but always wait for BRESP here.
// A read answers with the data, or POISON on SLVERR/DECERR or on an address
// outside the DDR; both set the illegal flag.
//
// BUFFERING AND CONTENTION. One request is held while it is served; in_room
// is low meanwhile, so the bus keeps other nodes' requests in their transmit
// queues and stays free for traffic between the tiles.

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_mem_ni #(
    parameter integer MY_ID     = `NOC_NUM_TILES - 1,
    parameter [31:0]  DDR_BYTES = 32'h0800_0000,      // 128 MB
    parameter [31:0]  POISON    = `NOC_POISON_DATA
) (
    input  wire clk,
    input  wire rst_n,

    // bus side
    input  wire                   in_valid,
    output wire                   in_ready,
    output wire                   in_room,
    input  wire [`NOC_FLIT_W-1:0] in_flit,
    output reg                    out_valid,
    input  wire                   out_ready,
    output reg  [`NOC_FLIT_W-1:0] out_flit,

    // AXI4 master
    output reg  [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    output reg  [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    output wire [4:0]  err_flags      // same bit positions as ni.v
);

`include "noc_funcs.vh"

    localparam FW = `NOC_FLIT_W;
    localparam IW = `NOC_ID_W;
    localparam TW = `NOC_TAG_W;
    localparam OB = `NOC_OFFSET_BITS;
    localparam NT = `NOC_NUM_TILES;
    localparam [OB-1:0] DDR_LO = 'h200;       // first offset of the DDR window
    localparam [OB-1:0] CSR_ID = 'h000, CSR_ERR = 'h004, CSR_NT = 'h00C,
                        CSR_KIND = 'h010, CSR_BASE = 'h020, CSR_AVAIL = 'h120;
    localparam [1:0] T_HEAD = `NOC_T_HEAD, T_HEADTAIL = `NOC_T_HEADTAIL, T_TAIL = `NOC_T_TAIL;

    assign m_axi_awlen = 8'd0;   assign m_axi_arlen = 8'd0;
    assign m_axi_awsize = 3'd2;  assign m_axi_arsize = 3'd2;
    assign m_axi_awburst = 2'b01; assign m_axi_arburst = 2'b01;
    assign m_axi_wlast = 1'b1;

    // ---------------------------------------------------------------
    // receive: HEAD then TAIL into one pending request (as in ni.v)
    // ---------------------------------------------------------------
    reg          rx_have, rx_in_pkt;
    reg          rx_is_resp, rx_is_write;
    reg [3:0]    rx_wstrb;
    reg [OB-1:0] rx_off;
    reg [IW-1:0] rx_src;
    reg [TW-1:0] rx_tag;
    reg [31:0]   rx_data;

    assign in_ready = !rx_have;
    assign in_room  = !rx_have;
    wire          rx_fire = in_valid && in_ready;
    wire [1:0]    in_type = in_flit[`NOC_F_TYPE_LSB +: 2];
    wire [31:0]   in_data = in_flit[`NOC_F_DATA_LSB +: 32];

    // ---------------------------------------------------------------
    // registers
    // ---------------------------------------------------------------
    reg        err_illegal, err_poison, err_chk;
    assign err_flags = {err_chk, 1'b0, err_poison, err_illegal, 1'b0};
    reg [31:0] base [0:NT-1];

    wire [31:0] ddr_addr = base[rx_src] + {{(32-OB){1'b0}}, rx_off} - 32'h200;
    wire        ddr_ok   = (ddr_addr < DDR_BYTES);

    function [31:0] csr_read;
        input [OB-1:0] off;
        input [31:0]   my_base;
        begin
            csr_read = (off == CSR_ID)    ? MY_ID :
                       (off == CSR_ERR)   ? {27'b0, err_flags} :
                       (off == CSR_NT)    ? NT :
                       (off == CSR_KIND)  ? 32'd2 :
                       (off == CSR_BASE)  ? my_base :
                       (off == CSR_AVAIL) ? {1'b1, {(31-NT){1'b0}}, {NT{1'b1}}} : 32'b0;
        end
    endfunction

    // ---------------------------------------------------------------
    // serve one request at a time
    // ---------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0, S_WR = 3'd1, S_B = 3'd2, S_AR = 3'd3, S_R = 3'd4,
                     S_TXH = 3'd5, S_TXT = 3'd6;
    reg [2:0]    state;
    reg [FW-1:0] tx_tail;

    assign m_axi_bready = (state == S_B);
    assign m_axi_rready = (state == S_R);

    // response to the pending read: HEAD now, TAIL (the data) kept for later
    task respond;
        input [31:0] data;
        reg   [31:0] hdr;
        begin
            hdr = 32'b0;
            hdr[`NOC_H_OFF_LSB +: OB]         = rx_off;
            hdr[`NOC_H_RSP]                   = 1'b1;
            hdr[`NOC_H_LEN_LSB +: `NOC_LEN_W] = 1;
            hdr[`NOC_H_TAG_LSB +: TW]         = rx_tag;
            out_flit  <= noc_make_flit(T_HEAD, 1'b0, MY_ID[IW-1:0],
                                       noc_id_x(rx_src), noc_id_y(rx_src), hdr);
            tx_tail   <= noc_make_flit(T_TAIL, 1'b0, MY_ID[IW-1:0],
                                       noc_id_x(rx_src), noc_id_y(rx_src), data);
            out_valid <= 1'b1;
            state     <= S_TXH;
        end
    endtask

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_have <= 1'b0;  rx_in_pkt <= 1'b0;  rx_is_resp <= 1'b0;  rx_is_write <= 1'b0;
            rx_wstrb <= 4'b0; rx_off <= {OB{1'b0}}; rx_src <= {IW{1'b0}};
            rx_tag <= {TW{1'b0}}; rx_data <= 32'b0;
            err_illegal <= 1'b0; err_poison <= 1'b0; err_chk <= 1'b0;
            for (i = 0; i < NT; i = i + 1) base[i] <= 32'b0;
            state <= S_IDLE;  tx_tail <= {FW{1'b0}};
            out_valid <= 1'b0; out_flit <= {FW{1'b0}};
            m_axi_awaddr <= 32'b0; m_axi_awvalid <= 1'b0;
            m_axi_wdata <= 32'b0;  m_axi_wstrb <= 4'b0;  m_axi_wvalid <= 1'b0;
            m_axi_araddr <= 32'b0; m_axi_arvalid <= 1'b0;
        end else begin
            // ---------------- receive ----------------
            if (rx_fire) begin
                if (!noc_chk_ok(in_flit)) begin
                    err_chk   <= 1'b1;
                    rx_in_pkt <= 1'b0;
                end else if (in_type == T_HEAD || in_type == T_HEADTAIL) begin
                    rx_src      <= in_flit[`NOC_F_SRC_LSB +: IW];
                    rx_off      <= in_data[`NOC_H_OFF_LSB +: OB];
                    rx_is_write <= in_data[`NOC_H_WR];
                    rx_is_resp  <= in_data[`NOC_H_RSP];
                    rx_wstrb    <= in_data[`NOC_H_WSTRB_LSB +: 4];
                    rx_tag      <= in_data[`NOC_H_TAG_LSB +: TW];
                    rx_data     <= 32'b0;
                    rx_in_pkt   <= (in_type == T_HEAD);
                    rx_have     <= (in_type == T_HEADTAIL);
                end else if (in_type == T_TAIL) begin
                    rx_in_pkt <= 1'b0;
                    if (in_flit[`NOC_F_POISON]) err_poison <= 1'b1;
                    else if (rx_in_pkt) begin rx_data <= in_data; rx_have <= 1'b1; end
                end
            end

            // ---------------- serve ----------------
            case (state)
                S_IDLE: if (rx_have) begin
                    if (rx_is_resp) begin
                        rx_have <= 1'b0;                 // this node never asks: discard
                    end else if (rx_is_write) begin
                        if (rx_off >= DDR_LO && ddr_ok) begin
                            m_axi_awaddr  <= {ddr_addr[31:2], 2'b00};
                            m_axi_awvalid <= 1'b1;
                            m_axi_wdata   <= rx_data;
                            m_axi_wstrb   <= rx_wstrb;
                            m_axi_wvalid  <= 1'b1;
                            state         <= S_WR;
                        end else begin
                            if (rx_off >= DDR_LO) err_illegal <= 1'b1;
                            else if (rx_off == CSR_BASE) base[rx_src] <= {rx_data[31:2], 2'b00};
                            else if (rx_off == CSR_ERR) begin
                                if (rx_data[1]) err_illegal <= 1'b0;
                                if (rx_data[2]) err_poison  <= 1'b0;
                                if (rx_data[4]) err_chk     <= 1'b0;
                            end
                            rx_have <= 1'b0;
                        end
                    end else if (rx_off < DDR_LO) begin
                        respond(csr_read(rx_off, base[rx_src]));
                    end else if (ddr_ok) begin
                        m_axi_araddr  <= {ddr_addr[31:2], 2'b00};
                        m_axi_arvalid <= 1'b1;
                        state         <= S_AR;
                    end else begin
                        err_illegal <= 1'b1;
                        respond(POISON);
                    end
                end
                S_WR: begin
                    if (m_axi_awvalid && m_axi_awready) m_axi_awvalid <= 1'b0;
                    if (m_axi_wvalid  && m_axi_wready)  m_axi_wvalid  <= 1'b0;
                    if ((!m_axi_awvalid || m_axi_awready) && (!m_axi_wvalid || m_axi_wready))
                        state <= S_B;
                end
                S_B: if (m_axi_bvalid) begin
                    if (m_axi_bresp[1]) err_illegal <= 1'b1;
                    rx_have <= 1'b0;
                    state   <= S_IDLE;
                end
                S_AR: if (m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    state         <= S_R;
                end
                S_R: if (m_axi_rvalid) begin
                    if (m_axi_rresp[1]) err_illegal <= 1'b1;
                    respond(m_axi_rresp[1] ? POISON : m_axi_rdata);
                end
                S_TXH: if (out_ready) begin
                    out_flit <= tx_tail;
                    state    <= S_TXT;
                end
                S_TXT: if (out_ready) begin
                    out_valid <= 1'b0;
                    rx_have   <= 1'b0;
                    state     <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
