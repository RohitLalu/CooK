# CooK — Cluster of On-chip Konnectivity

An AXI/DMA-extended, BIST-aware Network-on-Chip: a 2×2 mesh of **3 PicoRV32 compute
tiles + 1 gateway tile** (DMA/DDR, no core), built from a written specification with no
inherited code except PicoRV32.

This document is the orientation point: what is actually built and verified versus
pending, what is deliberately out of scope, and where the open questions stand.

---

## 1. What this project is

This extends *Network-on-Chip Built-In Self Test for enhancing availability of
Multi-Processor System-on-Chip* (Shashank V, NITK Surathkal / IISc CAD Lab, 2018) — a
distributed ping-pong link-test scheme on a toroidal mesh, plus a sequential
consolidation and decision-making algorithm determining which parts of the fabric are
safe to use. That thesis never connected its BIST result to anything: the compute
resources were black boxes and nothing downstream consumed the availability decision.

**The goal here:** make BIST-derived availability a live, hardware-enforced input to real
DMA data movement. Checked against OpenPiton, Chipyard/Constellation, ESP and PULP, none
wire self-test results into admission control for data movement. That gap is the
contribution.

**Non-goals**, stated up front:
- No Linux, no MMU, no cache coherence
- No adaptive or multi-path routing — deterministic X-Y only (Odd-Even considered and declined, §7)
- Small mesh scale, not a scaled demonstration
- No ASIC fabrication — synthesis/PnR numbers only, if pursued at all

**Toolchain (confirmed):** AMD Vivado targeting a real FPGA. Icarus Verilog during
development, XSIM for the FPGA flow. `riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32`
for baremetal images. Verification via directed Verilog testbenches plus cocotb/pyuvm.

Everything is simulation-first, mirroring the thesis's own methodology. FPGA bring-up is a
bonus milestone, not a requirement.

---

## 2. Status

| Component | File(s) | Status |
|---|---|---|
| Shared definitions (mesh knobs, flit layout, check bits, helper functions) | `rtl/include/noc_defs.vh`, `noc_funcs.vh` | **Built.** Single source of truth for every width and field |
| Router (crossbar, X-Y on absolute coordinates, **per-output wormhole lock**, whole-packet admission, same-cycle drop checks, poison TAILs, per-output watchdog, debug/BIST hooks) | `rtl/router/noc_router.v` | **Built and verified.** 159 directed checks + 2 cocotb tests |
| Link buffer (multi-flit FIFO, registered ready, whole-packet room, fault injection) | `rtl/router/link_buffer.v` | **Built and verified.** 229 checks incl. randomized stalls |
| Address decoder (absolute target coordinates) | `rtl/network_interface/address_decoder.v` | **Built and verified.** 17 tests, incl. out-of-window aliasing |
| Network interface (initiator + responder + response queue + tags + timeout/retry + block-RAM local memory with init file + CSRs) | `rtl/network_interface/ni.v` | **Built and verified.** 48 unit checks + every mesh test |
| End terminator (`MODE`: healthy sink vs silent) | `rtl/router/end_buff.v` | **Built.** Used on every mesh-edge port |
| **Generated mesh, one PicoRV32 per tile, real baremetal images** | `rtl/integrated/mesh/` | **Working.** 2×2 healthy with contention, silent-link fault, bit-flip fault, all-to-all self-check on 2×2 and 3×3 |
| **Nexys4 DDR board top** (MMCM to 50 MHz, reset synchronizer, blink-code and 7-segment status panel, constraints) | `rtl/board/` | **Built, simulated as built** (programs from init files, result read from LEDs). Not yet run through Vivado or on the board |
| Hand-wired two- and four-router configs | `rtl/integrated/two_router_config/`, `four_router_config/` | **Legacy.** Superseded by the generated mesh; no longer compile against the new port lists |
| Baremetal images | `sw/*.S`, `sw/build.sh` | **Working.** rv32i, linked at 0x100. `alltoall.S` and `hammer.S` are position and mesh-size independent. `build.sh` writes full-memory `.mem` images, plus `tileNN.mem` for the FPGA |
| DMA engine, DDR/BRAM model, gateway tile | `rtl/dma_ddr/` | **Not started** |
| BIST module | — | **Not started** |
| 3-core single-bus baseline (Step 9) | `rtl/baseline/` | **Not started** |
| cocotb / pyuvm router testbench | `cocotb/test_router.py`, `cocotb/noc_defs.py` | Working: 20/20 routing + no-interleave |

Run everything with `make test` (12 suites). `make synth_check` runs Yosys on the fabric
and reports latches and logic loops (currently zero of both). `make cocotb` runs the pyuvm
bench. A Yosys `synth_xilinx` run of the whole board top maps every tile memory to one
RAMB36 and uses roughly 11.6k LUTs and 6.6k flip-flops; Vivado timing is still to be run.

> **Board status at a glance (Nexys4 DDR):**
> LED[3:0] tile has an error · LED[7:4] tile software pass · LED[11:8] tile software fail ·
> LED[12] 1 Hz heartbeat · LED[13] out of reset · LED[14] blinks tile+1 · LED[15] blinks the
> error code · BTNC clears router error flags · 7-segment shows code, tile, and that tile's
> status low half. Codes, highest priority first: 1 trap, 2 NI timeout, 3 check-bit error,
> 4 poison received, 5 stale response, 6 router output dead, 7 watchdog fired, 8 router
> input error, 9 software failure, 10 illegal address. Details in `rtl/board/status_panel.v`.

> **Note:** `mesh_top` puts a core on every tile by default. `CORE_MASK` removes the core
> from a tile without rewiring anything; tile 3 loses its core when the DMA/DDR gateway
> lands, matching the thesis's own gateway routers.

> **Vivado:** `cook_vivado/cook_vivado.xpr` targets `xc7a100tcsg324-1` (Nexys4 DDR) and
> lists only the current files. Synthesis top: `nexys4ddr_top`, constraints
> `rtl/board/nexys4ddr/nexys4ddr.xdc`, block-RAM images `sw/tile00..03.mem` (commit them, or
> run `sh sw/build.sh`, before synthesis). Include directory: `rtl/include`. Simulation set
> `sim_1`: `tb_mesh_top` (default; `-generic_top TEST=1|2|3` for the fault and all-to-all
> modes), `tb_board`, `tb_ni`, `tb_status_panel`, `tb_link_buffer`, `tb_address_decoder`.
> Simulation set `sim_router`: `tb_noc_router` with `NOC_MESH_X=3`, `NOC_MESH_Y=3`.

### Bugs found and fixed

Latest round (router/link redesign) -- each reproduced before being fixed:

- **Packets could interleave on a shared output.** The router remembered which output each
  *input* was using, but never reserved the *output*. The round-robin pointer advanced per
  flit, so a second HEAD could win the output between the first packet's HEAD and TAIL.
  Reproduced in simulation: output E carried HEAD(tile 1), HEAD(tile 2), TAIL(tile 1),
  TAIL(tile 2). Downstream that is a permanent deadlock on a router port and a corrupted
  packet at an NI. Fixed with a per-output lock derived from the input route registers;
  the pointer now moves only when a new packet is granted.
- **Ready was combinational across the whole mesh.** The one-slot link buffer computed
  `in_ready = !full || out_ready`, so ready chained through every router and link and
  formed a structural loop around the ring. The link buffer is now a FIFO with registered
  ready; Yosys reports zero logic loops.
- **Request/response deadlock was possible.** The NI would not accept new input while its
  own response was unsent. Read requests now move into a response queue at once.
- **No defence against a corrupted or lost flit.** Added check bits on every flit, poison
  TAILs, same-cycle drop checks and a per-output watchdog (§4).
- **`make test` was broken**: the RTL `` `include ``s had been commented out for Vivado, so
  no suite found its modules. The Makefile now passes explicit file lists, like Vivado.

Earlier rounds: silent misroute of a Head arriving mid-packet; round-robin pointer
advancing from the wrong slot; `end_buff.out_ready` wired to the router's `in_ready`
*output*; `dx`/`dy`/`data` pointed at the wrong router; duplicate instance names; a
south-to-south link that should have been south-to-north.

Most recent pass — every item below was reproduced before being fixed, not inferred:

- **`ni.v` did not compile at all.** It contained a pasted picorv32 *module declaration*, not an instantiation.
- **The router silently dropped `router_code`.** `out_router_code_flit` was declared but never assigned anywhere in the body — Yosys reported all 15 bits undriven, simulation read `zzz`. The entire "source tag is the return address" plan had no transport. Now propagated through the crossbar, unchanged on every hop, with an all-ones sentinel on idle outputs.
- **All four NIs drove the router's `W` port instead of `L`** — and collided with the `end_buff` and link-buffer drivers already on those ports.
- **All four NIs were `ROUTER_CODE(1)`.** No tile had a unique identity.
- **Tile IDs did not match the address map.** Routers were numbered `1,2,3,4` as `1+2X+Y`; the address map wants `2Y+X`. Not an off-by-one — the axes were transposed. Now `r00=0, r10=1, r01=2, r11=3`, so router_code == tile ID == availability-bitmap index, which was the point of the shared ID space.
- **`four_router_top` would not elaborate**: 32 errors from `.in_router_code` vs `.in_router_code_flit`, and from nets named `to_rXX_out_...` that were never declared.
- **`end_buff` drove `2'bzz` / `32'hzz…` onto internal nets.** No internal tristates exist on the target fabric; this is a sim/synth mismatch. Now constant-driven.
- **`end_buff.out_ready` was wired to the router's `in_ready` output again** in the 4-router config — the same multi-driver bug the two-router config had already fixed once. All 8 instances rewired.
- **`tb_four_router.v` was a verbatim copy of the two-router bench** — wrong module name, instantiating `two_router_top`.
- **`tb_link_buffer.v` never included its DUT**, so the old `compile_lb` target could not have worked.
- **Hardcoded absolute paths** in 4 `` `include ``s plus a `$dumpfile`. All now relative to the repo root (`iverilog -I.`).
- **Response return-path race in the new NI**: the return decoder was fed the live receive register, which a newly arriving HEAD could overwrite before TX picked the response up. Now uses the latched destination.

The throughline remains: repetitive, direction-indexed, hand-copied wiring is where the
bugs hide.

---

## 3. Repository structure

```
CooK/
├── rtl/
│   ├── include/             noc_defs.vh (knobs, layout), noc_funcs.vh (functions, checks)
│   ├── router/              noc_router.v, link_buffer.v, end_buff.v
│   ├── network_interface/   address_decoder.v, ni.v
│   ├── core/                picorv32.v          (vendored)
│   ├── dma_ddr/             (empty — not started)
│   └── integrated/
│       ├── mesh/            noc_mesh.v (generated fabric), mesh_top.v, tb_mesh_top.v
│       ├── two_router_config/    (legacy)
│       └── four_router_config/   (legacy)
├── tb/                      tb_noc_router.v, tb_link_buffer.v, tb_address_decoder.v
├── sw/                      tile0.S, spin.S, hammer.S, build.sh   (baremetal rv32i images)
├── cocotb/                  Makefile, test_router.py (pyuvm), noc_defs.py
├── resources/               reference papers
└── Makefile                 `make test` runs every suite
```

---

## 4. Architecture

**Topology:** plain mesh, 2×2 by default, no toroidal wraparound, deterministic X-Y
routing. No virtual channels — dimension-order routing on a non-wraparound mesh is
deadlock-free by construction. The mesh size is two knobs in `noc_defs.vh`
(`NOC_MESH_X`, `NOC_MESH_Y`); `noc_mesh.v` generates routers, links and edge terminators
from them, and every width follows. 3×3 and 3×2 run the same software unchanged.

**Configuration rule:** anything that must agree across modules (mesh size, data width,
flit layout, check mode, tag width) is a `` `define `` in `rtl/include/noc_defs.vh` and is
never passed per instance. Per-instance values (router coordinates, link FIFO depth, fault
injection) stay parameters. Knobs can be overridden per compile with `-D`.

**Flow control: elastic buffers, not a bufferless network.** The router is a storage-free
crossbar; all flit storage is in `link_buffer` FIFOs on the links, which are logically the
downstream router's input buffers placed on the wire (elastic-buffer flow control,
Michelogiannakis/Balfour/Dally, HPCA 2009). There is full valid/ready backpressure, so no
deflection routing is needed. Each FIFO is `NOC_MAX_PKT_FLITS + 2` deep with registered
ready. A router admits a HEAD only when the downstream FIFO has room for a whole packet and
then locks that output until the TAIL, so a blocked packet sits in one FIFO and, in a
healthy network, ready never drops on a locked output.

**Fault handling, fastest first** (no rerouting: X-Y has one path, and detours would break
the deadlock argument; routing around faults is BIST's job):
1. Check bits on every flit (even parity per byte by default), generated by the sending NI
   and verified end to end; routers forward flits unmodified.
2. Same-cycle router checks: bad check bits, orphan BODY/TAIL, HEAD to a missing, disabled
   or dead port are dropped; faults inside a packet close it with a poison TAIL.
3. Per-output watchdog (shared prescaler, small counter per output): a locked output with
   no progress emits a poison TAIL (upstream lost) or is marked dead (downstream stuck); an
   output whose waiting HEAD can never be admitted is marked dead.
4. NI timeout and retry with a new transaction tag; POISON to the core when retries run out.
5. BIST (not started) localizes the fault and drives `port_disable` / the availability bitmap.

A **poison TAIL** is a TAIL with the poison bit set, carrying the cut packet's source and
destination. Routers treat it as a TAIL, so held routes release; the destination NI
discards the partial packet and sets a flag.

Router debug hooks, shared with BIST: `port_disable`, `err_clear`, sticky per-input error
bits, per-output dead and watchdog flags, a drop counter and a capture register holding the
first offending flit.

**Tile IDs and coordinates:** `id = 2·Y + X`, so tile 0 = (0,0), 1 = (1,0), 2 = (0,1),
3 = (1,1). The same number is the router code, the flit's source tag, and the index into
the availability bitmap.

**Address map** — each tile owns 4KB:

| Bits | Meaning |
|---|---|
| `[31:14]` | must match `NOC_BASE`; anything else is **not a tile address** and raises `is_illegal` |
| `[13:12]` | tile select |
| `[11:0]` | offset: `0x000–0x0FF` CSRs, `0x100–0xFFF` memory |

CSRs: `0x000` tile ID (read-only), `0x004` error flags, write 1 to clear: bit 0 timeout
(retries exhausted), bit 1 illegal address, bit 2 poison TAIL received, bit 3 stale
response discarded, bit 4 check-bit error. `0x008` software status (read/write; upper half
`0x600D` = pass, `0xFA11` = fail, shown on the board). `0x00C` number of tiles (read-only),
so one binary adapts to any mesh size.

Local memory is one true-dual-port block RAM per tile: the core on one port, the network
on the other. `INIT_FILE` preloads it for the FPGA.

`PROGADDR_RESET` for tile N is `(N<<12) + 0x100`.

**Packet format** — two flits per transaction:

Every flit is `[ CHK | POISON | TYPE | SRC_ID | DST_Y | DST_X | DATA ]`, 44 bits for the
default 2×2 mesh (39-bit body + 5 parity bits). The flit is an internal network format;
AXI only exists at the NI/gateway boundary, so the extra bits do not affect AXI
compliance.

| Flit | Contents |
|---|---|
| HEAD | `dst_x,dst_y` = **absolute** destination; `src` = source tile (the return address); `data` = `{reserved, class[1:0], tag[1:0], length-1[1:0], wstrb[3:0], is_resp, is_write, offset[11:0]}` |
| TAIL | `data` = write data, or read data on a response. Destination and source repeated, so check bits and poison TAILs are self-contained |

Reads wait for a response; writes are posted. Both carry byte strobes, so a remote `sb`
or `sh` no longer corrupts the neighbouring three bytes. Posted writes cannot be retried:
a dropped write is invisible to the sender, so confirm critical writes with a read-back.

**Per tile:** PicoRV32 (native memory interface) + NI + router. The NI's address decode
splits local accesses (serviced from local memory, never touching the router) from remote
ones. The responder is **pure hardware** — a tile answers a status read whether or not its
core is running anything, which is what the availability scheme depends on.

**Why the native picorv32 interface, not AXI4-Lite:** AXI4-Lite has five independently
handshaked channels that the NI would have to re-serialize back into one ordered flit
stream — converting a simple interface into a complex one and immediately back. The
native interface is already a single valid/ready pair with one outstanding transaction,
which is the shape a flit stream wants. AXI stays at the gateway tile, where the Xilinx
DMA IP requires it.

---

## 5. Build order

Current position: steps 1–2 done; **step 3 (NI) done and verified end-to-end**; step 4
(2×2 integration) done, now generated from mesh-size knobs, with link-level fault
detection and recovery in place. BIST and DMA are the next real work.

| Steps | Category |
|---|---|
| 1–2, 4–5 | Rebuild — faithful reconstruction of the thesis's router and BIST |
| 3, 7 | Catch-up — bus wrapping, DMA integration (standard modern practice) |
| 6 | Secondary departure — direct status reads replacing distributed consolidation |
| **8** | **The contribution — availability gates DMA** |
| 9 | Evaluation — measured comparison against a 3-core single-bus baseline (§5.1) |
| 10 | Evidence — FPGA numbers on an already-complete result |

### 5.1 Step 9 restated: a 3-core single-bus baseline

**The old framing is retired.** Step 9 used to read *"regression against the original's own
fault examples."* That is not achievable here and should not be claimed. The thesis's
Examples 1–7 all reference routers 3, 5, 11, 15, 17 and G1–G6 on a 6×6 fabric with a
gateway column, and every one turns on quadrants, pass-through routers and toroidal
wraparound. **None of those exist in a 2×2 plain mesh.** At 2×2 there is exactly one path
between any two tiles, so a single faulted link makes a tile unreachable and the analysis
is trivial. Reproducing those figures would mean rebuilding the thesis's topology, which
§1 puts out of scope.

**The replacement is a comparison 2×2 can actually carry:** the same workload on a 3-core
single-bus system versus this NoC. It is exactly apples-to-apples — this design is 3
compute cores plus a DMA/DDR gateway, so the baseline is the same 3 cores sharing one bus
to the same memory.

**Why 3 cores on one bus is the right baseline, not a strawman.** The thesis's own
motivation is that *"performance of a bus degrades as the number of processing cores
dependent on it moves beyond 4."* Three cores is therefore where a shared bus is still at
its **best**. Choosing it means any win is a win in the bus's favoured region.

**Baseline design:** 3 × picorv32 + one shared memory on a single round-robin-arbitrated
bus. Same cores, same memory depth, same clock, same compiler flags. This is the only
genuinely new RTL the plan needs (`rtl/baseline/`).

**Metrics, with the honest prediction for each:**

| # | Metric | 3-core single bus | 2×2 NoC | Winner |
|---|---|---|---|---|
| M1 | Single remote-word read latency | 1–3 cycles | ~30–40 cycles (2 hops each way) | **Bus.** Say so plainly; it is the price of the fabric |
| M2 | Aggregate cycles for *k* disjoint transfers issued together | serialized, ≈ *k* × latency | disjoint paths overlap | NoC, and the gap widens with *k* |
| M3 | **Cores still usable after one injected fault** | **0** — one shared resource, no alternative path, no partial availability | ≥2 — BIST localizes it, the bitmap excludes the tile, the rest keep running | **NoC. This is the contribution** |
| M4 | Fault localization granularity | none — a fault on a shared wire is global and anonymous | per-link in/out status, 10 bits per router | NoC |
| M5 | Time from fault until the system *knows* | unbounded — the bus hangs and nothing reports it | bounded by the NI timeout, then a BIST sweep | NoC |

**The headline, stated honestly:** at 3–4 cores the NoC does **not** win on speed, and the
write-up should lead with that rather than bury it. What it wins is that *partial*
availability exists at all. On a single bus availability is binary and global — one fault
and every core is gone, with no way to discover which fault or to keep working around it.
That is precisely the gap the 2018 thesis identified and never connected to data movement.
M3, M4 and M5 are the three numbers that demonstrate it.

**Fault injection for M3:** `mesh_top` takes `LINK_FAULT_MASK` (one bit per link, per
direction) and `LINK_FAULT_MODE` (`1` = silent link, `2` = bit-flip), passed down to the
chosen `link_buffer`s, so any internal link can be faulted with no extra hardware.
`make mesh_faults` already runs both modes and checks that the requester gets POISON,
not a hang. The equivalent on the bus baseline is a stuck arbiter grant or a stuck data
line.

---

## 6. Open design questions

1. ~~**Request/response disambiguation.**~~ **Resolved.** The packet carries an explicit
   `is_resp` bit rather than inferring intent from the source tag. Inference only works
   while exactly one tile initiates, and the roadmap breaks that twice over: distributed
   BIST has every tile pinging its neighbours simultaneously, and the DMA gateway is a
   second initiator. The failure mode of getting it wrong is a silent hang that no module
   can locally detect. One bit removes the dependence on a global rule nothing in hardware
   can check.
2. ~~**Target-side NI logic.**~~ **Resolved.** The responder is built and verified: it
   answers status-register and memory reads in hardware, and responses owed to others take
   priority over the local core's outbound traffic — a starved status read is
   indistinguishable from an unreachable tile.
3. ~~**Abandoned transfers / no timeout.**~~ **Resolved.** The NI has a timeout
   (`TIMEOUT_CYCLES`); on expiry it returns `POISON`, asserts ready, and latches a sticky
   error bit. The previous reasoning ("AXI4-Lite never bursts, so this is theoretical")
   only covered a *sender* abandoning a packet. It did not cover a response that never
   arrives because the target tile is faulted — which is the entire premise of the project.
   Without this, a faulted tile hangs the requesting core with no trap and no output, which
   on an FPGA is a dead board and nothing else.
4. **Request/response separation at scale — open, deferred.** The NI response queue
   removes protocol deadlock while every initiator has at most one outstanding read. Once
   the DMA gateway issues many outstanding requests, move to separate request and response
   classes (two virtual channels or two physical networks, as OpenPiton does).
5. **Pipelined router — deferred.** A 3-stage route-compute / switch-allocate / traversal
   pipeline is planned for timing at larger mesh sizes; lookahead routing can remove the
   first stage. It needs credit-based or almost-full flow control.
6. **Toroidal reconfiguration — still open.** Reintroducing wraparound reopens the
   deadlock-avoidance question (virtual channels, dateline routers) that was removed when
   the project moved to a plain mesh. Review when the design arrives.
7. **DMA engine — resolved** in favour of Xilinx's free AXI DMA IP (~1,149 LUTs for basic
   scatter-gather) now that Vivado is confirmed, rather than a custom engine.
8. **Local-alias window — open, recommended.** As mapped, tile 1's memory lives at
   `0x1000`, so each tile needs its own linker script and its own binary. Adding an alias
   so every tile sees its own memory at one fixed address would mean **one binary for all
   tiles**, with the orchestrator role chosen at runtime by reading the tile-ID CSR. One
   extra comparison in the decoder; the single biggest bring-up effort reduction available.
9. **Memory protection — open.** Each tile's 4KB is shared between its own code/stack and
   what remote tiles may write. A remote tile can scribble on a local stack. Consider
   splitting into a local-only region and a small NoC-exposed mailbox.
10. ~~**Reset fanout.**~~ **Resolved for bring-up.** The board top passes the reset button
   and MMCM lock through `reset_sync` (asynchronous assert, synchronous de-assert), so every
   flip-flop leaves reset on the same edge. Fanout is still high; Vivado replicates it if
   timing needs.

---

## 7. Deliberately excluded

- **Odd-Even (adaptive) routing** — better throughput under load, but real turn-restriction complexity for a benefit (load balancing) this project is not optimizing for.
- **Software-based self-test *of the network*** — its main benefit (no external ATE) is already true of the ping-pong BIST. Software self-test of the *cores* is a different job and is planned (`alltoall.S` is its first piece).
- **Full distance-vector routing** — per-router tables, a neighbour-exchange protocol, and transient-loop risk during reconvergence. X-Y needs none of that and is loop-free by construction.

---

## 8. Immediate next steps

- Build the BIST module on the router debug hooks (`port_disable`, error flags, capture register); give debug access a path that does not depend on the fabric under test (serial ring or JTAG via BSCANE2)
- Run Vivado synthesis and implementation for `nexys4ddr_top`; check timing at 50 MHz on the -1 part, then program the board and read the LEDs
- Build the 3-core single-bus baseline in `rtl/baseline/` and collect M1–M5
- Replace tile 3's core with the DMA/DDR gateway
- Add the local-alias window (§6.8) so all tiles share one binary

---

## 9. Key references

- Shashank V, 2018 NITK/IISc thesis (the foundation)
- AMBA AXI4/AXI4-Lite Protocol Specification (for the gateway's bus-facing half)
- PicoRV32 (`YosysHQ/picorv32`) — the one non-from-scratch component
- `tnoc` (`taichi-ishitani/tnoc`) — reference for full-AXI4 burst handling
- M3-hardware (`Barkhausen-Institut/M3-hardware`) — closest architectural analog
- IJETER survey on BIST-testing NoC router FIFOs
