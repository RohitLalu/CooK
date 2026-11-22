// sb_top.v
// The single-bus baseline system: three picorv32 cores and the DDR on one
// standard shared AXI4-Lite bus (sb_axil_bus.v). Counterpart of
// rtl/integrated/mesh/mesh_top.v with the gateway: nodes 0..2 are core tiles,
// node 3 holds the memory node's registers, and the DDR is a slave at
// 0x8000_0000 (128 MB, flat: any core addresses it directly).
//
// Each core tile is sb_axil_tile: the same core-side ports, block RAM and
// CSRs as the NoC's ni.v (instance name u_ni, array mem), so the NoC's
// images and testbenches run here unchanged. Only the interconnect differs.
// Shared with the NoC, unchanged: picorv32 and noc_defs.vh. The address map
// is the NoC's: node n owns the window n << NOC_OFFSET_BITS.
//
// The DDR port (m_axi_*) is AXI4, one beat per transfer, for the MIG
// (single_bus/rtl/create_sb_mem.tcl) or tb/axi4_mem_model.v. Its address
// starts at 0: the bus's 0x8000_0000 is DDR address 0.
// No BIST and no hold-off: the cores leave reset with the system.
// bus_err_drop is always 0 here: a bus error is reported in the master's
// tile_err (bit 1, DECERR or SLVERR; bit 0, timeout).

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_top #(
    parameter integer MEM_INIT     = 0,
    parameter         MEM_PREFIX   = "tile",
    parameter integer NI_TIMEOUT   = 1024,
    parameter integer NI_RETRY_MAX = 2,
    parameter integer RD_PROTECT   = 0,       // remote reads limited to CSRs and the mailbox
    parameter [`NOC_NUM_TILES-1:0] CORE_MASK = {`NOC_NUM_TILES{1'b1}}
) (
    input  wire clk,
    input  wire rst_n,

    output wire [`NOC_NUM_TILES-1:0]    tile_trap,
    output wire [`NOC_NUM_TILES*5-1:0]  tile_err,
    output wire [`NOC_NUM_TILES*32-1:0] tile_sw,

    // bus fault injection and status (sb_axil_bus.v); bus_err_drop is always 0
    input  wire                         fault_grant,
    input  wire                         fault_flip,
    output wire [`NOC_NUM_TILES-1:0]    bus_err_drop,
    output wire                         bus_active,

    // memory node: AXI4 master
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);

    localparam integer NT  = `NOC_NUM_TILES;
    localparam integer OB  = `NOC_OFFSET_BITS;
    localparam integer MEM = NT - 1;          // the memory node
    localparam integer NM  = NT - 1;          // masters: the core tiles
    localparam integer NS  = NT + 1;          // slaves: every node, then the DDR

    generate
        if (NT != 4) begin : sb_check_nt
            NOC_CONFIG_ERROR_bus_baseline_assumes_four_node_ids u_err ();
        end
    endgenerate

    wire [NM*32-1:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    wire [NM*3-1:0]  s_awprot, s_arprot;
    wire [NM*4-1:0]  s_wstrb;
    wire [NM*2-1:0]  s_bresp, s_rresp;
    wire [NM-1:0]    s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
    wire [NM-1:0]    s_arvalid, s_arready, s_rvalid, s_rready;
    wire [NS*32-1:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    wire [NS*3-1:0]  m_awprot, m_arprot;
    wire [NS*4-1:0]  m_wstrb;
    wire [NS*2-1:0]  m_bresp, m_rresp;
    wire [NS-1:0]    m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    wire [NS-1:0]    m_arvalid, m_arready, m_rvalid, m_rready;

    sb_axil_bus #(.MASTERS(NM), .NODES(NT), .DDR(1)) u_bus (
        .clk(clk), .rst_n(rst_n), .fault_grant(fault_grant), .fault_flip(fault_flip), .active(bus_active),
        .s_awaddr(s_awaddr), .s_awprot(s_awprot), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arprot(s_arprot), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awaddr(m_awaddr), .m_awprot(m_awprot), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arprot(m_arprot), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );
    assign bus_err_drop = {NT{1'b0}};

    // ---------------- node 3: the memory node's registers ----------------
    sb_axil_info #(.MY_ID(MEM)) u_info (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(m_awaddr[MEM*32 +: 32]), .s_axil_awvalid(m_awvalid[MEM]), .s_axil_awready(m_awready[MEM]),
        .s_axil_wvalid(m_wvalid[MEM]), .s_axil_wready(m_wready[MEM]),
        .s_axil_bvalid(m_bvalid[MEM]), .s_axil_bready(m_bready[MEM]),
        .s_axil_araddr(m_araddr[MEM*32 +: 32]), .s_axil_arvalid(m_arvalid[MEM]), .s_axil_arready(m_arready[MEM]),
        .s_axil_rdata(m_rdata[MEM*32 +: 32]), .s_axil_rvalid(m_rvalid[MEM]), .s_axil_rready(m_rready[MEM])
    );
    assign m_bresp[MEM*2 +: 2] = 2'b00;
    assign m_rresp[MEM*2 +: 2] = 2'b00;
    assign tile_trap[MEM]        = 1'b0;
    assign tile_err[MEM*5 +: 5]  = 5'b0;
    assign tile_sw[MEM*32 +: 32] = 32'b0;

    // ---------------- the DDR: AXI4-Lite to single-beat AXI4 ----------------
    localparam integer D = NT;
    assign m_axi_awaddr  = {5'b0, m_awaddr[D*32 +: 27]};
    assign m_axi_awlen   = 8'd0;   assign m_axi_arlen   = 8'd0;
    assign m_axi_awsize  = 3'd2;   assign m_axi_arsize  = 3'd2;
    assign m_axi_awburst = 2'b01;  assign m_axi_arburst = 2'b01;
    assign m_axi_awvalid = m_awvalid[D];   assign m_awready[D] = m_axi_awready;
    assign m_axi_wdata   = m_wdata[D*32 +: 32];
    assign m_axi_wstrb   = m_wstrb[D*4 +: 4];
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = m_wvalid[D];    assign m_wready[D]  = m_axi_wready;
    assign m_bresp[D*2 +: 2] = m_axi_bresp;
    assign m_bvalid[D]   = m_axi_bvalid;   assign m_axi_bready = m_bready[D];
    assign m_axi_araddr  = {5'b0, m_araddr[D*32 +: 27]};
    assign m_axi_arvalid = m_arvalid[D];   assign m_arready[D] = m_axi_arready;
    assign m_rdata[D*32 +: 32] = m_axi_rdata;
    assign m_rresp[D*2 +: 2]   = m_axi_rresp;
    assign m_rvalid[D]   = m_axi_rvalid;   assign m_axi_rready = m_rready[D];

    // ---------------- nodes 0..2: core tiles ----------------
    genvar t;
    generate
        for (t = 0; t < MEM; t = t + 1) begin : g_tile
            wire        mem_valid, mem_instr, mem_ready;
            wire [31:0] mem_addr, mem_wdata, mem_rdata;
            wire [ 3:0] mem_wstrb;
            wire        core_restart;

            // "<prefix>NN.mem", NN = tile number in two decimal digits
            localparam [7:0] DIG_HI = 8'd48 + ((t / 10) % 10);
            localparam [7:0] DIG_LO = 8'd48 + (t % 10);
            localparam [8*2-1:0] NUM_STR = {DIG_HI, DIG_LO};

            sb_axil_tile #(
                .MY_ID(t), .TIMEOUT_CYCLES(NI_TIMEOUT), .RETRY_MAX(NI_RETRY_MAX),
                .INIT_FILE(MEM_INIT ? {MEM_PREFIX, NUM_STR, ".mem"} : "none"),
                .RD_PROTECT(RD_PROTECT)
            ) u_ni (
                .clk(clk), .rst_n(rst_n),
                .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
                .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
                .m_axil_awaddr(s_awaddr[t*32 +: 32]), .m_axil_awprot(s_awprot[t*3 +: 3]),
                .m_axil_awvalid(s_awvalid[t]), .m_axil_awready(s_awready[t]),
                .m_axil_wdata(s_wdata[t*32 +: 32]), .m_axil_wstrb(s_wstrb[t*4 +: 4]),
                .m_axil_wvalid(s_wvalid[t]), .m_axil_wready(s_wready[t]),
                .m_axil_bresp(s_bresp[t*2 +: 2]), .m_axil_bvalid(s_bvalid[t]), .m_axil_bready(s_bready[t]),
                .m_axil_araddr(s_araddr[t*32 +: 32]), .m_axil_arprot(s_arprot[t*3 +: 3]),
                .m_axil_arvalid(s_arvalid[t]), .m_axil_arready(s_arready[t]),
                .m_axil_rdata(s_rdata[t*32 +: 32]), .m_axil_rresp(s_rresp[t*2 +: 2]),
                .m_axil_rvalid(s_rvalid[t]), .m_axil_rready(s_rready[t]),
                .s_axil_awaddr(m_awaddr[t*32 +: 32]), .s_axil_awprot(m_awprot[t*3 +: 3]),
                .s_axil_awvalid(m_awvalid[t]), .s_axil_awready(m_awready[t]),
                .s_axil_wdata(m_wdata[t*32 +: 32]), .s_axil_wstrb(m_wstrb[t*4 +: 4]),
                .s_axil_wvalid(m_wvalid[t]), .s_axil_wready(m_wready[t]),
                .s_axil_bresp(m_bresp[t*2 +: 2]), .s_axil_bvalid(m_bvalid[t]), .s_axil_bready(m_bready[t]),
                .s_axil_araddr(m_araddr[t*32 +: 32]), .s_axil_arprot(m_arprot[t*3 +: 3]),
                .s_axil_arvalid(m_arvalid[t]), .s_axil_arready(m_arready[t]),
                .s_axil_rdata(m_rdata[t*32 +: 32]), .s_axil_rresp(m_rresp[t*2 +: 2]),
                .s_axil_rvalid(m_rvalid[t]), .s_axil_rready(m_rready[t]),
                .err_flags(tile_err[t*5 +: 5]), .sw_status(tile_sw[t*32 +: 32]),
                .bist_status(10'b0), .core_trap(tile_trap[t]), .core_restart(core_restart)
            );

            if (CORE_MASK[t]) begin : g_core
                picorv32 #(
                    .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
                    .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
                    .PROGADDR_RESET((t << OB) + 32'h100),
                    .STACKADDR((t + 1) << OB)
                ) u_core (
                    .clk(clk), .resetn(rst_n && !core_restart), .trap(tile_trap[t]),
                    .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
                    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
                    .mem_rdata(mem_rdata),
                    .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
                    .irq(32'b0)
                );
            end else begin : g_nocore
                assign mem_valid    = 1'b0;
                assign mem_instr    = 1'b0;
                assign mem_addr     = 32'b0;
                assign mem_wdata    = 32'b0;
                assign mem_wstrb    = 4'b0;
                assign tile_trap[t] = 1'b0;
            end
        end
    endgenerate

endmodule
