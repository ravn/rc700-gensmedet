/*
 * Minimal reproducer for the clang spill-storm pattern on functions
 * with 9+ byte register-class locals.  Extracted from aes_mc_inv in
 * aes256.c (z80.eu / Ilya O. Levin AES-256).
 *
 * Compile with:
 *   clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
 *         -Wno-deprecated-non-prototype \
 *         -c repro_aes_mc_inv_spill_storm.c
 *
 * The generated `_mc_loop` function spills to SP-relative slots and
 * recomputes the slot address (`ld hl, N; add hl, sp; ld (hl), X`)
 * for every spill access.  IX-relative addressing would save ~2 B
 * per access; we measured ~150 B savings on the full aes_mc_inv.
 *
 * See ANALYSIS.md in the parent directory.
 */

typedef unsigned char uint8_t;

/* Same as aes256.c's rj_xtime — extern so clang can't inline. */
extern uint8_t f(uint8_t x);

void mc_loop(uint8_t *buf)
{
    uint8_t i, a, b, c, d, e, x, y, z;

    for (i = 0; i < 16; i += 4) {
        a = buf[i];
        b = buf[i + 1];
        c = buf[i + 2];
        d = buf[i + 3];
        e = a ^ b ^ c ^ d;
        z = f(e);
        x = e ^ f(f(z ^ a ^ c));
        y = e ^ f(f(z ^ b ^ d));
        buf[i]     ^= x ^ f(a ^ b);
        buf[i + 1] ^= y ^ f(b ^ c);
        buf[i + 2] ^= x ^ f(c ^ d);
        buf[i + 3] ^= y ^ f(d ^ a);
    }
}
