# DRI skeleton source as oracle: bounded symbol comparison vs H1

## Applied H1 symbol alignment

After committing the reference research, the rebuildable `src/dd759h1.a86`
was aligned with the verified roles. Historical `sub_*`/`v_*` names cited
below refer to the pre-rename source; CS/DATA offsets remain unchanged.

| Previous label | Current label / role |
|---|---|
| sub_34Dh, sub_46Ah | abline, concat (DRI skeleton role names) |
| sub_44Ah, sub_492h | plot_pixel, load_pixel_lut (RC759-specific mechanism) |
| sub_5AEh, sub_623h | draw_vector_glyph, draw_glyph_stroke (not bitmap draw_char) |
| sub_637h, sub_66Fh | transform_glyph_point, transform_text_advance |
| sub_6D7h, sub_6EAh | sincos_degrees, sin_quadrant |
| sub_DB3h | get_loc_key (DRI skeleton role name) |
| sub_FF2h, sub_100Ch | get_gcb_mutex, free_gcb_mutex |
| sub_1012h, sub_102Bh | init_graphics, exit_graphics |
| v_init_flag, v_polyline_mask | writing_mode, pixel_lut |
| v_cursor_vis, v_write_mode | draw_pattern, locator_step_offset |
| v_dev_height family | text_sine/text_cosine, marker_sine/marker_cosine |
| v_gfx_active, v_gcb_seg | gcb_mx, gcb_seg |

ESCAPE handlers now use the guide's `escfn0..9` and `escf10..19` names,
with the correct actual subfunction numbers and row/column descriptions.
Declaration-site labels identify DEV_TAB, SIZ_TAB, sine_table, line_types,
bit_masks and fill_tiles without fixed-address EQU aliases. All 90 ORG
directives were subsequently removed: sections are sequential, with RB for
actual gaps and trailing padding, including EXTRA. The previously documented
EXTRA RB failure did not recur in the current toolchain.
Numeric dispatch entries are intentionally retained to avoid new LINK fixups.

RASM-86 reported zero errors; LINK-86 emitted 8,576 bytes.
`scratch/emu2-current-20261031-233945/dd759h1.cmd` matches the original SYS
in every byte, verified with comparator and independent cmp, including all
groups and the relocation trailer. This establishes unchanged behavior through
identical machine code/data; no new graphics-runtime validation was claimed.

Per 2026-10-31 user directive, the retrieved DRI GSX-86 skeleton sources
(`reference/dri-skeleton/{mono,color}/`, provenance and caveats in
[`../reference/dri-skeleton/README.md`](../reference/dri-skeleton/README.md))
are used here as a semantic oracle for routine names, algorithms, and data
layout — not as proof of ancestry. All findings below are static source
reading only; no runtime behavior was exercised on either side.

## concat: address arithmetic and mask lookup are two separate mechanisms

Skeleton `concat` (`reference/dri-skeleton/mono/BWMMSKCP.A86:598-618`):
masks X to 10 bits, normalizes Y against `yresmx`, computes a byte offset by
`(normalized_y >> 1) * bytes_line + (x >> 3)`, adds `next_line` if the row is
odd, and leaves the **address** in DI and the **bit-within-byte index**
(0-7, from the 3 masked-off low bits of X) in BX. No table is used anywhere
in this routine; it is pure arithmetic, consistent with a contiguous
byte-addressable scanline memory layout (`monmmskc.html:51-76`).

H1's equivalent, `sub_46Ah` (`src/dd759h1.a86:593-610`), entered with BX/DX
holding a coordinate pair (callers at `:473,483,557` pass `x1/x2` or
`y1/y2`): computes a **strip base** by `bx AND 0FFF0h` (clearing the low 4
bits), left-shifts it by 4, adds a `0FFh - dx` term, shifts left once more,
and leaves that value in DI as the address — this part is, like the
skeleton, pure inline arithmetic, not a table lookup. Separately, the low 4
bits of the *original* BX (the position within a 16-pixel strip) are used to
index a table at `01D1h`, and the table result (a mask, consumed by the
pixel-toggle routine `sub_44Ah` at `:570-583` via `AND`/`XOR` against
`es:[di]`) is left in BX. So: **address = arithmetic, strip-based; mask =
table lookup, indexed by bit-position-within-strip.** These are exactly the
same two roles the skeleton's `concat`+`ortbl` convention uses (address via
arithmetic, OR-mask via table indexed by bit position), but H1's strip is 16
pixels wide against a 16-entry table at `01D1h`, where the skeleton's unit
is 8 pixels (one byte) against `ortbl`.

H1's 16-pixel-wide strip is not an unexplained artifact of the comparison —
it is the documented RC759 hardware pixel format: PICCOLINE §4.5.4 states
1 bit/pixel, word-addressed, 16 pixels per word
(`notes/03-xios-interrupt-abi.md:74-84`: `word_address = (X div 16)*256 +
(255-Y)`, `bit_mask = 1 << (15 - (X mod 16))`), independently confirmed in
`notes/04-gsx11-source-comparison.md:143-150` by decoding `CS:046A` itself.
This is a **known hardware-driven layout difference** from the skeleton's
byte-oriented, 8-pixel-wide convention — not speculation about why the
arithmetic differs. The shared idiom (mask-lookup-by-bit-position, address
by separate arithmetic) is a genuine structural parallel to the skeleton's
`concat`+`ortbl` convention; it is not a claim that H1's specific arithmetic
terms were derived from this skeleton's specific arithmetic terms, and no
runtime check confirmed either routine's output against real pixel
coordinates.

## abline vs H1 line renderer: algorithmic correspondence, KNOWN H1 routine

`abline` (`reference/dri-skeleton/mono/MONOMMRE.A86:322-345`) implements
Bresenham's algorithm (comment at `:315`, "using Bresenham's algorithm"),
calls `concat` for the initial pixel address (`:329`), and walks an OR-mask
table (`offset ortbl`, `:330-332`) to set/step bits along the line.

H1's line renderer is identified: `sub_34Dh` at `src/dd759h1.a86:462` (org
`034Dh`), called from `op06_POLYLINE` (`:411-446`, GSX opcode 6, table entry
`dw 02D7h` at `:2017`) once per segment (`:437-443`), and reused directly by
the glyph decoder (`sub_623h`, `:783-789`, which sets up points and calls
`op06_points`) and by three cursor/caret-drawing sites (`:1238,1246,1254,
1262`). `sub_34Dh` (`:462-540` approx.) computes `dx`/`dy`, determines the
major axis, sets a signed line-step constant (`v_line_step`,
`word ptr 0FFFEh` or `2`, `:490-494`), and calls `sub_46Ah` (`:473,483`) to
turn each endpoint coordinate into an address+mask pair before stepping —
i.e. this **is** a Bresenham-style major/minor-axis line walker using the
address+mask convention analyzed above, not merely a "same general class"
routine. This is a KNOWN, verified H1 routine (not inferred from the
skeleton): identified independently by its opcode-table entry, its callers,
and its major/minor-axis arithmetic. The correspondence to the skeleton's
`abline` is algorithmic (both are major/minor-axis incremental line
walkers over an address+mask pixel-plot primitive) — this is not a claim
that H1's specific step logic was copied from this specific skeleton
snapshot.

## draw_char vs H1 glyph renderer: H1 uses vector strokes, not a bitmap blit

`draw_char` (`reference/dri-skeleton/mono/MONOMMRE.A86:88-239`) blits an
8x8 (or similar) font cell using a per-bit OR-table indexed via
`offset ortbl` (`:91-92`) and a `char_mode` write-mode test (`:97`) — a
**bitmap** font renderer, consistent with this skeleton targeting a
memory-mapped bitmap screen.

H1's glyph renderer is a different kind of mechanism entirely, and it is
KNOWN rather than merely algorithmically similar: `sub_5AEh`
(`src/dd759h1.a86:735-736`, called from the text-output path at `:662,720`)
is a **signed-nibble stroke decoder**, not a bitmap blit. It reads font
data a byte at a time (`lodsb`, `:745`), treats each byte as two signed
4-bit (nibble) deltas — `and ax,000Fh` / sign-extend via `or ax,0FFF0h` if
bit 3 is set for Y (`:752-756`), same pattern shifted for X (`:758-764`) —
accumulates them as relative pen moves into a point list at `0316h`, and on
a stroke-terminator byte (`cmp al,88h`/`80h`, `:746-749`) calls `sub_623h`
(`:783-789`), which hands the accumulated point list to `op06_points`
(the same polyline point-walking code `abline`/`sub_34Dh` above uses) to
actually draw the glyph as connected line segments. Each point is also run
through the rotation/scale transform `sub_637h` (`:760`, detailed below)
before being drawn, so rotated/scaled text is literally drawn as rotated
line strokes, not as a rotated bitmap.

**There is no bitmap `draw_char` equivalent in H1**: H1 renders characters
as vector strokes through the same line-segment renderer used for
polylines, which is a structurally different font representation from the
skeleton's fixed 8x8 bitmap-cell blit. This is a verified architectural
difference (confirmed by reading `sub_5AEh` and its call chain), not an
unidentified gap.

## Trig table: KNOWN H1 usage (text and marker transform), absent from skeleton

H1's trig table is not a mystery requiring further search: it is
established in `notes/04-gsx11-source-comparison.md:91-117` that
`DATA:03FC..04B1` is a 91-word sine table (`round(2048*sin(angle))` for
0..90 degrees, verified word-for-word against Python `math.sin`), and that
its consumers are KNOWN and already named:

- `op13_SET_CHAR_UP_VECTOR` (`src/dd759h1.a86:1305-1306`, org `0AF6h`, GSX
  opcode 13, table entry `dw 0AF6h` at `:2024`) converts the caller's
  requested text angle (tenths of a degree, `:1310-1314`) to whole degrees
  and calls `sub_6D7h` (`:860`, cited as `CS:06D7` in `notes/04:101`) to
  look up sine/cosine for that angle (returned in CX/DX per `notes/04:102`).
- `sub_637h` (`src/dd759h1.a86:794-811`) applies that rotation/scale (via
  the `v_marker_tmp_x`/`v_marker_tmp_y` coefficients, `notes/04:113`) to
  each decoded glyph point — this is called directly from the stroke
  decoder `sub_5AEh` at `:760`, i.e. **text rotation runs through the sine
  table on every glyph point**.
- `sub_66Fh` (`src/dd759h1.a86:813-...`) applies the same
  rotation/scale to text advance/marker geometry (`notes/04:117`).

So: H1's trig table is KNOWN to drive text-angle and marker transforms,
not an open question of "does GDP use it."

What remains correctly unresolved is only whether this specific retained
skeleton package (mono/color disks, Dec83/Oct83 snapshots) is where that
trig table's DRI source originates. A targeted search of every retained
`mono/*.A86` and `color/*.A86` file for the literal substrings `sin`,
`cos`, `2048`, `0800h`, `90`, `sintbl`, `costbl` found **no genuine
trigonometric table or sine/cosine routine** — the only hits on `sin` are
the substring `ptsin` (the GSX point-input array parameter name, e.g.
`mono/MON1MMOB.A86:85,95,249,265`, declared at `mono/MON2MMOB.A86:796,877`),
an unrelated false-positive, not a trigonometry reference. This skeleton's
own text-rotation mechanism (`mono/MON1MMOB.A86:1213-1243`, calling
`rotate_raster` at `:454-527`) is instead **discrete**: three fixed
90-degree-step bitmap-cell rotations (`rotate_left`/`rotate_right`/
`rotate_upside`), not a continuous-angle transform — a different mechanism
from H1's sine-table-driven vector rotation, consistent with H1 rendering
text as vector strokes (above) rather than rotating fixed bitmap cells.

So the finding is: H1's trig table's *role* is fully known and verified
(text angle + marker transform, via `sub_6D7h`/`sub_637h`/`sub_66Fh`/
`op13_SET_CHAR_UP_VECTOR`); what is unresolved is only the narrower
question of *provenance* — whether a DRI original source for this table
exists on some other disk, which the retained mono/color disks do not
settle either way since they don't contain a trig table at all.

## escfn dispatch: closest verified structural match

Skeleton `escape` handler (`mono/MON1MMOB.A86:230-240`): reads escape
number from `contrl` word index 6 via `es:W_6[di]`, where
`W_6 equ word ptr 10` (`mono/BWMMSKCP.A86:51`, part of the `W_1..W_6`
byte-offset equate table at `:46-51`, i.e. byte offset 10 = `0Ah`), calls
`check_escape` (`mono/BWMMSKCP.A86:158-163`, bounds against
`last_dri_escape equ 19`, `:81`), doubles the index, and calls through
`esctbl` (`mono/MON2MMOB.A86:852-862`).

H1 dispatcher (`src/dd759h1.a86:207-215`): reads escape sub-function number
from `es:0Ah[di]` — offset `0Ah` = 10 decimal = word index 5 (0-based) /
word 6 (1-based), matching the skeleton's `W_6` word position exactly —
bounds-checks against `013h` (19 decimal, the same constant as
`last_dri_escape`), doubles the index (`shl bx,1`), and jumps through a
table at `DATA:0146`. Register (BX), source offset (0Ah), bound (19), and
doubling-then-table-dispatch shape all match. This remains the strongest
verified structural correspondence found between H1 and this skeleton
package, consistent with both implementing the same GSX-core-facing escape
protocol (role 1 in the README's oracle-usage breakdown), independent of
whether H1 descends from this specific disk.

## Summary table

| Symbol | Skeleton location | H1 location | Correspondence |
|---|---|---|---|
| escape dispatch | `mono/MON1MMOB.A86:230-240`, `mono/MON2MMOB.A86:852-862`, bound `mono/BWMMSKCP.A86:81,158-163` | `src/dd759h1.a86:207-215` | Strong: same offset (0Ah), same bound (19/013h), same double-and-table-dispatch shape |
| concat (address) | `mono/BWMMSKCP.A86:598-618`, arithmetic only | `sub_46Ah` arithmetic half, `src/dd759h1.a86:596-603` | Both pure arithmetic; different formulas (contiguous scanline vs 16-pixel strip) |
| concat (mask) | implicit bit index in `concat`, consumed via `ortbl` in `abline`/`draw_char` | `01D1h[bx]` table lookup, `src/dd759h1.a86:609`, consumed by `sub_44Ah` | Same idiom (table indexed by bit-within-unit), different unit width (8 vs 16) |
| abline | `mono/MONOMMRE.A86:322-345` | `sub_34Dh`, `src/dd759h1.a86:462` (org `034Dh`), called by `op06_POLYLINE` `:411-446` and glyph decoder `sub_623h` `:783-789` | Algorithmic match: both are major/minor-axis Bresenham-style line walkers over an address+mask pixel-plot primitive; H1 routine identity is KNOWN, not inferred from skeleton |
| draw_char | `mono/MONOMMRE.A86:88-239`, bitmap 8x8 cell blit via `ortbl` | `sub_5AEh`, `src/dd759h1.a86:735` — signed-nibble stroke decoder feeding the line renderer, NOT a bitmap blit | Verified architectural difference: H1 draws glyphs as vector strokes through the polyline renderer; no bitmap `draw_char` equivalent exists in H1 |
| trig table | not present in retained mono/color sources (searched, confirmed absent) | `DATA:03FC..04B1`; consumers KNOWN: `op13_SET_CHAR_UP_VECTOR` `:1305-1306`, `sub_6D7h` `:860`, `sub_637h` `:794-811`, `sub_66Fh` `:813` (`notes/04-gsx11-source-comparison.md:91-117`) | H1's trig-table role (text angle + marker transform) is fully established; only its DRI source-file provenance (not its function) is unresolved, since it is absent from these two disks |
