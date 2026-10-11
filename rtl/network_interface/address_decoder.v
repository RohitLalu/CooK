// address_decoder.v
// Pure combinational address math for the NI. No clock, no reset, no flits,
// no AXI, no router -- it answers exactly one question about one address:
// "is this mine, and if not, which way is it?"
//
// ADDRESS MAP (per the design spec)
//   [31:14]  must equal NOC_BASE[31:14]      -- outside this window is NOT a
//                                               tile address at all (see note
//                                               on is_illegal below)
//   [13:12]  tile select                     -- which tile owns the 4KB region
//   [11:0]   local offset, passed through    -- 0x000 status reg, 0x100+ memory
//
// TILE ID <-> COORDINATE MAPPING
//   id = MY_Y*MESH_X + MY_X   (row-major), so for the current 2x2 mesh
//   bit[12] happens to be X and bit[13] happens to be Y. That coincidence is
//   NOT relied on here: MY_X/MY_Y and TGT_X/TGT_Y are derived by divide/modulo
//   against MESH_X so this module stays correct when the mesh grows past 2x2
//   in either dimension. Synthesis folds the divide away because every operand
//   is a parameter or a 2-bit field.
//
// WHY is_illegal EXISTS (this is load-bearing for baremetal, not pedantry):
//   If bits [31:14] are ignored rather than checked, every address in the
//   32-bit space aliases into some tile. picorv32's default STACKADDR is
//   32'hffff_ffff, which would alias to tile 3 -- every stack push from tile 0
//   would silently become a remote NoC write. Decoding the window explicitly
//   turns that class of software bug into a bus error the NI can trap on
//   instead of a mesh-wide hang.

module address_decoder #(
    parameter integer MESH_X         = 2,
    parameter integer MESH_Y         = 2,
    parameter integer MY_TILE_ID     = 0,
    parameter integer DX_W           = 4,   // must match noc_router.DX_W
    parameter integer DY_W           = 4,   // must match noc_router.DY_W
    parameter integer OFFSET_BITS    = 12,  // 4KB per tile
    parameter integer TILE_SEL_BITS  = 2,   // enough for MESH_X*MESH_Y tiles
    parameter [31:0]  NOC_BASE       = 32'h0000_0000
) (
    input  wire [31:0]                 addr,

    output wire                        is_local,     // target tile == me
    output wire                        is_remote,    // target tile != me, in window
    output wire                        is_illegal,   // not a tile address at all
    output wire [TILE_SEL_BITS-1:0]    target_tile,  // same ID space as router_code
    output wire signed [DX_W-1:0]      target_dx,    // >0 = East, <0 = West
    output wire signed [DY_W-1:0]      target_dy,    // >0 = South, <0 = North
    output wire [OFFSET_BITS-1:0]      local_offset
);

    localparam integer WIN_LSB = OFFSET_BITS + TILE_SEL_BITS;  // = 14

    // This tile's own fixed coordinates, resolved at elaboration time.
    localparam integer MY_X = MY_TILE_ID % MESH_X;
    localparam integer MY_Y = MY_TILE_ID / MESH_X;

    wire [TILE_SEL_BITS-1:0] tgt = addr[WIN_LSB-1 : OFFSET_BITS];

    wire in_window = (addr[31:WIN_LSB] == NOC_BASE[31:WIN_LSB]);
    // A tile-select field can encode more tiles than the mesh actually has
    // (2 bits = 4 codes; a 3x2 mesh would need 3 bits and leave 2 codes spare).
    wire tile_exists = (tgt < MESH_X*MESH_Y);

    assign is_illegal   = !in_window || !tile_exists;
    assign is_local     = !is_illegal && (tgt == MY_TILE_ID);
    assign is_remote    = !is_illegal && (tgt != MY_TILE_ID);

    assign target_tile  = tgt;
    assign local_offset = addr[OFFSET_BITS-1:0];

    // Deltas are only meaningful when is_remote is high; they are still driven
    // to a defined value otherwise so nothing downstream ever samples an X.
    wire signed [DX_W-1:0] dx_calc = $signed(tgt % MESH_X) - $signed(MY_X[DX_W-1:0]);
    wire signed [DY_W-1:0] dy_calc = $signed(tgt / MESH_X) - $signed(MY_Y[DY_W-1:0]);

    assign target_dx = is_remote ? dx_calc : {DX_W{1'b0}};
    assign target_dy = is_remote ? dy_calc : {DY_W{1'b0}};

endmodule
