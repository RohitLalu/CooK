/* host_test.c -- known-answer tests for the crypto code, run on the
 * development machine before any of it goes onto a tile:
 *     cc -o /tmp/crypto_host host_test.c sha256.c aes128.c wots.c && /tmp/crypto_host
 * (add -DWOTS_LOGW=2 -DWOTS_N=1 for the simulation size). */
#include <stdio.h>
#include <string.h>
#include "sha256.h"
#include "aes128.h"
#include "wots.h"

static int fails;
static void check(int ok, const char *what) { printf("%s: %s\n", ok ? "PASS" : "FAIL", what); fails += !ok; }

int main(void)
{
    /* SHA-256("abc"), FIPS 180-4 */
    static const uint8_t abc[32] = {
        0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
        0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad };
    /* SHA-256 of the 56-byte message from FIPS 180-4 (two blocks) */
    static const uint8_t two[32] = {
        0x24,0x8d,0x6a,0x61,0xd2,0x06,0x38,0xb8,0xe5,0xc0,0x26,0x93,0x0c,0x3e,0x60,0x39,
        0xa3,0x3c,0xe4,0x59,0x64,0xff,0x21,0x67,0xf6,0xec,0xed,0xd4,0x19,0xdb,0x06,0xc1 };
    /* AES-128, FIPS 197 appendix C.1 */
    static const uint8_t ct[16] = { 0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a };
    uint8_t h[32], key[16], pt[16], out[16], back[16], seed[32], pk[32], sig[32 * WOTS_MAX_LEN];
    uint8_t msg[] = "CooK signs this";
    aes128_ctx a;
    int i;

    sha256((const uint8_t *)"abc", 3, h);
    check(!memcmp(h, abc, 32), "SHA-256(\"abc\")");
    sha256((const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56, h);
    check(!memcmp(h, two, 32), "SHA-256, two-block message");

    for (i = 0; i < 16; i++) { key[i] = (uint8_t)i; pt[i] = (uint8_t)(i * 0x11); }
    aes128_init(&a, key);
    aes128_encrypt(&a, pt, out);
    check(!memcmp(out, ct, 16), "AES-128 encrypt, FIPS 197 C.1");
    aes128_decrypt(&a, out, back);
    check(!memcmp(back, pt, 16), "AES-128 decrypt returns the plaintext");

    for (i = 0; i < 32; i++) seed[i] = (uint8_t)(0xA0 + i);
    wots_keygen(seed, pk);
    wots_sign(seed, msg, sizeof msg, sig);
    check(wots_verify(pk, msg, sizeof msg, sig), "WOTS signature verifies");
    msg[0] ^= 1;
    check(!wots_verify(pk, msg, sizeof msg, sig), "WOTS rejects a changed message");
    msg[0] ^= 1; sig[5] ^= 1;
    check(!wots_verify(pk, msg, sizeof msg, sig), "WOTS rejects a changed signature");
    printf("LOGW %d, N %d: %d chains, %d-byte signature\n", WOTS_LOGW, WOTS_N, wots_len(), 32 * wots_len());
    return fails != 0;
}
