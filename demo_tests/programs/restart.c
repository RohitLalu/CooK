/* restart.c -- one core stops, another notices and starts it again.
 * Build with -DVICTIM for core 1; core 0 runs the supervisor; core 2 idles.
 *   core 1  first run: marks its mailbox and executes an illegal instruction,
 *           so the core traps and stops. Second run: sees the mark and
 *           reports pass (0x600D0002: second life).
 *   core 0  polls core 1's core-control CSR (0x018, ni.v). When it shows a
 *           trap, writes 1 to it: core 1 restarts from its reset address.
 *           Then waits for core 1's pass and reports its own:
 *           0x600D0001, or 0xFA110000 | step (1 no trap seen, 2 no pass after
 *           the restart).
 * A restart does not reload the tile's memory, which is how the mark in the
 * mailbox survives it. The program's own initialised variables are put back
 * by the start-up code on every start (crt0.S); `lives` below checks that:
 * the first run changes it, and the second run must find it at 1 again. */
#include "tile.h"

#define CSR_CORE 0x018
#define MARK     440          /* a mailbox word nobody else uses */

#ifdef VICTIM
volatile uint32_t lives = 1;                     /* initialised data */

int main(void)
{
    volatile uint32_t *mark = MBOX(tile_id()) + MARK;
    if (lives != 1) tile_report(0, 3);           /* start-up did not restore it */
    if (*mark != 0x1BADC0DEu) {
        *mark = 0x1BADC0DEu;
        lives = 99;                              /* what a first run leaves behind */
        tile_status(0x52550001);                 /* first life */
        __asm__ volatile (".word 0x00000000");   /* illegal instruction: the core traps */
    }
    tile_report(1, 2);
    return 0;
}
#else
int main(void)
{
    uint32_t n;
    if (tile_id() != 0) for (;;) tile_status(0x600D0000);        /* core 2: nothing to do */
    tile_status(0x52550000);
    for (n = 0; n < 200000u && !(REG32(TILE_ADDR(1, CSR_CORE)) & 1); n++) ;
    if (!(REG32(TILE_ADDR(1, CSR_CORE)) & 1)) return 1;
    REG32(TILE_ADDR(1, CSR_CORE)) = 1;                           /* restart core 1 */
    for (n = 0; n < 200000u && REG32(TILE_ADDR(1, CSR_STATUS)) != 0x600D0002u; n++) ;
    if (REG32(TILE_ADDR(1, CSR_STATUS)) != 0x600D0002u) return 2;
    tile_report(1, 1);
    return 0;
}
#endif
