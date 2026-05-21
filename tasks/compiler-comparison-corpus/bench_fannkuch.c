/*
 * Fannkuch-redux — compiler-comparison-corpus benchmark.
 *
 * Adapted from z88dk's official compiler-comparison benchmark suite
 * (libsrc/_DEVELOPMENT/EXAMPLES/benchmarks/fannkuch/fannkuch.c),
 * originally from The Computer Language Benchmarks Game.
 *
 * For N=7, known good results:
 *   maxFlipsCount = 16
 *   checksum      = 228
 *
 * We use both as the verifier output: bench_run returns
 * (maxFlipsCount << 8) | (unsigned)(checksum & 0xff) so the harness
 * sentinel catches either miscomputation.  (checksum 228 fits in 8 bits.)
 *
 * Adaptations vs upstream:
 *   - Renamed entry to bench_run() (corpus convention).
 *   - Removed <stdio.h>/<stdlib.h>, PRINTF, TIMER, COMMAND.
 *   - Inlined main(N=7) directly.
 *
 * Workload class: array permutations, swap-heavy, integer arithmetic
 * + nested-loop bookkeeping.  Different shape from sieve (which is
 * memory-bound) and AES (register-bound XOR chains).
 */

#define N      7
#define N_MAX  16

int perm [N_MAX];
int perm1[N_MAX];
int count[N_MAX];

static int max_(int a, int b)
{
   return a > b ? a : b;
}

static int fannkuchredux(int n)
{
   int maxFlipsCount = 0;
   int permCount = 0;
   int checksum = 0;
   int i;
   int r = n;

   for (i = 0; i < n; ++i)
      perm1[i] = i;

   while (1) {
      int flipsCount = 0;
      int k;

      while (r != 1) {
         count[r - 1] = r;
         r -= 1;
      }

      for (i = 0; i < n; ++i)
         perm[i] = perm1[i];

      while (!((k = perm[0]) == 0)) {
         int k2 = (k + 1) >> 1;
         for (i = 0; i < k2; ++i) {
            int t = perm[i]; perm[i] = perm[k - i]; perm[k - i] = t;
         }
         flipsCount += 1;
      }

      maxFlipsCount = max_(maxFlipsCount, flipsCount);
      checksum += (permCount % 2 == 0) ? flipsCount : -flipsCount;

      while (1) {
         int perm0 = perm1[0];
         if (r == n)
            return (maxFlipsCount << 8) | ((unsigned int)(checksum) & 0xff);

         i = 0;
         while (i < r) {
            int j = i + 1;
            perm1[i] = perm1[j];
            i = j;
         }
         perm1[r] = perm0;
         count[r] = count[r] - 1;
         if (count[r] > 0) break;
         r++;
      }
      permCount++;
   }
}

unsigned int bench_run(void)
{
   return (unsigned int)fannkuchredux(N);
}

unsigned int bench_expected(void)
{
   /* N=7: maxFlipsCount = 16 (= 0x10), checksum = 228 (= 0xE4).
    * Packed: (16 << 8) | 228 = 0x10E4 = 4324. */
   return 0x10E4;
}
