# Software changes (to do)

> **Status: DONE in simulation.** Items 1 to 4 are fixed in the programs and checked by the `fixes` case of `demo_tests/run_demos.py`; item 5 is done for `demo_tests/README.md`. Open: rerun on the board, and `quick_look/3_testing_on_nexys4.md`. None of these needed a hardware change. Every item here was seen on the board or in the board-top simulation; each says which.

All the demo programs are in `demo_tests/programs/` unless stated otherwise. After a change, rebuild the images (`python3 demo_tests/run_demos.py --board`), rerun the simulation (`python3 demo_tests/run_demos.py`), and either rebuild the 64 KB bitstream or swap the new images into the existing one with `updatemem` (see `hw_changes.md`, item 12).

---

## 1. Treat the poison value as "unreachable" in every remote poll

**Seen on the board:** `restart.c` (SW 1003, 100B, 0500) and `dma_lock.c` (SW 1003, 1004, 1006, 1009, 100B, 0500, 0700).

**What happens.** When a remote read cannot reach its tile, the network interface retries twice and then gives the core `0xDEADBEEF` (`NOC_POISON_DATA`, `rtl/include/noc_defs.vh`) and sets the timeout flag (CSR `0x004` bit 0). The programs test single bits of the value they read, and `0xDEADBEEF` has most bits set, so the poison value passes those tests:

- **`restart.c`, core 0.** It polls core 1's core-control CSR (`0x018`) for bit 0, "trapped". Poison has bit 0 set, so core 0 believes core 1 has trapped on its first poll. It then writes the restart, which is lost, polls core 1's status 200,000 times (each poll times out, about 61 µs), and ends on `FA110002` ("no pass after the restart") after about 12.2 s on the board. The correct result is `FA110001` ("no trap seen"), or better a separate "core 1 unreachable" code.
- **`dma_lock.c`, every core.** An unreachable gateway returns `0xDEADBEEF` from the `DMA_LOCK` read. Bit 31 is set, so the core takes it as "lock granted". The `GW_STATUS` done bits (`0x8`, `0x2`) look set too. The core then compares buffers that never moved and reports `FA110004` ("data differs"). The correct result is `FA110001` ("lock never granted").

**Fix.** In every loop that polls a remote register, treat `0xDEADBEEF` as "no answer" before looking at any bit. A real lock reply and a real status word can never equal `0xDEADBEEF`: their unused bits are 0. Where the value read could legitimately be any 32-bit word (plain RAM), check the timeout flag instead: read the local CSR `0x004`, test bit 0, then clear it by writing 1.

```c
#define POISON 0xDEADBEEFu
static int wait_bit(uint32_t off, uint32_t mask)          /* dma_lock.c */
{
    uint32_t n, v;
    for (n = 0; n < 200000u; n++) {
        v = GW(off);
        if (v == POISON) return 0;                      /* gateway unreachable */
        if (v & mask) return 1;
    }
    return 0;
}
```

In `restart.c`, core 0: read `CSR_CORE` into a variable, leave the loop with a new code (for example `return 3`, "core 1 unreachable") when it equals `POISON`, and only then test bit 0. Treat the status poll after the restart the same way.

`encryption_code/crypto/core0_arbiter.c` already does this correctly: it reads each worker's ID register first and fails at once with `FA110008` if the answer is not the expected ID. The board confirmed it for every multi-link and router fault. Use it as the model.

---

## 2. Make the demos correct after CPU_RESET (tile RAM is not reloaded)

**Seen on the board:** `speedup.c` and `restart.c`.

**Background.** The tile RAM is block RAM, loaded with the program only when the FPGA is programmed. CPU_RESET restarts the cores but leaves the RAM as it was: the start-up code (`benchmarks/crt/crt0.S`) restores the program's own variables, but not the mailboxes (`0x800`–`0xEFF`). Anything a previous run left in a mailbox is still there.

### 2a. `speedup.c`

**What happens.** After one healthy run, core 0's result slots hold `seq = 1` and the correct digests, and each worker's job slot holds `seq = 1`. Press CPU_RESET with a multi-link fault: the new jobs are lost at the dead links, but each worker sees the old `seq = 1`, redoes the old job locally and shows `600D0001`. Core 0 finds the old results with the same seeds and reports `600D07D0`. The fault is hidden. With fresh RAM (programming the bitstream) the same switch settings fail correctly: core 0 `FA110002`, unreachable workers stay at `52550000`.

**Fix.**
- Worker, at the start of `main`: `last = job[0];`. Whatever is already in the mailbox is ignored, and only a sequence number written after this boot starts a job.
- Core 0, before phase B: clear its result slots (`mine[16 * t] = 0` for t = 1, 2), and choose a sequence number that differs from the one already in each worker's mailbox (`seq = MBOX(t)[0] + 1`, skipping 0). The worker's mailbox is readable even with the read window on.
- Confirm each job with a read-back of the sequence word, as `post_seq()` in `encryption_code/crypto/proto.h` does. A lost job is then reported at once instead of after the 40-million-poll wait.

### 2b. `restart.c`

**What happens.** Core 1 marks its mailbox (`0x1BADC0DE` at word 440) before it traps on purpose, so that its second life can tell it has already trapped. CPU_RESET does not clear the mark, so on every run after the first, core 1 passes at once without trapping. Core 0 never sees a trap and ends on `FA110001`. On the board: correct right after programming, `FA110001` on core 0 after every CPU_RESET (SW 1002, 1005, 1004 tested).

**Fix.** Let core 0, not core 1, say "this is a restart". Core 0 writes a restart token (for example `0x5E57A47D`) into core 1's mailbox immediately before it writes 1 to core 1's `0x018`. At boot, core 1 checks for the token: present means second life (clear the token, report `600D0002`); absent means first life (trap). A CPU_RESET then always starts with "first life", whatever the RAM holds.

---

## 3. `dma_lock.c`: keep the round count out of the upper half of the status word

**Seen on the board:** healthy run, after a few minutes.

**What happens.** The status is written as `0x52550000 | round`. `round` is a 32-bit counter, so once it passes `0xFFFF` its upper bits are ORed into `5255`. The board showed `5257xxxx`, then `525Fxxxx`, then `5255xxxx` again. It is harmless: `0x5255 | x` can never become `600D` or `FA11`, so the panel still reads "running". But it is misleading.

**Fix.** `tile_status(0x52550000 | (round & 0xFFFF));`

---

## 4. `dma_lock.c`: LED17 blue never lights

**Seen on the board:** LED17 blue stayed off for the whole DMA test.

**What happens.** The board top drives LED17 blue from the AXI DMA interrupt outputs (`mm2s_introut | s2mm_introut`). The program starts the DMA with `DMACR = 1` (run/stop only), without the interrupt-on-complete enable (bit 12), so the DMA never raises an interrupt. `demo_tests/README.md` says the LED flickers; that is wrong for the current program.

**Fix, one of:**
- Enable the interrupt: write `DMACR = 1 | (1u << 12)` on both channels, and after each transfer clear it by writing 1 to bit 12 of the matching status register (`MM2S_DMASR` at DMA offset `0x04`, `S2MM_DMASR` at `0x34`). Otherwise the interrupt stays pending and the LED stays on. Both status registers are among the eight DMA registers the gateway lets the lock owner write (`D_MM2S_SR`, `D_S2MM_SR` in `rtl/dma_ddr/gw_ni.v`), so no hardware change is needed.
- Or keep the program as it is and correct `demo_tests/README.md`.

---

## 5. Documentation to correct

- `demo_tests/README.md`:
  - The LED17 blue claim (item 4).
  - Note that fault tests of the speed-up and restart demos must reprogram the bitstream, not use CPU_RESET, until item 2 is done.
  - The DMA demo shows `5255` + round count and never lights a pass LED.
- `quick_look/3_testing_on_nexys4.md`: replace the predictions with the board results of 19 and 20 November (the measured tables are in the end-semester report, section "Board Tests").

---

## 6. Already correct, no change needed

- `loop_traffic.c`: every result matched on the board, including run-time faults.
- `alltoall.S` (`cook_gw1.bit`): every switch setting matched on the board.
- `encryption_code/crypto/*`: every row passed on the board. Healthy run 7.85 s from `52550000` to `600D2806`.
