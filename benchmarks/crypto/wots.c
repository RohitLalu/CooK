/* wots.c -- Winternitz one-time signature (see wots.h).
 *   secret  sk_i   = H(seed || i || 0xFF)
 *   chain   step j of chain i:  x <- H(x || i || j)
 *   public  pk     = H(end of chain 0 || end of chain 1 || ...)
 *   sign    d = first WOTS_N bytes of H(msg), cut into digits, plus the digits
 *           of the checksum sum(W-1 - digit); sig_i = chain i advanced digit_i steps
 *   verify  advance each sig_i the remaining W-1 - digit_i steps, hash, compare */
#include "wots.h"
#include "sha256.h"

int wots_len(void)
{
    int len2 = 0, max = WOTS_LEN1 * (WOTS_W - 1);
    while (max) { len2++; max >>= WOTS_LOGW; }
    return WOTS_LEN1 + len2;
}

/* message digest -> digits, checksum digits appended */
static void digits(const uint8_t *msg, unsigned len, uint8_t *d)
{
    uint8_t h[32];
    int i, n = wots_len();
    unsigned sum = 0;
    sha256(msg, len, h);
    for (i = 0; i < WOTS_LEN1; i++) {
        unsigned bit = (unsigned)i * WOTS_LOGW;
        unsigned v = h[bit >> 3] | ((bit >> 3) + 1 < WOTS_N ? (unsigned)h[(bit >> 3) + 1] << 8 : 0);
        d[i] = (uint8_t)((v >> (bit & 7)) & (WOTS_W - 1));
        sum += (WOTS_W - 1) - d[i];
    }
    for (; i < n; i++, sum >>= WOTS_LOGW) d[i] = (uint8_t)(sum & (WOTS_W - 1));
}

static void chain(uint8_t x[32], int i, int from, int steps)
{
    uint8_t buf[34];
    int j, k;
    for (j = from; j < from + steps; j++) {
        for (k = 0; k < 32; k++) buf[k] = x[k];
        buf[32] = (uint8_t)i; buf[33] = (uint8_t)j;
        sha256(buf, 34, x);
    }
}

static void secret(const uint8_t seed[32], int i, uint8_t out[32])
{
    uint8_t buf[34];
    int k;
    for (k = 0; k < 32; k++) buf[k] = seed[k];
    buf[32] = (uint8_t)i; buf[33] = 0xFF;
    sha256(buf, 34, out);
}

void wots_keygen(const uint8_t seed[32], uint8_t pk[32])
{
    sha256_ctx c;
    uint8_t x[32];
    int i, n = wots_len();
    sha256_init(&c);
    for (i = 0; i < n; i++) {
        secret(seed, i, x);
        chain(x, i, 0, WOTS_W - 1);
        sha256_update(&c, x, 32);
    }
    sha256_final(&c, pk);
}

void wots_sign(const uint8_t seed[32], const uint8_t *msg, unsigned len, uint8_t *sig)
{
    uint8_t d[WOTS_MAX_LEN];
    int i, n = wots_len();
    digits(msg, len, d);
    for (i = 0; i < n; i++) {
        secret(seed, i, sig + 32 * i);
        chain(sig + 32 * i, i, 0, d[i]);
    }
}

int wots_verify(const uint8_t pk[32], const uint8_t *msg, unsigned len, const uint8_t *sig)
{
    sha256_ctx c;
    uint8_t d[WOTS_MAX_LEN], x[32], got[32], diff = 0;
    int i, k, n = wots_len();
    digits(msg, len, d);
    sha256_init(&c);
    for (i = 0; i < n; i++) {
        for (k = 0; k < 32; k++) x[k] = sig[32 * i + k];
        chain(x, i, d[i], WOTS_W - 1 - d[i]);
        sha256_update(&c, x, 32);
    }
    sha256_final(&c, got);
    for (k = 0; k < 32; k++) diff |= (uint8_t)(got[k] ^ pk[k]);
    return diff == 0;
}
