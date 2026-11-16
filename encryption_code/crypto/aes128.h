/* aes128.h -- AES-128 (FIPS 197), single blocks, plain C: byte operations
 * and one 256-byte table per direction, no multiply. */
#ifndef COOK_AES128_H
#define COOK_AES128_H
#include <stdint.h>

typedef struct { uint8_t rk[176]; } aes128_ctx;      /* 11 round keys */

void aes128_init(aes128_ctx *c, const uint8_t key[16]);
void aes128_encrypt(const aes128_ctx *c, const uint8_t in[16], uint8_t out[16]);
void aes128_decrypt(const aes128_ctx *c, const uint8_t in[16], uint8_t out[16]);
#endif
