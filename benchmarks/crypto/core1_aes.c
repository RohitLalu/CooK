/* core1_aes.c -- the AES-128 worker (core 1). Waits for a job in its own
 * mailbox, encrypts or decrypts the blocks with the key in the job, and
 * writes only the result into core 0's mailbox. Before serving it checks
 * itself against the FIPS 197 vector; a core that fails that reports failure
 * and serves nothing. Status: 0x600D0000 | jobs done. */
#include "proto.h"
#include "aes128.h"

static int self_test(void)
{
    static const uint8_t ct[16] = { 0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a };
    uint8_t key[16], pt[16], out[16];
    aes128_ctx a;
    int i;
    for (i = 0; i < 16; i++) { key[i] = (uint8_t)i; pt[i] = (uint8_t)(i * 0x11); }
    aes128_init(&a, key);
    aes128_encrypt(&a, pt, out);
    return memcmp(out, ct, 16) == 0;
}

int main(void)
{
    volatile uint32_t *job = MBOX(tile_id());
    volatile uint32_t *res = MBOX(ARBITER) + RES_AES;
    uint8_t key[16], buf[JOB_MAX];
    aes128_ctx a;
    uint32_t seq, last = 0, jobs = 0, len, i;

    if (!self_test()) return 1;
    tile_status(0x52550000);                         /* running, waiting for work */
    for (;;) {
        seq = job[JOB_SEQ];
        if (seq == last) continue;
        last = seq;
        len = job[JOB_LEN];
        if (len > JOB_MAX || (len & 15) || (job[JOB_OP] != OP_AES_ENC && job[JOB_OP] != OP_AES_DEC))
            tile_report(0, 2);
        get_bytes(key, job + JOB_KEY, 16);
        get_bytes(buf, job + JOB_DATA, len);
        aes128_init(&a, key);
        for (i = 0; i < len; i += 16) {
            if (job[JOB_OP] == OP_AES_ENC) aes128_encrypt(&a, buf + i, buf + i);
            else                           aes128_decrypt(&a, buf + i, buf + i);
        }
        put_bytes(res + 2, buf, len);
        res[1] = len;
        res[0] = seq;                                /* last: the result is complete */
        tile_status(0x600D0000 | ++jobs);
    }
}
