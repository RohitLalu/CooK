# Known issues and gaps

From a review of the RTL, tests and documents on 2026-11-14. Ordered by how
much each could mislead or break a demo. "Fixed" items are listed so the
reason for the change is on record.

## Open

| # | Issue | Why it matters | Suggested fix |
|---|---|---|---|
| 1 | **NoC board: cores start before the DDR2 is calibrated.** `sys_ready` waits for BIST only (about 7 µs); calibration takes much longer. | A program that uses the DMA right after reset reaches a memory controller that is not ready. Simulation cannot show this: the DMA model is always ready. `alltoall.S` never touches the DMA, which is why the board test passed. | Hold `sys_ready` (or the gateway's DMA window) until `init_calib_complete`, synchronised into the 50 MHz domain. Done for the bus board top; not done for `nexys4ddr_top.v`, which has been hardware-tested and is yours to change. |
| 2 | **Nothing from the single-bus Vivado flow has run.** `create_project.tcl`, `build.tcl`, `create_sb_mem.tcl`. | Port names of the generated `sb_mem_wrapper`, and timing of the bus arbiter path, are unverified. | Run them on the Windows machine; adjust `sb_nexys4ddr_top.v` if the wrapper's AXI names differ. |
| 3 | **64 KB tiles are untested in Vivado.** All benchmarks and the crypto demo use `NOC_OFFSET_BITS=16`. | The board build still uses 4 KB tiles. Block-RAM inference, utilisation and timing at 64 KB are unknown. | Build once with the define and check the utilisation report (3 × 64 KB is about 48 RAMB36 of 135). |
| 4 | **Assembly programs assume 4 KB tiles.** `alltoall.S`, `hammer.S`, `tile0.S`, `ddr.S` shift tile numbers by 12. | They break silently on a 64 KB build. | Read the shift from a CSR, or keep them for 4 KB builds only (current state). |
| 5 | **The bus has no watchdog.** A sender that started a packet and never sends its TAIL would hold the bus forever. | Cannot happen with the present network interfaces, which always send HEAD and TAIL together, but the NoC router has this protection and the bus does not. | A small timeout in `sb_bus.v` that releases the channel. |
| 6 | **Posted writes are unacknowledged.** A remote write lost to a fault is invisible to the sender. | The crypto demo's jobs and results are posted writes. A fault after BIST would show as a timeout at core 0, not as a clear error. | Read-back of the sequence word, or accept and document (current state). |
| 7 | **Benchmarks do not compare the interconnects.** ISA tests, Dhrystone and CoreMark stay inside one tile. | Equal numbers on NoC and bus are expected, and say nothing about either fabric. | The planned remote-execution mode, or communication-heavy programs. |
| 8 | **Run-time faults are still invisible on the board.** `alltoall.S` ends within a millisecond. | The "flip a switch while running" demo needs a looping program. | Listed in `docs/fpga_demo_plan.md`. |
| 9 | **Rerouting is 2×2 only, and BIST does not test router internals.** | Stated limits of metric M3. | Router BIST is the planned next step. |

## Fixed in this pass

| Issue | Fix |
|---|---|
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
