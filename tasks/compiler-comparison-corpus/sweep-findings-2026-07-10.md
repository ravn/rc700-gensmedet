# Corpus sweep analysis (2026-07-10)

Six-lane sweep (llvm-z80, zsdcc, dcc, llvm-z88dk, xcc, ez80clang) over the five
benchmarks (sieve, fannkuch, pi, word_fill, licm_pessimize), each at SIZE and
SPEED. All 28 measured cells PASS (no XFAIL/XPASS). Numbers are from
`sweep/results.tsv` this date.

## Headline

llvm-z80 (clang) has the **smallest binary on every benchmark**, usually by a
large margin, and is competitive-to-winning on t-states:

| bench          | llvm-z80 size | next smallest    | llvm-z80 speed ts | fastest other      |
| -------------- | ------------- | ---------------- | ----------------- | ------------------ |
| sieve          | **198**       | zsdcc 624        | 3.50M             | zsdcc 5.08M        |
| fannkuch       | **584**       | xcc 1424         | **22.4M** (best)  | z88dk 22.5M        |
| pi             | **888**       | dcc 2048         | 38.0M             | dcc 39.3M          |
| word_fill      | **178**       | zsdcc 526        | 195k              | zsdcc 129k (best)  |
| licm_pessimize | **143**       | xcc 641          | **1.37M** (best)  | zsdcc 12.0M        |

Remaining llvm-z80 speed gap: word_fill vs zsdcc (~1.5x), already tracked in
ravn/llvm-z80#99 (see perf-findings-2026-07-06.md §1). No new codegen regressions.

## Finding 1 — sieve:xcc = 8696 B is NOT code quality; xcc emits no `.bss`

sieve:xcc ballooned to **8696 B**, a 5x outlier vs xcc's other cells (fannkuch
1424, pi 2239, word_fill 1661, licm 641). Root-caused (map + minimal repro):

- sieve declares `unsigned char flags[8000];` (file-scope, uninitialized → BSS
  by convention). The .COM carries an **8026-byte trailing zero run** = that
  array materialized as literal zero bytes in the image.
- The xcc-produced `.rel` records **only `_CODE` and `_DATA` areas — no `_BSS`**
  (`A _DATA size 1F44 …`, no `A _BSS`). The linker map confirms `l__BSS = 0`,
  with the 8000-byte array living in `_DATA`.
- Minimal repro (`uninit[4000]` + `zeroinit[4000]={0}` + `init[4]={1,2,3,4}`):
  `.com = 8363 B`, largest zero run **8002 B**, `l__BSS = 0`, `l__DATA = 0x1F5E`.

**Conclusion:** xcc places file-scope uninitialized / zero-initialized objects in
`_DATA` and emits them as zero bytes, i.e. it never uses `.bss`. For a flat CP/M
`.COM` this inflates every binary by the full size of its uninitialized data.
xcc's *code* is actually compact (fannkuch 1424, licm 641 are reasonable); the
sieve number is an artifact of this section-placement behavior, not code density.

Filed upstream (own fork): **ravn/xyz#5** with the minimal repro.

Corpus implication: the xcc SIZE datapoint is not comparable for BSS-heavy
programs until xcc emits `.bss`. `build_xcc_corpus.sh` already documents this
caveat (its NOTE block, now referencing ravn/xyz#5); sieve:xcc is left as a PASS
(correct result, just fat).

## Finding 2 — ez80clang size==speed everywhere (`--opt-code-size` is a no-op)

Every ez80clang row had byte/t-state-identical SIZE and SPEED cells. Cause:
`zcc` hardwires `-cc1 -S -O3` for `-compiler=ez80clang` and ignores
`--opt-code-size`, so the "size" (-Oz) and "speed" (-O3) cells compile the same.
(pi/sieve/fannkuch are additionally forced to `-O0` in `build_ez80clang_corpus.sh`
to dodge the IX frame-pointer miscompile, CE-Programming/llvm-project#50 /
rc700-gensmedet#124.)

Action taken this session: `run_ez80clang` now measures **once** (single -O3
build+ticks) and mirrors it into both TSV columns, with a documenting comment.
No new issue — the `--opt-code-size` no-op is an upstream ez80-clang/zcc property
already tracked via rc700-gensmedet#122/#124.

## Finding 3 — fannkuch:xcc fixed (was the session's XFAIL)

The `while(x!=1)` / `x==1` truthiness-fold miscompile (ravn/xyz#3) is fixed
locally (branch `fix/loop-only`); the corpus `xcc-current` symlink points at that
build, so fannkuch:xcc now PASSES (1424 B, ts 68.1M). Removed from
`EXPECTED_FAIL`.

## Non-findings (expected, documented for completeness)

- **zsdcc skips fannkuch + pi** (`SKIP_CELL`): the zsdcc lane builds `--sdcccall 1`
  and hits an stdlib-ABI mismatch, not a codegen bug (zsdcc-bench-divergence-
  2026-06-08.md). Intentional absence, not a failure.
- **z88dk / ez80clang ~5 KB flat binaries**: both bundle the z88dk RTL into the
  `.COM`; read as trend, not byte-parity with the freestanding lanes.
- **dcc ~1–2 KB**: bundles the CP/M RTL + fixed CRT-startup ts; trend, not parity.
