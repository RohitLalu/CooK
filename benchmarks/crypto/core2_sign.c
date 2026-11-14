/* core2_sign.c -- the signature worker (core 2). Waits for a job in its own
 * mailbox: a seed and a message. Derives the one-time key pair from the seed,
 * signs the message, and writes the public key and the signature into core
 * 0's mailbox. The secret chain values never leave this tile.
 * Status: 0x600D0000 | jobs done. */
#include "proto.h"
#include "wots.h"

int main(void)
{
    volatile uint32_t *job = MBOX(tile_id());
    volatile uint32_t *res = MBOX(ARBITER) + RES_SIG;
    static uint8_t sig[32 * WOTS_MAX_LEN];
    uint8_t seed[32], pk[32], msg[JOB_MAX];
    uint32_t seq, last = 0, jobs = 0, len;

    tile_status(0x52550000);
    for (;;) {
        seq = job[JOB_SEQ];
        if (seq == last) continue;
        last = seq;
        len = job[JOB_LEN];
        if (len > JOB_MAX || job[JOB_OP] != OP_SIGN) tile_report(0, 2);
        get_bytes(seed, job + JOB_KEY, 32);
        get_bytes(msg, job + JOB_DATA, (len + 3) & ~3u);
        wots_keygen(seed, pk);
        wots_sign(seed, msg, len, sig);
        put_bytes(res + 2, pk, 32);
        put_bytes(res + 10, sig, 32 * (unsigned)wots_len());
        res[1] = (uint32_t)wots_len();
        if (!post_seq(res, seq)) tile_report(0, 3);  /* last, and confirmed */
        tile_status(0x600D0000 | ++jobs);
    }
}
