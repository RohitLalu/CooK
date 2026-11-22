# Single-bus baseline

> **Status: OPEN.** RTL and all simulation suites complete and passing on the AXI4-Lite bus. Open, and only closable in Vivado: the project scripts and block design have never been run.

The comparison system for the NoC: three PicoRV32 cores and one DDR memory on
**one shared AXI4-Lite bus**, a standard interconnect rather than a custom
one. Built to differ from the NoC in the interconnect only: same cores, same
tile RAM, same CSRs and address map, so the NoC's images run here unchanged.

| Part | File | Notes |
|---|---|---|
| Shared bus | `rtl/sb_axil_bus.v` | `axil_interconnect` from verilog-axi (`third_party/verilog-axi`, MIT, unmodified): round-robin, one transaction at a time, DECERR for unmapped addresses. Adds the address map and the fault injection |
| Tile | `rtl/sb_axil_tile.v` | Core side as `ni.v`; an AXI4-Lite master for the core's remote accesses (posted writes, reads with a timeout that returns POISON) and a slave into the tile's block RAM. Mailbox write window `0x800`–`0xF00`; AxPROT[0] (a DMA access) may write anywhere |
| Memory-node registers | `rtl/sb_axil_info.v` | Node 3's ID, tile-count and status registers, so the NoC's probes of the gateway still answer |
| System | `rtl/sb_top.v` | Nodes 0–2: core + `sb_axil_tile`. Node 3: registers. DDR at `0x8000_0000` (128 MB, flat), mapped to the `m_axi_*` AXI4 port single-beat |
| Board top | `rtl/sb_nexys4ddr_top.v` | Same pins, LEDs and display as the NoC board; uses the NoC's `.xdc` |
| DDR block design | `rtl/create_sb_mem.tcl` | SmartConnect + MIG (or block RAM for simulation) |
| Vivado project | `vivado_proj/create_project.tcl`, `build.tcl` | Creates `vivado_proj/sb_vivado/`, separate from `cook_vivado/` |

Reused from the NoC, unmodified: `picorv32.v`, `noc_defs.vh`, `noc_funcs.vh`,
the board helpers and the constraints file. Nothing under `../rtl` is edited.

The earlier packet bus (`rtl/sb_bus.v`, `rtl/sb_mem_ni.v` and their
testbenches `tb/tb_sb_bus.v`, `tb/tb_sb_mem.v`) is no longer built or used.

## Run

```
make test          # all suites below (Icarus)
make synth_check   # Yosys: no loops; the two latches reported are loop counters inside axil_interconnect, with no logic behind them
```

| Suite | Checks | What it shows |
|---|---|---|
| `axi` | 22 | Tiles, write window and AxPROT, DDR, decode error, stuck bus (timeout, no hang), restart |
| `system` | 7 + 9 | Real cores: the NoC's `alltoall.mem` unchanged (150 checks per core), then `sw/ddr.S` on all three cores |
| `faults` | 4 + 4 | Stuck bus: every core times out, 0 of 3 usable, none hangs. Flipped data wire: 0 of 3 usable, and no hardware flag, because AXI4-Lite has no check bits and the corruption is silent |
| `board` | 5 + 4 | Board top from init files, read from the LEDs, healthy and faulted |
| `soak` | 2104 + 5080 | The NoC's randomised scoreboard soak (`../tb/tb_soak.v`) on four and nine nodes |

## Board

Fault switches: SW12 on injects a bus fault, SW11 picks stuck bus (down) or
flipped data wire (up). Press CPU_RESET after setting them. Expect LEDs 8–10 on
(all cores failed) and code 2 on the display.

With the DDR2 build the system stays in reset until the memory is calibrated,
so LED13 comes on only then.

**Not yet run:** the Vivado scripts and the block design. Vivado is not on the
development machine. The AXI4 port names on the generated `sb_mem_wrapper` are
the most likely thing to need adjusting in `sb_nexys4ddr_top.v`.
