/* dma_lock.c -- every core moves data to the DDR and back through the
 * gateway's DMA, contending for the one DMA lock. Runs on every core; NoC
 * only (the single-bus baseline has no gateway). Each round:
 *   1. claim the lock (read DMA_LOCK until granted; the gateway queues the
 *      cores and hands the lock on in turn)
 *   2. tile RAM -> DDR: WORDS words of a pattern, into this core's own zone
 *   3. DDR -> tile RAM: the same words back into a second buffer
 *   4. compare, release the lock
 * Status CSR: 0x600D0000 | rounds done, or 0xFA110000 | step that failed
 * (1 lock never granted, 2 to-DDR never finished, 3 from-DDR never finished,
 * 4 data differs, 5 the gateway refused a request). ROUNDS = 0 loops forever
 * (board); the simulation sets a small number.
 * An unreachable gateway answers every read with the poison value; it is
 * treated as "no answer" before any bit is tested, so a cut-off core reports
 * step 1, not a false "granted". Both DMA channels run with the
 * interrupt-on-complete enabled (LED17 blue on the board); the interrupt is
 * cleared after each transfer.
 * Registers: rtl/dma_ddr/gw_ni.v. */
#include "tile.h"

#ifndef ROUNDS
#define ROUNDS 0
#endif
#define WORDS 32

#define GW(off)        REG32(TILE_ADDR(tile_count() - 1, off))
#define MM2S_DST       0x100
#define S2MM_SRC       0x104
#define S2MM_CNT       0x108
#define GW_STATUS      0x10C        /* bit 1 from-DDR done, bit 3 to-DDR done */
#define DMA_LOCK       0x114        /* read: bit 31 granted; write: release */
#define DMA_REJECT     0x118        /* bit 31: a request was refused */
#define DMA(off)       GW(0x200 + (off))
#define MM2S_DMACR     0x00
#define MM2S_DMASR     0x04
#define MM2S_SA        0x18
#define MM2S_LENGTH    0x28
#define S2MM_DMACR     0x30
#define S2MM_DMASR     0x34
#define S2MM_DA        0x48
#define DMACR_RUN      0x00000001u
#define DMA_IOC        0x00001000u  /* DMACR: interrupt on complete; DMASR: write 1 to clear */
#define S2MM_LENGTH    0x58

static uint32_t out_buf[WORDS], in_buf[WORDS];
/* first byte of each core's DDR zone (gw_ni.v: three 40 MB zones, 4 MB shared windows between) */
static const uint32_t zone[3] = { 0x00000000u, 0x02C00000u, 0x05800000u };

static int wait_bit(uint32_t off, uint32_t mask)
{
    uint32_t n, v;
    for (n = 0; n < 200000u; n++) {
        v = GW(off);
        if (v == POISON) return 0;                   /* gateway unreachable */
        if (v & mask) return 1;
    }
    return 0;
}

/* failure code for a transfer that did not finish: 5 if the gateway refused it */
static int why(int step)
{
    uint32_t v = GW(DMA_REJECT);
    return (v != POISON && (v >> 31)) ? 5 : step;
}

int main(void)
{
    uint32_t me = tile_id(), round = 0, i, ddr = zone[me] + 0x1000;
    tile_status(0x52550000);
    for (;;) {
        if (!wait_bit(DMA_LOCK, 0x80000000u)) tile_report(0, 1);
        for (i = 0; i < WORDS; i++) { out_buf[i] = (me << 28) | (round << 8) | i; in_buf[i] = 0; }

        GW(S2MM_SRC) = (uint32_t)(uintptr_t)out_buf;             /* tile RAM -> DDR */
        DMA(S2MM_DMACR)  = DMACR_RUN | DMA_IOC;
        DMA(S2MM_DA)     = ddr;
        DMA(S2MM_LENGTH) = WORDS * 4;
        GW(S2MM_CNT)     = WORDS;                                /* go */
        if (!wait_bit(GW_STATUS, 0x8)) tile_report(0, why(2));
        GW(GW_STATUS) = 0x8;
        DMA(S2MM_DMASR) = DMA_IOC;                               /* clear the interrupt */

        GW(MM2S_DST) = (uint32_t)(uintptr_t)in_buf;              /* DDR -> tile RAM */
        DMA(MM2S_DMACR)  = DMACR_RUN | DMA_IOC;
        DMA(MM2S_SA)     = ddr;
        DMA(MM2S_LENGTH) = WORDS * 4;                            /* go */
        if (!wait_bit(GW_STATUS, 0x2)) tile_report(0, why(3));
        GW(GW_STATUS) = 0x2;
        DMA(MM2S_DMASR) = DMA_IOC;                               /* clear the interrupt */

        GW(DMA_LOCK) = 0;                                        /* release: next core's turn */
        for (i = 0; i < WORDS; i++)
            if (in_buf[i] != out_buf[i]) tile_report(0, 4);
        round++;
        if (ROUNDS && round == ROUNDS) tile_report(1, round);
        tile_status(0x52550000 | (round & 0xFFFF));             /* keep the count out of 5255 */
    }
}
