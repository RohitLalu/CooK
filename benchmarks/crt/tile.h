/* tile.h -- what a C program on a CooK tile can see. Same on the NoC and on
 * the single-bus baseline: both use the same address map. */
#ifndef COOK_TILE_H
#define COOK_TILE_H
#include <stdint.h>

#ifndef TILE_SHIFT
#define TILE_SHIFT 16                    /* NOC_OFFSET_BITS of the build */
#endif

/* address of offset `off` inside tile `t` */
#define TILE_ADDR(t, off) ((uintptr_t)(((uint32_t)(t) << TILE_SHIFT) + (off)))
#define REG32(a)          (*(volatile uint32_t *)(a))

/* CSRs (ni.v) */
#define CSR_ID      0x000
#define CSR_ERR     0x004                /* bit 0 timeout, 1 illegal, 2 poison, 3 stale, 4 check */
#define CSR_STATUS  0x008
#define CSR_NTILES  0x00C
#define CSR_KIND    0x010                /* 0 core, 1 NoC gateway, 2 bus memory node */

#define POISON      0xDEADBEEFu          /* what a failed remote read returns */

extern char __tile_base[];
static inline uint32_t tile_id(void)     { return REG32((uintptr_t)__tile_base + CSR_ID); }
static inline uint32_t tile_count(void)  { return REG32((uintptr_t)__tile_base + CSR_NTILES); }
static inline void tile_status(uint32_t v) { REG32((uintptr_t)__tile_base + CSR_STATUS) = v; }
/* report and stop: pass = 0x600D0000 | low, fail = 0xFA110000 | low */
static inline void tile_report(int pass, uint32_t low)
{
    tile_status((pass ? 0x600D0000u : 0xFA110000u) | (low & 0xFFFFu));
    for (;;) ;
}

/* Mailbox: offsets 0x800..0xEFF of every tile, the only RAM other tiles may
 * write. 448 words. Remote writes are posted (no acknowledge), remote reads
 * wait for the answer. */
#define MBOX_OFF    0x800
#define MBOX_WORDS  448
#define MBOX(t)     ((volatile uint32_t *)TILE_ADDR(t, MBOX_OFF))

void *memcpy(void *d, const void *s, unsigned n);
void *memset(void *d, int c, unsigned n);
int   memcmp(const void *a, const void *b, unsigned n);
char *strcpy(char *d, const char *s);
int   strcmp(const char *a, const char *b);

#endif
