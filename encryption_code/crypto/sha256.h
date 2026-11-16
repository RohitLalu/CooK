/* sha256.h -- SHA-256 (FIPS 180-4), plain C, no multiply. */
#ifndef COOK_SHA256_H
#define COOK_SHA256_H
#include <stdint.h>

typedef struct {
    uint32_t h[8];
    uint32_t nbytes;        /* message length so far (messages here are far below 512 MB) */
    uint8_t  buf[64];
} sha256_ctx;

void sha256_init(sha256_ctx *c);
void sha256_update(sha256_ctx *c, const uint8_t *data, unsigned len);
void sha256_final(sha256_ctx *c, uint8_t out[32]);
void sha256(const uint8_t *data, unsigned len, uint8_t out[32]);
#endif
