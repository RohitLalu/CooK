# Benchmark results, both architectures

> **Status: COMPLETE** (2026-11-16). Final for simulation. The other files in this folder are written by the runners and are covered by this status: `riscv_tests.md`, `arch_test.md`, `c_benchmarks.md`, `fabric.md`, `crypto.md` are all complete. Nothing here is a board result.

Stabilised 2026-11-14. Simulation only (Icarus Verilog); nothing here has run
on the board. Both systems built with 64 KB tiles (`NOC_OFFSET_BITS=16`),
RV32I, no multiplier, no barrel shifter. Rates assume the board's 50 MHz clock.
Per-test tables are in the other files in this folder.

## Summary

| Suite | NoC | Bus | Detail |
|---|---|---|---|
| riscv-tests `rv32ui`, three cores at once | 41 of 42 | 41 of 42 | `riscv_tests.md` |
| riscv-arch-test 3.9.1, RV32I base set, signatures against Spike | 38 of 39 | 38 of 39 | `arch_test.md` |
| Dhrystone 2.1, three cores at once | pass | pass | `c_benchmarks.md` |
| CoreMark, one core | pass | pass | `c_benchmarks.md` |
| Three-core crypto demo, healthy (`encryption_code/run_crypto.py`) | pass | pass | `crypto.md` |
| Three-core crypto demo, one fault | **pass** | **fail** | `crypto.md` |
| Fabric benchmark, three simultaneous flows | 1,807 cycles | 2,697 cycles | `fabric.md` |
| Random traffic from 9 nodes, same sequences | 13,513 cycles | 27,398 cycles | this file |
| riscv-tests executed from another tile (35 tests) | 184,817 cycles | 165,536 cycles | `remote_tests.md` |

## Fabric benchmark: the one that compares the interconnects

`fabric.md`, from `run_fabric.py`. The CPU benchmarks below cannot show a
difference, because a PicoRV32 issues so few accesses that either fabric
sits mostly idle. Here the cores are replaced by drivers that issue accesses
back to back, and the endpoints are identical on both fabrics (the same
network interfaces and the same DMA gateway); only the interconnect differs.
Three flows of 448 words that share no link on the mesh:

| Flow | NoC alone | NoC, all three | Bus alone | Bus, all three |
|---|---|---|---|---|
| DMA: DDR to tile 0 RAM | 1,807 | 1,807 (1.00×) | 1,805 | 2,697 (1.49×) |
| Tile 1 writes tile 2's mailbox | 1,796 | 1,796 (1.00×) | 1,795 | 2,687 (1.50×) |
| Tile 2 writes tile 1's mailbox | 1,797 | 1,796 (1.00×) | 1,796 | 2,689 (1.50×) |

- One flow at a time, the two fabrics are equal: the network interface, at
  four cycles per word, is the limit, not the fabric.
- All three at once: the mesh carries them on separate links and none slows
  down. The bus has one channel, the three flows need one and a half times
  what it can carry, and each takes 1.5× as long.
- So the combined work finishes in 1,807 cycles on the NoC against 2,697 on
  the bus. Every word arrived on both and no error flag was set.
- What this does and does not show: the gain needs traffic that is
  simultaneous and on different paths. Two flows into the same tile, or a
  single flow, gain nothing, and a lone remote read is still slower over the
  mesh's extra hops.

## The cost: one access at a time

`remote_tests.md`, from `run_remote_tests.py`. Thirty-five riscv-tests, each
executed by a core from **another tile's memory**, three cores at once, so
every instruction fetch is a remote read. All 35 pass on both systems.

| | Cycles, total over the 35 tests |
|---|---|
| Run from the core's own tile | 49,249 |
| Run remotely on the NoC | 184,817 |
| Run remotely on the bus | 165,536 |

With slow cores that wait for each access, neither fabric is loaded, and the
bus is about 10 % faster because the mesh adds hops. This is the price of the
NoC at this scale, and it belongs next to the gains above.

## Random traffic from every node: correctness and scaling

`make soak` in the repo root (mesh) and in `single_bus/` (bus), testbench
`tb/tb_soak.v`. Every node issues 1,000 random accesses to random other nodes,
all at once, with a scoreboard: each read must return the last value written
there, and afterwards every mailbox word must equal the scoreboard.

| Run | Result |
|---|---|
| Mesh 2×2, three seeds | pass, about 2,100 checks each |
| Mesh 3×3 | pass, 5,077 checks |
| Mesh 2×2 with a link dead from reset (routed around) | pass, 2,129 checks |
| Bus, 4 and 9 nodes | pass |

No access hung, no packet was lost, duplicated or misdelivered, no error flag
was set and no router dropped anything. How to state this: it is evidence
from random testing, not a proof, and it covers the condition the design
assumes, at most one read outstanding per node. `docs/known_issues.md` has
the exact wording to use.

The same runs, with identical access sequences on both fabrics, also show how
the two scale:

| Nodes | Mesh, cycles to finish | Bus, cycles to finish | Bus / mesh |
|---|---|---|---|
| 4 | 12,387 | 13,785 | 1.11× |
| 9 | 13,513 | 27,398 | 2.03× |

From 4 to 9 nodes the total traffic more than doubles. The mesh finishes in
almost the same time, because the added traffic uses added links; the bus has
one channel and takes twice as long.

## The two tests that do not pass

| Test | Result | Reason |
|---|---|---|
| riscv-tests `ma_data` | trap, both | Needs misaligned loads and stores. PicoRV32 traps on them, which the specification allows. Not fixable without a different core. |
| riscv-arch-test `jal-01` | not run, both | 1.76 MB of code. A tile is at most 1 MB: a packet header holds a 20-bit offset. |

Six arch tests (`beq`, `bge`, `bgeu`, `blt`, `bltu`, `bne`) need more than
64 KB and were run with 1 MB tiles; they pass.

`fence_i` passes only with the one-line change to `rtl/core/picorv32.v` that
accepts `fence.i` as a no-op (the core has no instruction cache).

## Performance

| Benchmark | Cycles per iteration | At 50 MHz | Per MHz |
|---|---|---|---|
| Dhrystone | 3,935 | 12,707 Dhrystones/s = 7.23 DMIPS | 0.145 DMIPS/MHz |
| CoreMark | 4,425,633 | 11.30 CoreMark | 0.226 CoreMark/MHz |

Identical on the NoC and on the bus, to the cycle. These programs stay inside
one tile, so they measure the core, its memory and the runtime, and say
nothing about either interconnect. Dhrystone includes about 2 % start-up,
because the suite fixes the run count at 500.

## Crypto demo

Core 0 derives the keys and hands out the work, core 1 does AES-128 (encrypt,
then decrypt), core 2 signs with WOTS over SHA-256. Simulation uses the small
signature size (`WOTS_LOGW=2`, `WOTS_N=1`); the board images use the full one.

| Case | Result | Cycles | Core 0 status |
|---|---|---|---|
| NoC, healthy | pass | 4,517,573 | `600D2806` |
| Bus, healthy | pass | 4,517,574 | `600D2806` |
| NoC, link 0-1 dead from reset (the direct link between the arbiter and the AES core) | pass | 4,517,589 | `600D2806` |
| Bus, arbiter stuck from reset | fail, code 8 (workers unreachable) | 5,010 | `FA110008` |

- All four cases run with the tiles' remote read window on, and core 0 first
  checks that reading core 1's private memory returns POISON.
- Every job and result carries a keyed checksum; core 0 also sends core 1 a
  forged job and checks that it is ignored.
- `2806` is the first two bytes of the ciphertext. OpenSSL on the laptop,
  given the same key and plaintext, produces a ciphertext starting `2806`.
- In the NoC fault case the start-up BIST reported the link dead
  (`dead_links = 01`) and the same computation finished within a few cycles
  of the healthy run.
- The crypto code also passes known-answer tests on the laptop
  (`encryption_code/crypto/host_test.c`): SHA-256 and AES-128 against the FIPS vectors, WOTS
  sign, verify and two tamper checks at three sizes.

## Regressions run with this state of the code

| What | Result |
|---|---|
| NoC `make test` (16 suite runs, including the M3 sweep: 16 single link faults, 3 of 3 cores usable in each) | all pass |
| NoC `make synth_check` | 0 latches, 0 problems |
| NoC `make cocotb` | 2 of 2 |
| Bus `make test` (8 suite runs) | all pass |
| Bus `make synth_check` | 0 latches, 0 problems |
