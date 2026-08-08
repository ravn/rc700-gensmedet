# Pixel-plotting speed — progress tracker

A living record of the RC700 pixel-drawing speed as we work toward a better
`plot`/`unplot` implementation. The number to drive down is the T-state cost of
a fixed, deterministic drawing workload (`z88dk/examples/rc700/pixelbench.c`),
measured on real RC702 timing in MAME.

## What is measured

`pixelbench.c` does a fixed amount of pure drawing — no multiply, no divide
anywhere (verified in emitted asm: the only calls are `_getmaxx/_getmaxy/_clg/
_plot/_unplot/_getk`). Two deterministic phases:

1. every 2x3 sextant cell cycled through all 64 on/off combinations
   (64 * 2000 cells * 6 sub-pixels = 768,000 `plot`/`unplot` calls);
2. prime-stride scatter fill then erase of all 12,000 pixels (24,000 calls).

Total = **792,000 `plot`/`unplot` calls**, identical across every build. The
harness brackets `_main` -> first `_getk` with the MAME debugger's
`totalcycles`, so the reported number is the whole-workload T-state cost.

## How to reproduce

```sh
# 1. build the demo (see z88dk/examples/rc700), grab _main/_getk from the .map:
#    grep -E '^_main |^_getk ' <name>.map
# 2. measure (from this dir):
./run_bench.sh <name> <main_hex> <getk_hex>
# prints:  BENCH_RESULT <NAME> <tstates>
```

`run_bench.sh` cpmcp's `<name>.com` onto a copy of the bootable base disk,
boots `rc702sem702` at 4 MHz with `-nothrottle`, and drives the run with
`bench.dbg` (debugscript) + `bench.lua` (autoboot). Paths are overridable via
env (`W`, `MAME`, `BASE`, `CPMCP`, `LUA`). Each full run is ~200 s wall.

## Interpreting the number — what counts as "improvement"

**The `plot`/`unplot` primitives currently come from the shared, classic-built
`rc700.lib`, which is identical across all three compiler lanes, and every build
issues exactly 792,000 calls.** So today's cross-compiler spread reflects only
the *caller-side* glue (loop control, `cell_pattern`, address arithmetic,
calling-convention overhead) — NOT the drawing primitive itself.

Two independent levers therefore move this number, and this tracker follows
both:

- **A. Compiler glue** — better codegen for the loop/glue around the calls
  (this is what separates the lanes below today).
- **B. The primitive** — a faster `plot`/`unplot` (or a batched span/cell API
  that cuts the 792,000-call overhead). This is the larger long-term win and
  the "better implementation" this document tracks toward.

When B lands, re-measure ALL lanes (the primitive change affects every lane
equally, so keep the cross-lane comparison honest by refreshing the whole row).

## Baseline — 2026-08-08

RC702 @ 4 MHz, `pixelbench.c`, optimal-speed flags, shared classic `rc700.lib`:

| Compiler       | Flags                      |        T-states | T/call | vs. best |
|----------------|----------------------------|----------------:|-------:|---------:|
| **llvmz80**    | `-O3`                      | **2,177,590,702** |  2,750 |   —      |
| sdcc (zsdcc)   | `-O3 --opt-code-speed`     |   2,578,386,272 |  3,255 |  +18.4 % |
| sccz80 (classic)| `-O3`                     |   3,061,777,994 |  3,866 |  +40.6 % |

Cross-lane: llvmz80 is **15.5 %** faster than sdcc and **28.9 %** faster than
sccz80; sdcc is 15.8 % faster than sccz80.

`_main` / `_getk` addresses used (from each `.map`):

| Compiler | `_main` | `_getk` |
|----------|:-------:|:-------:|
| sccz80   | `04F6`  | `179C`  |
| sdcc     | `04D3`  | `1724`  |
| llvmz80  | `0423`  | `1800`  |

## Progress log

Newest first. One row per measured change; keep the baseline row above intact.
Record: date, what changed, which lever (A glue / B primitive), the lane(s)
re-measured, the new T-state number, and the delta vs. the previous best for
that lane.

| Date       | Change                                   | Lever | Lane     |        T-states | Δ vs prev |
|------------|------------------------------------------|:-----:|----------|----------------:|----------:|
| 2026-08-08 | Baseline (shared classic rc700.lib)      |   —   | llvmz80  |   2,177,590,702 |     —     |
| 2026-08-08 | Baseline (shared classic rc700.lib)      |   —   | sdcc     |   2,578,386,272 |     —     |
| 2026-08-08 | Baseline (shared classic rc700.lib)      |   —   | sccz80   |   3,061,777,994 |     —     |
