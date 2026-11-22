/* dma_rate.c -- measures the DMA transfer rate on the board, both directions.
 * Core 0 only; cores 1 and 2 idle (their pass LEDs light at once).
 *   phase A  DDR -> tile RAM: ROUNDS_A transfers of WORDS words
 *            (status 5255000A while it runs, 5255000C when it ends)
 *   phase B  tile RAM -> DDR: ROUNDS_B transfers of WORDS words
 *            (status 5255000B while it runs, 5255000D when it ends)
 *   done     0x600D0000; or 0xFA110000 | step (1 lock, 2 phase A, 3 phase B
 *            setup, 4 data wrong after phase A, 5 data wrong after phase B,
 *            3xx a phase B transfer never finished, xx = the gateway's refusal reason)
 * Time phase A from 5255000A to 5255000C, and phase B from 5255000B to
 * 5255000D, with a stopwatch (SW7 on, SW5:4 = 0 shows core 0's status word).
 * The data checks run outside the timed phases. With the defaults,
 * each phase moves about 400 MB (phase A) or 100 MB (phase B), several
 * seconds at the simulated rates (49.6 and 12.5 MB/s), so a stopwatch error
 * of 0.2 s is a few percent.
 *   rate = WORDS * 4 * rounds / seconds
 * Simulation builds it with small ROUNDS_A / ROUNDS_B. NoC only.
 * The lock is claimed again before each phase: a local loop over the buffer
 * takes longer than the gateway's lease, and the lease rightly takes the
 * lock from an owner that goes quiet. Between status polls the core waits
 * locally, because every poll is a read through the gateway and polling flat
 * out slows the transfer being measured. */
#include "tile.h"

#ifndef WORDS
#define WORDS    4096                 /* 16 KB per transfer */
#endif
#ifndef ROUNDS_A
#define ROUNDS_A 25000                /* 25000 x 16 KB = 410 MB */
#endif
#ifndef ROUNDS_B
#define ROUNDS_B 6000                 /* 6000 x 16 KB = 98 MB */
#endif

#define GW(off)        REG32(TILE_ADDR(tile_count() - 1, off))
#define MM2S_DST       0x100
#define S2MM_SRC       0x104
#define S2MM_CNT       0x108
#define GW_STATUS      0x10C
#define DMA_LOCK       0x114
#define DMA(off)       GW(0x200 + (off))
#define DDR_ADDR       0x00100000u    /* inside core 0's zone Z0 */

static uint32_t buf[WORDS];

#ifndef POLLS
#define POLLS 2000000u
#endif
#ifndef GAP
#define GAP 64                        /* local delay-loop turns between polls */
#endif
static int wait_bit(uint32_t off, uint32_t mask)
{
    uint32_t n, v;
    volatile uint32_t d;
    for (n = 0; n < POLLS; n++) {
        for (d = 0; d < GAP; d++) ;
        v = GW(off);
        if (v == POISON) return 0;
        if (v & mask) return 1;
    }
    return 0;
}

int main(void)
{
    uint32_t r, i;
    if (tile_id() != 0) for (;;) tile_status(0x600D0000);
    tile_status(0x52550000);
    for (i = 0; i < WORDS; i++) buf[i] = 0xA5000000u | i;        /* the pattern, before taking the lock */
    if (!wait_bit(DMA_LOCK, 0x80000000u)) return 1;

    /* put the pattern in the DDR first (one S2MM transfer) */
    GW(S2MM_SRC) = (uint32_t)(uintptr_t)buf;
    DMA(0x30) = 1; DMA(0x48) = DDR_ADDR; DMA(0x58) = WORDS * 4;
    GW(S2MM_CNT) = WORDS;
    if (!wait_bit(GW_STATUS, 0x8)) return 3;
    GW(GW_STATUS) = 0x8;

    tile_status(0x5255000A);                                     /* phase A: DDR -> tile */
    for (r = 0; r < ROUNDS_A; r++) {
        GW(MM2S_DST) = (uint32_t)(uintptr_t)buf;
        DMA(0x00) = 1; DMA(0x18) = DDR_ADDR; DMA(0x28) = WORDS * 4;
        if (!wait_bit(GW_STATUS, 0x2)) return 2;
        GW(GW_STATUS) = 0x2;
    }
    tile_status(0x5255000C);                                     /* phase A ends */
    for (i = 0; i < WORDS; i++) if (buf[i] != (0xA5000000u | i)) return 4;
    if (!wait_bit(DMA_LOCK, 0x80000000u)) return 1;              /* the check above outlasts the lease */

    tile_status(0x5255000B);                                     /* phase B: tile -> DDR */
    for (r = 0; r < ROUNDS_B; r++) {
        GW(S2MM_SRC) = (uint32_t)(uintptr_t)buf;
        DMA(0x30) = 1; DMA(0x48) = DDR_ADDR; DMA(0x58) = WORDS * 4;
        GW(S2MM_CNT) = WORDS;
        if (!wait_bit(GW_STATUS, 0x8)) tile_report(0, 0x300 | (GW(0x118) & 0xF));   /* 3, with the refusal reason */
        GW(GW_STATUS) = 0x8;
    }
    tile_status(0x5255000D);                                     /* phase B ends */
    for (i = 0; i < WORDS; i++) buf[i] = 0;                      /* read it back to check */
    if (!wait_bit(DMA_LOCK, 0x80000000u)) return 1;
    GW(MM2S_DST) = (uint32_t)(uintptr_t)buf;
    DMA(0x00) = 1; DMA(0x18) = DDR_ADDR; DMA(0x28) = WORDS * 4;
    if (!wait_bit(GW_STATUS, 0x2)) return 2;
    GW(GW_STATUS) = 0x2;
    for (i = 0; i < WORDS; i++) if (buf[i] != (0xA5000000u | i)) return 5;

    GW(DMA_LOCK) = 0;
    tile_report(1, 0);
    return 0;
}
