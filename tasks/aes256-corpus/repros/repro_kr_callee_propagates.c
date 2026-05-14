/*
 * Minimal reproducer for "K&R callee propagates worse codegen to
 * the caller" — Effect 3 of the int-promotion gap.
 *
 * Same caller body `mc_loop` (extracted from AES inverse mix-columns).
 * Two variants of the callee `f` — K&R vs ANSI declaration — with
 * IDENTICAL function body.
 *
 * Build either variant by defining KR_F or ANSI_F at the command line:
 *
 *   clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
 *         -Wno-deprecated-non-prototype -DKR_F \
 *         -c repro_kr_callee_propagates.c -o kr.o
 *   clang --target=z80 -Oz -nostdlib -ffreestanding -std=c89 \
 *         -Wno-deprecated-non-prototype -DANSI_F \
 *         -c repro_kr_callee_propagates.c -o ansi.o
 *   llvm-nm --print-size --size-sort kr.o ansi.o
 *
 * Hypothesis: `mc_loop` is SOURCE-IDENTICAL across both builds, but
 * its compiled size differs because the K&R declaration of `f`
 * forces int-promoted argument types at the call sites, which
 * cascades into spill decisions in `mc_loop`'s regalloc.
 */

typedef unsigned char uint8_t;

#ifdef KR_F
/* K&R-style definition */
uint8_t f(x)
uint8_t x;
{
    return (x & 0x80) ? ((x << 1) ^ 0x1b) : (x << 1);
}
#else
/* ANSI-style definition (same body) */
uint8_t f(uint8_t x)
{
    return (x & 0x80) ? ((x << 1) ^ 0x1b) : (x << 1);
}
#endif

/* The caller — body is byte-identical regardless of declaration style.
 * 9 byte register-class locals + 1 pointer arg + 7 inlined f calls
 * per loop iteration. */
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
