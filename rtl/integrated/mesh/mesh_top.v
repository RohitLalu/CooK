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
// Hierarchy for testbenches: g_tile[t].u_ni.mem is tile t's memory.
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
    parameter         MEM_PREFIX      = "tile"
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
    output wire [`NOC_NUM_TILES*8-1:0] rt_drop_cnt
);

    localparam integer NT = `NOC_NUM_TILES;
    localparam integer FW = `NOC_FLIT_W;
    localparam integer OB = `NOC_OFFSET_BITS;

    wire [NT-1:0]    ni2r_valid, ni2r_ready;
    wire [NT*FW-1:0] ni2r_flit;
    wire [NT-1:0]    r2ni_valid, r2ni_ready, r2ni_room;
    wire [NT*FW-1:0] r2ni_flit;

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
        .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt)
    );

    generate
        if (NT > 100) begin : top_check_nt
            NOC_CONFIG_ERROR_memory_file_names_assume_at_most_100_tiles u_err ();
        end
    endgenerate

    genvar t;
    generate
        for (t = 0; t < NT; t = t + 1) begin : g_tile
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
                .in_valid(r2ni_valid[t]), .in_ready(r2ni_ready[t]),
                .in_room(r2ni_room[t]), .in_flit(r2ni_flit[t*FW +: FW]),
                .out_valid(ni2r_valid[t]), .out_ready(ni2r_ready[t]),
                .out_flit(ni2r_flit[t*FW +: FW]),
                .err_flags(tile_err[t*5 +: 5]),
                .sw_status(tile_sw[t*32 +: 32])
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
                // gateway / responder-only tile: nothing initiates from here yet
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
