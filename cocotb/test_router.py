"""
pyuvm testbench for noc_router -- actual UVM classes (uvm_driver,
uvm_monitor, uvm_scoreboard-style component, uvm_sequence, uvm_test),
running in Python on cocotb, on Icarus Verilog underneath.

The DUT is compiled with 3x3 mesh knobs and sits at (1,1), so it has a real
neighbour on every side. Flit layout comes from noc_defs.py, which reads the
same Verilog header the RTL uses.

Tests:
  test_router_routing     the 20 single-flit port-pair combinations, checked
                          against an independent X-Y model
  test_router_no_interleave  two 2-flit packets from different inputs to one
                          output must leave as HEAD,TAIL,HEAD,TAIL
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer, ReadOnly
from cocotb.clock import Clock
from pyuvm import *

from noc_defs import Layout, N, S, E, W, L, HEAD, HEADTAIL, TAIL

LAY = Layout(NOC_MESH_X=3, NOC_MESH_Y=3)   # must match COMPILE_ARGS in Makefile
MY_X, MY_Y = 1, 1
FW = LAY.flit_w
FMASK = (1 << FW) - 1

# destination coordinates that make the DUT at (1,1) pick each output
DST_FOR = {N: (1, 0), S: (1, 2), E: (2, 1), W: (0, 1), L: (1, 1)}


def expected_output(dst_x, dst_y):
    """Independent golden model of X-Y routing on absolute coordinates.
    Deliberately re-derived here, not imported from anywhere near the
    RTL, so a shared bug between DUT and model can't hide a failure."""
    if dst_x < MY_X:
        return W
    if dst_x > MY_X:
        return E
    if dst_y < MY_Y:
        return N
    if dst_y > MY_Y:
        return S
    return L


def set_port(bus_value, port, flit):
    return (bus_value & ~(FMASK << (FW * port))) | ((flit & FMASK) << (FW * port))


# ---------------------------------------------------------------------
# Sequence item
# ---------------------------------------------------------------------
class FlitItem(uvm_sequence_item):
    def __init__(self, name="FlitItem", port=0, dst=(0, 0), data=0):
        super().__init__(name)
        self.port = port
        self.dst = dst
        self.data = data
        self.flit = LAY.make_flit(HEADTAIL, port, dst[0], dst[1], data)

    def __str__(self):
        return f"port={self.port} dst={self.dst} data={self.data:#x}"


class Result:
    def __init__(self, out_port, flit):
        self.out_port = out_port
        self.flit = flit


# ---------------------------------------------------------------------
# Sequence: every input to every other output
# ---------------------------------------------------------------------
class RoutingSequence(uvm_sequence):
    async def body(self):
        n = 0
        for src in (N, S, E, W, L):
            for out in (N, S, E, W, L):
                if src == out:
                    continue
                item = FlitItem(port=src, dst=DST_FOR[out], data=0xC0000000 + n)
                n += 1
                await self.start_item(item)
                await self.finish_item(item)


# ---------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------
class FlitDriver(uvm_driver):
    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)

    def start_of_simulation_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT")

    async def run_phase(self):
        while True:
            item = await self.seq_item_port.get_next_item()
            await self._drive(item)
            self.seq_item_port.item_done()

    async def _drive(self, item):
        dut = self.dut
        dut.in_flit.value = set_port(int(dut.in_flit.value), item.port, item.flit)
        dut.in_valid.value = 1 << item.port
        await Timer(1, unit="ns")

        # expected result from the INDEPENDENT model, not from the DUT
        self.ap.write(Result(expected_output(*item.dst), item.flit))

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        dut.in_valid.value = 0
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")


# ---------------------------------------------------------------------
# Monitor
# ---------------------------------------------------------------------
class FlitMonitor(uvm_monitor):
    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)

    def start_of_simulation_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT")

    async def run_phase(self):
        dut = self.dut
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            ov = int(dut.out_valid.value)
            orr = int(dut.out_ready.value)
            for k in range(5):
                if ((ov >> k) & 1) and ((orr >> k) & 1):
                    f = (int(dut.out_flit.value) >> (FW * k)) & FMASK
                    self.ap.write(Result(k, f))


# ---------------------------------------------------------------------
# Scoreboard
# ---------------------------------------------------------------------
class RouterScoreboard(uvm_component):
    def build_phase(self):
        self.expected_fifo = uvm_tlm_analysis_fifo("expected_fifo", self)
        self.actual_fifo = uvm_tlm_analysis_fifo("actual_fifo", self)
        self.match_count = 0
        self.mismatch_count = 0

    async def run_phase(self):
        while True:
            exp = await self.expected_fifo.get()
            act = await self.actual_fifo.get()
            if exp.out_port == act.out_port and exp.flit == act.flit and LAY.chk_ok(act.flit):
                self.match_count += 1
                self.logger.info(f"MATCH: out port {exp.out_port}, data {LAY.data(exp.flit):#x}")
            else:
                self.mismatch_count += 1
                self.logger.error(
                    f"MISMATCH: expected out {exp.out_port} flit {exp.flit:#x}, "
                    f"got out {act.out_port} flit {act.flit:#x}")


# ---------------------------------------------------------------------
# Env / Test
# ---------------------------------------------------------------------
class RouterEnv(uvm_env):
    def build_phase(self):
        self.sequencer = uvm_sequencer("sequencer", self)
        self.driver = FlitDriver("driver", self)
        self.monitor = FlitMonitor("monitor", self)
        self.scoreboard = RouterScoreboard("scoreboard", self)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.sequencer.seq_item_export)
        self.driver.ap.connect(self.scoreboard.expected_fifo.analysis_export)
        self.monitor.ap.connect(self.scoreboard.actual_fifo.analysis_export)


class RoutingTest(uvm_test):
    def build_phase(self):
        self.env = RouterEnv("env", self)

    async def run_phase(self):
        self.raise_objection()
        seq = RoutingSequence("routing_seq")
        await seq.start(self.env.sequencer)
        await Timer(20, unit="ns")  # drain final scoreboard compares
        sb = self.env.scoreboard
        self.logger.info(f"RESULT: {sb.match_count} matched, {sb.mismatch_count} mismatched")
        assert sb.mismatch_count == 0, f"{sb.mismatch_count} routing mismatches"
        assert sb.match_count == 20, f"expected 20 checked transactions, got {sb.match_count}"
        self.drop_objection()


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    assert len(dut.in_flit) == 5 * FW, \
        f"noc_defs.py layout ({FW} bits) does not match the DUT ({len(dut.in_flit) // 5} bits)"
    dut.rst_n.value = 0
    dut.in_valid.value = 0
    dut.in_flit.value = 0
    dut.out_ready.value = 0x1F
    dut.out_room.value = 0x1F
    dut.port_disable.value = 0
    dut.err_clear.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


# ---------------------------------------------------------------------
# cocotb entry points
# ---------------------------------------------------------------------
@cocotb.test()
async def test_router_routing(dut):
    await reset(dut)
    ConfigDB().set(None, "*", "DUT", dut)
    # run_test() clears singletons by default (for test isolation) --
    # ConfigDB is a singleton too, so without keep_set it would wipe out
    # the DUT handle just set above before any component can read it.
    await uvm_root().run_test("RoutingTest", keep_set={ConfigDB})


@cocotb.test()
async def test_router_no_interleave(dut):
    """Two packets from W and L to E at once must not interleave on E."""
    await reset(dut)
    pkts = {
        W: [LAY.make_flit(HEAD, 1, 2, 1, 0x11110000), LAY.make_flit(TAIL, 1, 2, 1, 0x11110001)],
        L: [LAY.make_flit(HEAD, 2, 2, 1, 0x22220000), LAY.make_flit(TAIL, 2, 2, 1, 0x22220001)],
    }
    idx = {W: 0, L: 0}
    seen = []
    for _ in range(10):
        bus, valid = 0, 0
        for p, flits in pkts.items():
            if idx[p] < len(flits):
                bus = set_port(bus, p, flits[idx[p]])
                valid |= 1 << p
        dut.in_flit.value = bus
        dut.in_valid.value = valid
        await ReadOnly()
        ready = int(dut.in_ready.value)
        if (int(dut.out_valid.value) >> E) & 1:
            seen.append((int(dut.out_flit.value) >> (FW * E)) & FMASK)
        await RisingEdge(dut.clk)
        for p in pkts:
            if (valid >> p) & 1 and (ready >> p) & 1:
                idx[p] += 1
    types = [LAY.ftype(f) for f in seen]
    srcs = [LAY.src(f) for f in seen]
    dut._log.info(f"E carried types {types} from sources {srcs}")
    assert types == [HEAD, TAIL, HEAD, TAIL], f"interleaved or lost flits: {types}"
    assert srcs[0] == srcs[1] and srcs[2] == srcs[3], f"TAIL did not follow its HEAD: {srcs}"
