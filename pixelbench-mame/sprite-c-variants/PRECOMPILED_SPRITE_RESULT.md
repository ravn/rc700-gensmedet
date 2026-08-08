# Precompiled-sprite blit (spr_or_precomp) — the sparse-sprite fix

Answers the question: *can we exploit that empty pixels are one value and set
pixels another, before doing the heavy per-cell work?* Yes — by doing that
heavy work **once**, not per frame.

## Idea
A sprite is static across a game loop. `spr_compile()` walks the bitmap ONCE
and emits a list of only the **non-empty cells**, each with a precomputed
`(vram_offset, mask)`. Per-frame `spr_draw()` then does zero bit-testing and
never visits an empty cell:

    cp = base + cells[i].off;
    *cp = textpixl[ rev[*cp] | cells[i].mask ];

`base = 0xF800 + (y0/3)*80 + (x0>>1)`; `off` is relative to the top-left cell,
so placement costs one 16-bit add per cell.

## Correctness
Byte-identical to generic `putsprite(spr_or,…)` on the 16×16 pawn across 5
positions (incl. overlap), MAME VRAM-diff oracle.

## Throughput (4000 draws, rc702sem702 -nothrottle, llvmz80 -O3, 16×16 pawn)
| routine                | T total      | T/sprite | vs generic |
|------------------------|--------------|----------|------------|
| generic putsprite      | 264,626,537  | 66,156   | 1.00×      |
| cell-batch (spr_or_big)| 352,245,836  | 88,061   | 0.75×      |
| **precomp (spr_draw)** | **41,905,354** | **10,476** | **6.31×** |

precomp is **8.4× faster than the naive cell-batch** and turns the sparse-
sprite loss into a large win.

### Net of fixed overhead
The bench window is `_main → first _getk`, so it stops when drawing finishes
(the spacebar-wait `getk` is NOT counted). But the window still includes a
fixed **8,464,423 T** of non-drawing work — `clg()` (clears 2000 cells) +
`spr_compile` (once) + the position-math loop, whose `%68`/`%136`/`%18` are
runtime Z80 divisions. That constant is identical across all three variants,
so subtracting it gives the pure per-sprite draw cost:

| routine                | raw T/spr | net T/spr | net vs generic |
|------------------------|-----------|-----------|----------------|
| generic putsprite      | 66,156    | 64,040    | 1.00×          |
| cell-batch (spr_or_big)| 88,061    | 85,945    | 0.75×          |
| **precomp (spr_draw)** | 10,476    | **8,360** | **7.66×**      |

Net of overhead, precomp is **10.3× faster than the naive cell-batch**. The
overhead (~2,116 T/sprite) lives in the harness's position arithmetic, not in
any blit.

## Why it works — the two effects combine
The pawn touches only **18 of 48 covered cells (38%)**.
1. **Skip empty cells:** the list holds only the 18 non-empty cells, so the
   70%/62%-empty coverage is never scanned.
2. **Hoist the heavy work out of the frame loop:** all bit-testing and
   mask-building happen once in `spr_compile`; the per-frame inner loop is a
   tight offset-add + two-LUT RMW.

For a static game sprite (drawn many times) the compile cost amortizes to
nothing. This is the general answer for BOTH dense and sparse sprites, and it
supersedes the naive cell-batch as the recommended structure — the earlier
density-crossover caveat (LARGER_SPRITE_RESULT.md) applies only to the *naive*
per-frame cell scan, not to this precompiled form.

## Caveats / scope
- Cell-aligned (x even, y mult-3), OR mode, no clipping — same PoC constraints.
- The cell list must be rebuilt if the sprite bitmap changes (not its position).
- `CCELL` = {uint16_t off; uint8_t mask;}; 48-entry buffer covers any ≤16×16.
