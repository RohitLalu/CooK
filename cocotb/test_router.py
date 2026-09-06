"""
pyuvm testbench for noc_router -- actual UVM classes (uvm_driver,
uvm_monitor, uvm_scoreboard-style component, uvm_sequence, uvm_test),
running in Python on cocotb, on Icarus Verilog underneath.

Covers the same 20 single-flit routing combinations as the hand-written
Verilog testbench, as a first example -- multi-flit route-holding and
contention are natural next additions once this pattern is established,
same as the Verilog testbench itself was built up incrementally.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer, ReadOnly
from cocotb.clock import Clock
from pyuvm import *

N, S, E, W, L = 0, 1, 2, 3, 4
BODY, HEAD, HEADTAIL, TAIL = 0b00, 0b01, 0b10, 0b11
DX_W, DY_W, DATA_W = 4, 4, 8
DX_MASK = (1 << DX_W) - 1
DY_MASK = (1 << DY_W) - 1
DATA_MASK = (1 << DATA_W) - 1


def expected_output(dx, dy):
    """Independent golden model of the router's X-Y routing rule.
    Deliberately re-derived here, not imported from anywhere near the
    RTL, so a shared bug between DUT and model can't hide a failure."""
    if dx < 0:
        return W
    elif dx > 0:
        return E
    elif dy < 0:
        return N
    elif dy > 0:
        return S
    else:
        return L


# ---------------------------------------------------------------------
# Sequence item
# ---------------------------------------------------------------------
class FlitItem(uvm_sequence_item):
    def __init__(self, name="FlitItem", port=0, ftype=HEADTAIL, dx=0, dy=0, data=0):
        super().__init__(name)
        self.port = port
        self.ftype = ftype
        self.dx = dx
        self.dy = dy
        self.data = data

    def __str__(self):
        return f"port={self.port} type={self.ftype:02b} dx={self.dx} dy={self.dy} data={self.data:#x}"


class ExpectedResult:
    def __init__(self, out_port, data):
        self.out_port = out_port
        self.data = data


class ActualResult:
    def __init__(self, out_port, data):
        self.out_port = out_port
        self.data = data


# ---------------------------------------------------------------------
# Sequence: the same 20 port-pair combinations as the Verilog testbench
# ---------------------------------------------------------------------
class RoutingSequence(uvm_sequence):
    async def body(self):
        cases = []
        # Want N: dx=0,dy=-1, legal sources S,E,W,L
        for i, src in enumerate([S, E, W, L]):
            cases.append((src, 0, -1, 0xA0 + i))
        # Want S: dx=0,dy=+1, legal sources N,E,W,L
        for i, src in enumerate([N, E, W, L]):
            cases.append((src, 0, 1, 0xB0 + i))
        # Want E: dx=+1, legal sources N,S,W,L
        for i, src in enumerate([N, S, W, L]):
            cases.append((src, 1, 0, 0xC0 + i))
        # Want W: dx=-1, legal sources N,S,E,L
        for i, src in enumerate([N, S, E, L]):
            cases.append((src, -1, 0, 0xD0 + i))
        # Want L (destination reached): dx=0,dy=0, legal sources N,S,E,W
        for i, src in enumerate([N, S, E, W]):
            cases.append((src, 0, 0, 0xE0 + i))

        for (port, dx, dy, data) in cases:
            item = FlitItem(port=port, dx=dx, dy=dy, data=data)
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

        dut.in_valid.value = 1 << item.port

        tval = int(dut.in_type.value)
        tval = (tval & ~(0b11 << (2 * item.port))) | ((item.ftype & 0b11) << (2 * item.port))
        dut.in_type.value = tval

        dxval = int(dut.in_dx.value)
        dxval = (dxval & ~(DX_MASK << (DX_W * item.port))) | ((item.dx & DX_MASK) << (DX_W * item.port))
        dut.in_dx.value = dxval

        dyval = int(dut.in_dy.value)
        dyval = (dyval & ~(DY_MASK << (DY_W * item.port))) | ((item.dy & DY_MASK) << (DY_W * item.port))
        dut.in_dy.value = dyval

        dval = int(dut.in_data.value)
        dval = (dval & ~(DATA_MASK << (DATA_W * item.port))) | ((item.data & DATA_MASK) << (DATA_W * item.port))
        dut.in_data.value = dval

        await Timer(1, unit="ns")

        # Publish the expected result using the INDEPENDENT reference
        # model -- not anything read back from the DUT.
        exp_port = expected_output(item.dx, item.dy)
        self.ap.write(ExpectedResult(exp_port, item.data))

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        dut.in_valid.value = int(dut.in_valid.value) & ~(1 << item.port)
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
                    data_all = int(dut.out_data.value)
                    d = (data_all >> (DATA_W * k)) & DATA_MASK
                    self.ap.write(ActualResult(k, d))


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
            if exp.out_port == act.out_port and exp.data == act.data:
                self.match_count += 1
                self.logger.info(
                    f"MATCH: out port {exp.out_port}, data {exp.data:#x}"
                )
            else:
                self.mismatch_count += 1
                self.logger.error(
                    f"MISMATCH: expected out port {exp.out_port} data {exp.data:#x}, "
                    f"got out port {act.out_port} data {act.data:#x}"
                )


# ---------------------------------------------------------------------
# Env
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


# ---------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------
class RoutingTest(uvm_test):
    def build_phase(self):
        self.env = RouterEnv("env", self)

    async def run_phase(self):
        self.raise_objection()
        seq = RoutingSequence("routing_seq")
        await seq.start(self.env.sequencer)
        await Timer(20, unit="ns")  # drain final scoreboard compares
        sb = self.env.scoreboard
        self.logger.info(
            f"RESULT: {sb.match_count} matched, {sb.mismatch_count} mismatched"
        )
        assert sb.mismatch_count == 0, f"{sb.mismatch_count} routing mismatches"
        assert sb.match_count == 20, f"expected 20 checked transactions, got {sb.match_count}"
        self.drop_objection()


# ---------------------------------------------------------------------
# cocotb entry point
# ---------------------------------------------------------------------
@cocotb.test()
async def test_router_routing(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    dut.in_valid.value = 0
    dut.in_type.value = 0
    dut.in_dx.value = 0
    dut.in_dy.value = 0
    dut.in_data.value = 0
    dut.out_ready.value = 0x1F  # all five outputs always ready
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    ConfigDB().set(None, "*", "DUT", dut)
    # run_test() clears singletons by default (for test isolation) --
    # ConfigDB is a singleton too, so without keep_set it would wipe out
    # the DUT handle just set above before any component can read it.
    await uvm_root().run_test("RoutingTest", keep_set={ConfigDB})