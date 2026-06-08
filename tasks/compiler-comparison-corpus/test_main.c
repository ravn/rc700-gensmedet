/*
 * test_main.c -- compiler-comparison-corpus harness.
 *
 * Each benchmark exposes:
 *   unsigned int bench_run(void);       -- compute + return result
 *   unsigned int bench_expected(void);  -- known-good result
 *
 * Termination + verification protocol (2026-06-08):
 *
 *   We exit via z88dk-ticks's canonical syscall trap (ED FE with
 *   A = CMD_EXIT = 0).  See z88dk/src/ticks/hook.c:39 and
 *   z88dk/lib/target/test/classic/test_crt0.asm:100 -- this is the
 *   same mechanism z88dk's own testsuite uses.  cmd_exit() prints
 *   "Ticks: <N>" to stdout and calls exit(L), so:
 *
 *     - stdout's "Ticks:" line -> measured cycles (one parse, both
 *       compilers, no CRT-exit-handler dependency).
 *     - ticks process exit code = register L = our verify status,
 *       Unix-style: exit=0 PASS, exit=1 FAIL.
 *
 *   Note that cmd_exit() bypasses ticks's `-output` flag, so the
 *   harness can NOT rely on the 0xC000 sentinel RAM dump for PASS/FAIL
 *   verification after the trap fires.  The sentinel writes below are
 *   retained for post-mortem debugging (RAM dump from -output BEFORE
 *   the trap, or via -trace), not for the primary verify path.
 *
 * Sentinel layout at 0xC000 (unchanged, debugging only):
 *   [0..1] : actual result (little-endian uint16_t)
 *   [2..3] : expected result (little-endian uint16_t)
 *   [4]    : 0x01 if equal else 0x00
 *   [5]    : 0x00 (reserved)
 *   [6]    : 0xA5 (end-of-test sentinel)
 */

extern unsigned int bench_run(void);
extern unsigned int bench_expected(void);

/* Verify status loaded into L before the trap.  Unix convention:
 * 0 = PASS (results match), 1 = FAIL.  Read by inline asm below;
 * volatile prevents the optimizer from removing the store across the
 * asm block that doesn't list it as a C-visible input. */
static volatile unsigned char ticks_exit_code;

int main(void)
{
    unsigned char *out = (unsigned char *)0xC000;
    unsigned int r = bench_run();
    unsigned int e = bench_expected();
    unsigned char match = (r == e) ? 1 : 0;

    out[0] = (unsigned char)(r & 0xff);
    out[1] = (unsigned char)((r >> 8) & 0xff);
    out[2] = (unsigned char)(e & 0xff);
    out[3] = (unsigned char)((e >> 8) & 0xff);
    out[4] = match;
    out[5] = 0;
    out[6] = 0xA5;

    ticks_exit_code = match ? 0 : 1;  /* Unix: 0 = PASS */

    /* ED FE trap: A=CMD_EXIT(0), L=ticks_exit_code.
     * Inline-asm content differs (GAS .byte vs SDCC defb / hex prefix);
     * trap semantics identical. */
#if defined(__clang__) && defined(__z80__)
    __asm__ volatile (
        "ld a, (_ticks_exit_code)\n\t"
        "ld l, a\n\t"
        "xor a\n\t"                  /* A = CMD_EXIT = 0 */
        ".byte 0xED, 0xFE\n\t"       /* ticks syscall trap */
        ::: "memory"
    );
#elif defined(__SDCC)
    __asm
        ld a, (_ticks_exit_code)
        ld l, a
        xor a, a
        .db #0xED, #0xFE
    __endasm;
#endif

    return 0;  /* unreached -- trap takes us straight to exit(L) */
}
