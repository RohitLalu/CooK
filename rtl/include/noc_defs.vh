// noc_defs.vh
// Single source of truth for every system-wide NoC constant.
//
// Include this at FILE scope (before `module`) in every NoC file. Everything
// here is a `define so it can size module ports. Per-module helper functions
// live in noc_funcs.vh, which is included INSIDE module bodies.
//
// Rule: anything that must be identical in every module lives here and is
// never passed as a per-instance parameter. Per-instance values (router
// coordinates, FIFO depth of one link, fault-injection mode) stay parameters.
//
// The knobs in section 1 are wrapped in `ifndef so a testbench or a build can
// override them from the command line, e.g. iverilog -DNOC_MESH_X=3. Every
// width in section 2 and every field offset in section 4 is DERIVED -- never
// edit those by hand.

`ifndef NOC_DEFS_VH
`define NOC_DEFS_VH

// ---------------------------------------------------------------------------
// 1. System knobs
// ---------------------------------------------------------------------------
`ifndef NOC_MESH_X
`define NOC_MESH_X        2
`endif
`ifndef NOC_MESH_Y
`define NOC_MESH_Y        2
`endif
`ifndef NOC_DATA_W
`define NOC_DATA_W        32
`endif
// Longest packet any agent may send, in flits. Sets the length-field width,
// the minimum link FIFO depth and the room a router demands before it admits
// a HEAD (whole-packet admission, see link_buffer.v).
`ifndef NOC_MAX_PKT_FLITS
`define NOC_MAX_PKT_FLITS 4
`endif
// Check bits carried on every flit. 0 = none, 1 = even parity per byte of the
// flit body. SECDED is the planned mode 2; add it in noc_funcs.vh only.
`ifndef NOC_CHK_MODE
`define NOC_CHK_MODE      1
`endif
// Transaction tag width: lets an NI reject a late response to an attempt it
// already gave up on.
`ifndef NOC_TAG_W
`define NOC_TAG_W         2
`endif
// Default link FIFO depth: one whole packet plus two slots of slack so that
// ready can come straight from a register at full throughput.
`ifndef NOC_LB_DEPTH
`define NOC_LB_DEPTH      (`NOC_MAX_PKT_FLITS + 2)
`endif
// Address map: each tile owns 2**NOC_OFFSET_BITS bytes.
`ifndef NOC_OFFSET_BITS
`define NOC_OFFSET_BITS   12
`endif
`ifndef NOC_BASE
`define NOC_BASE          32'h0000_0000
`endif
`define NOC_POISON_DATA   32'hDEAD_BEEF

// ---------------------------------------------------------------------------
// 2. Derived widths
// ---------------------------------------------------------------------------
// clog2 that never returns 0, so a 1-wide mesh still gets a 1-bit field
// instead of an illegal zero-width vector.
`define NOC_CLOG2_1(n)    (((n) > 1) ? $clog2(n) : 1)

`define NOC_NUM_TILES     (`NOC_MESH_X * `NOC_MESH_Y)
`define NOC_X_W           `NOC_CLOG2_1(`NOC_MESH_X)
`define NOC_Y_W           `NOC_CLOG2_1(`NOC_MESH_Y)
`define NOC_ID_W          `NOC_CLOG2_1(`NOC_NUM_TILES)
`define NOC_LEN_W         `NOC_CLOG2_1(`NOC_MAX_PKT_FLITS)

// ---------------------------------------------------------------------------
// 3. Encodings
// ---------------------------------------------------------------------------
`define NOC_T_BODY        2'b00
`define NOC_T_HEAD        2'b01
`define NOC_T_HEADTAIL    2'b10
`define NOC_T_TAIL        2'b11

// Router port indices. Every 5-wide router bus uses this order.
`define NOC_P_N           0
`define NOC_P_S           1
`define NOC_P_E           2
`define NOC_P_W           3
`define NOC_P_L           4
`define NOC_NPORTS        5

// Tile ID <-> coordinates: id = y*MESH_X + x (row-major).
// North is y-1, South is y+1, West is x-1, East is x+1.

// ---------------------------------------------------------------------------
// 4. Flit layout, least-significant field first
//
//   [ CHK | POISON | TYPE(2) | SRC_ID | DST_Y | DST_X | DATA ]
//
// Destination is ABSOLUTE (x,y), not a per-hop delta. Routers never modify a
// flit they forward, so the check bits are generated once by the sender and
// verified end to end. Only a router-generated poison TAIL is built fresh.
// ---------------------------------------------------------------------------
`define NOC_F_DATA_LSB    0
`define NOC_F_DSTX_LSB    (`NOC_F_DATA_LSB + `NOC_DATA_W)
`define NOC_F_DSTY_LSB    (`NOC_F_DSTX_LSB + `NOC_X_W)
`define NOC_F_SRC_LSB     (`NOC_F_DSTY_LSB + `NOC_Y_W)
`define NOC_F_TYPE_LSB    (`NOC_F_SRC_LSB  + `NOC_ID_W)
`define NOC_F_POISON      (`NOC_F_TYPE_LSB + 2)
`define NOC_BODY_W        (`NOC_F_POISON + 1)
`define NOC_CHK_W         ((`NOC_CHK_MODE == 1) ? ((`NOC_BODY_W + 7) / 8) : 1)
`define NOC_F_CHK_LSB     `NOC_BODY_W
`define NOC_FLIT_W        (`NOC_BODY_W + `NOC_CHK_W)

// ---------------------------------------------------------------------------
// 5. HEAD payload layout (the DATA field of a HEAD / HEADTAIL flit)
//
//   [31:24] reserved   [23:22] class   [21:20] tag   [19:18] length-1
//   [17:14] wstrb      [13] is_resp    [12] is_write [11:0] offset
//
// (bit numbers shown for the default knobs; offsets below are derived)
// ---------------------------------------------------------------------------
`define NOC_H_OFF_LSB     0
`define NOC_H_WR          (`NOC_H_OFF_LSB + `NOC_OFFSET_BITS)
`define NOC_H_RSP         (`NOC_H_WR + 1)
`define NOC_H_WSTRB_LSB   (`NOC_H_RSP + 1)
`define NOC_H_LEN_LSB     (`NOC_H_WSTRB_LSB + 4)
`define NOC_H_TAG_LSB     (`NOC_H_LEN_LSB + `NOC_LEN_W)
`define NOC_H_CLASS_LSB   (`NOC_H_TAG_LSB + `NOC_TAG_W)
`define NOC_H_CLASS_W     2
`define NOC_H_USED        (`NOC_H_CLASS_LSB + `NOC_H_CLASS_W)

// ---------------------------------------------------------------------------
// 6. Router status bus layout (per router)
// ---------------------------------------------------------------------------
// Sticky error bits per INPUT port, 4 per port, port p at [4p +: 4]:
`define NOC_E_CHK         0   // check bits failed
`define NOC_E_ORPHAN      1   // BODY/TAIL arrived with no route held
`define NOC_E_ROUTE       2   // HEAD aimed at a missing, disabled or dead port
`define NOC_E_PROTO       3   // HEAD inside a packet, or source tag changed mid-packet
`define NOC_E_W           4

`endif // NOC_DEFS_VH
