# Larger-sprite test: 16×16 chess pawn (spr_or_big)

Extends the cell-batched C blit to **multi-byte rows (w>8)** and a **partial
final band (h not a multiple of 3)**, tested on a real 16×16 chess pawn
(`chessb16.h`), OR mode, cell-aligned (x even / y mult-3), no clipping.

## Correctness
Byte-identical to the generic `putsprite(spr_or,…)` across 5 positions
(incl. an overlap), verified via the MAME VRAM-diff oracle (231 non-zero
bytes in the reference — a real drawing). `spr_or_big.c` is the source.

## Throughput (4000 draws, rc702sem702 -nothrottle, llvmz80 -O3)
| routine                 | T total      | T/sprite | vs generic |
|-------------------------|--------------|----------|------------|
| generic putsprite       | 264,626,537  | 66,156   | 1.00×      |
| spr_or_big (cell-batch) | 352,245,836  | 88,061   | **0.75×**  |

**On this 16×16 pawn the cell-batched blit is 1.33× SLOWER than generic.**

## Why — the density crossover (the key finding)
The pawn is only **18% dense** (46 of 256 pixels set). The generic
`putsprite` plots **only the set pixels** (~46 RMWs). The cell-batched blit
scans **every covered cell** (8 cells × 6 bands = 48 cells) every draw,
regardless of content, doing a VRAM read-modify-write per cell.

- Cell-batching wins when the sprite is **dense** (the 8×9 ball is nearly
  solid → up to 5.1× pure-C / 6.26× hand-asm, because one cell RMW replaces
  up to 6 per-pixel plots).
- Cell-batching loses when the sprite is **large and sparse**: it pays for
  empty cells the per-pixel plotter skips entirely.

Crossover is governed by set-pixels-per-covered-cell. Below ~1 set pixel per
cell the per-pixel generic wins; above it, cell-batching wins. The ball sits
well above the line; the 18%-dense pawn sits below it.

## Takeaway for productionizing
A batched blit should either (a) be reserved for dense sprites, or (b) gain a
per-cell "skip if all three source rows contribute nothing" fast-out — but
that guard re-introduces branchiness and only helps sparse input, so the
honest conclusion is: **cell-batching is a dense-sprite optimization, not a
general putsprite replacement.**
