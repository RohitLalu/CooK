# Hardware changes (to do)

> **Status: OPEN** (2026-11-20). Collected during the board tests of 19 and 20 November 2026. **No board test failed because of the hardware**: every failure found was in software (see `sw_changes.md`). The items below are design choices taken for now, that we aim to change in the future, plus small fixes to the build files. The DMA lock in particular worked correctly on the board: three cores shared the one DMA engine fairly for hundreds of thousands of rounds.

Each item gives what the hardware does now, why that was chosen, what it costs, and the proposed change.

---

## A. Design choices to revisit

### 1. Poison is returned in-band

**Now.** A remote read that exhausts its retries (`ni.v`, `TIMEOUT_CYCLES` = 1024, `RETRY_MAX` = 2, about 61 µs at 50 MHz) completes with the data value `0xDEADBEEF` and sets the sticky timeout flag (CSR `0x004` bit 0). The core cannot tell from the value alone whether the read worked.

**Why chosen.** PicoRV32's native memory interface has no bus-error signal, and a core waiting forever would hang the tile, which is the failure this project exists to prevent. An in-band value needs no change to the core.

**Cost seen on the board.** Every program must check for poison itself. Two demos did not (restart and DMA), and the poison value passed their bit tests: `FA110002` and `FA110004` instead of `FA110001`.

**Proposed change, cheapest first.**
- Make every hardware reply that software tests bit by bit impossible to confuse with poison. For example, the gateway's `DMA_LOCK` reply could carry a fixed pattern in its unused bits (bits [29:8] are 0 today, so software can already check this).
- Add a per-access error indication the core can see without a second read: a "last remote read failed" CSR bit that is set and cleared by hardware on every remote read.
- Raise a PicoRV32 interrupt (`ENABLE_IRQ`) on a read timeout, so the core enters a handler instead of continuing with the poison value.

### 2. CPU_RESET does not restore tile memory, and software cannot tell which reset happened

**Now.** Tile RAM is block RAM initialised only when the FPGA is programmed. CPU_RESET, a core restart through CSR `0x018`, and power-on all start the core at the same address with the same registers. Mailboxes keep their old contents.

**Why chosen.** Reloading 64 KB per tile would need a second copy of every image (double the block RAM) or a loader. The restart demo relies on the memory surviving a core restart.

**Cost seen on the board.** Speed-up and restart give wrong results after CPU_RESET (stale mailbox data), so fault tests had to reprogram the bitstream.

**Proposed change.** Add a read-only reset-cause CSR (for example at `0x01C`, now reserved): 0 = FPGA configured, 1 = CPU_RESET, 2 = restarted by another core through `0x018`. Software can then clear its mailboxes on the first two and keep them on the third. This is small: two flip-flops per tile and one decode.

### 3. Faults that appear after reset are not routed around

**Now.** BIST runs once, after a total reset. A link that breaks later is detected (router watchdog, NI timeout and poison), but the routers keep sending across it until the next reset.

**Why chosen.** X-Y routing with a fixed dead-link mask is deadlock-free by construction. Changing routes while packets are in flight reopens deadlock and ordering problems.

**Cost seen on the board.** Traffic test B: a link switched off without reset makes the cores that use it fail (`FA11`, panel code 2) until CPU_RESET; after the reset BIST finds the link and every core runs again.

**Proposed change.** BIST on demand: a CSR write or a button that quiesces the network (cores held, NIs drained), reruns `bist_node` and the gossip, and releases. Later, adaptive rerouting with a deadlock-avoidance scheme.

### 4. A broken in-link also removes the out-link

**Now.** The ping-pong sends the pong back over the reverse link. If the reverse link is broken, the pong is lost and the forward link is marked faulty too. Every one-direction fault therefore removes the whole physical link, at both ends.

**Why chosen.** It is inherited from the thesis BIST and needs no extra path. Treating the link as all-or-nothing keeps routing simple.

**Cost.** Half of a usable link is thrown away. Not visible in the demos, because the ring detour covers any single link.

**Proposed change.** Return the pong by another route, or have the receiving end report its in-link result through the gossip, so the two directions can be judged separately.

### 5. Routing around faults works on the 2 × 2 ring only

**Now.** With dead links, a packet goes whichever way round the ring 0-1-3-2-0 is clean. Larger meshes ignore the dead-link mask and keep plain X-Y.

**Proposed change.** Up*/down* or table-based routing computed from the dead-link mask after BIST, for 3 × 3 and larger.

### 6. A router fault cuts its whole tile off

**Now.** If a router fails any part of its self-test, all its ports are reported dead and all its links go into the dead-link mask (panel code F).

**Why chosen.** A router that failed one path cannot be trusted with the others, and it is simple.

**Proposed change.** Use the self-test's per-port result (`rt_status = {in_bad, out_bad}`) to disable only the failed ports, when the remaining ones still give the tile a route.

### 7. The display shows one error at a time

**Now.** `status_panel.v` shows the highest-priority code on the lowest tile. A router fault (F) hides a link fault (E) present at the same time; a trapped core (1) hides both.

**Proposed change (chosen, on hold).** Cycle the display through every active error, for example `F…` then `E…`, about 2 s each. Change in `status_panel.v`; needs every bitstream rebuilt. The error LEDs (LED0–3) already show every tile with an error.

### 8. Posted writes are not acknowledged

**Now.** Remote writes and DMA MM2S words have no reply. A write lost at a dead link is not reported to the sender.

**Why chosen.** Halves the traffic for writes and keeps the NI small.

**Proposed change.** Optional acknowledged writes (a flag in the HEAD), used for mailbox sequence words and other writes that must be confirmed. Today software confirms with a read-back (`post_seq()` in `encryption_code/crypto/proto.h`).

### 9. The gateway is a single point of failure for memory

**Now.** Tile 3 is the only way to DDR2. Router 3 faulty (SW 0700) fails every DMA user. Crypto, which needs no DDR, still passed with router 3 broken.

**Proposed change.** A second gateway, with lock and zone ownership across the two.

### 10. Status word format is software-defined

**Now.** CSR `0x008` is plain read/write; the panel only interprets the upper half (`600D` pass, `FA11` fail, anything else running). A program can write misleading values (seen: `5257` from the DMA round counter).

**Proposed change (optional).** Keep as is, or split it into a hardware-checked state field and a free count field.

---

## B. Build and source fixes

### 11. Timing constraint added for the DDR calibration synchroniser (done, uncommitted)

The GATEWAY = 1 build failed timing by 1.9 ns on `init_calib_complete` (MIG `ui_clk`) into `calib_s_reg[0]` (NoC clock): a clock-domain crossing without a constraint. Fixed with `set_false_path -to [get_cells {calib_s_reg[0]}]` in `rtl/board/nexys4ddr/nexys4ddr.xdc`. All six bitstreams now meet timing: WNS +1.187 ns (4 KB) and +1.316 ns (64 KB). Commit it.

### 12. Change the program without rebuilding the bitstream (`updatemem`)

Every program change now costs about an hour of synthesis and implementation per bitstream, because the images are block-RAM initial values. Vivado's `updatemem` can replace them in a finished `.bit` in seconds, using a `.mmi` file that describes which RAMB36 blocks hold which address bits of tiles 0–2. Generate the `.mmi` once from the implemented 64 KB design by Tcl. Check it by applying the speed-up images to the traffic bitstream and comparing the result with `cook_gw1_demo64_speedup.bit`. Limit: only RAM contents change. A different `RD_PROTECT`, top level or tile size still needs a full build.

### 13. The GATEWAY = 0 build fails DRC

`DRC BIVRU-1` (bank 34 VREF): the DDR2 SSTL18 pin constraints in `nexys4ddr.xdc` apply to every build, but the MIG's own constraints (internal VREF, differential clock) are only read when the MIG is present. Move the DDR2 pin constraints into a file used only by GATEWAY = 1 builds, or guard them.

### 14. `bist_node.v` uses signals before declaring them

`rt_fail` (line 201, declared at 309), `rtr`, `rt_valid` and `rt_in_flit` are used before their declarations. Vivado synthesis warns (`Synth 8-6901`) and XSim rejects the file without `--relax`. Move the declarations up.

### 15. LD16 green does not light on our board

Not a design fault: LED16_G is driven by the MIG's `init_calib_complete` on pin M16, and calibration completes (LED13 cannot light otherwise). The board's LED channel is faulty, like SW13–15. Use LED13 as the "DDR2 calibrated, system ready" indicator on this board.
