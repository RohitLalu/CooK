/* loop_traffic.c -- traffic that never stops, so a fault that appears while
 * the system runs is visible. Runs on every core.
 * Each pass: for every other tile, read its ID register, and (core tiles
 * only) write a counter into a slot of its mailbox and read it back.
 * Status CSR, rewritten every pass, so the board's display counts up:
 *   0x600D0000 | passes (low 16 bits)   while every access has been right
 *   0xFA110000 | failed accesses        from the first failure on
 * On the board: flip a fault switch WITHOUT pressing reset. The start-up
 * BIST never saw that fault, so nothing routes around it: accesses across
 * the link time out and the cores that use it turn their fail LEDs on. */
#include "tile.h"

int main(void)
{
    uint32_t me = tile_id(), n = tile_count(), t, pass = 0, fails = 0, v;
    for (;;) {
        for (t = 0; t < n; t++) {
            if (t == me) continue;
            if (REG32(TILE_ADDR(t, CSR_ID)) != t) { fails++; continue; }
            if (REG32(TILE_ADDR(t, CSR_KIND)) != 0) continue;       /* gateway: no mailbox */
            v = (me << 28) | pass;
            MBOX(t)[400 + me] = v;
            if (MBOX(t)[400 + me] != v) fails++;
        }
        pass++;
        tile_status(fails ? 0xFA110000u | (fails & 0xFFFF) : 0x600D0000u | (pass & 0xFFFF));
    }
}
