/* proto.h -- how the three cores of the crypto demo talk. Everything shared
 * goes through mailboxes (the only memory other tiles may write, tile.h);
 * everything else a core computes stays in its own tile.
 *
 *   core 0  key generator and arbiter: makes the keys, hands out jobs,
 *           collects and checks the results
 *   core 1  AES-128 worker        core 2  signature worker (WOTS, wots.h)
 *
 * A JOB is written by core 0 into the worker's mailbox. The sequence word
 * goes last, so the worker never sees half a job; the worker polls its own
 * mailbox, which is local memory and costs no network traffic.
 * A RESULT is written by the worker into its area of core 0's mailbox, again
 * with the sequence word last. Only the result leaves the worker's tile:
 * round keys, S-boxes, secret chain values and hash state never do. */
#ifndef COOK_CRYPTO_PROTO_H
#define COOK_CRYPTO_PROTO_H
#include "tile.h"

/* job, word offsets in the worker's mailbox */
#define JOB_SEQ    0        /* nonzero, changes with every job; written last */
#define JOB_OP     1
#define JOB_KEY    2        /* AES key (4 words) or signature seed (8 words) */
#define JOB_LEN    10       /* bytes of data */
#define JOB_DATA   12
#define JOB_MAX    256      /* most data bytes in one job */

#define OP_AES_ENC 1
#define OP_AES_DEC 2
#define OP_SIGN    3

/* results, word offsets in core 0's mailbox */
#define RES_AES    0        /* [0] seq  [1] bytes  [2..] data */
#define RES_SIG    80       /* [0] seq  [1] signature blocks  [2..9] public key  [10..] signature */

#define ARBITER    0
#define AES_CORE   1
#define SIGN_CORE  2

/* bytes <-> mailbox words (little endian, like the cores) */
static inline void put_bytes(volatile uint32_t *w, const uint8_t *b, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; i += 4)
        w[i >> 2] = b[i] | ((uint32_t)b[i+1] << 8) | ((uint32_t)b[i+2] << 16) | ((uint32_t)b[i+3] << 24);
}
static inline void get_bytes(uint8_t *b, const volatile uint32_t *w, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; i += 4) {
        uint32_t v = w[i >> 2];
        b[i] = (uint8_t)v; b[i+1] = (uint8_t)(v >> 8); b[i+2] = (uint8_t)(v >> 16); b[i+3] = (uint8_t)(v >> 24);
    }
}
#endif
