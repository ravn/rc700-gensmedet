/*
 * test_main.c — compiler-comparison-corpus harness.
 *
 * Each benchmark exposes:
 *   unsigned int bench_run(void);       -- compute + return result
 *   unsigned int bench_expected(void);  -- known-good result
 *
 * This harness invokes both, writes a 7-byte result vector at 0xC000:
 *   [0..1] : actual result (little-endian uint16_t)
 *   [2..3] : expected result (little-endian uint16_t)
 *   [4]    : 0x01 if equal else 0x00
 *   [5]    : 0x00 (reserved / future tstate marker)
 *   [6]    : 0xA5 (end-of-test sentinel)
 *
 * Mirrors aes256-corpus's sentinel convention so the same flag_sweep.sh
 * skeleton applies.  Verifier in flag_sweep.sh checks v[4]==1 and
 * v[6]==0xA5.
 *
 * No stdio / freestanding -- reset_clang.s halts after main returns.
 */

extern unsigned int bench_run(void);
extern unsigned int bench_expected(void);

int main(void)
{
    unsigned char *out = (unsigned char *)0xC000;
    unsigned int r = bench_run();
    unsigned int e = bench_expected();

    out[0] = (unsigned char)(r & 0xff);
    out[1] = (unsigned char)((r >> 8) & 0xff);
    out[2] = (unsigned char)(e & 0xff);
    out[3] = (unsigned char)((e >> 8) & 0xff);
    out[4] = (r == e) ? 1 : 0;
    out[5] = 0;
    out[6] = 0xA5;
    return 0;
}
