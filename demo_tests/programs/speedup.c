/* speedup.c -- the same work on one core, then shared between three.
 * The work: BLOCKS chained SHA-256 hashes for each of three different seeds.
 *   phase A  core 0 does all three chains itself
 *   phase B  core 0 gives one chain each to cores 1 and 2 (a job in their
 *            mailboxes) and does the third itself, then collects the digests
 * The digests of phase B must equal those of phase A. Build with -DWORKER for
 * cores 1 and 2. Core 0's status CSR marks the phases, so the testbench (or
 * a stopwatch on the board, with a large BLOCKS) can time them:
 *   0x5255000A  phase A running      0x5255000B  phase B running
 *   0x600D0000 | BLOCKS  done, digests equal     0xFA110000 | step  on failure
 * Workers: 0x600D0000 | jobs done. */
#include "tile.h"
#include "sha256.h"

#ifndef BLOCKS
#define BLOCKS 2000
#endif
/* job in a worker's mailbox: [0] seq (written last) [1] blocks [2] seed
 * result in core 0's mailbox at 16 * worker: [0] seq [1..8] digest */

static void chain(uint32_t seed, uint32_t blocks, uint8_t d[32])
{
    uint32_t i;
    for (i = 0; i < 32; i++) d[i] = (uint8_t)(seed >> (8 * (i & 3)));
    for (i = 0; i < blocks; i++) sha256(d, 32, d);
}

#ifdef WORKER
int main(void)
{
    volatile uint32_t *job = MBOX(tile_id()), *res = MBOX(0) + 16 * tile_id();
    uint32_t seq, last = 0, jobs = 0, i, w[8];
    uint8_t d[32];
    tile_status(0x52550000);
    for (;;) {
        seq = job[0];
        if (seq == last) continue;
        last = seq;
        chain(job[2], job[1], d);
        for (i = 0; i < 8; i++) w[i] = d[4*i] | ((uint32_t)d[4*i+1] << 8) | ((uint32_t)d[4*i+2] << 16) | ((uint32_t)d[4*i+3] << 24);
        for (i = 0; i < 8; i++) res[1 + i] = w[i];
        res[0] = seq;
        tile_status(0x600D0000 | ++jobs);
    }
}
#else
int main(void)
{
    static const uint32_t seed[3] = { 0x11111111u, 0x22222222u, 0x33333333u };
    volatile uint32_t *mine = MBOX(0);
    uint8_t a[3][32], b[32];
    uint32_t t, i, n;

    tile_status(0x5255000A);
    for (t = 0; t < 3; t++) chain(seed[t], BLOCKS, a[t]);

    tile_status(0x5255000B);
    for (t = 1; t < 3; t++) {
        MBOX(t)[2] = seed[t];
        MBOX(t)[1] = BLOCKS;
        MBOX(t)[0] = 1;
    }
    chain(seed[0], BLOCKS, b);
    if (memcmp(b, a[0], 32)) return 1;
    for (t = 1; t < 3; t++) {
        for (n = 0; n < 40000000u && mine[16 * t] != 1; n++) ;
        if (mine[16 * t] != 1) return 2;
        for (i = 0; i < 32; i++) b[i] = (uint8_t)(mine[16 * t + 1 + (i >> 2)] >> (8 * (i & 3)));
        if (memcmp(b, a[t], 32)) return 3;
    }
    tile_report(1, BLOCKS);
    return 0;
}
#endif
