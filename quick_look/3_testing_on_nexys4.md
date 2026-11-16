# Testing on the Nexys4 DDR through Vivado

> **Status: OPEN** (2026-11-16). The guide is complete. Open, and only closable on the board: stages D and E and the items under "changed since the first session" have never been run, so their expected readings are predictions.

**Where this stands.** The first board session, on 7 November, passed for the design as it was then: the healthy test and the single-street fault switches. Everything added since has passed in simulation only and needs a fresh build: the intersection test (code F), the wait for the memory to calibrate, the privacy options, restart, the laptop link, and all the demos, which need bigger house memories. Treat every "expect" below that mentions those as a prediction. If the board disagrees, that is a useful finding. The short checklist is `docs/hardware_test.md`; the demos are in `demo_tests/README.md`.

## The idea in plain words

An FPGA is like a giant box of Lego that can rebuild itself in a second. It starts with no function at all. You give it a set of building instructions, and it becomes your circuit.

Vivado is the program that writes those instructions from our Verilog. It works like an architect's office:

| Vivado step | Analogy | What it does |
|---|---|---|
| **Synthesis** | Turn the blueprint into a parts list | Verilog becomes logic blocks and memory |
| **Implementation** | Decide where each part sits and lay the wiring | Places parts on the chip and routes the wires |
| **Timing check** | Can a runner get across the building before the next bell? | Every signal must arrive before the next clock tick (20 ns at 50 MHz) |
| **Bitstream** | The finished instructions | The `.bit` file the chip loads |
| **Programming** | Hand the instructions to the Lego box | Sent over USB |

**Slack** is how much time a runner has left when the bell rings. Positive is good. Negative means a signal arrives late, and the board may behave randomly, so we don't test such a build.

Programming doesn't last. Turn the board off and the design is gone. That's fine for testing.

## What you need

- Nexys4 DDR board and its micro-USB cable, plugged into the port marked PROG/UART
- The Windows machine with Vivado and an up-to-date copy of this repo
- The `.mem` files in `sw/`, already built and in the repo. **No compiler is needed**

## Step 1: Build

Open the **Vivado Tcl Shell** from the Start menu, go to the repo folder with `cd`, and run:

```
vivado -mode batch -source cook_vivado/build.tcl -tclargs 0
```

The `0` means four ordinary workers and no warehouse. Later, `1` adds the gateway and DDR2 memory. **Always start with `0`.** It leaves out the big memory controller, so a problem there must be in our own design.

Expect this to take a while, and longer for `1`. When it finishes, check three things:

1. It printed a line like `COOK: GATEWAY=0 WNS=... WHS=...`, and both numbers are 0 or higher. These are the slack values. If either is negative, the script stops and gives no bitstream. Look in `cook_vivado/out/timing_gw0.rpt`.
2. The file `cook_vivado/out/cook_gw0.bit` exists.
3. The synthesis log (`cook_vivado/cook_vivado.runs/synth_1/runme.log`) has no `$readmemh` warning about `tile00.mem` to `tile03.mem`. Without those files the workers have no program.

Size check: `cook_vivado/out/util_gw0.rpt` should show roughly 17,000 LUTs, 7,000 flip-flops and 4 block RAMs. That's an estimate from another tool (Yosys), so Vivado's numbers will differ somewhat.

**Prefer clicking?** Open `cook_vivado/cook_vivado.xpr` in Vivado and press **Generate Bitstream**. One catch: the build script saves the `GATEWAY` setting into the project, so the GUI uses whichever value the script last set.

**Before stage C,** run the one test only Vivado can do: `tb_gw_dma_ip`, which uses the real DMA. Set it as the simulation top and run simulation. It needs the `cook_gw_sim` block design in the project.

## Step 2: Program

Turn the board on, then run:

```
vivado -mode batch -source cook_vivado/program.tcl -tclargs cook_vivado/out/cook_gw0.bit
```

Or use Vivado's Hardware Manager: Open Target, Auto Connect, Program Device.

## Reading the board

The board is your dashboard, so learn it before testing.

| Light | Meaning |
|---|---|
| LED 12 | Heartbeat, blinks once a second. The clock is running |
| LED 13 | System ready. Inspection finished, workers running |
| LEDs 4–7 | Tile 0–3 passed its test |
| LEDs 0–3 | Tile 0–3 has an error |
| LEDs 8–11 | Tile 0–3 reported failure |
| LED 15 | Blinks the error code |
| LED 14 | Blinks the tile number + 1 |
| LED 17 red | The inspection found a broken street |
| LED 16 green | DDR2 memory is calibrated (gateway build only) |
| LED 17 blue | DMA interrupt pending (gateway build only) |

**The display** has 8 digits, in the form `C TT 0 DDDD`: error code, tile number, a zero, then details.

## Stage A: healthy, four workers

All switches down. Press the red **CPU_RESET** button.

| Look at | Expect |
|---|---|
| LED 12 | Blinking |
| LED 13 | On, almost immediately |
| LEDs 4–7 | All on |
| LEDs 0–3, 8–11, 14, 15, LED 17 red | Off |
| Display | `000000DE` (no error, tile 0, 0xDE = 222 checks) |

Press CPU_RESET a few times. You should get the same result each time, because every reset reruns the inspection and the programs. Pressing BTNC (centre button) should change nothing.

**If stage A fails, stop here and fix it.** The later stages depend on it.

## Stage B: break a street on purpose

This is the big demo. The switches damage a street inside the chip, and the board has to cope.

**Recipe:**

1. Move the switches to one row of the table below.
2. Press **CPU_RESET**. This is essential, because the inspection only runs after a reset.
3. Check the display. LED 17 red should be on, and **LEDs 4–7 should still all be on**. That is the result: a street is broken and nobody lost their work.

SW12 up turns the fault on. Switches 0–3 pick the street. SW11 picks the failure style: down for silent, up for scrambled bits. Both styles give the same reading.

| Switches up (plus SW12) | Street broken | Display |
|---|---|---|
| SW0 | tile 0 going south | `E00002D4` |
| SW1 | tile 0 going east | `E00002D2` |
| SW0, SW2 | tile 1 going south | `E0100358` |
| SW0, SW1, SW2 | tile 1 going west | `E0000252` |
| SW3 | tile 2 going north | `E0000294` |
| SW1, SW3 | tile 2 going east | `E02002B1` |
| SW2, SW3 | tile 3 going north | `E0100318` |
| SW0, SW1, SW2, SW3 | tile 3 going west | `E0200231` |

**How to read `E0100358`:** code `E` (broken street found), tile `01`, a `0`, then `0358`, which is that tile's inspection report. The tile shown is the lower-numbered of the two ends of the street, which isn't always the end you broke.

The switch patterns that don't name a real street now do other things: three are unused and change nothing, and five break several streets at once (the list is at the top of `rtl/board/nexys4ddr/nexys4ddr_top.v`). With several streets broken the town splits, so some workers fail; that is expected. SW13 to SW15 are not used, because they are faulty on our board.

With code E, LED 15 blinks 14 times per cycle, which is hard to count, so trust the display.

Afterwards, put the switches down and press CPU_RESET to return to stage A.

**Tick each of the 8 rows in both styles.** That's 16 results, the same 16 cases as the `make m3` simulation, now on real hardware.

**A trap to avoid:** changing a switch *without* a reset will show nothing. The test program finishes within a millisecond of reset, so no traffic is left to run into the fault. This isn't a bug. Showing a live failure needs a program that keeps looping, which comes with the compiler work.

## Stage C: add the warehouse

Build and program with `1` in place of `0` (the file is `cook_gw1.bit`). Switches down, press CPU_RESET.

| Look at | Expect |
|---|---|
| LED 16 green | On, once the DDR2 finishes calibrating |
| LED 13 | On |
| LEDs 4–6 | On (the three workers passed) |
| LED 7 | **Off, and that's correct.** Tile 3 is the gateway, with no worker to report a pass |
| LEDs 0–3, 8–11, LED 17 blue | Off |
| Display | `00000096` (0x96 = 150 checks: 74 + 74 + 2 for the gateway) |

Then repeat the stage B table. The displays should match, with LEDs 4–6 still on.

## Stage D: break an intersection on purpose

SW10 up breaks a traffic cop from the inside. SW9 and SW8 pick which one, as a binary number (both down = tile 0, SW8 up = tile 1, SW9 up = tile 2, both up = tile 3). Press CPU_RESET.

| Look at | Expect |
|---|---|
| Display | starts with `F` (intersection test failed), then the tile number |
| That tile's LEDs | its pass LED stays off: the town has cut that house off |
| The other tiles | still pass |

This has been simulated but never run on the board. The exact display for each router is in `docs/hardware_test.md` (for example `F0100150` for router 1). LED 17 red also comes on.

## Stage E: the demos

These need a build with bigger house memories (64 KB instead of 4 KB) and their own programs. That build has not been made yet. `demo_tests/README.md` has the list and what each should show:

- three workers doing encryption and a signature, with and without a fault;
- traffic that never stops, where flipping a fault switch **without** reset makes the workers on that street fail while the others keep counting;
- one worker restarting another;
- the laptop link: type a message on the laptop, and the board decrypts it and shows the first 8 letters.

## What this doesn't test yet

- **Real warehouse transfers.** The program never uses the DMA, so only memory calibration is shown. Moving data needs a new test program, which comes with the compiler work. `tb_gw_dma_ip` covers it in simulation until then.
- **Faults that appear while running,** for the reason above.
- **Inside-the-router faults,** which are planned after these tests pass.

## Things that changed since the first session

- **LED 13 now waits for the big memory.** With the warehouse build, the system holds everything until the DDR2 has calibrated, so LED 13 comes on a moment later than before, after LED 16 green.
- **The morning inspection is longer** (545 ticks, up from 329). Still far too fast to see.
- **A new code, F,** ranks above E. A failed intersection also closes its streets, so you may see its neighbours report E as well; F is the cause.
- **Two new pins** are used for the laptop link (the USB serial port). They do nothing unless the link is switched on in the build.

## If something looks wrong

| You see | Look at first |
|---|---|
| Nothing lit, no heartbeat | The bitstream didn't load. Check the board's DONE LED and the USB cable |
| Heartbeat, but LED 13 never on | Reset stuck, or the inspection stuck. If this is the gateway build, go back to `0` |
| Code 1 on every tile | The programs are missing. See the `$readmemh` check in step 1 |
| Code F with SW10 down | An intersection failed its own test. Check slack first: the test adds logic on every router. Then note the display |
| Code E with all switches down | Either a timing problem (check slack first) or a real fault. Note the display |
| Code 2 or 9 with no E | A fault the inspection didn't see. Note the display and the switches |
| LED 16 green never on | The memory controller couldn't calibrate. Check the 200 MHz clock and DDR2 pins in `rtl/dma_ddr/mig_nexys4ddr.prj` |
| Build stops on negative slack | Open `timing_gw<g>.rpt` and find the worst path. The new detour logic in the router is a likely suspect |

All error codes are listed at the top of `rtl/board/status_panel.v`.

**Whenever something differs, write down:** the build (`0` or `1`), the switch positions, the display, and which LEDs are lit. That's enough to reproduce it in simulation.
