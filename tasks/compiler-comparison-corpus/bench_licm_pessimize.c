/*
 * bench_licm_pessimize.c -- MachineLICM-pessimization repro for #23.
 *
 * Targets ravn/llvm-z80#23 (MachineLICM / MachineCSE pessimize
 * tiny-register-file targets).  Z80 currently ships a global
 * disablePass(MachineLICMID + EarlyMachineLICMID + MachineCSELegacyID)
 * in Z80PassConfig (Z80TargetMachine.cpp), which is BOTH a size
 * workaround (#128) AND a correctness guard at -O2 (MachineCSE alone
 * miscompiles AES, #198).
 *
 * The compiler-comparison-corpus sweep can build this bench in three
 * cells per compiler:
 *
 *   1. clang default:   the disablePass is in effect (LICM/CSE off)
 *   2. clang LICM on:   `-mllvm -z80-enable-licm`
 *   3. clang CSE on:    `-mllvm -z80-enable-cse` (use at -Oz/-Os ONLY;
 *                       miscompiles at -O2 per #198)
 *   4. zsdcc baseline
 *
 * Hypothesis: cells 2 and 3 produce LARGER and/or SLOWER binaries than
 * cell 1 on this pattern, demonstrating that the workaround is doing
 * real work.
 *
 * THE PATTERN
 *
 * The hot loop has three invariant expressions derived from a single
 * runtime `base`.  MachineLICM will hoist them to the preheader:
 *
 *     a = base + 100;        // hoisted by LICM
 *     b = base * 7;          // hoisted by LICM
 *     c = (base << 4) | 0xF; // hoisted by LICM
 *
 *     for (i = 0; i < N; ++i) {
 *         noinline_callee(i);    // CALL clobbers HL/DE/BC
 *         sum += a + b + c;      // uses all three invariants
 *     }
 *
 * With LICM ON: 5 values live across the call (sum, i, a, b, c) +
 *   loop ctrl = 5 live i16 values vs 3 GR16 pairs on Z80.  Regalloc
 *   must spill ~2 invariants to BSS each iteration.  Cost per iter:
 *   ~6 B + ~26 ts for two BSS reloads.
 *
 * With LICM OFF: 3 values live across the call (sum, i, base) — fits
 *   in 3 GR16 pairs.  a/b/c are recomputed inside the loop after the
 *   call.  Cost per iter: the three computes (~3-5 instructions each)
 *   but no spill traffic.
 *
 * On Z80 the recompute wins because BSS reloads cost more than the
 * arithmetic.  Generic LLVM MachineLICM doesn't know this — it sees
 * "loop-invariant computation -> hoist" without consulting a target
 * register-pressure cost model.
 *
 * The `noinline_callee` is external-linkage with a volatile store so
 * (a) both clang and zsdcc must emit a CALL, (b) the call has a
 * side-effect the optimizer can't remove, (c) sdcccall(1) clobbers
 * HL/DE/BC at the call (forcing the invariant-spill question).
 *
 * VERIFICATION
 *
 * For base=0x1234:
 *   a = 0x1234 + 100         = 0x1298
 *   b = 0x1234 * 7           = 0x7F6C  (low 16 bits of 32620)
 *   c = (0x1234 << 4) | 0x0F = 0x234F  (low 16 bits of 0x12340)
 *   a + b + c                = 0xB553  (low 16 bits)
 *   N = 32 iterations
 *   sum (mod 2^16) = 32 * 0xB553 mod 65536 = 0xAA60
 *
 * Both compilers (with or without the workaround) must agree on
 * 0xAA60.  The investigation is about size+tstates, not correctness.
 */

#define N 32

/* `base` lives in volatile static storage so neither compiler can
 * fold the entire bench to a constant via inter-procedural analysis.
 * The volatile store also prevents the optimizer from hoisting the
 * load out of bench_run() and constant-propagating from there. */
static volatile unsigned int base_storage;

/* External-linkage callee: a side-effect via volatile store at a
 * fixed address (0xC100, well outside the 0xC000 sentinel).  Both
 * compilers must emit a CALL to this; sdcccall(1) clobbers HL/DE/BC
 * at the call site, putting the invariant-survival question to the
 * register allocator. */
void noinline_callee(unsigned int x);

void noinline_callee(unsigned int x)
{
    *(volatile unsigned char *)0xC100 = (unsigned char)x;
}

unsigned int bench_run(void)
{
    unsigned int base;
    unsigned int a, b, c;
    unsigned int sum;
    unsigned int i;

    base_storage = 0x1234;   /* prime the volatile slot */
    base = base_storage;     /* one volatile load; rest is reg-resident */

    a = base + 100;
    b = base * 7;
    c = (unsigned int)(base << 4) | 0x000F;

    sum = 0;
    for (i = 0; i < N; ++i) {
        noinline_callee(i);
        sum += a + b + c;
    }

    return sum;
}

unsigned int bench_expected(void)
{
    /* N=32 iterations of `sum += (a + b + c)` where the invariant
     * (a + b + c) = 0xB553 (low 16 bits) for base = 0x1234.
     * 32 * 0xB553 = 0x16AA60; low 16 bits = 0xAA60. */
    return 0xAA60;
}
