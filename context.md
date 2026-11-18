# CooK: project context

A record of everything done on CooK across the working sessions so far: what
was built, why, what was decided, what went wrong, the results, and what is
still open. It is meant for anyone, person or AI assistant, picking the
project up without the history. Written 2026-11-18; the repository was fully
committed at that point (last commit `97ba036`).

For navigation use `quick_look/user_guide.md`. For the live list of open
items use `docs/known_issues.md`. This file explains how things got to where
they are.

---

## 1. The project in one paragraph

CooK (Cluster of On-chip Konnectivity) is a 2×2 mesh Network-on-Chip (NoC)
connecting three PicoRV32 RISC-V cores and one gateway tile that reaches
on-board DDR2 memory through a Xilinx AXI DMA, on a Digilent Nexys4 DDR board
(xc7a100tcsg324-1, Vivado on a separate Windows machine). It extends Shashank
V's 2018 NITK thesis, which built a distributed "ping-pong" link self-test
(BIST) but never used its result. **CooK's contribution: the self-test result
is a live, hardware-enforced input to routing and to DMA admission.** A
single-bus system built from the same parts measures what the mesh buys.

---

## 2. Working preferences that shaped how the work was done

- The user asked for edits only after an explicit go-ahead, and only in the
  scope named. Design and status questions get answers, not edits.
- At each design junction the user wanted the pros and cons stated.
- Replies in the terminal were terse ("caveman" style); anything written to a
  file (code, docs, reports) is in plain prose.
- Coding followed a "smallest complete change" rule: no unrequested features,
  every change finished through its callers, tests and documents, and a
  closing note of what was skipped and any risk.
- The user does not write SystemVerilog; everything is Verilog-2001 plus a
  shared `define header.

---

## 3. Chronology

### Before these sessions (mid-semester state)

A single router with X-Y routing, a single-slot link buffer, a hand-wired
two-router link, and a directed testbench. The mid-semester report
(`reports_and_ppt/midsem/`) describes this state.

### Session 1: rebuild of the fabric and the BIST

- Rewrote the router: per-output wormhole lock (a reproduced interleaving bug),
  whole-packet admission, parity check bits, poison TAILs, per-output watchdog.
- Replaced the single-slot link buffer with a FIFO with registered ready (the
  old one formed a combinational loop around the mesh).
- Built the network interface (`ni.v`): local block RAM, remote reads with
  timeout, tags and retry, posted writes, response queue, CSRs.
- Generated the mesh from two size knobs (`noc_mesh.v`); 3×3 runs the same
  software.
- Built the DMA/DDR gateway (`gw_ni.v`) and the block-design script (AXI DMA +
  SmartConnect + MIG).
- Built the board top: MMCM, reset synchroniser, status panel with blink codes
  and a 7-segment display.
- **BIST (`bist_node.v`)**: hybrid design agreed with the user. A distributed
  ping-pong runs in each router, and the gateway is the control point. It runs
  after every total reset.
- **Gateway rules agreed:** a DMA lock (read-to-claim, round-robin handoff,
  lease of 16,384 cycles); DDR zones of three 40 MB plus two 4 MB shared
  windows; a remote write window (mailbox `0x800`–`0xEFF`); error codes B, C,
  D, E.

### Session 2: making metric M3 strong

- **M3 = cores still usable after one injected fault.** The first BIST closed
  bad links without routing around them. Counting every case gave a worst case
  of 1 of 3 cores, and the README's claim of "≥2" was wrong.
- **Fix:** routers exchange a dead-link mask ("gossip") over verified links,
  then route the other way round the 2×2 ring. Result: 3 of 3 cores for all 16
  single link faults.
- **Added tests:**
  - `make m3`, a fault sweep;
  - `make soak`, added later;
  - a test of a link that fails after BIST, which keeps the POISON path tested.
- **Hardware preparation:**
  - pins checked against Digilent's master XDC, all 54 matching;
  - `cook_vivado/build.tcl` and `program.tcl`;
  - `docs/hardware_test.md` with expected readings for every switch setting.

### Between sessions: first board test (7 November)

The user ran the gateway build on the board. Timing was met: 1.316 ns slack,
17,379 LUTs, 16,219 flip-flops, 5 block-RAM tiles. The healthy test and the
single-link fault switches passed. Three board switches (SW13–SW15) turned
out faulty, so the user moved the fault switches to SW12/SW11 and added
multi-link fault codes on SW[3:0].

### Session 3: single-bus baseline and benchmarks

- **Single-bus baseline (`single_bus/`):**
  - a shared channel with a transmit queue per node, round-robin arbitration,
    and a packet holding the bus from HEAD to TAIL;
  - a memory node with a single-beat AXI4 master, DDR reached through a
    per-core base register;
  - the NoC's `ni.v`, PicoRV32 and software reused unchanged, so only the
    interconnect differs;
  - its own board top and Vivado scripts.
- Benchmark harness (`benchmarks/`): one testbench builds either system.
- **riscv-tests rv32ui:** 41/42 on both. The one failure, `ma_data`, needs
  misaligned access, which PicoRV32 traps on. `fence_i` passes after a
  one-line PicoRV32 change that accepts `fence.i` as a no-op.
- **Spike:** built from source (`benchmarks/tools/install_spike.sh`), because
  Homebrew refused it over unrelated untrusted taps.
- **riscv-arch-test 3.9.1:** signatures compared with Spike, 38/39 on both.
  `jal-01` is 1.76 MB, beyond the largest possible tile of 1 MB. The tests
  must be built with `-mno-relax`.
- **C runtime (`benchmarks/crt/`):** crt0, a linker script keeping programs
  clear of the mailbox, `tile.h`, and a minimal libc.
- **Dhrystone and CoreMark:** 7.23 DMIPS and 11.30 CoreMark at 50 MHz,
  identical on both systems.
- **Crypto code in C:** SHA-256, AES-128 and WOTS, passing known-answer tests
  on the host.

### Session 4: crypto demo, fabric benchmark, demos, laptop link, fixes

- **Three-core crypto demo:**
  - core 0 generates the keys and arbitrates, core 1 runs AES-128, core 2 signs
    with WOTS over SHA-256;
  - it passes on both systems, and the ciphertext matches OpenSSL;
  - with a link dead, the NoC passes and a stuck bus fails.
- **Fabric benchmark:** test drivers replace the cores. Three flows that are
  simultaneous and on separate paths finish in 1,807 cycles on the NoC against
  2,697 on the bus.
- **Laptop link:**
  - an optional UART on core 0 that sits in front of the NI, which is
    otherwise unchanged;
  - a text mode on the 7-segment display;
  - `laptop.py` on the laptop side.
- **Demos (`demo_tests/`):** looping traffic, DMA with lock contention, a
  parallel speed-up of 2.89×, and later a core restart.
- **Known-issue fixes:**
  - the NoC board waits for DDR calibration (the bus board top too);
  - the assembly programs take the tile size as a parameter;
  - the bus has a watchdog;
  - crypto messages are confirmed by read-back.
- **Robustness additions:**
  - a randomised soak test with a scoreboard on the mesh at 2×2, 3×3 and with
    a dead link, and on the bus;
  - an optional remote read window (`RD_PROTECT`);
  - a per-tile core restart register (CSR `0x018`).

### Session 5: router self-test, firmware checksum, documents, report

- **Router self-test in BIST:**
  - every crossbar path plus one arbitration case;
  - new code F, and a router-fault switch on SW10 with SW9:8;
  - a failed router is cut out together with all its links.
- **Mailbox sender check:** a keyed checksum in firmware, chosen by the user
  over a hardware owner check.
- **Restart restores initialised data:** crt0 copies a pristine data image on
  every start.
- **Architectural decision recorded:** no atomic operations in hardware. The
  DMA lock covers the DDR; shared words are firmware's job, with the
  silent-corruption risk highlighted.
- **Documents:**
  - `docs/assumptions_decisions_risks.md`;
  - `quick_look/` guides rewritten in simple terms, plus `user_guide.md`;
  - status lines on every markdown file.
- **Crypto code and laptop link moved** to `encryption_code/`, with a separate
  live-demo board top `nexys4ddr_live_top.v`.
- **Remote-execution benchmark:** riscv-tests run from another tile's memory.
  The bus is about 10% faster for this one-access-at-a-time load; this is the
  NoC's cost.
- **End-semester report** in LaTeX (`reports_and_ppt/endsem/latex/`), uncompiled.
- **README** revised end to end.

---

## 4. Architecture as it stands

| Part | File | Key facts |
|---|---|---|
| Shared definitions | `rtl/include/noc_defs.vh`, `noc_funcs.vh` | Mesh size, flit layout, address widths defined once; `NOC_OFFSET_BITS` 12 (4 KB tiles) by default, 16 for benchmarks and demos |
| Router | `rtl/router/noc_router.v` | 5 ports, X-Y on absolute coordinates, storage-free crossbar, per-output lock, whole-packet admission, parity, poison TAIL, watchdog; ring detour on 2×2 when links are dead |
| Link buffer | `rtl/router/link_buffer.v` | 6-flit FIFO, registered ready, fault injection (silent / bit-flip, build-time or run-time) |
| BIST node | `rtl/router/bist_node.v` | Link ping-pong, router self-test, dead-link gossip; 545 cycles; outputs link status, router status, dead-link mask |
| Network interface | `rtl/network_interface/ni.v` | Block RAM, CSRs, remote read with timeout/retry/tags, posted write, response queue, write window, optional read window, core restart |
| Mesh | `rtl/integrated/mesh/noc_mesh.v`, `mesh_top.v` | Generated; optional UART hook on core 0; router-fault injection input |
| Gateway | `rtl/dma_ddr/gw_ni.v` | NoC ↔ AXI DMA; lock, lease, zones, checks at "go", BIST collection, availability bitmap at CSR `0x120` |
| Board | `rtl/board/` | Status panel (codes 1, F, E, 2–8, B, 9, C, D, A), fault switches, calibration wait |
| Single bus | `single_bus/rtl/` | `sb_bus.v`, `sb_mem_ni.v`, `sb_top.v`, `sb_nexys4ddr_top.v`, `create_sb_mem.tcl` |
| Live demo | `encryption_code/rtl/` | `uart_port.v`, `seven_seg_text.v`, `nexys4ddr_live_top.v` |

**Packet:** two flits (HEAD, TAIL), 44 bits each on 2×2. **Address map:**
the upper bits select the tile. Within a tile: CSRs at `0x000`–`0x0FF`,
program from `0x100`, mailbox at `0x800`–`0xEFF`.

**CSRs:**

| Offset | Register |
|---|---|
| `0x000` | tile ID |
| `0x004` | error flags |
| `0x008` | software status (`0x600D…` pass, `0xFA11…` fail) |
| `0x00C` | number of tiles |
| `0x010` | tile kind |
| `0x014` | BIST status, with its complement |
| `0x018` | core control (trap and restart) |

---

## 5. Results (all simulation unless stated)

| Question | NoC | Bus |
|---|---|---|
| Cores usable after any single link fault (16 cases) | 3 of 3 | 0 of 3 |
| One router broken inside | 2 of 3 | n/a |
| Three simultaneous flows, cycles | 1,807 | 2,697 |
| Random traffic, 4 nodes / 9 nodes, cycles | 12,387 / 13,513 | 13,785 / 27,398 |
| 35 riscv-tests run from another tile, cycles | 184,817 | 165,536 |
| Programs inside one tile | identical | identical |
| riscv-tests / arch-test vs Spike | 41/42, 38/39 | same |
| Dhrystone / CoreMark at 50 MHz | 7.23 DMIPS / 11.30 | same |
| Crypto demo healthy / one fault | pass / pass | pass / fail |
| Soak test (~19,000 checked reads) | no hang, no loss | same |

**How to read them:**
- The NoC wins under simultaneous traffic on separate paths and under faults.
- It costs about 10% when slow cores make one access at a time.
- Programs that stay inside one tile cannot tell the two systems apart.

**How to word the deadlock result:** evidence from random testing, not a
proof, and only for at most one read outstanding per node.

**Regression state:** every NoC suite, every bus suite, Yosys (0 latches, 0
loops) and cocotb (2/2) all pass.

---

## 6. Decisions and their trade-offs

The full table is in `docs/assumptions_decisions_risks.md`. The main ones:

| Decision | Gain | Cost |
|---|---|---|
| X-Y routing, no virtual channels | Deadlock-free by construction | One path; relies on one outstanding read per core (A1) |
| BIST only at reset | Faults named before cores run | Run-time faults detected but not rerouted |
| Ring detour | No core lost to a single link fault | 2×2 only |
| Native core interface, AXI only at the gateway | Small NI | No bursts |
| No hardware atomics (user's decision) | Small NI, flexible policy | Silent corruption if firmware races |
| Firmware checksum for mailbox | No RTL change | Key holders can forge |
| WOTS, not ML-DSA | Fits a tile, needs only a hash | One-time signature |
| AES-128 only | — | AES-256 not written |
| Read window optional (off by default) | Privacy when on | `alltoall.S` needs remote fetch |
| No caches | No coherence problem | Not a shared-memory multiprocessor |

**Assumptions:**

| # | Assumption |
|---|---|
| A1 | One outstanding read per core |
| A2 | One clock and one reset |
| A3 | Faults are permanent and present at start-up |
| A4 | Only links and routers fail |
| A5 | Firmware cooperates |
| A6 | The mesh is 2×2 |
| A7 | Power is stable |
| A8 | Packets are two flits; a tile is at most 1 MB |
| A9 | The demo keys are compiled in |

---

## 7. Mistakes worth remembering

- **Interleaving packets, ready-signal loop, request/response deadlock:**
  found in early design and fixed.
- **Expectations wrong, hardware right:** BIST tests that forgot the thesis's
  known limitation, where a broken inlink hides its healthy reverse.
- **Reserved keywords:** `local`, `expect` and `use` are reserved in `-g2012`.
- **Lease shorter than the NI retry interval:** fixed by setting the lease to
  16,384 cycles.
- **A false "duplicate assign" claim:** caused by overlapping printouts;
  retracted.
- **README claimed M3 ≥2 before counting:** the real worst case was 1, and
  counting it led to the detour fix.
- **"Flip a switch while running shows timeouts":** false, because the test
  program ends within 1 ms. The fix was a looping demo program.
- **Dhrystone "passed" unchecked:** `-Dmain=` also renamed crt0's call. Also,
  the suite silently fixes 500 runs.
- **Old switch value `0x8005` kept in the regression after the remap:** the
  fault run injected nothing.
- **Cores started before DDR calibration:** invisible in simulation; found by
  review.
- **The router self-test cut out a router:** a debug `port_disable` override
  was active during BIST. It now applies only after BIST.
- **Soak test "hung":** it was only slow. Its 61 false failures came from
  unknown (X) initial memory.
- **LED17 red did not light for router faults.**

---

## 8. Where things are

| Need | Location |
|---|---|
| Map of the repo | `quick_look/user_guide.md` |
| Plain-language guides | `quick_look/1_…`, `2_…`, `3_…` |
| Open items and fixed list | `docs/known_issues.md` |
| Assumptions, risks, failure modes, future work | `docs/assumptions_decisions_risks.md` |
| Board checklist with expected readings | `docs/hardware_test.md` |
| Demo status | `docs/fpga_demo_plan.md`, `demo_tests/README.md` |
| All benchmark numbers | `benchmarks/results/SUMMARY.md` |
| Benchmark install and run | `benchmarks/README.md` |
| Crypto and laptop link | `encryption_code/README.md` |
| Baseline | `single_bus/README.md` |
| Reports | `reports_and_ppt/midsem/`, `reports_and_ppt/endsem/latex/` |

**Main commands, from the repo root:**

| Command | Runs |
|---|---|
| `make test` | every NoC suite |
| `make m3` | the fault sweep |
| `make soak` | random traffic with a scoreboard |
| `make synth_check` | Yosys check for latches and loops |
| `cd single_bus && make test` | every bus suite |
| `python3 benchmarks/run_fabric.py` | NoC against bus under load |
| `python3 benchmarks/run_remote_tests.py` | riscv-tests from another tile |
| `python3 benchmarks/run_riscv_tests.py`, `run_arch_test.py`, `run_c_benchmarks.py` | the standard suites |
| `python3 encryption_code/run_crypto.py` | the crypto demo |
| `python3 encryption_code/run_link_sim.py [--top]` | the laptop link |
| `python3 demo_tests/run_demos.py` | the board demos |

---

## 9. Open items

**Need Vivado or the board (cannot be closed in simulation):**
1. Rebuild the NoC bitstream. Every change since 7 November is simulation
   only: router self-test, calibration wait, read window, restart, UART hook,
   status panel, `fence.i`. Then rerun `docs/hardware_test.md`, including the
   router-fault step.
2. Timing of the router self-test logic is unknown.
3. Run the single-bus Vivado scripts (never run). The wrapper's AXI port names
   may need adjusting.
4. Build a 64 KB-tile bitstream (`NOC_OFFSET_BITS=16`), needed by every
   benchmark and demo; utilisation is unknown.
5. Run the demos on the board, and `laptop.py` against a real serial port.
6. Rerun `tb_gw_dma_ip` (Vivado only, real DMA IP).
7. Compile the end-semester report. No LaTeX on the development machine. It
   still has placeholders for course, names, roll numbers, guide and date.

**Design limits (stated, not overlooked):**
- rerouting is 2×2 only;
- deadlock safety rests on A1;
- run-time faults are not rerouted;
- the gateway is a single point of failure;
- the router self-test skips the watchdog and drop paths;
- the mailbox checksum is firmware, with a 32-bit tag;
- no hardware atomics.

---

## 10. Future work (agreed list)

1. Fix the known limitations. Separate request and response channels come
   first, because caches, faster cores and larger meshes all break A1.
2. Formal verification: deadlock freedom, packet integrity, router lock,
   gateway lock.
3. Caches with coherence and consistency (MESI; snooping or directory). This
   is the step to true multiprocessing.
4. Dynamic X-Y routing, and a comparison of buffers inside the router against
   the present link-FIFO design.
5. In-order and out-of-order cores.
6. 3×3 and larger meshes (needs up*/down* rerouting tables).
7. A second memory element, which needs a second gateway.
8. ML-based verification: optional, not planned.

---

## 11. Environment notes

| Item | Note |
|---|---|
| Development machine | macOS; Icarus Verilog, Yosys, RISC-V GCC 15.1 (Homebrew `riscv-gnu-toolchain`, rv32i multilib), Python 3.12 |
| Spike and dtc | built locally in `benchmarks/third_party/tools/` |
| Not on this machine | Vivado, LaTeX |
| zsh | does not split unquoted variables; use `bash -c` for shell loops |
| `timeout` command | does not exist on macOS |
| Icarus speed | about 1,500 cycles per second with three PicoRV32 cores. The full crypto run takes about 40 minutes and CoreMark over an hour |
| Not committed (gitignored) | `benchmarks/third_party/` and `benchmarks/build/`. Recreate with the clone commands in `benchmarks/README.md` |
| Vivado project | `cook_vivado/cook_vivado.xpr`, built on the Windows machine. The project folder was in OneDrive, so the MIG configuration step retries on file locks |
