// sb_top.v
// The single-bus baseline system: three picorv32 cores, each with the same
// network interface and block-RAM as a NoC tile (ni.v), one memory node
// (sb_mem_ni, AXI4 master towards the DDR) and one shared bus (sb_bus)
// instead of the mesh. Counterpart of rtl/integrated/mesh/mesh_top.v with
// the gateway enabled: nodes 0..2 are cores, node 3 is the memory.
//
// Shared with the NoC, unchanged: picorv32, ni.v, address_decoder.v,
// link_buffer.v (as the bus transmit queue), noc_defs.vh / noc_funcs.vh
// (packet format, address map). Nothing under rtl/ is modified for the bus.
//
// The address map is the NoC's: node n owns the window n << NOC_OFFSET_BITS,
// so the same images run here. There is no BIST and no hold-off: the cores
// leave reset with the system.

`timescale 1ns/1ps
`include "noc_defs.vh"

module sb_top #(
    parameter integer MEM_INIT     = 0,
    parameter         MEM_PREFIX   = "tile",
    parameter integer NI_TIMEOUT   = 1024,
    parameter integer NI_RETRY_MAX = 2,
    parameter [`NOC_NUM_TILES-1:0] CORE_MASK = {`NOC_NUM_TILES{1'b1}}
) (
    input  wire clk,
    input  wire rst_n,

    output wire [`NOC_NUM_TILES-1:0]    tile_trap,
    output wire [`NOC_NUM_TILES*5-1:0]  tile_err,
    output wire [`NOC_NUM_TILES*32-1:0] tile_sw,

    // bus fault injection and status (sb_bus.v)
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
    localparam integer FW  = `NOC_FLIT_W;
    localparam integer OB  = `NOC_OFFSET_BITS;
    localparam integer MEM = NT - 1;          // the memory node

    wire [NT-1:0]    n2b_valid, n2b_ready;    // node -> bus
    wire [NT*FW-1:0] n2b_flit;
    wire [NT-1:0]    b2n_valid, b2n_ready, b2n_room;   // bus -> node
    wire [NT*FW-1:0] b2n_flit;

    sb_bus #(.N(NT)) u_bus (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(n2b_valid), .loc_in_ready(n2b_ready), .loc_in_flit(n2b_flit),
        .loc_out_valid(b2n_valid), .loc_out_ready(b2n_ready),
        .loc_out_room(b2n_room), .loc_out_flit(b2n_flit),
        .fault_grant(fault_grant), .fault_flip(fault_flip),
        .err_drop(bus_err_drop), .bus_active(bus_active)
    );

    sb_mem_ni #(.MY_ID(MEM)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .in_valid(b2n_valid[MEM]), .in_ready(b2n_ready[MEM]), .in_room(b2n_room[MEM]),
        .in_flit(b2n_flit[MEM*FW +: FW]),
        .out_valid(n2b_valid[MEM]), .out_ready(n2b_ready[MEM]), .out_flit(n2b_flit[MEM*FW +: FW]),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .err_flags(tile_err[MEM*5 +: 5])
    );
    assign tile_trap[MEM]         = 1'b0;
    assign tile_sw[MEM*32 +: 32]  = 32'b0;

    genvar t;
    generate
        for (t = 0; t < MEM; t = t + 1) begin : g_tile
            wire        mem_valid, mem_instr, mem_ready;
            wire [31:0] mem_addr, mem_wdata, mem_rdata;
            wire [ 3:0] mem_wstrb;

            // "<prefix>NN.mem", NN = tile number in two decimal digits
            localparam [7:0] DIG_HI = 8'd48 + ((t / 10) % 10);
            localparam [7:0] DIG_LO = 8'd48 + (t % 10);
            localparam [8*2-1:0] NUM_STR = {DIG_HI, DIG_LO};

            ni #(
                .MY_ID(t),
                .TIMEOUT_CYCLES(NI_TIMEOUT),
                .RETRY_MAX(NI_RETRY_MAX),
                .INIT_FILE(MEM_INIT ? {MEM_PREFIX, NUM_STR, ".mem"} : "none")
            ) u_ni (
                .clk(clk), .rst_n(rst_n),
                .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
                .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
                .mem_rdata(mem_rdata),
                .in_valid(b2n_valid[t]), .in_ready(b2n_ready[t]),
                .in_room(b2n_room[t]), .in_flit(b2n_flit[t*FW +: FW]),
                .out_valid(n2b_valid[t]), .out_ready(n2b_ready[t]),
                .out_flit(n2b_flit[t*FW +: FW]),
                .err_flags(tile_err[t*5 +: 5]),
                .sw_status(tile_sw[t*32 +: 32]),
                .bist_status(10'b0)          // no link BIST on a bus
            );

            if (CORE_MASK[t]) begin : g_core
                picorv32 #(
                    .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
                    .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
                    .PROGADDR_RESET((t << OB) + 32'h100),
                    .STACKADDR((t + 1) << OB)
                ) u_core (
                    .clk(clk), .resetn(rst_n), .trap(tile_trap[t]),
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
