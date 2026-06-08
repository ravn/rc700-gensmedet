/*
 * bench_word_fill.c — i16-counter loop benchmark, targets #99.
 *
 * Pattern mirrors the canonical XFAIL test
 * llvm/test/CodeGen/Z80/issue-97a-bc-pingpong-i16-counter.ll:
 *
 *     for (i = N; i != 0; --i) *p++ = i;     // N > 255 -> i16 counter
 *
 * Counter `i` and walking pointer `p` both want HL.
 *
 *   SDCC --opt-code-size -SO3 reliably places the counter in BC and
 *   the pointer in HL, producing a tight body roughly:
 *
 *       fill_loop:
 *         ld   (hl),c        ; *p = i (low byte)
 *         inc  hl
 *         ld   (hl),b        ; *p = i (high byte)
 *         inc  hl
 *         dec  bc
 *         ld   a,b
 *         or   c
 *         jr   nz, fill_loop
 *
 *   clang HEAD constrains the counter to BC via Z80SplitDjnzCounters'
 *   i16 path (added in Phase 3), but the pointer ALSO coalesces to BC
 *   at entry (the source vreg arrives in HL from `ld hl,#_buf` and the
 *   coalescer drags it through BC).  Regalloc resolves the BC conflict
 *   by spilling the COUNTER to BSS every iteration:
 *
 *       fill_loop:
 *         ld   (hl),c        ; ok, low byte
 *         inc  hl
 *         ld   (hl),b
 *         inc  hl
 *         ld   a,(__sfrend)  ; <-- spill reload, every iter
 *         sub  #1
 *         ld   (__sfrend),a
 *         ld   a,(__sfrend+1)
 *         sbc  a,#0
 *         ld   (__sfrend+1),a
 *         or   a, ...        ; cc test
 *         jr   nz, fill_loop
 *
 *   The fix per the XFAIL writeup is a sister HLReg single-register
 *   class for the pointer vreg (sibling of the existing BCReg counter
 *   class), so the coalescer can't drag it to BC.
 *
 * Two loops back-to-back (fill + sum) amplify the per-iteration cost
 * delta into a measurable wall-clock gap.  Both loops have the same
 * regalloc shape (i16 counter + walking i16 pointer).
 *
 * Expected sweep symptom WHILE #99 is open (run via sweep.sh):
 *   llvm-z80 tstates > zsdcc tstates by ~15-25 %
 *   llvm-z80 .text   > zsdcc .text   (visible in bin/text columns)
 *
 * Closing #99 should collapse the gap to within a few percent.
 *
 * `volatile unsigned int *p` prevents IR-level constant-folding of the
 * workload (mirrors `store volatile i16` in the canonical XFAIL .ll)
 * and forces both compilers to emit real memory traffic.
 *
 * Workload class: tight i16-counter loops over a 1 KB word array.
 * Distinct from sieve (byte-array, i16-counter outer), fannkuch
 * (recursive perms), pi (long arithmetic).
 */

#define N 512  /* > 255: i16 counter mandatory; no DJNZ-i8 legalization */

static unsigned int buf[N];

unsigned int bench_run(void)
{
    unsigned int           i;
    volatile unsigned int *p;
    unsigned int           sum;

    /* Loop 1: descending fill.  Hot shape #1. */
    p = buf;
    for (i = N; i != 0; --i) {
        *p++ = i;
    }

    /* Loop 2: walk + accumulate.  Hot shape #2 (same regalloc class). */
    sum = 0;
    p = buf;
    for (i = N; i != 0; --i) {
        sum += *p++;
    }

    return sum;
}

unsigned int bench_expected(void)
{
    /* sum_{k=1..N} k = N * (N+1) / 2
     * N = 512: 512 * 513 / 2 = 131328
     * 131328 mod 65536 = 131328 - 2 * 65536 = 256
     */
    return 256;
}
