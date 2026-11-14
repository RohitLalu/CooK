/* core0_arbiter.c -- key generator and arbiter (core 0).
 *   1. derives an AES-128 key and a signing seed (SHA-256 of a label and a nonce)
 *   2. gives core 1 the plaintext to encrypt and core 2 the message to sign,
 *      at the same time: the two workers run in parallel
 *   3. sends the ciphertext back to core 1 to decrypt: must return the plaintext
 *   4. verifies core 2's signature, and that a changed message is rejected
 * Core 0 has no AES code at all, so the ciphertext can only have come from
 * core 1. Result in the status CSR (and so on the board's display):
 *   pass  0x600D0000 | first two ciphertext bytes
 *   fail  0xFA110000 | step that failed (1 AES timeout, 2 ciphertext equals
 *         plaintext, 3 decrypt timeout, 4 decrypt mismatch, 5 signature
 *         timeout, 6 signature rejected, 7 forged message accepted, 8 a worker
 *         does not answer: checked first, so a broken interconnect is
 *         reported at once instead of after a long wait) */
#include "proto.h"
#include "sha256.h"
#include "wots.h"

#ifndef NONCE
#define NONCE 0x00C0FFEEu
#endif
#define WAIT_POLLS 40000000u        /* local polls before giving up on a worker */

static const uint8_t plain[32] = "CooK: 3 cores, 1 NoC, AES + sig.";
static uint8_t message[] = "signed by core 2";

static void derive(const char *label, uint8_t out[32])
{
    sha256_ctx c;
    uint32_t nonce = NONCE;
    unsigned n = 0;
    while (label[n]) n++;
    sha256_init(&c);
    sha256_update(&c, (const uint8_t *)label, n);
    sha256_update(&c, (const uint8_t *)&nonce, 4);
    sha256_final(&c, out);
}

static void send_job(int worker, uint32_t seq, uint32_t op, const uint8_t *key, unsigned keylen,
                     const uint8_t *data, unsigned len)
{
    volatile uint32_t *job = MBOX(worker);
    put_bytes(job + JOB_KEY, key, keylen);
    put_bytes(job + JOB_DATA, data, (len + 3) & ~3u);
    job[JOB_LEN] = len;
    job[JOB_OP]  = op;
    job[JOB_SEQ] = seq;                              /* last: the job is complete */
}

static int wait_for(const volatile uint32_t *res, uint32_t seq)
{
    uint32_t n;
    for (n = 0; n < WAIT_POLLS; n++)
        if (res[0] == seq) return 1;
    return 0;
}

int main(void)
{
    volatile uint32_t *mine = MBOX(tile_id());
    static uint8_t sig[32 * WOTS_MAX_LEN];
    uint8_t aes_key[32], seed[32], ct[32], back[32], pk[32];

    tile_status(0x52550000);
    /* are the workers there? A remote read that fails returns POISON. */
    if (REG32(TILE_ADDR(AES_CORE, CSR_ID)) != AES_CORE || REG32(TILE_ADDR(SIGN_CORE, CSR_ID)) != SIGN_CORE)
        return 8;
    derive("CooK AES key", aes_key);                 /* first 16 bytes are the key */
    derive("CooK signing seed", seed);

    send_job(AES_CORE, 1, OP_AES_ENC, aes_key, 16, plain, 32);
    send_job(SIGN_CORE, 1, OP_SIGN, seed, 32, message, sizeof message);

    if (!wait_for(mine + RES_AES, 1)) return 1;
    get_bytes(ct, mine + RES_AES + 2, 32);
    if (memcmp(ct, plain, 32) == 0) return 2;
    send_job(AES_CORE, 2, OP_AES_DEC, aes_key, 16, ct, 32);
    if (!wait_for(mine + RES_AES, 2)) return 3;
    get_bytes(back, mine + RES_AES + 2, 32);
    if (memcmp(back, plain, 32) != 0) return 4;

    if (!wait_for(mine + RES_SIG, 1)) return 5;
    get_bytes(pk, mine + RES_SIG + 2, 32);
    get_bytes(sig, mine + RES_SIG + 10, 32 * (unsigned)wots_len());
    if (!wots_verify(pk, message, sizeof message, sig)) return 6;
    message[0] ^= 1;
    if (wots_verify(pk, message, sizeof message, sig)) return 7;

    tile_report(1, ((uint32_t)ct[0] << 8) | ct[1]);
    return 0;
}
