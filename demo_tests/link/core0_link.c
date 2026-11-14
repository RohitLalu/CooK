/* core0_link.c -- core 0 of the live demo: the laptop link.
 * Replaces core0_arbiter.c on tile 0; cores 1 and 2 run the same workers as
 * the crypto demo (benchmarks/crypto/core1_aes.c, core2_sign.c). Needs the
 * optional serial port (demo_tests/rtl/uart_port.v, UART_EN = 1).
 *
 * Core 0 holds the AES key but has no AES code: every message is sent across
 * the NoC to core 1 as a job, and the answer comes back the same way.
 *
 * FRAMES on the serial line (115200 baud, 8N1)
 *   laptop -> board   0xA5, op, len, len bytes
 *   board  -> laptop  0x5A, status, len, len bytes
 *   op 1  the bytes are ciphertext: core 1 decrypts, the first 8 characters
 *         go to the board's display, the reply carries no data
 *   op 2  the bytes are plaintext: core 1 encrypts, the reply is the ciphertext
 *   len   16, 32, 48 or 64 (whole AES blocks)
 *   status 0 ok, 1 bad frame, 2 job not delivered, 3 no answer from core 1
 * The key is the crypto demo's: SHA-256("CooK AES key" || nonce), first 16
 * bytes. It is compiled in on both sides; this is not a key exchange.
 * Status CSR: 0x600D0000 | messages served. */
#include "proto.h"
#include "sha256.h"

#ifndef NONCE
#define NONCE 0x00C0FFEEu
#endif

#define UART        ((volatile uint32_t *)0xFFFFF000u)
#define UART_DATA   0
#define UART_STATUS 1       /* bit 0 byte waiting, bit 1 sender free */
#define UART_TEXT   2       /* two words: 8 display characters */

static uint8_t rx(void)
{
    while (!(UART[UART_STATUS] & 1)) ;
    return (uint8_t)UART[UART_DATA];
}
static void tx(uint8_t b)
{
    while (!(UART[UART_STATUS] & 2)) ;
    UART[UART_DATA] = b;
}
static void reply(uint8_t status, const uint8_t *data, unsigned len)
{
    unsigned i;
    tx(0x5A); tx(status); tx((uint8_t)len);
    for (i = 0; i < len; i++) tx(data[i]);
}

int main(void)
{
    volatile uint32_t *mine = MBOX(tile_id());
    static const char label[] = "CooK AES key";
    uint8_t key[32], buf[64];
    uint32_t nonce = NONCE, seq = 0, op, len, i;
    sha256_ctx c;

    if (REG32(TILE_ADDR(AES_CORE, CSR_ID)) != AES_CORE) return 8;     /* is core 1 there? */
    sha256_init(&c);
    sha256_update(&c, (const uint8_t *)label, sizeof label - 1);
    sha256_update(&c, (const uint8_t *)&nonce, 4);
    sha256_final(&c, key);
    tile_status(0x52550000);                         /* ready for the laptop */

    for (;;) {
        while (rx() != 0xA5) ;
        op = rx();
        len = rx();
        if ((op != 1 && op != 2) || len == 0 || len > 64 || (len & 15)) { reply(1, 0, 0); continue; }
        for (i = 0; i < len; i++) buf[i] = rx();

        seq++;
        if (!send_job(AES_CORE, seq, op == 1 ? OP_AES_DEC : OP_AES_ENC, key, 16, buf, len)) { reply(2, 0, 0); continue; }
        if (!wait_for(mine + RES_AES, seq)) { reply(3, 0, 0); continue; }
        get_bytes(buf, mine + RES_AES + 2, len);

        if (op == 1) {
            UART[UART_TEXT]     = buf[0] | ((uint32_t)buf[1] << 8) | ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
            UART[UART_TEXT + 1] = buf[4] | ((uint32_t)buf[5] << 8) | ((uint32_t)buf[6] << 16) | ((uint32_t)buf[7] << 24);
            reply(0, 0, 0);
        } else {
            reply(0, buf, len);
        }
        tile_status(0x600D0000 | seq);
    }
}
