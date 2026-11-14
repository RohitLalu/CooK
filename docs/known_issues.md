# Known issues and gaps

From a review of the RTL, tests and documents on 2026-11-14. Ordered by how
much each could mislead or break a demo. "Fixed" items are listed so the
reason for the change is on record.

## Open

| # | Issue | Why it matters | Suggested fix |
|---|---|---|---|
| 2 | **Nothing from the single-bus Vivado flow has run.** `create_project.tcl`, `build.tcl`, `create_sb_mem.tcl`. | Port names of the generated `sb_mem_wrapper`, and timing of the bus arbiter path, are unverified. | Run them on the Windows machine; adjust `sb_nexys4ddr_top.v` if the wrapper's AXI names differ. |
| 3 | **64 KB tiles are untested in Vivado.** All benchmarks, the crypto demo and everything in `demo_tests/` use `NOC_OFFSET_BITS=16`. | The board build still uses 4 KB tiles. Block-RAM inference, utilisation and timing at 64 KB are unknown. | Build once with the define and check the utilisation report (3 × 64 KB is about 48 RAMB36 of 135). |
| 9 | **Rerouting is 2×2 only, and BIST does not test router internals.** | Stated limits of metric M3. | Not attempted in this pass: router BIST is a design task of its own and was already planned as the next step after the board checks. |
| 10 | **Changes to hardware-tested files are simulated only.** `nexys4ddr_top.v` now waits for DDR2 calibration and has two UART pins; `nexys4ddr.xdc` has the two pins; `mesh_top.v` has the optional UART hook; `picorv32.v` accepts `fence.i`. | The last bitstream was built before these. | Rebuild and rerun `docs/hardware_test.md` stage A and C before relying on them. |
| 11 | **The crypto read-back confirms only the last word of a job.** | A single packet lost in the middle of a job, with later ones arriving, would still go unnoticed. | A checksum word in the job, if it ever matters. |

## Fixed in this pass

| Issue | Fix |
|---|---|
| (was 1) NoC board: cores started before the DDR2 was calibrated. | `nexys4ddr_top.v` holds the mesh in reset until `init_calib_complete` when the gateway is built. Simulated with `GATEWAY = 0` only: the MIG has no simulation model. |
| (was 4) Assembly programs assumed 4 KB tiles. | They use `TILE_SHIFT`, passed by `sw/build.sh` (default 12; the default images are byte-identical). `alltoall.S` passes on 64 KB tiles on both architectures. |
| (was 5) The bus had no watchdog. | `sb_bus.v` releases the channel after `WD_CYCLES` without progress and flags the sender; tested in `tb_sb_bus`. |
| (was 6) Posted writes in the crypto demo were unacknowledged. | The sequence word that publishes a job or a result is read back and rewritten up to three times (`post_seq` in `crypto/proto.h`). See open item 11 for what that does not cover. |
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
