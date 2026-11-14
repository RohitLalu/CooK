// mesh_top.v
// Full system: the generated noc_mesh fabric plus one tile per node.
// A tile is an NI (with local memory and CSRs) and, if CORE_MASK says so, a
// picorv32 core. A tile without a core still answers remote reads and writes
// in hardware -- that is what the gateway tile and the availability scheme
// rely on. The DMA/DDR gateway will replace the core on its tile.
//
// Tile t: coordinates (t % MESH_X, t / MESH_X), address window starting at
// t << NOC_OFFSET_BITS, reset vector (t << NOC_OFFSET_BITS) + 0x100.
//
// Hierarchy for testbenches: g_tile[t].g_ni.u_ni.mem is tile t's memory;
// the gateway tile's NI is g_tile[GW_TILE].g_gw.u_gw.
//
// GATEWAY TILE (GW_EN = 1)
//   Tile GW_TILE gets gw_ni instead of ni: no core, no local RAM. Its
//   AXI4-Lite master and its two AXI-Stream ports leave through the gw_*
//   ports and go to the AXI DMA block design (cook_gw) in the board top.
//   With GW_EN = 0 every tile is a normal tile, the gw_* outputs are held
//   at 0 and the gw_* inputs are ignored. Register map: rtl/dma_ddr/gw_ni.v.
//
// BIST ATTACH POINTS
//   port_disable / err_clear are the router control inputs and rt_* / tile_*
//   are the status outputs. They are ports here, not tied off inside, so the
//   BIST module can be instantiated beside (or above) mesh_top and drive them
//   without editing the fabric. Until then the board top ties port_disable to
//   0 and drives err_clear from a button. Status outputs can fan out to any
//   number of observers (board display, BIST, ILA) -- nothing here consumes
//   or clears them.
//
// BIST AND START-UP
//   After rst_n the routers run their link ping-pong (bist_node). With a
//   gateway (GW_EN = 1), the gateway then reads every tile's result and
//   builds the availability bitmap; without one, start-up ends when the
//   ping-pong does. Only then do the cores leave reset (sys_ready), so no
//   program traffic can collide with the test and DMA is never admitted on
//   an untested fabric. NIs and routers are not held: they serve BIST.
//
// MEMORY INIT
//   MEM_INIT = 1 preloads tile t's RAM from "<MEM_PREFIX>NN.mem" (NN = two
//   decimal digits of t, e.g. tile00.mem). That is how the FPGA gets its
//   programs. Testbenches leave MEM_INIT = 0 and load memories themselves.

`timescale 1ns/1ps
`include "noc_defs.vh"

module mesh_top #(
    parameter [`NOC_NUM_TILES-1:0]   CORE_MASK       = {`NOC_NUM_TILES{1'b1}},
    parameter [4*`NOC_NUM_TILES-1:0] LINK_FAULT_MASK = {4*`NOC_NUM_TILES{1'b0}},
    parameter integer LINK_FAULT_MODE = 1,
    parameter integer NI_TIMEOUT      = 1024,
    parameter integer NI_RETRY_MAX    = 2,
    parameter integer MEM_INIT        = 0,
    parameter         MEM_PREFIX      = "tile",
    parameter integer GW_EN           = 0,
    parameter integer GW_TILE         = `NOC_NUM_TILES - 1,
    // optional serial port on core 0 (the live demo's laptop link):
    // demo_tests/rtl/uart_port.v, only needed and only built when UART_EN = 1
    parameter integer UART_EN         = 0,
    parameter integer UART_CLKS_PER_BIT = 434
) (
    input  wire                        clk,
    input  wire                        rst_n,
    output wire [`NOC_NUM_TILES-1:0]   tile_trap,   // core trapped, one per tile
    output wire [`NOC_NUM_TILES*5-1:0] tile_err,    // NI error flags, tile t at [5t +: 5]
    output wire [`NOC_NUM_TILES*32-1:0] tile_sw,    // NI software status CSR, tile t at [32t +: 32]

    // router control (BIST drives these; tie to 0 without BIST)
    input  wire [`NOC_NUM_TILES*5-1:0] port_disable,
    input  wire                        err_clear,
    // router status, router t at slice t (layouts in noc_defs.vh / noc_mesh.v)
    output wire [`NOC_NUM_TILES*5*`NOC_E_W-1:0] rt_in_err,
    output wire [`NOC_NUM_TILES*5-1:0] rt_out_dead,
    output wire [`NOC_NUM_TILES*5-1:0] rt_out_wd,
    output wire [`NOC_NUM_TILES*8-1:0] rt_drop_cnt,

    // run-time link fault injection (board switches), see noc_mesh.v
    input  wire [4*`NOC_NUM_TILES-1:0] fault_rt_mask,
    input  wire                        fault_rt_flip,
    // BIST results
    output wire [`NOC_NUM_TILES*10-1:0] bist_status,   // per router, {in, out}
    output wire                        sys_ready,       // BIST done, cores running
    output wire [`NOC_NUM_TILES-1:0]   avail,           // gateway's bitmap (0 without a gateway)
    // gateway DMA-control status (0 without a gateway), see gw_ni.v
    output wire [2:0]                  gw_flags,
    output wire [31:0]                 gw_info,

    // gateway tile -> axi_dma S_AXI_LITE (AXI4-Lite master)
    output wire [9:0]  gw_axil_awaddr,
    output wire        gw_axil_awvalid,
    input  wire        gw_axil_awready,
    output wire [31:0] gw_axil_wdata,
    output wire [3:0]  gw_axil_wstrb,
    output wire        gw_axil_wvalid,
    input  wire        gw_axil_wready,
    input  wire [1:0]  gw_axil_bresp,
    input  wire        gw_axil_bvalid,
    output wire        gw_axil_bready,
    output wire [9:0]  gw_axil_araddr,
    output wire        gw_axil_arvalid,
    input  wire        gw_axil_arready,
    input  wire [31:0] gw_axil_rdata,
    input  wire [1:0]  gw_axil_rresp,
    input  wire        gw_axil_rvalid,
    output wire        gw_axil_rready,
    // axi_dma M_AXIS_MM2S -> gateway (DDR -> NoC)
    input  wire [31:0] gw_mm2s_tdata,
    input  wire [3:0]  gw_mm2s_tkeep,
    input  wire        gw_mm2s_tlast,
    input  wire        gw_mm2s_tvalid,
    output wire        gw_mm2s_tready,
    // gateway -> axi_dma S_AXIS_S2MM (NoC -> DDR)
    output wire [31:0] gw_s2mm_tdata,
    output wire [3:0]  gw_s2mm_tkeep,
    output wire        gw_s2mm_tlast,
    output wire        gw_s2mm_tvalid,
    input  wire        gw_s2mm_tready,

    // serial port of core 0 (UART_EN = 1; otherwise tx idles high, text is off)
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [63:0] uart_text,
    output wire        uart_text_en
);

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer FW = `NOC_FLIT_W;
    localparam integer OB = `NOC_OFFSET_BITS;

    wire [NT-1:0]    ni2r_valid, ni2r_ready;
    wire [NT*FW-1:0] ni2r_flit;
    wire [NT-1:0]    r2ni_valid, r2ni_ready, r2ni_room;
    wire [NT*FW-1:0] r2ni_flit;

    wire mesh_bist_done;
    wire gw_ready;
    assign sys_ready = (GW_EN != 0) ? gw_ready : mesh_bist_done;
    wire core_rst_n = rst_n & sys_ready;

    noc_mesh #(
        .LINK_FAULT_MASK(LINK_FAULT_MASK),
        .LINK_FAULT_MODE(LINK_FAULT_MODE)
    ) u_mesh (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .port_disable(port_disable),
        .err_clear(err_clear),
        .rt_in_err(rt_in_err), .rt_out_dead(rt_out_dead),
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt),
        .fault_rt_mask(fault_rt_mask), .fault_rt_flip(fault_rt_flip),
        .bist_status(bist_status), .bist_done(mesh_bist_done)
    );

    generate
        if (NT > 100) begin : top_check_nt
            NOC_CONFIG_ERROR_memory_file_names_assume_at_most_100_tiles u_err ();
        end
        if (GW_EN != 0 && (GW_TILE < 0 || GW_TILE >= NT)) begin : top_check_gw
            NOC_CONFIG_ERROR_gateway_tile_out_of_range u_err ();
        end
        if (GW_EN == 0) begin : g_no_gw
            assign gw_axil_awaddr  = 10'b0;
            assign gw_axil_awvalid = 1'b0;
            assign gw_axil_wdata   = 32'b0;
            assign gw_axil_wstrb   = 4'b0;
            assign gw_axil_wvalid  = 1'b0;
            assign gw_axil_bready  = 1'b0;
            assign gw_axil_araddr  = 10'b0;
            assign gw_axil_arvalid = 1'b0;
            assign gw_axil_rready  = 1'b0;
            assign gw_mm2s_tready  = 1'b0;
            assign gw_s2mm_tdata   = 32'b0;
            assign gw_s2mm_tkeep   = 4'b0;
            assign gw_s2mm_tlast   = 1'b0;
            assign gw_s2mm_tvalid  = 1'b0;
            assign gw_flags        = 3'b0;
            assign gw_info         = 32'b0;
            assign avail           = {NT{1'b0}};
            assign gw_ready        = 1'b0;
        end
    endgenerate

    genvar t;
    generate
        for (t = 0; t < NT; t = t + 1) begin : g_tile
            wire        mem_valid, mem_instr, mem_ready;       // at the NI
            wire [31:0] mem_addr, mem_wdata, mem_rdata;
            wire [ 3:0] mem_wstrb;
            wire        cpu_valid, cpu_instr, cpu_ready;       // at the core
            wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
            wire [ 3:0] cpu_wstrb;

            if (UART_EN != 0 && t == 0) begin : g_uart
                // core 0's bus goes through the serial port, which answers its
                // own page and hands every other access to the NI untouched
                uart_port #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart (
                    .clk(clk), .rst_n(rst_n),
                    .c_valid(cpu_valid), .c_instr(cpu_instr), .c_ready(cpu_ready),
                    .c_addr(cpu_addr), .c_wdata(cpu_wdata), .c_wstrb(cpu_wstrb), .c_rdata(cpu_rdata),
                    .n_valid(mem_valid), .n_instr(mem_instr), .n_ready(mem_ready),
                    .n_addr(mem_addr), .n_wdata(mem_wdata), .n_wstrb(mem_wstrb), .n_rdata(mem_rdata),
                    .rx(uart_rx), .tx(uart_tx), .text(uart_text), .text_en(uart_text_en)
                );
            end else begin : g_direct
                assign mem_valid = cpu_valid;
                assign mem_instr = cpu_instr;
                assign mem_addr  = cpu_addr;
                assign mem_wdata = cpu_wdata;
                assign mem_wstrb = cpu_wstrb;
                assign cpu_ready = mem_ready;
                assign cpu_rdata = mem_rdata;
            end

            // "<prefix>NN.mem", NN = tile number in two decimal digits
            localparam [7:0] DIG_HI = 8'd48 + ((t / 10) % 10);
            localparam [7:0] DIG_LO = 8'd48 + (t % 10);
            localparam [8*2-1:0] NUM_STR = {DIG_HI, DIG_LO};

            localparam integer IS_GW = (GW_EN != 0) && (t == GW_TILE);

            if (IS_GW) begin : g_gw
                // gateway: AXI DMA bridge instead of a core and local RAM
                gw_ni #(
                    .MY_ID(t),
                    .TIMEOUT_CYCLES(NI_TIMEOUT),
                    .RETRY_MAX(NI_RETRY_MAX)
                ) u_gw (
                    .clk(clk), .rst_n(rst_n),
                    .in_valid(r2ni_valid[t]), .in_ready(r2ni_ready[t]),
                    .in_room(r2ni_room[t]), .in_flit(r2ni_flit[t*FW +: FW]),
                    .out_valid(ni2r_valid[t]), .out_ready(ni2r_ready[t]),
                    .out_flit(ni2r_flit[t*FW +: FW]),
                    .m_axil_awaddr(gw_axil_awaddr), .m_axil_awvalid(gw_axil_awvalid),
                    .m_axil_awready(gw_axil_awready),
                    .m_axil_wdata(gw_axil_wdata), .m_axil_wstrb(gw_axil_wstrb),
                    .m_axil_wvalid(gw_axil_wvalid), .m_axil_wready(gw_axil_wready),
                    .m_axil_bresp(gw_axil_bresp), .m_axil_bvalid(gw_axil_bvalid),
                    .m_axil_bready(gw_axil_bready),
                    .m_axil_araddr(gw_axil_araddr), .m_axil_arvalid(gw_axil_arvalid),
                    .m_axil_arready(gw_axil_arready),
                    .m_axil_rdata(gw_axil_rdata), .m_axil_rresp(gw_axil_rresp),
                    .m_axil_rvalid(gw_axil_rvalid), .m_axil_rready(gw_axil_rready),
                    .s_axis_mm2s_tdata(gw_mm2s_tdata), .s_axis_mm2s_tkeep(gw_mm2s_tkeep),
                    .s_axis_mm2s_tlast(gw_mm2s_tlast), .s_axis_mm2s_tvalid(gw_mm2s_tvalid),
                    .s_axis_mm2s_tready(gw_mm2s_tready),
                    .m_axis_s2mm_tdata(gw_s2mm_tdata), .m_axis_s2mm_tkeep(gw_s2mm_tkeep),
                    .m_axis_s2mm_tlast(gw_s2mm_tlast), .m_axis_s2mm_tvalid(gw_s2mm_tvalid),
                    .m_axis_s2mm_tready(gw_s2mm_tready),
                    .err_flags(tile_err[t*5 +: 5]),
                    .sw_status(tile_sw[t*32 +: 32]),
                    .gw_flags(gw_flags), .gw_info(gw_info),
                    .bist_mesh_done(mesh_bist_done),
                    .bist_own_status(bist_status[t*10 +: 10]),
                    .sys_ready(gw_ready), .avail(avail)
                );
            end else begin : g_ni
                ni #(
                    .MY_ID(t),
                    .TIMEOUT_CYCLES(NI_TIMEOUT),
                    .RETRY_MAX(NI_RETRY_MAX),
                    .INIT_FILE(MEM_INIT ? {MEM_PREFIX, NUM_STR, ".mem"} : "none"),
                    .GW_ID((GW_EN != 0) ? GW_TILE : -1)
                ) u_ni (
                    .clk(clk), .rst_n(rst_n),
                    .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
                    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
                    .mem_rdata(mem_rdata),
                    .in_valid(r2ni_valid[t]), .in_ready(r2ni_ready[t]),
                    .in_room(r2ni_room[t]), .in_flit(r2ni_flit[t*FW +: FW]),
                    .out_valid(ni2r_valid[t]), .out_ready(ni2r_ready[t]),
                    .out_flit(ni2r_flit[t*FW +: FW]),
                    .err_flags(tile_err[t*5 +: 5]),
                    .sw_status(tile_sw[t*32 +: 32]),
                    .bist_status(bist_status[t*10 +: 10])
                );
            end

            if (CORE_MASK[t] && !IS_GW) begin : g_core
                picorv32 #(
                    .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
                    .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
                    .PROGADDR_RESET((t << OB) + 32'h100),
                    .STACKADDR((t + 1) << OB)
                ) u_core (
                    .clk(clk), .resetn(core_rst_n), .trap(tile_trap[t]),
                    .mem_valid(cpu_valid), .mem_instr(cpu_instr), .mem_ready(cpu_ready),
                    .mem_addr(cpu_addr), .mem_wdata(cpu_wdata), .mem_wstrb(cpu_wstrb),
                    .mem_rdata(cpu_rdata),
                    .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
                    .irq(32'b0)
                );
            end else begin : g_nocore
                // gateway / responder-only tile: nothing initiates from here yet
                assign cpu_valid    = 1'b0;
                assign cpu_instr    = 1'b0;
                assign cpu_addr     = 32'b0;
                assign cpu_wdata    = 32'b0;
                assign cpu_wstrb    = 4'b0;
                assign tile_trap[t] = 1'b0;
            end
        end
    endgenerate

    generate
        if (UART_EN == 0) begin : g_no_uart
            assign uart_tx      = 1'b1;
            assign uart_text    = 64'b0;
            assign uart_text_en = 1'b0;
        end
    endgenerate

endmodule
