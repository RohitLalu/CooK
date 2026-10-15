// address_decoder.v
// Pure combinational address math for the NI. No clock, no reset, no flits,
// no AXI, no router -- it answers exactly one question about one address:
// "is this mine, and if not, where is it?"
//
// ADDRESS MAP (widths come from noc_defs.vh; defaults shown)
//   [31:OFF+ID]  must equal NOC_BASE        -- [31:14] for a 2x2 mesh. Outside
//                                              this window is NOT a tile
//                                              address at all (see is_illegal)
//   [OFF+ID-1:OFF] tile select              -- [13:12]; same ID space as the
//                                              flit source tag and the
//                                              availability bitmap index
//   [OFF-1:0]    local offset, passed through -- 0x000 CSRs, 0x100+ memory
//
// TILE ID <-> COORDINATE MAPPING
//   id = y*MESH_X + x (row-major). The decoder outputs the target's ABSOLUTE
//   coordinates; the router compares them with its own. Divide/modulo against
//   MESH_X keeps this correct for any mesh size, and synthesis folds them
//   away when MESH_X is a power of two.
//
// WHY is_illegal EXISTS (this is load-bearing for baremetal, not pedantry):
//   If the high bits are ignored rather than checked, every address in the
//   32-bit space aliases into some tile. picorv32's default STACKADDR is
//   32'hffff_ffff, which would alias to the last tile -- every stack push
//   would silently become a remote NoC write. Decoding the window explicitly
//   turns that class of software bug into a bus error the NI can trap on
//   instead of a mesh-wide hang.

`timescale 1ns/1ps
`include "noc_defs.vh"

module address_decoder #(
    parameter integer MY_TILE_ID = 0
) (
    input  wire [31:0]                  addr,

    output wire                         is_local,     // target tile == me
    output wire                         is_remote,    // target tile != me, in window
    output wire                         is_illegal,   // not a tile address at all
    output wire [`NOC_ID_W-1:0]         target_tile,
    output wire [`NOC_X_W-1:0]          target_x,
    output wire [`NOC_Y_W-1:0]          target_y,
    output wire [`NOC_OFFSET_BITS-1:0]  local_offset
);

`include "noc_funcs.vh"

    localparam integer OFF     = `NOC_OFFSET_BITS;
    localparam integer IW      = `NOC_ID_W;
    localparam integer WIN_LSB = OFF + IW;
    localparam [31:0]  BASE    = `NOC_BASE;

    wire [IW-1:0] tgt = addr[WIN_LSB-1 : OFF];

    wire in_window = (addr[31:WIN_LSB] == BASE[31:WIN_LSB]);
    // A tile-select field can encode more tiles than the mesh actually has
    // (a 3x2 mesh needs 3 bits and leaves 2 codes spare).
    wire tile_exists = (tgt < `NOC_NUM_TILES);

    assign is_illegal   = !in_window || !tile_exists;
    assign is_local     = !is_illegal && (tgt == MY_TILE_ID);
    assign is_remote    = !is_illegal && (tgt != MY_TILE_ID);

    assign target_tile  = tgt;
    assign local_offset = addr[OFF-1:0];

    // Only meaningful when is_remote is high; still driven to a defined value
    // otherwise so nothing downstream ever samples an X.
    assign target_x = is_remote ? noc_id_x(tgt) : {`NOC_X_W{1'b0}};
    assign target_y = is_remote ? noc_id_y(tgt) : {`NOC_Y_W{1'b0}};

endmodule
