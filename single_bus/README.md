# Single-bus baseline

The comparison system for the NoC: three PicoRV32 cores and one DDR memory on
**one shared bus**. Built to differ from the NoC in the interconnect only.

| Part | File | Notes |
|---|---|---|
| Shared bus | `rtl/sb_bus.v` | One channel, one flit per cycle. A transmit queue per node absorbs contention; round-robin arbiter; a packet holds the bus from HEAD to TAIL; a busy destination is skipped, not waited for |
| Memory node | `rtl/sb_mem_ni.v` | Bus packets to one AXI4 master (single-beat). DDR seen through a window at offset `0x200`, positioned by a per-core `DDR_BASE` register (`0x020`) |
| System | `rtl/sb_top.v` | Nodes 0–2: core + `ni.v` + block RAM, exactly as a NoC tile. Node 3: memory |
| Board top | `rtl/sb_nexys4ddr_top.v` | Same pins, LEDs and display as the NoC board; uses the NoC's `.xdc` |
| DDR block design | `rtl/create_sb_mem.tcl` | SmartConnect + MIG (or block RAM for simulation) |
| Vivado project | `vivado_proj/create_project.tcl`, `build.tcl` | Creates `vivado_proj/sb_vivado/`, separate from `cook_vivado/` |

Reused from the NoC, unmodified: `picorv32.v`, `ni.v`, `address_decoder.v`,
`link_buffer.v` (as the transmit queue), `noc_defs.vh`, `noc_funcs.vh`, the
board helpers and the constraints file. Nothing under `../rtl` is edited.
Same packet format and address map, so the NoC's images run here unchanged.

## Run

```
make test          # all suites below (Icarus)
make synth_check   # Yosys: no latches, no loops
```

| Suite | Checks | What it shows |
|---|---|---|
| `bus` | 13 | No interleaving, round-robin order, busy-destination skip, drops, both faults |
| `mem` | 20 | Registers, DDR read/write/strobes, per-core base, two cores at once, out-of-range and SLVERR give POISON |
| `system` | 7 + 9 | Real cores: the NoC's `alltoall.mem` unchanged (150 checks per core), then `sw/ddr.S` on all three cores |
| `faults` | 4 + 4 | Stuck arbiter, flipped data wire: 0 of 3 cores usable, none hangs |
| `board` | 5 + 4 | Board top from init files, read from the LEDs, healthy and faulted |

## Board

Fault switches: SW12 on injects a bus fault, SW11 picks stuck arbiter (down) or
flipped data wire (up). Press CPU_RESET after setting them. Expect LEDs 8–10 on
(all cores failed) and code 2 on the display.

**Not yet run:** the Vivado scripts and the block design. Vivado is not on the
development machine. The AXI4 port names on the generated `sb_mem_wrapper` are
the most likely thing to need adjusting in `sb_nexys4ddr_top.v`.
