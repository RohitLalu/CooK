/* restart.c -- one core stops, another notices and starts it again.
 * Build with -DVICTIM for core 1; core 0 runs the supervisor; core 2 idles.
 *   core 1  at boot, looks for a restart token in its mailbox. None: first
 *           life, it executes an illegal instruction, so the core traps and
 *           stops. Token present: second life, it clears the token and
 *           reports pass (0x600D0002).
 *   core 0  polls core 1's core-control CSR (0x018, ni.v). When it shows a
 *           trap, it writes the restart token into core 1's mailbox, then
 *           writes 1 to 0x018: core 1 restarts from its reset address.
 *           Then it waits for core 1's pass and reports its own:
 *           0x600D0001, or 0xFA110000 | step (1 no trap seen, 2 no pass after
 *           the restart, 3 core 1 unreachable).
 * Core 0, not core 1, says "this is a restart". A CPU_RESET leaves the
 * mailbox as it was but writes no token, so every reset starts with a first
 * life, whatever the RAM still holds. Every remote read is checked for the
 * poison value before any bit is tested: an unreachable core 1 is reported
 * as such (step 3), not mistaken for a trap. The program's own initialised variables are put back
 * by the start-up code on every start (crt0.S); `lives` below checks that:
 * the first run changes it, and the second run must find it at 1 again. */
#include "tile.h"

#define CSR_CORE 0x018
#define MARK     440          /* a mailbox word nobody else uses */
#define TOKEN    0x5E57A47Du  /* "restart", written by core 0 just before it restarts core 1 */

#ifdef VICTIM
volatile uint32_t lives = 1;                     /* initialised data */

int main(void)
{
    volatile uint32_t *mark = MBOX(tile_id()) + MARK;
    if (lives != 1) tile_report(0, 3);           /* start-up did not restore it */
    if (*mark != TOKEN) {
        lives = 99;                              /* what a first run leaves behind */
        tile_status(0x52550001);                 /* first life */
        __asm__ volatile (".word 0x00000000");   /* illegal instruction: the core traps */
    }
    *mark = 0;                                   /* second life: consume the token */
    tile_report(1, 2);
    return 0;
}
#else
int main(void)
{
    uint32_t n, v = 0;
    if (tile_id() != 0) for (;;) tile_status(0x600D0000);        /* core 2: nothing to do */
    tile_status(0x52550000);
    for (n = 0; n < 200000u; n++) {
        v = REG32(TILE_ADDR(1, CSR_CORE));
        if (v == POISON) return 3;                               /* core 1 unreachable */
        if (v & 1) break;                                        /* trapped */
    }
    if (!(v & 1)) return 1;
    MBOX(1)[MARK] = TOKEN;                                       /* "this is a restart" */
    if (MBOX(1)[MARK] != TOKEN) return 3;                        /* posted write: confirm it */
    REG32(TILE_ADDR(1, CSR_CORE)) = 1;                           /* restart core 1 */
    for (n = 0; n < 200000u; n++) {
        v = REG32(TILE_ADDR(1, CSR_STATUS));
        if (v == POISON) return 3;
        if (v == 0x600D0002u) break;
    }
    if (v != 0x600D0002u) return 2;
    tile_report(1, 1);
    return 0;
}
#endif
