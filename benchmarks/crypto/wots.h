/* wots.h -- Winternitz one-time signature over SHA-256. Hash-based: the only
 * arithmetic is the hash, so it suits an RV32I core with no multiplier.
 * ONE-TIME: a key pair must sign one message only.
 *
 * Two knobs, set at compile time:
 *   WOTS_LOGW  bits per digit (2, 4 or 8); chains are 2^LOGW - 1 hashes long
 *   WOTS_N     bytes of the message digest that are signed (1..32)
 * Board default: LOGW 8, N 32 -- the whole 256-bit digest, 34 chains, a
 * 1088-byte signature. Simulation uses LOGW 2, N 1 (6 chains): the same code
 * path at a size Icarus can run, and no security at all. */
#ifndef COOK_WOTS_H
#define COOK_WOTS_H
#include <stdint.h>

#ifndef WOTS_LOGW
#define WOTS_LOGW 8
#endif
#ifndef WOTS_N
#define WOTS_N 32
#endif
#define WOTS_W        (1 << WOTS_LOGW)
#define WOTS_LEN1     ((8 * WOTS_N + WOTS_LOGW - 1) / WOTS_LOGW)
#define WOTS_MAX_LEN  (WOTS_LEN1 + 4)                 /* room for the checksum digits */
#define WOTS_HASH     32

int  wots_len(void);                                  /* chains = 32-byte blocks in a signature */
void wots_keygen(const uint8_t seed[32], uint8_t pk[32]);
void wots_sign(const uint8_t seed[32], const uint8_t *msg, unsigned len, uint8_t *sig);
int  wots_verify(const uint8_t pk[32], const uint8_t *msg, unsigned len, const uint8_t *sig);
#endif
