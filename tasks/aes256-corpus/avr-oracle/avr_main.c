/*
 * AVR port of AES corpus test_main.c — verdict via simavr console (.mmcu).
 * Uses our llvm-z80 clang (with --target=avr); links via avr-gcc.
 */
#include <stdint.h>
#include "/Users/ravn/z80/simavr/simavr/sim/avr/avr_mcu_section.h"

#define F_CPU 16000000UL
AVR_MCU_SIMAVR_CONSOLE(0x3E);   /* GPIOR0 — write-only console hook */
AVR_MCU(F_CPU, "atmega328p");

static volatile uint8_t *console = (volatile uint8_t *)0x3E;
static void putch(char c) { *console = c; }
static void putstr(const char *s) { while (*s) putch(*s++); }
static void puthex(uint8_t v) {
  const char hex[] = "0123456789abcdef";
  putch(hex[(v >> 4) & 0xF]);
  putch(hex[v & 0xF]);
}

typedef struct {
    uint8_t key[32];
    uint8_t enckey[32];
    uint8_t deckey[32];
} aes256_context;
void aes256_init(aes256_context *ctx, uint8_t *k);
void aes256_encrypt_ecb(aes256_context *ctx, uint8_t *buf);
void aes256_decrypt_ecb(aes256_context *ctx, uint8_t *buf);
void aes_done(aes256_context *ctx);

static const uint8_t expected_ct[16] = {
    0x8e, 0xa2, 0xb7, 0xca, 0x51, 0x67, 0x45, 0xbf,
    0xea, 0xfc, 0x49, 0x90, 0x4b, 0x49, 0x60, 0x89
};

int main(void) {
    aes256_context ctx;
    uint8_t key[32];
    uint8_t buf[16];
    uint8_t i, enc_ok, dec_ok;

    for (i = 0; i < 16; i++) buf[i] = (uint8_t)(i * 16 + i);
    for (i = 0; i < 32; i++) key[i] = i;

    putstr("AES-256: ENCRYPT ");
    aes256_init(&ctx, key);
    aes256_encrypt_ecb(&ctx, buf);

    enc_ok = 1;
    for (i = 0; i < 16; i++) {
        if (buf[i] != expected_ct[i]) { enc_ok = 0; break; }
    }
    putstr(enc_ok ? "PASS  CT=" : "FAIL  CT=");
    for (i = 0; i < 16; i++) puthex(buf[i]);
    putch('\n');

    putstr("AES-256: DECRYPT ");
    aes256_init(&ctx, key);
    aes256_decrypt_ecb(&ctx, buf);

    dec_ok = 1;
    for (i = 0; i < 16; i++) {
        if (buf[i] != (uint8_t)(i * 16 + i)) { dec_ok = 0; break; }
    }
    putstr(dec_ok ? "PASS" : "FAIL");
    putch('\n');

    aes_done(&ctx);

    putstr("VERDICT: ");
    putstr((enc_ok && dec_ok) ? "PASS\n" : "FAIL\n");

    /* CLI + sleep -> simavr detects stuck CPU and exits cleanly */
    __asm__ volatile("cli\n\tsleep" : : : "memory");
    for(;;) {}
    return 0;
}
