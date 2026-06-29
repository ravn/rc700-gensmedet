/*
 * dcc_test_main.c -- dcc-specific harness for compiler-comparison-corpus.
 *
 * Why a separate harness from test_main.c (clang/SDCC):
 *
 *   dcc emits a CP/M .COM (loads at 0x0100).  Unlike the freestanding
 *   clang/SDCC corpus binaries -- which have no CCP and nowhere to return
 *   to, hence the ED-FE syscall trap to stop ticks -- a dcc program that
 *   returns from main falls back through dcc's CRT to the CCP, i.e. a warm
 *   boot: JP 0x0000.  z88dk-ticks run with `-pc 100 -end 0` therefore stops
 *   the moment PC reaches 0x0000 and still reports the cycle count.  So dcc
 *   needs no trap: it just writes the sentinel and returns.
 *
 *   Verification is read from the ticks RAM dump (`-output`) at 0xC000, the
 *   same 7-byte sentinel layout test_main.c documents:
 *     [0..1] result LE, [2..3] expected LE, [4] match(1/0), [5] 0, [6] 0xA5.
 *
 * Build contract:
 *   - SINGLE translation unit: this file is concatenated AFTER bench_<x>.c
 *     (build_dcc_corpus.sh does the concat).  dcc miscompiles cross-unit
 *     calls -- a separate-compilation argument-passing defect, see
 *     aes256-corpus commit 4876aee -- so the bench and harness must share
 *     one TU.
 *   - `int main()` is required: dcc rejects implicit-int `main(){`.
 *   - K&R prototypes (no `(void)`) keep dcc's parser happy for the externs;
 *     the real definitions in bench_<x>.c carry the ANSI `(void)` form,
 *     which dcc also accepts.
 */
extern unsigned int bench_run();
extern unsigned int bench_expected();

int main()
{
    unsigned char *o;
    unsigned int r, e;

    o = (unsigned char *)0xC000;
    r = bench_run();
    e = bench_expected();

    o[0] = r & 0xff;
    o[1] = (r >> 8) & 0xff;
    o[2] = e & 0xff;
    o[3] = (e >> 8) & 0xff;
    o[4] = (r == e) ? 1 : 0;
    o[5] = 0;
    o[6] = 0xA5;

    return 0;
}
