# CooK — Cluster of On-chip Konnectivity

> **Status: COMPLETE** (2026-11-16) as a description of the repository. The design passes in simulation; what has and has not run in Vivado and on the board is in section 2.

A BIST-aware Network-on-Chip with DMA access to DDR memory: a 2×2 mesh of **3 PicoRV32
cores** and **1 gateway tile** (Xilinx AXI DMA, DDR2), on a Digilent Nexys4 DDR
(xc7a100tcsg324-1). The network tests its own links and routers at start-up, routes around
what is dead, and uses the result to decide which tiles may move data through the DMA. A
single-bus baseline built from the same parts measures what the mesh buys.

**New here? Start with `quick_look/user_guide.md`.**

---

## 1. What this project is

This extends *Network-on-Chip Built-In Self Test for enhancing availability of
Multi-Processor System-on-Chip* (Shashank V, NITK Surathkal / IISc CAD Lab, 2018): a
distributed ping-pong link test on a mesh, plus a consolidation step that decides which
parts of the fabric are safe. That thesis never connected its BIST result to anything; the
compute resources were black boxes and nothing consumed the availability decision.

**The contribution here:** BIST-derived availability is a live, hardware-enforced input to
routing and to DMA data movement. Among the platforms reviewed (OpenPiton, tnoc,
M3-hardware), none feeds a self-test result into admission of data movement.

**What is the same as the thesis:** the five-port router, X-Y routing, the ping-pong link
test. **What is different:** the result is used (routers avoid dead links, the gateway
refuses DMA to unreachable tiles), routers are tested as well as links, every router
learns the full dead-link list, and the whole system is measured against a bus.

**Non-goals:**
- No Linux, no MMU, no caches, no cache coherence
- No adaptive routing at run time: deterministic X-Y, plus a fixed detour around what the
  start-up BIST found dead (2×2 only)
- No atomic operation between cores in hardware; mutual exclusion on shared words is
  firmware's job (a recorded decision: `docs/assumptions_decisions_risks.md`)
- Small mesh scale; no ASIC flow

**Toolchain:** Icarus Verilog for simulation, Yosys for synthesis checks, AMD Vivado for
the FPGA, `riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32` for software, Spike as the
reference model for the compliance tests.

---

## 2. Status

| Part | Where | Simulation | Vivado / board |
|---|---|---|---|
| Router, link buffer, address decoder, network interface | `rtl/router/`, `rtl/network_interface/` | Verified: 159, 229, 17 and 66 checks; cocotb 2 tests | Ran on the board 7 Nov (earlier revision) |
| Generated mesh with real cores | `rtl/integrated/mesh/` | Verified on 2×2 and 3×3, healthy and faulted | Ran on the board 7 Nov (earlier revision) |
| BIST: link test, router self-test, dead-link list, routing around faults | `rtl/router/bist_node.v` | Verified: six fault cases, two router mutations caught | Link test ran 7 Nov; router self-test not yet |
| DMA/DDR gateway: lock, lease, zones, checks, availability | `rtl/dma_ddr/gw_ni.v` | Verified against a DMA model: 67 checks | Built and met timing (earlier revision); DMA transfers not exercised on the board |
| Board top, status panel, fault switches | `rtl/board/` | Verified | Ran 7 Nov; later changes not yet |
| Fault sweep (metric M3) | `make m3` | 16 single link faults: 3 of 3 cores usable in each | Single-link switches ran 7 Nov |
| Random traffic with scoreboard | `make soak` | Passes on mesh 2×2, 3×3, with a dead link, and on the bus | simulation only |
| Single-bus baseline | `single_bus/` | All suites pass | Vivado scripts never run |
| Standard tests and benchmarks | `benchmarks/` | riscv-tests 41/42, arch-test 38/39 against Spike, Dhrystone, CoreMark | simulation only |
| NoC against bus | `benchmarks/run_fabric.py`, `run_remote_tests.py` | Done: section 4 | simulation only |
| Crypto demo and laptop link | `encryption_code/` | Pass, including the live-demo top | not yet |
| Board demos | `demo_tests/` | Pass | not yet |

The last Vivado build (gateway, 4 KB tiles, before the router self-test) met timing at
50 MHz with 1.3 ns of slack: 17,379 LUTs (27 %), 16,219 flip-flops, 5 block-RAM tiles.
Everything changed since then needs a new build; `docs/known_issues.md` item 10 lists the
files. The benchmarks and demos also need a 64 KB-tile build, which has never been made.

Open items and design limits: `docs/known_issues.md`.

---

## 3. Architecture

**Topology:** plain mesh, 2×2 by default, no toroidal wraparound, deterministic X-Y
routing. No virtual channels — dimension-order routing on a non-wraparound mesh is
deadlock-free by construction. On the 2×2 mesh, links the start-up BIST found dead switch
every router to a fixed detour (item 5 below). The mesh size is two knobs in `noc_defs.vh`
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

**Fault handling, fastest first** (no rerouting at run time: X-Y has one path, and
run-time detours would break the deadlock argument; routing around faults is BIST's job):
1. Check bits on every flit (even parity per byte by default), generated by the sending NI
   and verified end to end; routers forward flits unmodified.
2. Same-cycle router checks: bad check bits, orphan BODY/TAIL, HEAD to a missing, disabled
   or dead port are dropped; faults inside a packet close it with a poison TAIL.
3. Per-output watchdog (shared prescaler, small counter per output): a locked output with
   no progress emits a poison TAIL (upstream lost) or is marked dead (downstream stuck); an
   output whose waiting HEAD can never be admitted is marked dead.
4. NI timeout and retry with a new transaction tag; POISON to the core when retries run out.
5. Start-up BIST (after every total reset, 545 cycles): each router ping-pongs every link
   with all-0s / all-1s vectors across the full flit width (stuck-at and broken links), and
   never sends on an outlink it could not verify. Each router is then tested from the
   inside: a packet through every crossbar path, and two packets at once to check
   arbitration. A router that fails is cut out, with all its links (code F on the board). The gateway then reads every tile's status over
   the network; a tile is available only if that round trip succeeds with a self-checking
   (complemented) status word. Cores leave reset only after this, and the gateway refuses DMA
   to or from unavailable tiles. Known limitation, inherited from the thesis: a broken
   one-way link also hides its healthy reverse, so both directions go out of use.
   **Routing around dead links:** after the ping-pong, routers gossip a dead-link mask
   (one bit per physical link) for N rounds over verified links only, so every router
   ends with the same mask. Both ends stop using a dead link. On the 2×2 mesh the four
   links form a ring 0-1-3-2-0, and a packet then goes the way round that crosses no dead
   link. That stays deadlock-free: no route crosses the dead link, so neither ring
   direction can close a cycle, and no route turns back. One dead link of either kind
   (silent or bit-flip, either direction) costs no tile. Larger meshes keep X-Y and only
   drop the link; they would need up\*/down\* tables built from the same mask.
   A link that fails *after* start-up is not routed around until the next reset; until
   then the NI timeout and POISON (items 2–4) report it.

A **poison TAIL** is a TAIL with the poison bit set, carrying the cut packet's source and
destination. Routers treat it as a TAIL, so held routes release; the destination NI
discards the partial packet and sets a flag.

Router debug hooks, shared with BIST: `port_disable`, `err_clear`, sticky per-input error
bits, per-output dead and watchdog flags, a drop counter and a capture register holding the
first offending flit.

**Tile IDs and coordinates:** `id = 2·Y + X`, so tile 0 = (0,0), 1 = (1,0), 2 = (0,1),
3 = (1,1). The same number is the router code, the flit's source tag, and the index into
the availability bitmap.

**Address map** — each tile owns 4KB by default (`NOC_OFFSET_BITS = 12`; the benchmarks and
demos use 16, for 64 KB tiles):

| Bits | Meaning |
|---|---|
| `[31:14]` | must match `NOC_BASE`; anything else is **not a tile address** and raises `is_illegal` |
| `[13:12]` | tile select |
| `[11:0]` | offset: `0x000–0x0FF` CSRs, `0x100–0xFFF` memory |

CSRs: `0x000` tile ID (read-only), `0x004` error flags, write 1 to clear: bit 0 timeout
(retries exhausted), bit 1 illegal address, bit 2 poison TAIL received, bit 3 stale
response discarded, bit 4 check-bit error. `0x008` software status (read/write; upper half
`0x600D` = pass, `0xFA11` = fail, shown on the board). `0x00C` number of tiles (read-only),
so one binary adapts to any mesh size. `0x010` tile kind (0 core, 1 gateway). `0x014` this
tile's link BIST status `{in[4:0], out[4:0]}` with its complement in bits 25:16. `0x018`
core control: reads 1 when this tile's core has trapped; writing 1 restarts it (any tile
may do either).
The gateway's DMA registers (lock `0x114`, refusal reason `0x118`, BIST bitmap `0x120`,
per-tile status `0x130+4t`) are documented at the top of `rtl/dma_ddr/gw_ni.v`.

Local memory is one true-dual-port block RAM per tile: the core on one port, the network
on the other. `INIT_FILE` preloads it for the FPGA. Other tiles may write only the mailbox
window `0x800`–`0xEFF` (option-b isolation); the gateway may write anywhere from `0x100`,
because DMA lands there. Reads are unrestricted by default; with `RD_PROTECT = 1` another
tile may read only the CSRs and the mailbox, and anything else returns POISON.

DDR2 is split into three 40 MB core zones and two 4 MB shared windows (`B0`: tiles 0 and 2,
`B1`: tiles 0 and 1). The gateway enforces them on every DMA request.

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

## 4. Results (simulation)

Full tables: `benchmarks/results/SUMMARY.md`.

| Question | NoC | Single bus |
|---|---|---|
| Cores usable after any single link fault | **3 of 3** | 0 of 3 |
| Cores usable with one router broken inside | 2 of 3 | n/a |
| Three simultaneous flows on separate paths, cycles to finish | **1,807** | 2,697 |
| The same flows one at a time | equal | equal |
| Random traffic from 9 nodes, cycles to finish | **13,513** | 27,398 |
| Random traffic from 4 nodes | 12,387 | 13,785 |
| 35 riscv-tests executed from another tile's memory, total cycles | 184,817 | **165,536** |
| Programs that stay in one tile (ISA tests, Dhrystone, CoreMark) | identical | identical |

**Read these together.** The NoC wins when several transfers happen at once on different
paths, and when something breaks. With slow cores making one access at a time it is about
10 % slower than the bus, because the mesh adds hops. Programs that never leave their tile
cannot tell the two apart.

Core performance (RV32I, no multiplier, no barrel shifter): 7.23 DMIPS and 11.30 CoreMark
at 50 MHz.

The deadlock result should be worded with its condition: random traffic found no hang and
no lost packet, as evidence and not proof, for at most one read outstanding per node
(`docs/known_issues.md` has the wording).

---

## 5. Repository structure

```
CooK/
├── rtl/
│   ├── include/             noc_defs.vh (knobs, layout), noc_funcs.vh (functions, checks)
│   ├── router/              noc_router.v, link_buffer.v, end_buff.v, bist_node.v
│   ├── network_interface/   address_decoder.v, ni.v
│   ├── dma_ddr/             gw_ni.v, create_cook_gw.tcl (axi_dma + SmartConnect + MIG)
│   ├── integrated/mesh/     noc_mesh.v (generated fabric), mesh_top.v, tb_mesh_top.v
│   ├── board/               status_panel.v, seven_seg.v, nexys4ddr/ (top, constraints)
│   └── core/                picorv32.v (vendored; one line changed for fence.i)
├── tb/                      unit and system testbenches, tb_m3.v, tb_soak.v
├── sw/                      assembly images: alltoall, hammer, tile0, spin
├── single_bus/              the baseline: rtl/, tb/, sw/, vivado_proj/, Makefile
├── benchmarks/              C runtime (crt/), runners, results/
├── encryption_code/         crypto/ (AES, SHA-256, WOTS, protocol), link/, rtl/ (UART, live top)
├── demo_tests/              board demo programs and their runner
├── cocotb/                  pyuvm router bench
├── cook_vivado/             Vivado project, build.tcl, program.tcl
├── docs/                    hardware checklist, known issues, assumptions and risks, demo status
├── quick_look/              plain-language guides; start with user_guide.md
├── reports_and_ppt/         mid-sem and end-sem reports
└── resources/               reference thesis and paper
```

Legacy, not built: `rtl/integrated/two_router_config/`, `four_router_config/`,
`rtl/trial_barebones/`.

---

## 6. How to run

```
make test                                  # every NoC suite, about 10 minutes
make synth_check                           # Yosys: no latches, no loops
make cocotb                                # pyuvm router bench
cd single_bus && make test                 # the baseline's suites
python3 benchmarks/run_fabric.py           # NoC against bus under load, 1 minute
python3 benchmarks/run_riscv_tests.py      # and run_arch_test.py, run_c_benchmarks.py, run_remote_tests.py
python3 encryption_code/run_crypto.py      # three-core crypto demo, both systems
python3 demo_tests/run_demos.py            # board demos in simulation
```

Knobs live in `rtl/include/noc_defs.vh` and can be overridden per compile, for example
`make mesh MESH_DEFS="-DNOC_MESH_X=3 -DNOC_MESH_Y=3"`. What to install for the benchmarks:
`benchmarks/README.md`.

**Board.** `cook_vivado/build.tcl` (`-tclargs 0|1` for `GATEWAY`) builds a bitstream and
stops on negative slack; `cook_vivado/program.tcl` loads it. Synthesis top `nexys4ddr_top`,
constraints `rtl/board/nexys4ddr/nexys4ddr.xdc`, images `sw/tile00..03.mem`. The live
laptop demo uses a different top, `encryption_code/rtl/nexys4ddr_live_top.v`. The
checklist with expected readings is `docs/hardware_test.md`.

> **Board at a glance:** LED[3:0] tile error · LED[7:4] tile passed · LED[11:8] tile
> failed · LED[12] heartbeat · LED[13] system ready · LED[14] blinks tile+1 · LED[15]
> blinks the error code · LED16 green DDR2 calibrated · LED17 red BIST found a faulty link
> or router. Display: code, tile, 0, detail. Codes: 1 trap, F router self-test, E link
> BIST, 2 NI timeout, 3 check bits, 4 poison, 5 stale response, 6 output dead, 7 watchdog,
> 8 router input error, B DMA error, 9 software failure, C DMA refused, D lease expired,
> A illegal address (`rtl/board/status_panel.v`).
> **Fault switches** (then press CPU_RESET): SW[12] injects a link fault, SW[11] silent or
> bit-flip, SW[3:0] the fault code; SW[10] breaks a router, SW[9:8] which one. SW[15:13]
> are faulty on our board and unused.

---

## 7. Open design questions

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
9. ~~**Memory protection.**~~ **Resolved.** Remote writes are limited to the mailbox window,
   and with `RD_PROTECT = 1` remote reads are too. The C linker script keeps programs clear
   of the mailbox.
10. ~~**Reset fanout.**~~ **Resolved for bring-up.** The board top passes the reset button
   and MMCM lock through `reset_sync` (asynchronous assert, synchronous de-assert), so every
   flip-flop leaves reset on the same edge. Fanout is still high; Vivado replicates it if
   timing needs.

---

## 8. Deliberately excluded

- **Odd-Even (adaptive) routing** — better throughput under load, but real turn-restriction complexity for a benefit (load balancing) this project is not optimizing for.
- **Software-based self-test *of the network*** — its main benefit (no external ATE) is already true of the ping-pong BIST. Software self-test of the *cores* is a different job: `alltoall.S`, and the standard suites in `benchmarks/`.
- **Full distance-vector routing** — per-router tables, a neighbour-exchange protocol, and transient-loop risk during reconvergence. X-Y needs none of that and is loop-free by construction. The start-up detour (section 3) is computed once from a mask that is final before any traffic flows, so it has no reconvergence.

---

## 9. Limits and future work

Design limits (each a consequence of a recorded decision): rerouting is 2×2 only; deadlock
safety assumes one read outstanding per core; a fault that appears after start-up is
detected but not routed around; the gateway is a single point of failure; shared words
have no hardware lock. `docs/assumptions_decisions_risks.md` gives the assumptions, the
decisions, what each costs, and how the system fails when firmware is wrong or hardware
breaks while running.

Future work, in the order the assumptions suggest: fix the known limitations (separate
request and response channels first), formal verification, caches with a coherence
protocol (MESI, snooping or directory), dynamic X-Y routing and a comparison with buffers
inside the router, in-order and out-of-order cores, 3×3 and larger, a second memory
element.

---

## 10. History: bugs found and fixed

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
  TAILs, same-cycle drop checks and a per-output watchdog (section 3).
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

## 11. Key references

- Shashank V, 2018 NITK/IISc thesis (the foundation)
- AMBA AXI4/AXI4-Lite Protocol Specification (for the gateway's bus-facing half)
- PicoRV32 (`YosysHQ/picorv32`) — the one non-from-scratch component
- `tnoc` (`taichi-ishitani/tnoc`) — reference for full-AXI4 burst handling
- M3-hardware (`Barkhausen-Institut/M3-hardware`) — closest architectural analog
- IJETER survey on BIST-testing NoC router FIFOs
