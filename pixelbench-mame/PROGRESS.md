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
| 2026-08-09 | Arithmetic reverse-map (rc700.lib override) |   B   | llvmz80  |   1,271,565,612 | **−41.6 %** |
| 2026-08-09 | Arithmetic reverse-map (rc700.lib override) |   B   | sdcc     |   1,672,188,728 | **−35.1 %** |
| 2026-08-09 | Arithmetic reverse-map (rc700.lib override) |   B   | sccz80   |   2,155,604,725 | **−29.6 %** |

### Lever B landed — arithmetic reverse-map, 2026-08-09

Replaced the gencon `ckmap` up-to-64-iteration linear reverse-scan (on-screen
char → 6-bit sextant mask, step 3 above) with a ~5-instruction **arithmetic**
reverse-map, delivered as rc700-specific override routines that live in
`rc700.lib` and are pulled ahead of the shared gencon body by `rc700.lst` link
order (rc700 target objects globbed before the gencon manifest, so the
librarian resolves `plotpixel`/`respixel`/`pointxy`/`xorpixel` from the rc700
objects — no duplicate-symbol error, gencon's bodies never linked).

The reverse-map exploits that `textpixl` is two contiguous char runs
(`$20–$3F` → mask 0–31, `$60–$7F` → mask 32–63), so char→mask is pure
arithmetic (`sub $20` / range-check / `add 32`) with no table and no scan.
Proven equivalent to gencon `ckmap` for **all 256 char values** (exhaustive
Python check, 0 mismatches); screen output visually confirmed correct in MAME.

**The absolute saving is ~906 M T-states in every lane** (llvmz80 906,025,360;
sdcc 906,197,544; sccz80 906,173,269) — a near-constant delta that corroborates
the fix lives entirely in the shared primitive and is compiler-independent, as
expected for a lever-B change. Files:
`z88dk/libsrc/target/rc700/graphics/rc700_pixel6.inc` + the four
`rc700_{plotpixl,unplotpixl,pointpixl,xorpixl}.asm` wrappers.

New `_main` / `_getk` addresses (rebuilt against the fast lib):

| Compiler | `_main` | `_getk` |
|----------|:-------:|:-------:|
| sccz80   | `04F6`  | `17A4`  |
| sdcc     | `04D3`  | `172E`  |
| llvmz80  | `0423`  | `1808`  |

## Optimization opportunities — lever B (the primitive), 2026-08-08

Investigation of the actual `plot`/`unplot` hot path for rc700. Evidence in
`z88dk/libsrc/classic/gfx/gencon/pixel6.inc` (the included body of
`plotpixl6.asm`) and `z88dk/libsrc/target/rc700/generic_console.asm`.

### Layout facts (known, from `lib/config/cpm.cfg:148`)

- `CONSOLE_COLUMNS=80`, `CONSOLE_ROWS=25`, `RC700_DISPLAY=0xF800`.
- VRAM is a contiguous 80×25 = 2000-byte memory-mapped grid. **A cell index
  `row*80+col` therefore equals the VRAM byte offset**: `vaddr = 0xF800 + cell`.
  This 1:1 mapping is the key enabler for the fixes below.
- Sextant char codes are non-contiguous: `textpixl` maps mask 0..63 to display
  codes `$20..$3F` then `$60..$7F` (`target/rc700/graphics/textpixl6.asm`).

### Where the T-states go, per `plot()` call (known, from the source)

1. Bounds check + `y/3` via the `div3` lookup table + `x/2` via `rra`.
   Already division-free and cheap. **Not a target.**
2. **`vpeek`** (`generic_console_vpeek`) → `xypos`: computes the VRAM address
   with an **O(row) `add hl,de` djnz loop (up to 25 iterations)**, then
   `ld a,(hl)`. (`generic_console.asm:219,241`)
3. **`ckmap` reverse scan** (`pixel6.inc`): a linear scan of **up to 64**
   `cp (hl)/jr z/inc/inc/djnz` iterations to convert the char just read back
   into its 6-bit sextant mask. This runs because rc700 does **not** define
   `_GFX_TEXT_USE_INDEX` (contrast the 160×72 sibling `alphatp2`, which does —
   `grafix.inc:33-36`). Worst case ≈ 64×~30 T ≈ 1900 T; average ≈ 950 T against
   a measured ≈2750 T/call on the fastest lane — i.e. **this single scan is
   plausibly ~a third of the whole per-call cost.**
4. Forward map mask→char (`ld hl,textpixl; add hl,de; ld a,(hl)`) — cheap.
5. **`printc`** (`generic_console_printc`) → `xypos` **again** (a second O(row)
   djnz loop) + `ld (hl),a`. (`generic_console.asm:206,241`)

So every pixel pays the row-addressing loop **twice** and an up-to-64-entry
linear scan. Note `_GFX_GENCON_USEPLOTC` is also unset for rc700, so the raw
`vpeek`/`printc` path (above) is what runs — not `pointxy`/`plotc`.

### Ranked levers

**B-shadow (RECOMMENDED — biggest win, target-local, API-preserving).**
Keep a 2000-byte RAM shadow, one byte per cell holding its current 6-bit mask.
Then `plot`/`unplot`:
  - compute `cell = row*80 + col` **once**;
  - read `shadow[cell]` (a single `ld a,(hl)`) instead of `vpeek`+`ckmap` —
    **removes the up-to-64-iter scan (step 3) AND the first `xypos` loop
    (step 2) entirely**;
  - set/clear the wanted bit; store back to `shadow[cell]`;
  - `vaddr = 0xF800 + cell` is a **single 16-bit add** (no djnz loop), and the
    VRAM write is `ld (hl), textpixl[mask]` — **removes the second `xypos`
    loop (step 5)** too.
Cost: 2000 bytes BSS + a one-time shadow-clear hooked into `clg`. No public API
change — `pixelbench.c` and every existing demo benefit unchanged. Estimated
several-hundred-T saving per call (dominated by killing the reverse scan),
i.e. a plausible 20-35% drop; **must be re-measured, not assumed.**

**B-index (`_GFX_TEXT_USE_INDEX`).** Add `defc _GFX_TEXT_USE_INDEX = 1` to the
rc700 block in `grafix.inc` to drop the `ckmap` scan (step 3) and the forward
map (step 4), exactly as `alphatp2` does. BUT it requires the on-screen char to
equal the mask index 0..63, which the current i8275 font does not satisfy
(sextants live at `$20-$3F`/`$60-$7F`). Viable only by loading a **remapped
SEM702 RAM font** (chargen is RAM-backed via ports 0xD1/D2/D3) so glyph code N
renders sextant pattern N. Bigger blast radius (font + `textpixl` retire), and
hardware/font-coupled. Lower priority than B-shadow, and largely redundant with
it (B-shadow already removes the scan without a font change).

**B-cell (batch/span API).** Add a `plotcell(cx,cy,mask)` that writes one cell
directly — no read, no per-subpixel work. pixelbench Phase 1 sets whole 2×3
cells: 64 patterns × 2000 cells × 6 sub-pixel `plot`s = 768,000 calls collapse
to 128,000 cell writes (~6×). This changes/extends the public API and only
helps cell-oriented callers, so it is complementary to B-shadow, not a
replacement. Good candidate once B-shadow lands.

**B-addr-only (smallest step).** If B-shadow is deferred, at minimum replace the
`xypos` djnz row loop with `vaddr = 0xF800 + (row*80 + col)` computed once and
reused for both the read and the write (the read/write are the same cell).
Removes one full O(row) loop and the duplicate address computation without any
RAM cost. A safe incremental win and a natural first commit toward B-shadow.

### Suggested order of work

1. **B-addr-only** — safe, no RAM, removes duplicate `xypos`; land + re-measure.
2. **B-shadow** — the headline win; removes the reverse scan; land + re-measure
   all three lanes (primitive change affects every lane equally).
3. **B-cell** — optional batch API for cell-oriented drawing once B-shadow is in.
4. **B-index** — only if a remapped SEM702 font is pursued for other reasons.

After each step, add a row to the progress log above with the new measured
T-state number (never mark a win from reasoning alone — building is not
behaving; run the harness).
