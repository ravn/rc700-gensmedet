# User-supplied GSX-80/86 source tree

## Trailing locator-data reference audit (2026-11-01)

The 42 bytes following the active locator table occupy DATA offsets
722..763. Original binary words decode to four small/large diagonal pairs
followed by 1000,1000,1,1,0. The intended use of these words is unknown.

Static inspection found no explicit H1 instruction reference to that
interval. The original disassembly has just two indexed locator loads,
at CODE offsets 3571 and 3577, using base DATA offset 690.
get_loc_key supplies direction offsets 0,8,16,24, adds a step selector
0 or 4, then reads two words. The union of those reads is exactly
DATA 690..721, excluding the trailing bytes.

Other internal pointer setup and bulk-copy paths were inspected:
palette copies, input-mode initialization, identification/console output,
glyph streams, sine/fill tables and polygon scratch start elsewhere.
XIOS initialization receives the GCB address at DATA 1420, not this block.
No alternate consumer was found. This is a static reference result, not
a runtime watchpoint proof: caller-provided aliasing pointers, corrupted
indices or stack exhaustion could access memory outside intended ranges.
Do not delete these bytes while preserving original binary identity.

## Follow-up driver analysis (2026-11-01)

There are 45 subdirectories under `dd/` excluding the shared `s/` directory.
Across `dd/`, 144 source files have extensions .asm (42), .a86 (38),
.r (27), .rat (22), or .c (15). These are source-file counts, not counts
of independently working drivers. Families include IBM, Orchid, PC Plus,
Tektronix 40xx, GraphOn, printers, plotters and terminal drivers.

### Strongest additional oracles

All paths below are relative to `scratch/gsx80_86/`. The inspected IBM C,
IBM pixel assembly, Orchid C, printer primitive Ratfor and GraphOn 2b
Ratfor files each have one SCCS delta (1.1), one `I 1` body and no deleted
weave blocks. Findings from those bodies are not competing revisions.

| Source and lines | Verified knowledge | Use for H1, with limits |
|---|---|---|
| `dd/ddibm/s/sddibm.c:937-1071` | `ddfill` gathers scanline intersections, handles repeated vertices, sorts, fills pairs, and phases pattern rows relative to coordinate zero. | Independent high-level explanation of H1's scanline architecture, not identical endpoint or rounding behavior. |
| `dd/ddibm/s/sddibm.c:1073-1195` | `ddsort` is bubble sort; `ddint` rejects horizontal edges and handles endpoint intersections before an integer line walk. | H1 sub_84Bh combines intersection calculation and sorted insertion instead; do not rename it ddsort or claim identical code. |
| `dd/ddibm/s/syyibm.a86:143-198` | `ddflin` rotates a 16-bit row mask and applies `bitblt` for every pixel, including pattern-zero background pixels; includes both span endpoints. | Explains why zero pattern bits still enter writing-mode logic. H1 rotates right/consumes the low bit, rather than IBM's left/high-bit convention. |
| `dd/printer/s/sddprim.r:492-670` | Ratfor `ddfill` has 4x8 row masks, duplicate-vertex handling, sorted intersections and paired horizontal spans. | Useful readable scan-conversion oracle; H1 has 8x8 tiles, different row ordering and clipping/endpoint rules. |
| `dd/ddgn2b/s/sddgn2b.r:1219-1232` | Only XOR is selected specially; other requests are coerced to replace and returned as the realized mode. | Confirms that mode support is device-specific. It cannot settle H1's pixel-LUT truth tables. |
| `dd/ddorch/s/sddorch.c:12-48` | Authored C GIOS explicitly targets IBM PC with Orchid graphics hardware and shares five four-row pattern types. | Additional raster-driver reference, not RC759-specific hardware evidence. |

### Font and rotation differences

IBM's embedded `fntary[768]` is a bitmap font
(`dd/ddibm/s/sddibm.c:1407-1504`). Its text routine exchanges axes for
90/270 degrees and uses four direction-table entries (`:1517-1537`).
It is not H1's signed-nibble vector font or arbitrary-angle sine transform.

The separate Hershey library is also not H1's encoding. In
`fonts/s/shshrec.r:145-163`, `upe64w` derives a move/draw flag from the sign
of a 16-bit word and decodes coordinates with division/remainder by 128
and a bias of 64. H1 instead packs two signed four-bit coordinates in one
byte and uses 80h/88h stroke/glyph sentinels.
This routine is inside the original `I 1` body outside subsequent changes;
the file as a whole has three revisions. `shshini.r:32-41,62-71` separately
records the change from hershy.tbl to graphz.tbl.

### Practical conclusions

Use these sources to document the stages of H1 polygon fill and to design
tests around horizontal edges, shared vertices, span endpoints, pattern
phase and zero-pattern pixels under each writing mode. Keep algorithm
roles separate from implementation identity: H1's sorted insertion and
division-based intersection are not IBM's bubble sort and line walk.

No exact H1 source ancestor, matching vector-font bytes, or explanation of
the 42-word identification count was established in this analysis.
No H1 code was changed, no historical file was compiled, and no source
files were copied out of the supplied tree. Restrictive historical notices
remain intact; this note records analysis rather than redistributing code.

Inspected 2026-10-31 at `scratch/gsx80_86/`, after the user copied the
collection into the workspace. This note records local findings only;
the source files were not edited, built, uploaded, or redistributed.
Their original archive URL and chain of custody have not been supplied.

## What is present

The tree contains 689 files (local `find -type f` count), approximately
6 MB allocated on disk, across `access10`, `dd`, `fonts`, `graph`, `gsx`,
`io`, `kernel`, `plot`, `tools`, and `util`.

These are not simply flat build-ready source files. The inspected `s/`
files contain SCCS history records and control-A insertion/deletion markers.
For example, `dd/s/sskeldd.r:1-11` records revision 1.1 dated 1983-03-24,
then opens a source insertion. `plot/s/ssincos.r` has multiple revisions,
including deleted and replacement definitions.
Do not compile raw history files or remove control lines blindly: extracting
a revision requires interpreting the SCCS weave so that deleted source is
not retained alongside its replacement.

## Relevant verified files

| File relative to scratch/gsx80_86 | Evidence / role |
|---|---|
| `dd/s/sskeldd.r` | Ratfor-style skeleton driver; header describes testing and GSX parameter arrays (`:12-54`) |
| `dd/ddibm/s/sddibm.c` | IBM monochrome GIOS **C source**, not disassembly (`:12-32`); header identifies Computer Innovations C and assembly helpers for far pointers (`:43-48`) |
| `dd/ddibm/s/sddibm.vsn` | Embedded release text: IBM high-resolution monochrome, V1.1, 18 Mar 83 (`:12-16`) |
| `dd/ddibm/s/saaibm.a86`, `syyibm.a86` | Assembly files present alongside the IBM C source; not yet analyzed |
| `gsx/gsx86/s/sgsx.a86` | GSX loader/dispatcher source with SCCS revisions dated 1983-03-17 (`:1-8`) and public GSX entry symbols (`:17-22`) |
| `fonts/s/shshini.r` | Vector-font initialization; revision changes font filename from hershy.tbl to graphz.tbl (`:32-41,62-71`) |
| `plot/s/ssincos.r` | Floating-point sine/cosine routine with 19 samples and five-degree linear interpolation (`:18-50,52-96`) |

`sddibm.c` gives a direct authored-language reference for this IBM driver.
Seasip's GIOS11 README conjectures a high-level language, "likely RATFOR";
that conjecture must not override the C source now available locally.
Exact source-to-GIOS11-binary correspondence has not yet been checked.

## Sine routine is not H1's table

The copied `plot/s/ssincos.r` uses a real-valued angle, a 19-element real
sine table at five-degree spacing, quadrant sign/direction arrays, and linear
interpolation. H1 instead uses 91 integer words at one-degree spacing, scaled
by 2048, with quadrant reflection and no such interpolation.
The routines share a mathematical strategy, but are **not the same data
layout or implementation**. This file alone does not establish H1 ancestry.

Likewise, `shshini.r` describes loading an external vector-font table. H1's
embedded signed-nibble glyph streams have not been matched to that format.

## Relationship to retained developer skeletons

The separately downloaded later DRI assembly skeletons are retained under
`reference/dri-skeleton/`; see
[the skeleton comparison](06-dri-skeleton-oracle-comparison.md).
The user-supplied tree adds an earlier source-history collection with IBM C,
Ratfor-style code, and assembly. Keep these packages distinct, including
their versions, hardware-specific implementations, and source languages.

Further extraction/building and wholesale label changes were not performed
in this initial inventory. The historical source headers include restrictive
license/confidentiality notices; retain them and do not assume the public
availability of related archives grants new redistribution rights.
