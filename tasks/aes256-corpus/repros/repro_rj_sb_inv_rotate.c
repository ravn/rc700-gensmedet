/*
 * Minimal reproducer for the clang missing uint8_t rotate-left
 * recognition pattern.
 *
 * The C idiom `(x << N) | (x >> (8-N))` on a uint8_t IS rotate-
 * left by N.  zsdcc recognises this and emits `rlca` × N (1 byte
 * each).  Clang lowers to literal 16-bit shift via `add hl,hl`
 * sequences + masks + OR, producing ~10× the bytes.
 *
 * Extracted from aes256.c's rj_sb_inv (z80.eu / Ilya O. Levin
 * AES-256), which chains three such rotates by 1, 2, 3.
 *
 * Build:
 *   clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
 *         -Wno-deprecated-non-prototype \
 *         -c repro_rj_sb_inv_rotate.c
 */

typedef unsigned char uint8_t;

/* Single-rotate function — simplest case. */
uint8_t rotl1(uint8_t x) {
    return (x << 1) | (x >> 7);
}

/* Multi-rotate chain — the rj_sb_inv shape. */
uint8_t rj_sb_inv_like(uint8_t x) {
    uint8_t y, sb;

    y = x ^ 0x63;
    sb = y = (y << 1) | (y >> 7);   /* ROTL 1 */
    y = (y << 2) | (y >> 6); sb ^= y;   /* ROTL 2 */
    y = (y << 3) | (y >> 5); sb ^= y;   /* ROTL 3 */

    return sb;
}
