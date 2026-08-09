# RC700 mandelbrot: llvmz80 renders byte-identical to sccz80 (2026-08-09)

End-to-end closure of the z88dk `<graphics.h>` calling-convention work
(ravn/llvm-z80 #281/#282 + the graphics.h `__z88dk_fastcall` return bridge,
CALLEE_GRAPHICS_FINDING.md). `mandelbrot.c` is the heaviest of the three RC700
demos on integer codegen (nested loops + Q6.10 32-bit fixed-point multiplies),
so it exercises both the fixed calling conventions (`getmaxx`/`getmaxy` return,
`plot` args) and the 32-bit multiply path.

## Result — VERIFIED

Same source (`mandelbrot.c`), two compilers, MAME rc702:

| build   | draw time (emu) | drawn cells | on-pixels | snapshot                    |
|---------|-----------------|-------------|-----------|-----------------------------|
| llvmz80 | ~322 s          | 498         | 32296     | snap/gfxtest-llvmz80.png    |
| sccz80  | ~258 s          | 498         | 32296     | snap/gfxtest-sccz80.png     |

**The two snapshots are BYTE-IDENTICAL** (`cmp` clean; 0 foreground-mask pixel
differences). llvmz80 is slower (default `__mulsi3`; the #283 `__mulsi3_fast`
path is -O3-only and this build is not -O3), but the render is exact.

## Opt-level sweep (llvmz80, all levels, MAME rc702, -nothrottle)

Every level renders **byte-identical to the sccz80 oracle** (32296 on-pixels, 0
foreground diff) — correctness of the CC composition + return bridge is
opt-level-independent. `draw_s` = emulated seconds of pure drawing.

| opt | clang | size (B) | draw time | on-pixels | match |
|-----|-------|----------|-----------|-----------|-------|
| O0  | -O0   | 6860 | 307.2 s | 32296 | IDENTICAL |
| O1  | -O1   | 6836 | 302.4 s | 32296 | IDENTICAL |
| O2  | -O2   | 6753 | 295.2 s | 32296 | IDENTICAL |
| O3  | -O3   | 6788 | **171.6 s** | 32296 | IDENTICAL |
| Os  | -Os   | 6744 | 296.4 s | 32296 | IDENTICAL |

**Headline: O3 is ~1.72x faster (−42% draw time) for +35 B.** That is #283's
`__mulsi3_fast` isolated in the wild: mandelbrot is dominated by the 32-bit
fixed-point multiply, and the 16-bit-fitting operands hit the 32→16×16 demote
fast path. O0/O1/O2/Os cluster at ~295–307 s because they all share the default
`__mulsi3` — the C opt level only changes loop glue, not the dominant multiply
libcall; only O3 swaps the routine. Os is the smallest build (6744 B).

Reproduce the sweep: `./opt_sweep.sh` (writes `opt_sweep_results.txt`, snapshots
`snap/mandel-{o0,o1,o2,o3,os}.png`).

## Reproduce (single build)

From `rc700-gensmedet/scratch/sine-demo/` (needs the fresh llvm-z80
`build-macos/bin/clang`, the z88dk fork with the graphics.h fastcall fix, MAME
`regnecentralend`, cpmtools, and the SW1711-I8 system disk — see Makefile vars):

```sh
make compare SRC=mandelbrot.c LUA=mandelbrot_run.lua SECONDS=700
cmp snap/gfxtest-llvmz80.png snap/gfxtest-sccz80.png && echo IDENTICAL
```

`mandelbrot_run.lua` boots rc702, types `B:GFXTEST`, and snapshots once the
screen has been **static for ~24 emulated seconds** (`stable >= 20` windows).
The long static window is deliberate: one RC700 text cell holds 6 sextant
subpixels, so the non-blank *cell* count saturates and briefly plateaus (~1-2 s)
while the heavy middle rows fill subpixels into already-lit cells — a short
window (the first attempt used 4) false-fires mid-draw and snapshots only the
top half. Only the finished, `getk()`-held image is static long enough.

## Note on the compiler state this validates

Run against llvm-z80 `main` after consolidating #281/#282/#283 (merge
`4ba5d59`) + #284. The `__smallc __z88dk_callee` composition (cc133) and the
value-return register are both correct here: a miscompile of either would move
or corrupt `plot`/`draw` coordinates and distort the silhouette (as the pre-fix
renders did). Byte-identical to the sccz80 oracle is the strongest available
end-to-end signal.
