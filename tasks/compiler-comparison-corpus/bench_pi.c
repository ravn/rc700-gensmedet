/*
 * Pi spigot — compiler-comparison-corpus benchmark.
 *
 * Adapted from z88dk's official compiler-comparison benchmark suite
 * (libsrc/_DEVELOPMENT/EXAMPLES/benchmarks/pi/pi.c), original from
 * https://crypto.stanford.edu/pbc/notes/pi/code.html
 *
 * Computes pi to 800 digits using a spigot algorithm.  Exercises
 * 32-bit integer math heavily (ldiv-like d/(uint32_t)b).
 *
 * Workload class: 32-bit integer arithmetic, big-num style.  Different
 * shape from sieve (16-bit byte ops) and fannkuch (array permutations).
 *
 * Verifier: a checksum of the digit stream (sum of all 4-digit blocks
 * mod 65536).  We don't print digits — the harness sentinel mode
 * checks the checksum's known-correct value.
 *
 * Adaptations vs upstream:
 *   - Renamed entry to bench_run().
 *   - Removed PRINTF, TIMER.
 *   - Replaced printf("%.4d", x) with checksum accumulation.
 *   - SCALE_DOWN: reduced from 2800 to 280 to keep tstate count
 *     reasonable (full 2800 takes ~minutes; 280 takes ~seconds).
 *     This still exercises the same arithmetic patterns.
 *   - Split init into pi_init() with noinline -- workaround for
 *     ravn/llvm-z80#182 (SCEV crash when two loops over the same
 *     array are visible to the optimizer in one function).
 *
 * XFAIL under zsdcc (sweep.sh EXPECTED_FAIL set, 2026-06-08): zsdcc
 * returns 0 instead of the computed checksum.  Suspected: --sdcccall 1
 * + sdcc_iy + uint32_t interaction, similar to known z88dk#5/#6.
 * Investigation deferred -- see tasks/zsdcc-bench-divergence-2026-06-08.md
 * for the full writeup, hypotheses, and reduction strategy.
 */

typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;
typedef unsigned long  uint32_t;

#ifdef __clang__
#  define NOINLINE __attribute__((noinline))
#else
#  define NOINLINE  /* SDCC doesn't have the #182 crash; inlining is fine */
#endif

#define DIGITS_PER_BLOCK 14
#define SCALE            280

static uint16_t r[SCALE + 1];

NOINLINE
static void pi_init(void)
{
   uint16_t i;
   /* upstream uses r[i] = 2000 to initialize the spigot state. */
   for (i = 0; i < SCALE; ++i) r[i] = 2000;
}

unsigned int bench_run(void)
{
   uint16_t i, k;
   uint16_t b;
   uint32_t d;
   uint16_t c, checksum;

   pi_init();

   c = 0;
   checksum = 0;

   for (k = SCALE; k > 0; k -= DIGITS_PER_BLOCK)
   {
      d = 0;
      i = k;

      while (1)
      {
         d += (uint32_t)(r[i]) * 10000UL;
         b = i * 2 - 1;
         r[i] = (uint16_t)(d % (uint32_t)b);
         d   /= (uint32_t)b;

         if (--i == 0) break;
         d *= (uint32_t)i;
      }

      checksum += c + (uint16_t)(d / 10000UL);
      c = (uint16_t)(d % 10000UL);
   }

   return checksum;
}

unsigned int bench_expected(void)
{
   /* SCALE=280, DIGITS_PER_BLOCK=14: pi digits computed in 20 blocks.
    * Captured from llvm-z80 reference run.  zsdcc must produce the
    * same checksum -- any mismatch is a real correctness divergence
    * worth investigating.
    *
    * Checksum derivation: sum of (c + d/10000) per block, mod 2^16,
    * where c starts at 0 and updates per block.  The exact value
    * depends on the spigot algorithm's integer-arithmetic order;
    * both compilers should produce identical results when the
    * computation is bit-correct. */
   return 28116;
}
