"""Python mirror of rtl/include/noc_defs.vh.

The system knobs are READ from the Verilog header (the `define values inside
its `ifndef blocks), so the RTL stays the single source of truth. Only the
derivation rules are repeated here, and the testbench asserts that the
resulting flit width matches the DUT's port width, so any drift between the
two fails loudly instead of silently mis-packing flits.

Pass the same -D overrides the simulator gets, e.g.
    Layout(NOC_MESH_X=3, NOC_MESH_Y=3)
"""

import os
import re

HEADER = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "..", "rtl", "include", "noc_defs.vh")

BODY, HEAD, HEADTAIL, TAIL = 0b00, 0b01, 0b10, 0b11
N, S, E, W, L = 0, 1, 2, 3, 4
POISON_DATA = 0xDEADBEEF


def _read_knobs():
    text = open(HEADER).read()
    knobs = {}
    for name, value in re.findall(r"^`define\s+(NOC_\w+)\s+(\d+)\s*$", text, re.M):
        knobs[name] = int(value)
    return knobs


def _clog2_1(n):
    return max(1, (n - 1).bit_length())


class Layout:
    def __init__(self, **overrides):
        k = _read_knobs()
        k.update(overrides)
        self.mesh_x = k["NOC_MESH_X"]
        self.mesh_y = k["NOC_MESH_Y"]
        self.data_w = k["NOC_DATA_W"]
        self.chk_mode = k["NOC_CHK_MODE"]

        self.x_w = _clog2_1(self.mesh_x)
        self.y_w = _clog2_1(self.mesh_y)
        self.id_w = _clog2_1(self.mesh_x * self.mesh_y)

        self.data_lsb = 0
        self.dstx_lsb = self.data_lsb + self.data_w
        self.dsty_lsb = self.dstx_lsb + self.x_w
        self.src_lsb = self.dsty_lsb + self.y_w
        self.type_lsb = self.src_lsb + self.id_w
        self.poison_bit = self.type_lsb + 2
        self.body_w = self.poison_bit + 1
        self.chk_w = (self.body_w + 7) // 8 if self.chk_mode == 1 else 1
        self.chk_lsb = self.body_w
        self.flit_w = self.body_w + self.chk_w

    def chk_gen(self, body):
        if self.chk_mode != 1:
            return 0
        chk = 0
        for b in range(self.body_w):
            if (body >> b) & 1:
                chk ^= 1 << (b // 8)
        return chk

    def make_flit(self, ftype, src, dst_x, dst_y, data, poison=0):
        body = ((data & ((1 << self.data_w) - 1)) << self.data_lsb) \
            | (dst_x << self.dstx_lsb) | (dst_y << self.dsty_lsb) \
            | (src << self.src_lsb) | (ftype << self.type_lsb) \
            | (poison << self.poison_bit)
        return (self.chk_gen(body) << self.chk_lsb) | body

    def field(self, flit, lsb, width):
        return (flit >> lsb) & ((1 << width) - 1)

    def ftype(self, flit):
        return self.field(flit, self.type_lsb, 2)

    def src(self, flit):
        return self.field(flit, self.src_lsb, self.id_w)

    def data(self, flit):
        return self.field(flit, self.data_lsb, self.data_w)

    def chk_ok(self, flit):
        body = flit & ((1 << self.body_w) - 1)
        return self.chk_mode == 0 or \
            self.field(flit, self.chk_lsb, self.chk_w) == self.chk_gen(body)
