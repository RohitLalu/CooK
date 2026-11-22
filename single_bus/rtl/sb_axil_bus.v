// sb_axil_bus.v
// The single shared bus of the AXI baseline: a standard AXI4-Lite shared
// interconnect (axil_interconnect from verilog-axi, third_party/verilog-axi)
// with the address map of the NoC system, plus the baseline's fault
// injection. One transaction crosses the bus at a time, with round-robin
// arbitration between the masters: the textbook shared bus.
//
// SLAVES (M side): node i at i << NOC_OFFSET_BITS for i < NODES, each with
// a window of 2**NOC_OFFSET_BITS bytes; with DDR = 1 one more slave, the
// DDR, at 0x8000_0000 (128 MB). Any other address gets DECERR from the
// interconnect.
// MASTERS (S side): MASTERS of them, in any order the user chooses.
// Buses are flattened, master or slave k at slice k.
//
// FAULTS (metric M3): fault_grant = the bus grants nothing (every master
// waits, then times out); fault_flip = one data wire of the shared bus is
// inverted (bit 0 of every read and written word), which AXI4-Lite, having
// no check bits, cannot detect.

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_axil_bus #(
    parameter integer MASTERS = 3,
    parameter integer NODES   = `NOC_NUM_TILES,
    parameter integer DDR     = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire fault_grant,
    input  wire fault_flip,
    output wire active,           // a channel of the bus is busy this cycle

    // masters
    input  wire [MASTERS*32-1:0] s_awaddr,
    input  wire [MASTERS*3-1:0]  s_awprot,
    input  wire [MASTERS-1:0]    s_awvalid,
    output wire [MASTERS-1:0]    s_awready,
    input  wire [MASTERS*32-1:0] s_wdata,
    input  wire [MASTERS*4-1:0]  s_wstrb,
    input  wire [MASTERS-1:0]    s_wvalid,
    output wire [MASTERS-1:0]    s_wready,
    output wire [MASTERS*2-1:0]  s_bresp,
    output wire [MASTERS-1:0]    s_bvalid,
    input  wire [MASTERS-1:0]    s_bready,
    input  wire [MASTERS*32-1:0] s_araddr,
    input  wire [MASTERS*3-1:0]  s_arprot,
    input  wire [MASTERS-1:0]    s_arvalid,
    output wire [MASTERS-1:0]    s_arready,
    output wire [MASTERS*32-1:0] s_rdata,
    output wire [MASTERS*2-1:0]  s_rresp,
    output wire [MASTERS-1:0]    s_rvalid,
    input  wire [MASTERS-1:0]    s_rready,

    // slaves: NODES nodes, then the DDR when DDR = 1
    output wire [(NODES+DDR)*32-1:0] m_awaddr,
    output wire [(NODES+DDR)*3-1:0]  m_awprot,
    output wire [NODES+DDR-1:0]      m_awvalid,
    input  wire [NODES+DDR-1:0]      m_awready,
    output wire [(NODES+DDR)*32-1:0] m_wdata,
    output wire [(NODES+DDR)*4-1:0]  m_wstrb,
    output wire [NODES+DDR-1:0]      m_wvalid,
    input  wire [NODES+DDR-1:0]      m_wready,
    input  wire [(NODES+DDR)*2-1:0]  m_bresp,
    input  wire [NODES+DDR-1:0]      m_bvalid,
    output wire [NODES+DDR-1:0]      m_bready,
    output wire [(NODES+DDR)*32-1:0] m_araddr,
    output wire [(NODES+DDR)*3-1:0]  m_arprot,
    output wire [NODES+DDR-1:0]      m_arvalid,
    input  wire [NODES+DDR-1:0]      m_arready,
    input  wire [(NODES+DDR)*32-1:0] m_rdata,
    input  wire [(NODES+DDR)*2-1:0]  m_rresp,
    input  wire [NODES+DDR-1:0]      m_rvalid,
    output wire [NODES+DDR-1:0]      m_rready
);

    localparam integer OB = `NOC_OFFSET_BITS;
    localparam integer MC = NODES + DDR;

    function [MC*32-1:0] bases;
        input integer dummy;
        integer i;
        begin
            bases = {MC*32{1'b0}};
            for (i = 0; i < NODES; i = i + 1) bases[i*32 +: 32] = i << OB;
            if (DDR) bases[NODES*32 +: 32] = 32'h8000_0000;
        end
    endfunction
    function [MC*32-1:0] widths;
        input integer dummy;
        integer i;
        begin
            widths = {MC*32{1'b0}};
            for (i = 0; i < NODES; i = i + 1) widths[i*32 +: 32] = OB;
            if (DDR) widths[NODES*32 +: 32] = 27;
        end
    endfunction

    // fault gating between the masters and the interconnect
    wire [MASTERS-1:0]    ic_awready, ic_wready, ic_bvalid, ic_arready, ic_rvalid;
    wire [MASTERS*32-1:0] ic_rdata;
    wire [MASTERS-1:0]    go = {MASTERS{!fault_grant}};
    wire [31:0]           flip = {31'b0, fault_flip};
    assign s_awready = ic_awready & go;
    assign s_wready  = ic_wready  & go;
    assign s_bvalid  = ic_bvalid  & go;
    assign s_arready = ic_arready & go;
    assign s_rvalid  = ic_rvalid  & go;
    wire [MASTERS*32-1:0] wdata_f;
    genvar k;
    generate
        for (k = 0; k < MASTERS; k = k + 1) begin : g_flip
            assign s_rdata[k*32 +: 32] = ic_rdata[k*32 +: 32] ^ flip;
            assign wdata_f[k*32 +: 32] = s_wdata[k*32 +: 32] ^ flip;
        end
    endgenerate

    axil_interconnect #(
        .S_COUNT(MASTERS), .M_COUNT(MC), .DATA_WIDTH(32), .ADDR_WIDTH(32),
        .M_BASE_ADDR(bases(0)), .M_ADDR_WIDTH(widths(0))
    ) u_ic (
        .clk(clk), .rst(!rst_n),
        .s_axil_awaddr(s_awaddr), .s_axil_awprot(s_awprot), .s_axil_awvalid(s_awvalid & go),
        .s_axil_awready(ic_awready),
        .s_axil_wdata(wdata_f), .s_axil_wstrb(s_wstrb), .s_axil_wvalid(s_wvalid & go), .s_axil_wready(ic_wready),
        .s_axil_bresp(s_bresp), .s_axil_bvalid(ic_bvalid), .s_axil_bready(s_bready & go),
        .s_axil_araddr(s_araddr), .s_axil_arprot(s_arprot), .s_axil_arvalid(s_arvalid & go),
        .s_axil_arready(ic_arready),
        .s_axil_rdata(ic_rdata), .s_axil_rresp(s_rresp), .s_axil_rvalid(ic_rvalid), .s_axil_rready(s_rready & go),
        .m_axil_awaddr(m_awaddr), .m_axil_awprot(m_awprot), .m_axil_awvalid(m_awvalid), .m_axil_awready(m_awready),
        .m_axil_wdata(m_wdata), .m_axil_wstrb(m_wstrb), .m_axil_wvalid(m_wvalid), .m_axil_wready(m_wready),
        .m_axil_bresp(m_bresp), .m_axil_bvalid(m_bvalid), .m_axil_bready(m_bready),
        .m_axil_araddr(m_araddr), .m_axil_arprot(m_arprot), .m_axil_arvalid(m_arvalid), .m_axil_arready(m_arready),
        .m_axil_rdata(m_rdata), .m_axil_rresp(m_rresp), .m_axil_rvalid(m_rvalid), .m_axil_rready(m_rready)
    );

    assign active = |{m_awvalid, m_wvalid, m_bvalid, m_arvalid, m_rvalid};

endmodule
