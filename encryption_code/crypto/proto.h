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
 * round keys, S-boxes, secret chain values and hash state never do.
 *
 * WHO SENT IT. Any tile can write any mailbox (the hardware checks where a
 * write lands, not who sent it), so every job and every result carries a
 * keyed checksum: 32 bits of SHA-256 over a key the three programs share
 * (LINK_KEY, compiled in) and the whole message. A receiver ignores a message
 * whose checksum is wrong. That stops a core without the key from forging a
 * job or a result, and it also catches a message damaged or cut short on the
 * way. It is firmware, not hardware: a program that has the key can still
 * forge, and 32 bits is a demonstration strength, not a real one. */
#ifndef COOK_CRYPTO_PROTO_H
#define COOK_CRYPTO_PROTO_H
#include "tile.h"
#include "sha256.h"

/* job, word offsets in the worker's mailbox */
#define JOB_SEQ    0        /* nonzero, changes with every job; written last */
#define JOB_OP     1
#define JOB_KEY    2        /* AES key (4 words) or signature seed (8 words) */
#define JOB_LEN    10       /* bytes of data */
#define JOB_TAG    11       /* keyed checksum of the job */
#define JOB_DATA   12
#define JOB_MAX    256      /* most data bytes in one job */

#define OP_AES_ENC 1
#define OP_AES_DEC 2
#define OP_SIGN    3

/* results, word offsets in core 0's mailbox */
#define RES_AES    0        /* [0] seq  [1] bytes  [2..] data  [RES_AES_TAG] checksum */
#define RES_SIG    80       /* [0] seq  [1] signature blocks  [2..9] public key  [10..] signature */
#define RES_AES_TAG 20
#define RES_SIG_TAG 300     /* word offsets from RES_AES / RES_SIG */

#ifndef LINK_KEY
#define LINK_KEY "CooK mailbox key"         /* 16 bytes, the same in all three programs */
#endif

/* keyed checksum of a message: header words a, b, c and two byte strings */
static inline uint32_t proto_tag(uint32_t a, uint32_t b, uint32_t c,
                                 const uint8_t *x, unsigned nx, const uint8_t *y, unsigned ny)
{
    sha256_ctx s;
    uint8_t h[32];
    uint32_t hdr[3];
    hdr[0] = a; hdr[1] = b; hdr[2] = c;
    sha256_init(&s);
    sha256_update(&s, (const uint8_t *)LINK_KEY, 16);
    sha256_update(&s, (const uint8_t *)hdr, 12);
    sha256_update(&s, x, nx);
    if (ny) sha256_update(&s, y, ny);
    sha256_final(&s, h);
    return h[0] | ((uint32_t)h[1] << 8) | ((uint32_t)h[2] << 16) | ((uint32_t)h[3] << 24);
}

#define ARBITER    0
#define AES_CORE   1
#define SIGN_CORE  2

/* Remote writes are posted: the sender gets no acknowledge. So the sequence
 * word, which is written last and makes a job or result visible, is read back
 * (a remote read does get an answer) and rewritten if it is not there.
 * Returns 0 when it still is not after three tries: the path is broken.
 * This confirms the last word; the words before it took the same path in
 * order, so a single lost packet in the middle would still go unnoticed. */
static inline int post_seq(volatile uint32_t *seq_word, uint32_t seq)
{
    int tries;
    for (tries = 0; tries < 3; tries++) {
        *seq_word = seq;
        if (*seq_word == seq) return 1;
    }
    return 0;
}

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

/* ---- the arbiter's side: hand a job to a worker, wait for its result ---- */
#ifndef WAIT_POLLS
#define WAIT_POLLS 40000000u        /* local polls before giving up on a worker */
#endif

static inline int send_job(int worker, uint32_t seq, uint32_t op, const uint8_t *key, unsigned keylen,
                           const uint8_t *data, unsigned len)
{
    volatile uint32_t *job = MBOX(worker);
    put_bytes(job + JOB_KEY, key, keylen);
    put_bytes(job + JOB_DATA, data, (len + 3) & ~3u);
    job[JOB_LEN] = len;
    job[JOB_OP]  = op;
    job[JOB_TAG] = proto_tag(seq, op, len, key, keylen, data, len);
    return post_seq(job + JOB_SEQ, seq);             /* last, and confirmed: the job is complete */
}

static inline int wait_for(const volatile uint32_t *res, uint32_t seq)
{
    uint32_t n;
    for (n = 0; n < WAIT_POLLS; n++)
        if (res[0] == seq) return 1;
    return 0;
}
#endif
