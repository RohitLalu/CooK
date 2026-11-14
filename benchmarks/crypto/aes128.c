/* aes128.c -- AES-128 (FIPS 197). State is column-major, as in the standard:
 * s[4*c + r]. The S-boxes are computed once from the field arithmetic, so no
 * table is typed in by hand. */
#include "aes128.h"

static uint8_t sbox[256], inv_sbox[256];
static int tables_ready;

static uint8_t xtime(uint8_t x) { return (uint8_t)((x << 1) ^ ((x & 0x80) ? 0x1b : 0)); }

static uint8_t gmul(uint8_t a, uint8_t b)
{
    uint8_t p = 0;
    while (b) {
        if (b & 1) p ^= a;
        a = xtime(a);
        b >>= 1;
    }
    return p;
}

/* S-box: multiplicative inverse in GF(2^8), then the affine map. 3 generates
 * the field, so walking p = 3^i and q = 3^-i visits every inverse pair. */
static void make_tables(void)
{
    uint8_t p = 1, q = 1, x;
    do {
        p = (uint8_t)(p ^ xtime(p));                 /* p *= 3 */
        q ^= (uint8_t)(q << 1); q ^= (uint8_t)(q << 2); q ^= (uint8_t)(q << 4);
        if (q & 0x80) q ^= 0x09;                     /* q /= 3 */
        x = (uint8_t)(q ^ (q << 1 | q >> 7) ^ (q << 2 | q >> 6) ^ (q << 3 | q >> 5) ^ (q << 4 | q >> 4) ^ 0x63);
        sbox[p] = x;
        inv_sbox[x] = p;
    } while (p != 1);
    sbox[0] = 0x63;
    inv_sbox[0x63] = 0;
    tables_ready = 1;
}

void aes128_init(aes128_ctx *c, const uint8_t key[16])
{
    uint8_t rcon = 1, t[4], k;
    int i;
    if (!tables_ready) make_tables();
    for (i = 0; i < 16; i++) c->rk[i] = key[i];
    for (i = 16; i < 176; i += 4) {
        t[0] = c->rk[i-4]; t[1] = c->rk[i-3]; t[2] = c->rk[i-2]; t[3] = c->rk[i-1];
        if ((i & 15) == 0) {
            k = t[0];
            t[0] = (uint8_t)(sbox[t[1]] ^ rcon); t[1] = sbox[t[2]]; t[2] = sbox[t[3]]; t[3] = sbox[k];
            rcon = xtime(rcon);
        }
        c->rk[i] = c->rk[i-16] ^ t[0];  c->rk[i+1] = c->rk[i-15] ^ t[1];
        c->rk[i+2] = c->rk[i-14] ^ t[2]; c->rk[i+3] = c->rk[i-13] ^ t[3];
    }
}

static void add_round_key(uint8_t *s, const uint8_t *k)
{
    int i;
    for (i = 0; i < 16; i++) s[i] ^= k[i];
}

void aes128_encrypt(const aes128_ctx *c, const uint8_t in[16], uint8_t out[16])
{
    uint8_t s[16], t[16], a0, a1, a2, a3;
    int r, i, col;
    for (i = 0; i < 16; i++) s[i] = in[i];
    add_round_key(s, c->rk);
    for (r = 1; r <= 10; r++) {
        /* SubBytes + ShiftRows: row r of column c comes from column c + r */
        for (i = 0; i < 16; i++) t[i] = sbox[s[(i + 4 * (i & 3)) & 15]];
        if (r < 10) {
            for (col = 0; col < 16; col += 4) {      /* MixColumns */
                a0 = t[col]; a1 = t[col+1]; a2 = t[col+2]; a3 = t[col+3];
                s[col]   = (uint8_t)(xtime(a0) ^ xtime(a1) ^ a1 ^ a2 ^ a3);
                s[col+1] = (uint8_t)(a0 ^ xtime(a1) ^ xtime(a2) ^ a2 ^ a3);
                s[col+2] = (uint8_t)(a0 ^ a1 ^ xtime(a2) ^ xtime(a3) ^ a3);
                s[col+3] = (uint8_t)(xtime(a0) ^ a0 ^ a1 ^ a2 ^ xtime(a3));
            }
        } else {
            for (i = 0; i < 16; i++) s[i] = t[i];
        }
        add_round_key(s, c->rk + 16 * r);
    }
    for (i = 0; i < 16; i++) out[i] = s[i];
}

void aes128_decrypt(const aes128_ctx *c, const uint8_t in[16], uint8_t out[16])
{
    uint8_t s[16], t[16], a0, a1, a2, a3;
    int r, i, col;
    for (i = 0; i < 16; i++) s[i] = in[i];
    add_round_key(s, c->rk + 160);
    for (r = 9; r >= 0; r--) {
        /* InvShiftRows + InvSubBytes: row r of column c comes from column c - r */
        for (i = 0; i < 16; i++) t[i] = inv_sbox[s[(i - 4 * (i & 3)) & 15]];
        add_round_key(t, c->rk + 16 * r);
        if (r > 0) {
            for (col = 0; col < 16; col += 4) {      /* InvMixColumns */
                a0 = t[col]; a1 = t[col+1]; a2 = t[col+2]; a3 = t[col+3];
                s[col]   = (uint8_t)(gmul(a0, 14) ^ gmul(a1, 11) ^ gmul(a2, 13) ^ gmul(a3, 9));
                s[col+1] = (uint8_t)(gmul(a0, 9) ^ gmul(a1, 14) ^ gmul(a2, 11) ^ gmul(a3, 13));
                s[col+2] = (uint8_t)(gmul(a0, 13) ^ gmul(a1, 9) ^ gmul(a2, 14) ^ gmul(a3, 11));
                s[col+3] = (uint8_t)(gmul(a0, 11) ^ gmul(a1, 13) ^ gmul(a2, 9) ^ gmul(a3, 14));
            }
        } else {
            for (i = 0; i < 16; i++) s[i] = t[i];
        }
    }
    for (i = 0; i < 16; i++) out[i] = s[i];
}
