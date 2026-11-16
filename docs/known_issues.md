# Known issues and gaps

> **Status: OPEN** (2026-11-16). This is the live list and stays open while any item is. Open items: 2 and 3 (Vivado), 10 (board), and the design limits 9, 13, 16, 17.

From a review of the RTL, tests and documents on 2026-11-14. Ordered by how
much each could mislead or break a demo. "Fixed" items are listed so the
reason for the change is on record.

## Open

| # | Issue | Why it matters | Suggested fix |
|---|---|---|---|
| 2 | **Nothing from the single-bus Vivado flow has run.** `create_project.tcl`, `build.tcl`, `create_sb_mem.tcl`. | Port names of the generated `sb_mem_wrapper`, and timing of the bus arbiter path, are unverified. | Run them on the Windows machine; adjust `sb_nexys4ddr_top.v` if the wrapper's AXI names differ. |
| 3 | **64 KB tiles are untested in Vivado.** All benchmarks, the crypto demo and everything in `demo_tests/` use `NOC_OFFSET_BITS=16`. | The board build still uses 4 KB tiles. Block-RAM inference, utilisation and timing at 64 KB are unknown. | Build once with the define and check the utilisation report (3 × 64 KB is about 48 RAMB36 of 135). |
| 9 | **Rerouting is 2×2 only.** On a larger mesh a dead link, or a router that failed its self-test, is dropped but not routed around. | Stated limit of metric M3. | Up\*/down\* tables built from the dead-link mask. |
| 10 | **Changes to hardware-tested files are simulated only.** Since the last bitstream: `bist_node.v` (router self-test), `noc_mesh.v`, `mesh_top.v`, `ni.v`, `status_panel.v`, `nexys4ddr_top.v` (calibration wait, UART pins, router fault switch, code F), `nexys4ddr.xdc`, `picorv32.v`. | The board has run none of it. BIST now takes 545 cycles, not 329. | Rebuild and rerun `docs/hardware_test.md` before relying on the board. |
| 13 | **Deadlock freedom rests on one outstanding read per node.** The soak test exercises exactly that case and found nothing. | A node that issued several reads at once, or separate request and response traffic at larger scale, is not covered. See "How to word the deadlock result" below. | Separate request and response channels, as the README's open question 4 says. |
| 16 | **The router self-test does not cover everything in a router.** It walks every crossbar path, the route for each direction and one arbitration case. | The watchdog and the error-drop paths are not exercised, and a fault that appears after start-up is not seen. | Extend the test, or accept: those paths only matter once something else has already failed. |
| 17 | **The mailbox checksum is firmware.** A program that holds the key can still forge a message, and the tag is 32 bits. | It stops a core without the key and catches damaged messages; it is not hardware enforcement. | A per-slot owner check in the NI, if hardware enforcement is ever wanted. |

## Architectural decisions (deliberate, not gaps)

**No atomic operation between cores in hardware.** The only hardware mutual
exclusion is the gateway's DMA lock. That is enough for the DDR: a transfer
is claimed, runs and is released as one unit, so it finishes unless a reset
or a power loss interrupts it, which a board on a stable USB supply does not
see in practice. For the shared memory windows and the mailboxes, mutual
exclusion is left to firmware:
- today every mailbox slot has exactly one writer, so no lock is needed;
- a program that wants several writers on one shared word must build the lock
  in firmware (for example on top of the DMA lock, or a turn-taking scheme).

Why firmware and not hardware: it keeps the network interface small and lets
a system program override or change the policy without a new bitstream.
**The price, stated plainly: nothing in hardware stops two cores from racing
on a shared word, so a firmware mistake here corrupts data silently.** This
is the point to highlight when the shared windows are used for more than
single-writer messages.

**A restart does not reload a tile's memory.** The start-up code puts a
program's initialised variables back on every start, and clears its
zero-initialised ones, so a restarted program begins as after power-on. The
mailbox, and the program code itself, are left as they were. A core whose
code has been damaged needs a full reset, or a reload through the DMA.

## How to word the deadlock result

Say: "Randomised traffic from every node, with a scoreboard, completed on the
2×2 and 3×3 mesh, on the 2×2 mesh with a dead link, and on the bus, with no
hang, no lost or duplicated packet and no error flag (about 19,000 checked
reads in the regression runs)."

Say also: "This is evidence, not a proof. It covers the operating condition
the design assumes: each node has at most one read outstanding."

Do not say "deadlock-free" without that condition. The argument for the
condition itself is structural (X-Y routing has no cyclic channel dependency;
a 2×2 ring with a link removed has none either; the response queue is sized
for one read per node) and is given in the README and in `noc_router.v`.

## Fixed in this pass

| Issue | Fix |
|---|---|
| No CPU benchmark used the interconnect. | `benchmarks/run_remote_tests.py`: riscv-tests executed from another tile's memory. 35 of 35 pass on both; the bus is about 10 % faster for this one-access-at-a-time load. |
| The live-demo top was only elaboration-checked. | `run_link_sim.py --top` simulates `nexys4ddr_live_top` as built, at 115200 baud, reading the text from the display pins. Passes. |
| LED17 red did not light for a router fault, and the display values for the router fault and multi-link switch codes were not recorded. | The LED now lights for either kind of BIST failure; the values are in `docs/hardware_test.md`. |
| (was 9, part) BIST did not test router internals. | `bist_node.v` now runs a router self-test after the link tests: every crossbar path and one arbitration case. A router that fails reports `rt_status`, shows code F on the board, and is cut out: the mesh drops all its links. `tb_bist` case F, the M3 sweep's broken-router case, and two mutations of the router confirm it. |
| (was 11, 12) Mailbox messages could be forged, and a damaged job went unnoticed. | Every job and result carries a keyed checksum over the whole message (`encryption_code/crypto/proto.h`); receivers ignore a wrong one. The crypto demo sends a forged job and checks core 1 ignores it. Firmware only: see open item 17. |
| (was 15) A restarted core kept its old variables. | `crt0.S` restores initialised data from a pristine copy on every start. `restart.c` checks it. |
| No randomised test of the fabric: every test was directed. | `tb/tb_soak.v` (`make soak`): random traffic from every node with a scoreboard, on the mesh at 2×2 and 3×3, with a dead link, and on the bus. All pass. |
| Any tile could read all of any other tile's memory, including keys. | `ni.v` `RD_PROTECT = 1`: other tiles may read only the CSRs and the mailbox; anything else returns POISON and is flagged. Off by default, because `alltoall.S` fetches code remotely. The crypto demo is simulated with it on and checks that core 0 cannot read core 1's memory. |
| A core that trapped stayed stopped until a full reset. | Core-control CSR `0x018` in `ni.v`: any tile can read whether a core has trapped and restart it. `demo_tests/programs/restart.c` shows it. Memory is not reloaded on a restart. |
| (was 1) NoC board: cores started before the DDR2 was calibrated. | `nexys4ddr_top.v` holds the mesh in reset until `init_calib_complete` when the gateway is built. Simulated with `GATEWAY = 0` only: the MIG has no simulation model. |
| (was 4) Assembly programs assumed 4 KB tiles. | They use `TILE_SHIFT`, passed by `sw/build.sh` (default 12; the default images are byte-identical). `alltoall.S` passes on 64 KB tiles on both architectures. |
| (was 5) The bus had no watchdog. | `sb_bus.v` releases the channel after `WD_CYCLES` without progress and flags the sender; tested in `tb_sb_bus`. |
| (was 6) Posted writes in the crypto demo were unacknowledged. | The sequence word that publishes a job or a result is read back and rewritten up to three times (`post_seq` in `encryption_code/crypto/proto.h`). See open item 11 for what that does not cover. |
| (was 7) Benchmarks did not compare the interconnects. | `benchmarks/run_fabric.py`: the same endpoints on both fabrics under three simultaneous flows, including a DMA stream from DDR. Results in `benchmarks/results/fabric.md`. |
| (was 8) Run-time faults were invisible on the board. | `demo_tests/programs/loop_traffic.c` loops forever; with a link killed mid-run the cores that use it report failure. Simulated. |
| `make board`'s fault run still drove the old switch value `0x8005` after the fault switches moved to SW12/SW11, so it injected no fault. | Makefile now passes `0x1005`, matching `tb_board.v`. |
| `docs/hardware_test.md`, `quick_look/3_testing_on_nexys4.md` and the README still described SW15/SW14. | Updated to SW12/SW11 and the multi-link codes. |
| PicoRV32 trapped on `fence.i`. | Accepted as a no-op, like `fence` (the core has no instruction cache). One line in `rtl/core/picorv32.v`, marked "CooK change". |
| Bus board: cores could use the DDR before calibration. | `sb_nexys4ddr_top.v` holds the system in reset until `init_calib_complete`. |
| C start-up code skipped the result check when a benchmark's `main` was renamed. | `crt0.S` now undefines `main` first. A Dhrystone "pass" recorded before this fix was not a checked pass; the current one is. |
| A benchmark tile with no program held unknown values and never trapped, so the run would have gone to its cycle limit. | `tb_bench.v` zero-fills tile memory first. |

## Will not pass, by design

| Test | Reason |
|---|---|
| riscv-tests `ma_data` | Needs misaligned loads and stores. PicoRV32 traps on them, which the RISC-V specification allows. |
| riscv-arch-test `jal-01` | 1.76 MB of code. A tile can be at most 1 MB, because a packet header has room for a 20-bit offset. |
