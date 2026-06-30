/*
 * Sieve of Eratosthenes — compiler-comparison-corpus benchmark.
 *
 * Adapted from z88dk's official compiler-comparison benchmark suite
 * (libsrc/_DEVELOPMENT/EXAMPLES/benchmarks/sieve/sieve.c).
 *
 * SIZE = 8000.  Counts primes in [2, 7999].  Known good answer: 1007.
 *
 * Adaptations vs upstream:
 *   - Renamed entry to bench_run() returning uint16_t prime count
 *     (test_main.c is the corpus-wide harness; expects this signature).
 *   - Removed <stdio.h>/<string.h> includes -- freestanding build.
 *   - Removed K&R-style `main()`; explicit zero-init of flags[].
 *   - Removed TIMER + PRINTF -- corpus harness uses memory sentinel.
 *
 * Workload class: tight integer loops, byte-array memory bound,
 * 8000-byte BSS.  Different shape from AES (which is register-bound
 * and 16-byte state).
 */

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;

#define SIZE 8000

unsigned char flags[SIZE];

unsigned int bench_run(void)
{
   uint16_t i, i_sq, k, count;

   /* The freestanding clang/zsdcc cells arrive here with zeroed BSS from
    * their startup path.  dcc's CP/M runtime does not, so the dcc cell must
    * clear the sieve bitmap explicitly to preserve the same source-level
    * semantics without perturbing the other compilers' setup. */
#ifdef _DCC_
   for (i = 0; i < SIZE; ++i)
      flags[i] = 0;
#endif

   count = SIZE - 2;

   i_sq = 4;
   for (i = 2; i_sq < SIZE; ++i)
   {
      if (!flags[i])
      {
         for (k = i_sq; k < SIZE; k += i)
         {
            count   -= !flags[k];
            flags[k] = 1;
         }
      }
      i_sq += i + i + 1;  /* (n+1)^2 = n^2 + 2n + 1 */
   }

   return count;
}

unsigned int bench_expected(void)
{
   /* sieve of Eratosthenes on [2, 7999] finds exactly 1007 primes.
    * https://primes.utm.edu/lists/small/10000.txt verifies this. */
   return 1007;
}
