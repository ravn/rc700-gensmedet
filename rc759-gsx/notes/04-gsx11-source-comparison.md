# RC759 H1 compared with historical GSX-86 sources

Analysis date: 2026-10-31. No driver instructions or data were changed.
The H1 reconstruction remains identical to the original 8,576-byte SYS.

## Evidence and limits

The retained references and archive hashes are in
[`reference/seasip/`](../reference/seasip/README.md). Paths below abbreviate
that directory. RC addresses are **CS/DATA offsets**, not file offsets;
CODE starts at file `0080h`, DATA at `10C0h`.

GIOS11 contains disassembled sources of five DRI/GSS implementations, not
original authored source (`gios11/README.TXT:4-10,23-35`). Its modern video-mode
ports and FreeGEM are excluded. GDOS 1.3 is a separate ABI reference, not proof
of the exact GDOS version used with H1.

**Known:** shared GSX interface and several matching semantic operations.
**Not established:** common binary ancestry, original implementation language,
the meanings of other RC759 suffixes, or graphics correctness at runtime.
Agreement between two drivers is an equivalence check, not proof that both
conform to the GSX specification.

## 1. Parameter block, stack and dispatch

Both interfaces use five far pointers, occupying **20 bytes**:

| PB offset | Array | H1 stack pointer slot |
|---|---|---|
| `00h` | contrl | `BP+2` |
| `04h` | intin | `BP+6` |
| `08h` | ptsin | `BP+0Ah` |
| `0Ch` | intout | `BP+0Eh` |
| `10h` | ptsout | `BP+12h` |

H1 starts at `DS:DX+12h`, the **segment word of the ptsout pointer**, then
uses `STD/LODSW/PUSH` ten times. It reads offsets `12,10,0E,...,02,00`,
leaving the five pointers in normal order above saved BP. It does **not**
copy the contrl array. `POP BP` and `ADD SP,14h` separately discard saved BP
and the 20 pointer bytes. The earlier source annotation was wrong.

GIOS11 instead copies ten words forward into `p_contrl` and four following
pointer slots (`COMMON0.INC:47-67,5782-5786`). It caches the DATA segment and
has an initialization/BSS and stack-frame wrapper (`COMMON0.INC:10-67`).
H1 has a much smaller wrapper, explicit segment fixups, stack `0791h`,
and direct near-pointer dispatch through `DATA:0100`.

GDOS 1.3 independently consumes the same five PB slots
(`gdos13/GSX.A86:561,567,577,612,639`), rasterizes input points and converts
output points back (`:887-1000`). For nonzero point counts, this path scales
coordinates; the shown transform does not invert Y. H1's own address routine
does invert Y. A future test must distinguish GDOS coordinates from raw driver
coordinates instead of assuming that a direct driver call is equivalent.

## 2. Workstation tables have established meanings

`OPEN_WORKSTATION` copies 45 words at `DATA:04B2` to intout and 12 words at
`DATA:050C` to ptsout. These correspond to GIOS11's `DEV_TAB` and `SIZ_TAB`
(`COMMON0.INC:340-398,5815-5860`). The GSX Programmer's Guide independently
defines them, Appendix C, Open Workstation, pages C-4..C-7
(`docs/gsx86-programmer-manual-retrobrew.txt:2280-2455`).

Selected **original H1 binary values**, using the guide's one-based indexing:

| Output | Value | Meaning |
|---|---:|---|
| intout(1..2) | 559, 255 | Maximum coordinates -> 560 x 256 rasters |
| intout(3) | 1 | Device coordinate-units flag; not a geometry dimension |
| intout(4..5) | 392, 578 | Pixel width/height in micrometers |
| intout(6) | 232 | Number of character heights |
| intout(7..8) | 7, 1 | Line types and line widths |
| intout(9..10) | 5, 232 | Marker types and marker sizes |
| intout(11..14) | 1, 6, 6, 2 | Fonts, patterns, hatch styles, simultaneous colors |
| intout(15..16) | 1, 1 | One GDP: number 1, bar |
| intout(17..25) | -1 | No further GDPs |
| intout(26) | 3 | Bar uses fill-area attributes |
| intout(36..39) | 1, 1, 1, 0 | Color, text rotation, fill area, no read-cell-array capability |
| intout(40) | 4 | Advertised palette size; not four bitmap planes |
| intout(41..45) | 1, 1, 1, 1, 2 | Locator/valuator/choice/string counts; input/output workstation |
| ptsout(1..4) | 0, 7, 0, 210 | Min/max character height pairs |
| ptsout(5..8) | 1, 0, 1, 0 | Min/max line width pairs |
| ptsout(9..12) | 0, 6, 0, 180 | Min/max marker height pairs |

These are **advertised capabilities**, not all demonstrated behavior.
H1 opcode 27 (cell-array inquiry) is `RET`, consistent with intout(39)=0.
Valuator input is opcode 29 at CS:0E47, not opcode 27.
GDP dispatch at `DATA:016E` has `RET` entries for GDP 2..5; only bar is
advertised, so those entries are not evidence of working arcs or circles.
GIOS11 likewise advertises just bar (`COMMON0.INC:5829-5839`).

## 3. The supposed font-metrics table is a sine table

All **91 words** at `DATA:03FC..04B1` equal
`round(2048 * sin(angle_degrees))`, for angles 0..90.
Checked independently using Python `math.sin` against the original SYS:
zero differing words; maximum unrounded error approximately `0.495`.
Examples: 0 -> 0, 30 -> 1024, 90 -> 2048.
The first zero word occupies an implicit source gap at `03FCh`; the explicitly
initialized bytes begin at `03FEh`, which made the table easy to misidentify.

`CS:06D7` divides the input angle by 90, then `CS:06EA` reflects the table
index and changes signs by quadrant. It returns sine in CX and cosine in DX.
At angle 0, CX=0 and DX=2048; at 90, CX=2048 and DX=0.

This corrects several misleading variable comments:

| DATA | Existing source label | Established role |
|---|---|---|
| `03DE,03E0` | v_dev_height, v_dev_height2 | Text sine/cosine, scaled by 2048 |
| `03E2` | v_marker_sz_w | Text scale |
| `03E4,03E6` | v_dev_height3, v_dev_height4 | Marker sine/cosine |
| `03E8` | v_marker_sz_h | Marker scale |
| `03EA..03EE` | v_marker_tmp_* | Current transform coefficients and scale |

They are **not screen dimensions**. `CS:0AF6` converts the requested text angle
from tenths of a degree to rounded whole degrees before calling the helper.
`CS:0637` applies the rotation/scale to glyph points; `CS:066F` applies it
to text advance with six extra shifts. Text origins at `DATA:03F8/03FA`
are kept with six fractional bits during a string.
GIOS11 uses small direction tables for bitmap-text orientation
(`COMMON0.INC:2241ff,5890-5893`); it is not an interchangeable font renderer.

## 4. Vectors, not downloaded character-generator glyphs

H1 `CS:05AE` uses 128 word offsets at `DATA:0792..0891` to find streams at
`DATA:0892..0C3A`. Each ordinary byte contains two **signed four-bit**
coordinates: high nibble X, low nibble Y. `80h` ends a stroke and starts a
new one; `88h` ends the glyph. Decoded points use scratch `DATA:0316`.
`CS:0623` draws each stroke through the existing polyline renderer.

Concrete marker-2 stream at `DATA:08A4`:
`D0 30 80 0D 03 88` -> stroke `(-3,0)..(3,0)`, then
`(0,-3)..(0,3)`. Text and markers share this decoder; it is not merely
a text-font table. `CS:050F` substitutes space for input characters >127.

GIOS11 IBM `FONT.INC` contains eight bitmap bytes per character, and
`COMMON0.INC:5379-5757` renders scaled bitmap text.
The NEC 7220 driver is not a closer replacement: it sends GDC commands
(`DDCSA1.A86:17-48`, `CSA10.INC:2456-2490`) and does not support filled areas
(`README.TXT:18-20`). No matching RC759 vector-font ancestry was established.

## 5. Pixel operations: semantic similarity with important qualifications

H1 `CS:046A` calculates:

```text
byte_offset = 2 * ((X div 16) * 256 + (255 - Y))
bit_mask    = 1 << (15 - (X mod 16))
```

Moving to the next X word adds `0200h` bytes; a Y step changes the offset by
two bytes. `CS:034D` is an integer-error/Bresenham-like line renderer,
not a character-cell upload routine.
The PICCOLINE guide §4.5.1/4.5.3 independently documents the GCB and exclusive
bitmap access (`docs/PICCOLINE_Programmers_Guide_v2.txt:2189-2231,2298-2339`).
Its semaphore example is particularly close to H1:
`XCHG` with `FFh`, delay one tick if occupied, clear after drawing.

H1 `CS:0492` selects a four-byte truth table by writing mode and color.
`CS:044A` indexes it with `2*pattern_bit + old_pixel`, duplicates the selected
`00h/FFh` byte into a word, masks the target bit, and XORs it into the bitmap.

All **32 combinations** of four modes, two colors, two pattern bits and
two old pixels match the independent instruction expressions from IBM
`DDIBM.A86:315-355`:

| Mode | H1 and IBM actual binary operation |
|---|---|
| 1, replace | `new = color & pattern` |
| 2, transparent/OR | `new = old OR (color & pattern)` |
| 3, XOR | `new = old XOR (color & pattern)` |
| 4, erase | `new = old AND NOT (color & pattern)` |

**This is not blanket GSX conformance.** The Programmer's Guide pages C-57..58
(`gsx86-programmer-manual-retrobrew.txt:4770-4850`) says transparent mode
replaces selected pixels with FORE, and erase uses BACK independently of FORE.
For color=0, pattern=1, old=1, both monochrome drivers leave the pixel at 1
in modes 2 and 4, whereas those published expressions with BACK=0 give 0.
That difference was observed in static instruction/table modeling, **not**
in a running graphics application. Whether it is an accepted historical
monochrome convention or an application-visible defect remains unverified.
No behavior was "corrected" to match either reference.

Related corrected state comments: `DATA:01B7` is GSX writing mode,
`01B9` is a truth-table pointer, `01BF` is the rotating line/fill pattern,
and `058C` is the XIOS GCB semaphore. `DATA:02B0`, despite its old
`v_write_mode` name, selects locator movement tables (`CS:0DB3/0E08`).

## 6. Line masks and polygon-fill tiles are device-specific

H1's seven masks at `DATA:01C3` are:
`FFFF,007F,1C1C,1C7F,0FFF,3333,5555`.
IBM's are `FFFF,F00F,8888,E10F,C3C3,E247,9999`
(`COMMON0.INC:5883-5889`). A shared line-type number does not imply the
same dash lengths or phase. H1 avoids some shared polyline endpoints in XOR
mode (`CS:0337`); endpoint tests must preserve this detail.

Both implementations collect scanline/edge intersections and draw paired spans:
H1 `CS:0706/084B`, IBM `COMMON0.INC:4070-4540`.
H1 sorts into the same `DATA:0316` scratch used by glyph decoding.
Its tiles at `DATA:0524..058B` are **13 eight-byte, 8x8 patterns**:
solid, six hatch and six halftone tiles. Interior style 2 adds six to the
tile index; style 3 does not. Polygon fill reverses the row index and rotates
the duplicated byte by X phase; bar has its own row traversal.
IBM has five four-word/16-bit pattern rows (`COMMON0.INC:5794-5800`).
The scanline conventions and pattern layout must not be substituted blindly.

H1 palette set/inquiry are implemented (`CS:0B20/0CDA`) and use XIOS palette
function 31, unlike the reference package's deliberately unimplemented palette
operations (`README.TXT:41-42`). They are not font uploads.
There are eight interrupt sites: four XIOS and four BDOS/CCP/M.

## Verification and remaining boundary

The only H1 source changes are annotations. Rebuilt using current emu2 through
`sh tools/build.sh`: RASM-86 zero errors, LINK-86 8,576-byte CMD.
`tools/compare_sys_cmd.py` and independent `cmp` both match the original,
including all five relocation records and trailer padding.
Artifact: `scratch/emu2-current-20261031-224305/dd759h1.cmd`.
Both SHA-256 hashes:
`dcbe221f5efc105c9f983f63d31327a7a39df0739d9c050a110d917dbe8eddfe`.
All 21 retained reference files were compared byte-for-byte with archive entries.

No new MAME graphics run was performed. The comparisons establish a better
interpretation of H1's bytes, not a complete runtime graphics oracle.
High-value future oracle cases are XOR shared endpoints, all four writing modes
including color zero, rotated text, polygon extrema, and pattern phase.

Follow-up: [DRI's 1983 skeleton guides](05-dri-skeleton-guides.md) identify
the original package filenames, document MODETEST for both pen values, and
expose off-by-one ESCAPE labels in the reconstructed source.
