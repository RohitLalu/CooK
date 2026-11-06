# Hardware test: Nexys4 DDR bring-up

A checklist for the first sessions on the board. Every expected reading below
comes from simulation of the same RTL and images (`make board`, `make m3`, and
the switch-table run noted in section 5). If the board disagrees with a row,
that row is the bug report.

No compiler is needed: the board runs the prebuilt images `sw/tile00.mem` to
`sw/tile03.mem` (all `alltoall.S`), which the Vivado project loads into the
tile RAMs at synthesis.

## 1. What to bring

- Nexys4 DDR, micro-USB cable to the PROG/UART port, power switch on
- the Windows machine with Vivado and this repo (with `cook_vivado/`)

## 2. Build

From the repo root, in a Vivado Tcl shell:

```
vivado -mode batch -source cook_vivado/build.tcl -tclargs 0
vivado -mode batch -source cook_vivado/build.tcl -tclargs 1
```

`0` builds four cores and no DDR2. `1` builds three cores, the gateway on tile 3 and
the DDR2 path. Start with `0`: it has no memory-controller (MIG) IP, so anything
that goes wrong is in our RTL. The script stops when timing is not met. The
bitstream and reports land in `cook_vivado/out/`.

Check after each build:
- [ ] The script printed `COOK: GATEWAY=<g> WNS=... WHS=...` with both values ≥ 0.
- [ ] The synthesis log (`cook_vivado/cook_vivado.runs/synth_1/runme.log`) has no
      `$readmemh` warning about `tile00.mem` to `tile03.mem`. A missing image
      leaves the cores running zeros (code 1, trap).
- [ ] `util_gw<g>.rpt` is roughly 17k LUTs, 7k FFs and 4 RAMB36 for `0`, plus
      the MIG and DMA for `1`. Yosys estimates 26 % of the LUTs for `0`.

## 3. Program

```
vivado -mode batch -source cook_vivado/program.tcl -tclargs cook_vivado/out/cook_gw0.bit
```

This is volatile: power-cycling the board erases the design.

## 4. Stage A: healthy, GATEWAY = 0

All switches down. Program, then press CPU_RESET once.

| What | Expected |
|---|---|
| LED12 | blinks at 1 Hz (the clock runs) |
| LED13 | on almost at once (BIST done after about 330 cycles, 7 µs) |
| LED[7:4] | all on: every tile passed `alltoall.S` |
| LED[3:0], LED[11:8] | off |
| LED14, LED15 | dark (no error code) |
| LED17 red | off |
| Display | `000000DE`: code 0, tile 0, and its check count 0xDE = 222 |

- [ ] All rows as expected.
- [ ] Press CPU_RESET a few times: the same readings come back each time.
      Each reset reruns BIST and the programs.
- [ ] Press BTNC: nothing changes, because it only clears router error flags.

## 5. Stage B: fault switches

Set the switches, then press CPU_RESET. The BIST runs only after a reset.
- SW15 on breaks the link selected by SW[3:0], which is the link leaving tile
  `SW[3:0] / 4` in direction `SW[3:0] % 4` (0 N, 1 S, 2 E, 3 W).
- SW14 picks silent (down) or bit-flip (up). Both give the same readings.

Expected for every real link:
- LED17 red is on and the display shows code E.
- The pass LEDs read the same as in stage A, because the routers go around
  the dead link.
- LED14 and LED15 blink the code (14 blinks) and tile+1. For codes above 9,
  read the display instead.

| SW (hex) | Link | Dead physical link | Display |
|---|---|---|---|
| `8001` | tile 0 → S | 0–2 | `E00002D4` |
| `8002` | tile 0 → E | 0–1 | `E00002D2` |
| `8005` | tile 1 → S | 1–3 | `E0100358` |
| `8007` | tile 1 → W | 0–1 | `E0000252` |
| `8008` | tile 2 → N | 0–2 | `E0000294` |
| `800A` | tile 2 → E | 2–3 | `E02002B1` |
| `800C` | tile 3 → N | 1–3 | `E0100318` |
| `800F` | tile 3 → W | 2–3 | `E0200231` |
| `8000 8003 8004 8006 8009 800B 800D 800E` | off the mesh edge | none | as stage A, LED17 off |

With SW14 up, the SW value is `C0xx` and the readings are the same.

How to read the display: `E` is the code, the next two digits are the tile (the
lower-numbered end of the dead link), then `0`, then that router's BIST status
`{6'b0, in[4:0], out[4:0]}`. Each 5-bit group reads L W E S N from the left,
and 1 = passed. For example, `02D4` = in `10110`, out `10100`: tile 0 received
correctly from E, S and its local port, but could not verify its S output.

- [ ] Every row of the table as expected, in both modes.
- [ ] The pass LEDs stay on for every row: this is the M3 result on silicon.
- [ ] Switches back down and CPU_RESET: back to stage A.

A switch changed *without* a reset injects a fault the start-up BIST never saw.
`alltoall.S` finishes within a millisecond of reset, so with no traffic left,
nothing shows. A test of run-time faults needs a looping program; it is left
for later.

## 6. Stage C: GATEWAY = 1

Program `cook_gw1.bit`, all switches down, CPU_RESET.

| What | Expected |
|---|---|
| LED16 green | on once the DDR2 calibration finishes (MIG `init_calib_complete`) |
| LED13 | on: BIST done and every tile's status collected at the gateway |
| LED[6:4] | on: cores 0 to 2 passed |
| LED[7] | off: tile 3 is the gateway, with no core and no pass report |
| LED[3:0], LED[11:8] | off |
| LED17 blue | off (`alltoall.S` does not use the DMA) |
| Display | `00000096`: the check count 0x96 = 150 = 74 + 74 + 2 for the gateway |

- [ ] All rows as expected.
- [ ] Repeat the stage B table: the same displays, with LED[6:4] still on.

## 7. Not covered on the board yet

- DMA transfers through the gateway: these need a DMA test program (compiler
  work). `tb_gw_dma_ip` in Vivado simulation covers the real IP until then.
- Run-time faults: these need a looping program (section 5).
- DDR2 contents: only calibration is checked.

## 8. If something is off

| Symptom | Look at first |
|---|---|
| Nothing lit, no heartbeat | bitstream not loaded (check the board's DONE LED) |
| Heartbeat, LED13 never on | reset held (CPU_RESETN pin C12), BIST or gateway collection stuck. With GATEWAY = 1, try GATEWAY = 0 |
| Code 1 (trap) on every tile | RAM images missing at synthesis (section 2 check) |
| Code 2 or 9 on a tile, display not E | a fault BIST did not see. Note the display and the switch setting |
| Code E with all switches down | a real link fault, or a timing problem: check WNS, then the router named |
| LED16 green never on | MIG calibration: the 200 MHz clock, the DDR2 pins (`mig_nexys4ddr.prj`) |

All codes are listed in `rtl/board/status_panel.v`.
