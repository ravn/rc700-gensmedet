# RC700 cell-batched sprite blit — design & knowledge dump

Authoritative reference for the cell-batched sprite blit
(`z88dk/libsrc/target/rc700/graphics/rc700_spriteblit.asm`, symbol
`sprite_or` / `_sprite_or`). Captures the hardware model, the algorithm, every
optimization lever with **measured** T-states, the correctness oracle, the
benchmark method, and — because a likely future goal is *"rewrite as much as
possible in C"* — a measured comparison of a pure-C port plus concrete guidance
on what can and cannot move to C.

All T-state numbers here are **measured in MAME** (`rc702sem702`, full-speed
`-nothrottle`), llvmz80 clang `-O3`, 4000 draws of an 8×9 ball (60 set pixels
over 12 sextant cells) unless stated. Correctness = **byte-for-byte identical
VRAM** to the generic `putsprite`, verified by a MAME memory dump (never "looks
right").

---

## 1. Why this exists

The generic z88dk sprite renderer `__generic_putsprite` (classic
`gfx/narrow/__generic_putsprite.asm`) draws **one pixel at a time**: for every
set bit in the sprite bitmap it calls `plotpixel`/`respixel`/`xorpixel`, paying
the whole RC700 sextant primitive (address compute + VRAM read + reverse-map +
forward-map + write + gfx-page assert) **per pixel**.

On the RC700 the display is not a bitmap — it is an 80×25 grid of **2×3 sextant
character cells**, so up to **6 sprite pixels share one cell**. The blit builds
the 6-bit cell mask **once per cell** and does a single read-modify-write,
amortising the fixed per-cell cost over up to 6 pixels.

Measured on the 8×9 ball: generic **56,856 T/sprite** → shipped blit
**9,086 T/sprite** = **6.26× faster**, pixel-identical.

---

## 2. Hardware / encoding model (all verified in source)

**Display memory.** `RC700_DISPLAY = 0xF800`. The visible grid is 80 columns ×
25 rows, laid out contiguously: cell `(row,col)` lives at
`0xF800 + row*80 + col`. The shared table `rc700_rowaddr` (in
`generic_console.asm`, `PUBLIC`) holds `0xF800 + row*80` for `row = 0..24` as
**25 words (50 bytes)** — a full 16-bit address per row (the region spans
0xF800..0xFF80, 1920 bytes, so it genuinely needs 16 bits; it cannot be a
25-byte single-byte table — see §6 "running base pointer").

**Sextant cell.** A cell covers pixels `x ∈ [2·col, 2·col+1]`,
`y ∈ [3·row, 3·row+2]`. The 6 sub-pixels map to mask bits:

```
bit = (y%3)*2 + (x%2)          cell layout:   bit0 bit1     (y%3=0, top)
                                              bit2 bit3     (y%3=1, middle)
                                              bit4 bit5     (y%3=2, bottom)
                              (x%2=0 left, x%2=1 right)
```

**Glyph encoding** (`textpixl6.asm`, `PUBLIC textpixl`, 64 bytes). The 64
sextant patterns are two contiguous runs of character codes, so the map is pure
arithmetic (no table scan):

```
forward  mask -> glyph:   textpixl[mask]
         mask 0..31  -> char $20..$3F
         mask 32..63 -> char $60..$7F
reverse  glyph -> mask:   $20..$3F -> mask = char-$20   (0..31)
                          $60..$7F -> mask = char-$40   (32..63)
                          anything else            -> 0   (e.g. a plain space)
```

**Gfx-page assert (`setgfx`, `generic_console.asm`).** `setgfx` writes
`GFXMODE = 132` to `RC700_DISPLAY` (0xF800) — the same base the cell writes
target (0xF800 doubles as the i8275 mode latch). The per-pixel primitive
re-asserts it after *every* write because it inherited that from `printc`.
Whether the i8275 needs it re-asserted per cell was an open question — **tested
and answered: no** (see §5 lever 1).

**Sprite format** (`<games.h>`, confirmed from `__generic_putsprite.asm`):
`[width_px, height_px, row bytes…]`, `ceil(w/8)` bytes per row, **MSB-first**
(leftmost pixel = bit 7).

---

## 3. Calling convention (ABI)

`sprite_or` is `__z88dk_fastcall` → on llvmz80 that is
`__attribute__((z80_fastcall))`. A single-pointer fastcall passes the pointer in
**HL**. HL points at a 4-byte parameter block:

```
+0  x0    (even, pixel column of the sprite's left edge)
+1  y0    (multiple of 3, pixel row of the sprite's top edge)
+2  spr   (word LE: pointer to the sprite = {w, h, rows…})
```

C caller (avoids struct-padding ambiguity by passing a raw byte block):

```c
extern void sprite_or(void*) __attribute__((z80_fastcall));
unsigned char pb[4] = { x0, y0, (unsigned)spr & 0xff, ((unsigned)spr)>>8 };
sprite_or(pb);
```

---

## 4. Algorithm (shipped asm)

Register allocation is the whole point — see the ASCII map:

```
B, C, D  = the 3 sprite row bytes of the current band (row0/row1/row2).
           Shifted left in-register (sla) as their 2 MSBs are consumed per cell.
E        = the accumulating 6-bit cell mask (per cell).
A, HL    = all address / map / read / write work.
sb_base  = running VRAM base for this band's cell-row (0xF800 + crow*80),
           advanced by +80 per band (a running pointer, not a table lookup).
sb_ccol / sb_ccnt / sb_ccol0 / sb_wcells / sb_hrem / sb_bmptr / sb_addr : BSS,
           touched once per cell/band (NOT in the 6×/cell shift path).
```

Flow:

```
entry (HL->param block):
    unpack x0,y0,spr ; ccol0 = x0>>1 ; crow0 = y0/3 (repeated-subtract)
    setgfx  ONCE                              ; gfx-page assert hoisted
    sb_base = rc700_rowaddr[crow0]            ; ONE table lookup, top band only
    wcells = w>>1 ; hrem = h ; bmptr = spr+2

band_loop (each band = 3 sprite rows = one cell-row):
    if hrem==0: done
    B,C,D <- bmptr[0..2] ; bmptr += 3         ; load rows into registers
    ccol = ccol0 ; ccnt = wcells

    cell_loop (per cell-column across the band):
        E = 0
        sla B; jr nc; set 0,E    sla B; jr nc; set 1,E     ; row0 -> bits 0,1
        sla C; jr nc; set 2,E    sla C; jr nc; set 3,E     ; row1 -> bits 2,3
        sla D; jr nc; set 4,E    sla D; jr nc; set 5,E     ; row2 -> bits 4,5
        if E==0: next cell                                 ; nothing set here
        ; RMW, A+HL only so B,C,D,E survive:
        HL = sb_base + ccol ; sb_addr = HL
        A  = (HL)                                          ; current glyph
        A  = revmap(A)          ; A-only range compare, no temp reg
        A  |= E                 ; OR sprite mask
        A  = textpixl[A]        ; forward map, add-to-L with carry (no DE)
        (sb_addr) = A                                      ; write glyph
        ; (setgfx NOT re-asserted here — hoisted)
        ccol++ ; ccnt-- ; loop if ccnt

    sb_base += 80 ; hrem -= 3 ; band_loop                  ; running base pointer
```

`revmap` A-only (frees D & E vs the original `ld d,a` version):

```
cp $60 ; jr c,low            ; char<$60
  cp $80 ; jr nc,zero        ; >=$80 -> 0
  sub $40                    ; $60..$7F -> 32..63
  jr ok
low: cp $20 ; jr c,zero      ; <$20 -> 0
     cp $40 ; jr nc,zero     ; $40..$5F -> 0
     sub $20                 ; $20..$3F -> 0..31
zero: xor a
ok:
```

**PoC scope / restrictions** (deliberately narrow to isolate the batching win):
`spr_or` mode only; **x0 even, y0 multiple of 3** (cell-aligned); **w ≤ 8** (one
bitmap byte per row); **h multiple of 3**; **no bounds clipping**. A production
`putsprite` override would add odd-x / misaligned-y partial edge cells,
multi-byte rows, AND/XOR modes, and clipping (see §8).

---

## 5. Optimization levers, each measured

| # | version (all asm unless noted)            | total T (4000×) | T/sprite | vs generic |
|---|-------------------------------------------|----------------:|---------:|-----------:|
| 0 | generic `putsprite` (per-pixel)           | 227,425,204     | 56,856   | 1.00×      |
| A | cell-batched, per-cell `setgfx`, full RMW |  49,525,264     | 12,381   | 4.59×      |
| B | + `setgfx` hoisted out of the loop        |  46,372,548     | 11,593   | 4.90×      |
| C | + register-resident mask build            |  36,832,155     |  9,208   | 6.17×      |
| D | + running base pointer  **(SHIPPED)**     |  36,342,675     |  9,086   | **6.26×**  |
|   | C outer + asm inner leaf                  |  39,295,491     |  9,824   | 5.79×      |
|   | pure C, llvmz80-tuned                     |  44,632,980     | 11,158   | 5.10×      |
|   | pure C, naive (all of A+B+D structurally) |  48,925,596     | 12,231   | 4.65×      |
|   | empty-target ceiling (drops overlap)      |  42,847,194     | 10,712   | 5.31×      |

**Lever A — cell batching** (the algorithm). One RMW per *cell* (12) instead of
one primitive call per *set-pixel* (60). The win scales with pixel-density per
cell: dense sprites win more, sparse less.

**Lever B — hoist `setgfx`** (gave up the assumption "gfx page must be
re-asserted per cell"). Verified byte-identical incl. an OR-overlap → the
per-cell re-assert was pure overhead. This is the **only** assumption we could
safely drop. −6.4%.

**Lever C — register-resident mask build** (pure refactor, no assumption). The
mask was built with load-`sla`-store round-trips to BSS (~156 T/cell of RAM
traffic). Holding rows in B,C,D and mask in E, shifting in-register, needs D & E
free during the RMW — achieved by rewriting revmap to A-only and forward-map /
base-compute to add-to-L-with-carry (no DE). **No stack, no EXX** (EXX would
clash with the target's `+shadow-regs` ISR usage). −20.6%; larger than the ~15%
estimate because it also removed the DE-based forward-map and the revmap temp.

**Lever D — running base pointer** (pure refactor). `crow` advances by exactly 1
per band, so keep the band VRAM base in `sb_base` and add **+80 per band** rather
than re-reading `rc700_rowaddr[crow]` each band. One lookup for the top band
only; removes the per-band lookup + `row*80` and frees a BSS byte. −1.3% (it was
per-band, off the per-cell hot path). See §6 for the "25-byte table" question.

**Not shipped — empty-target** (would give up overlap / OR-accumulate). Assuming
cells are blank lets you skip the VRAM read + revmap and just write
`textpixl[mask]`. Extra ~7% (5.31×) but **NOT pixel-identical when sprites
overlap** — correct only for "draw on a cleared screen". Left as a possible
opt-in `sprite_or_blank`, never the default.

---

## 6. The "can `*80` be a 25-byte table?" question

There is **no runtime `*80` multiply** in the hot path — the row base already
comes from `rc700_rowaddr`. That table is **50 bytes** (25 × 16-bit) because each
entry is a full VRAM address (`0xF800 + row*80`, spanning 1920 bytes > 255), so a
25-byte (1-byte/entry) table **cannot** encode it. Storing only the high byte
(25 bytes) doesn't help — the low byte `(80·row)&0xFF` would then need its own
table or multiply.

The better answer is **no table at all in the loop**: `crow` increments by 1 per
band, so a **running base pointer** advanced by +80 per band costs 0 extra bytes,
no multiply, no per-band lookup — strictly better than a 25-byte table. That is
lever D, shipped. (The one initial `rc700_rowaddr[crow0]` lookup for the top band
is fine and reuses the table the console/plotpixel already ship, so the blit adds
**0 bytes** of its own.)

---

## 7. Rewriting in C — measured, with guidance

A self-contained **pure-C** port (`sprite-c-variants/spr_or_baseline.c`; same
algorithm, its own `textpixl` const, running base pointer, direct
`*(volatile uint8_t*)0xF800 = 132` for the gfx assert) was built and measured,
then two further variants — a **tuned pure C** and a **C outer + tiny asm inner
leaf** — completing the ladder. All are byte-for-byte identical to generic (incl.
the OR-overlap; so writing GFXMODE directly once matches `setgfx` in gfx mode).
Sources + rebuild recipe: `sprite-c-variants/` (see its README).

| variant                       | file(s)                           | total T (4000×) | T/sprite | vs generic |
|-------------------------------|-----------------------------------|----------------:|---------:|-----------:|
| pure C, naive/branchy         | `spr_or_baseline.c`               |  48,925,596     | 12,231   | 4.65×      |
| pure C, llvmz80-tuned         | `spr_or_tuned.c`                  |  44,632,980     | 11,158   | 5.10×      |
| C outer + asm inner leaf      | `spr_or_leaf.c` + `blit_band.asm` |  39,295,491     |  9,824   | 5.79×      |
| full hand asm (shipped)       | `rc700_spriteblit.asm`            |  36,342,675     |  9,086   | 6.26×      |

Interpretation (all **measured**, 2026-08-08):

- **Pure C captures the whole *structural* win.** Batching, `setgfx`-hoist and
  the running base pointer are algorithm-level and the compiler expresses them
  fine: 56,856 → 12,231 T/sprite (**4.65×**). Notably ≈ the *naive* asm (lever A,
  12,381) — **C matches hand-written naive asm** for the inner loop.
- **"Best chance for llvmz80" ≠ textbook branchless.** Tuning the pure C is a
  mixed bag on Z80 — verified by measuring each lever, not guessing:
  - walking cell pointer + **down-counting** loop (`for(n=wcells;n;n--)`):
    **helped** (→4.97×, dec+jnz beats cp+jr up-count);
  - **256-byte `rev[]` LUT** replacing the glyph→mask compare chain: **helped**
    (→5.10×);
  - **"branchless" mask** (`swap2[r>>6]`): **backfired** to 54.7M, *worse than
    naive* — `r>>6` (rlca/rlca/and) + LUT index costs more than six plain
    bit-test branches. Keep the branchy mask. Net best pure C = **5.10×**
    (`spr_or_tuned.c`).
- **A tiny asm inner leaf recovers most of the rest.** Keeping only the
  register-pressure-critical inner cell loop in asm (B,C,D = rows, E = mask,
  A+HL-only RMW so nothing spills) — `spr_or_leaf.c` calling `blit_band.asm` per
  band — reaches **5.79×** with all structure still in clear C: ~76% of the way
  from 4.65× to the full hand-asm 6.26×.
- **The final ~13% (5.79×→6.26×) is per-band C overhead** — filling the 6-byte
  block + the fastcall per band — that the fully-fused hand asm avoids. The
  shipped library routine stays the full asm; the leaf split is the recommended
  shape whenever the source should read as C.

**Recommended structure — C outer, tiny asm inner leaf (clarity first).**
Express everything possible in C; drop to assembly only for the one small kernel
the compiler cannot match. Measured **5.79×** (vs full-asm 6.26×), all readable.

- **C (the whole readable body):** parameter unpack, the band / cell loop
  structure, cell→address arithmetic (running base pointer), the reverse/forward
  map (`textpixl[]` + `rev[]` LUT), the `setgfx` hoist, **and the future
  edge/alignment/clipping + AND/XOR mode dispatch** (§8) — control-flow-heavy
  code where C is as good as asm and far clearer.
- **One small asm leaf (`blit_band`) = the innermost mask-build + RMW** (the
  endorsed "assembler stump"): keeps B,C,D = the 3 row bytes, E = mask, A/HL =
  work, does the 6 `sla`+`set`, the A-only revmap, `or e`, the forward map, and
  the write across a whole band — so the row/mask registers survive. This is what
  the compiler cannot reproduce (it spills across the volatile VRAM RMW).
- **100% C** at 4.65–5.10× is a fine, simpler default if the last ~13–26% ever
  stops mattering; `spr_or_tuned.c` is the fastest 100%-C option.

**C-linkage gotchas found while porting (save yourself the debugging):**

1. **Underscore prefix.** z88dk C symbols get a `_` prefix; the asm tables export
   only the unprefixed names (`textpixl`, `rc700_rowaddr`, `setgfx`). C cannot
   link them directly (you get `undefined symbol: _textpixl`). Either add
   `PUBLIC _textpixl` aliases in asm, or (cleaner for a self-contained C blit)
   define the 64-byte `textpixl` as a `static const` in C and write GFXMODE /
   compute the base directly in C — the self-contained ports do the latter and
   are byte-identical. The asm leaf `blit_band` exports both `blit_band` and
   `_blit_band` so C links the `_`-prefixed name.
2. **Don't drop the loop decrement.** An early C draft advanced `base += 80` but
   dropped `hrem -= 3`, giving an **infinite loop** — the program hangs in the
   blit, never reaches `getk`, and the harness produces **no VRAM dump and no
   BENCH_RESULT at all**. "No dump produced" is the signature of a hang, not a
   pixel mismatch; check for a runaway loop first.

---

## 8. Productionizing (scope beyond the PoC)

To land behind the public `putsprite` symbol as a full RC700 target override
(same mechanism as the `plotpixel` override — its object is pulled from
`rc700.lib` ahead of the gencon generic), add:

- **odd x0 / misaligned y0**: partial top/left/right/bottom edge cells (mask only
  the covered sub-pixels of the boundary cells).
- **w > 8**: multi-byte rows (loop the row bytes; the current PoC assumes 1
  byte/row).
- **AND / XOR modes** (`spr_and`/`spr_mask`=166, `spr_xor`=174, `spr_or`=182):
  swap the `or e` in the RMW for `and`/`xor` and the appropriate
  clear-vs-set-vs-toggle semantics.
- **bounds clipping**: the PoC has none; clip cells to the 80×25 grid (the
  generic primitive bounds-checks per pixel via `__console_w/__console_h`).

This is a genuine fork of `__generic_putsprite` — confirm scope before starting.

---

## 9. How to re-verify / re-measure

Everything lives under `pixelbench-mame/` (tracker: `PROGRESS.md`). The volatile
test harness in a session lives in `/tmp/pxbench/`.

**Correctness oracle** (`run_cmp.sh` + `cmp.lua`): boots `rc702sem702`, types the
`.COM` name at the `A>` prompt, the program draws 8 cell-aligned sprites (incl.
an OR-overlap) then spins on `getk`; a debugscript sets flag `0xA5` at `0x7008`
at the first `_getk`, the lua dumps VRAM `0xF800..+2000` to a file. Compare two
dumps with `cmp` — **must be byte-identical** (54 populated cells, 14 distinct
sextant glyphs; not a blank match).

```
bash run_cmp.sh <name> <getk_hex> <dump_path>       # getk addr from <name>.map
cmp -s dump_gen.bin dump_new.bin && echo IDENTICAL
```

**Throughput** (`run_bench.sh` + `bench.lua`): brackets `_main` → **first**
`_getk` via the debugger's `totalcycles`, so the trailing `while(getk())` wait
loop is **excluded**; the draw path itself is wait-free (no status/retrace/`djnz`
spin). Verified by linearity: 2000 sprites = 23,199,061 T ≈ ½ of 4000's
46,372,548 T (marginal 11,587 T/sprite, fixed overhead ~25.7k T = one `clg`).

```
bash run_bench.sh <name> <main_hex> <getk_hex>      # -> BENCH_RESULT <NAME> <T>
```

**Build the lib after editing the asm:**

```
export PATH=/…/z88dk/bin:$PATH ZCCCFG=/…/z88dk/lib/config
rm -f libsrc/rc700.lib lib/clibs/rc700.lib ; rm -rf libsrc/target/rc700/obj
make -C libsrc rc700.lib && cp libsrc/rc700.lib lib/clibs/rc700.lib
```

**Build a bench** (llvmz80): `zcc +cpm -subtype=rc700 -compiler=llvmz80 -O3 -o
NAME -m SRC.c [extra.c]`; addresses from `NAME.map` (`^_main `, `^_getk `).

**Alignment caveat for throughput fixtures:** the batched routine has no
clipping, so bench positions must stay in-bounds and cell-aligned (x even, y
mult-3, and `y/3 + h/3 - 1 ≤ 24`), or it writes past the grid.

---

## 10. File / symbol index

- `z88dk/libsrc/target/rc700/graphics/rc700_spriteblit.asm` — the blit
  (`sprite_or`/`_sprite_or`). SHIPPED: setgfx-hoist + register-resident mask +
  running base pointer.
- `z88dk/libsrc/target/rc700/graphics/rc700_pixel6.inc` — the per-pixel sextant
  primitive; source of the address/revmap/forward-map logic the blit reuses.
- `z88dk/libsrc/target/rc700/graphics/textpixl6.asm` — `textpixl` (mask→glyph).
- `z88dk/libsrc/target/rc700/generic_console.asm` — `rc700_rowaddr`, `setgfx`,
  `GFXMODE`, `RC700_DISPLAY`.
- `z88dk/libsrc/classic/gfx/narrow/__generic_putsprite.asm` — the generic
  per-pixel renderer (the comparison baseline).
- `z88dk/include/games.h` — `putsprite` + sprite API / ortype constants.
- `pixelbench-mame/PROGRESS.md` — the running tracker (lever C/D history, this
  design's summary).
