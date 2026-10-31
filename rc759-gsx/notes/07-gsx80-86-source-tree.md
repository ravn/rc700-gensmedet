# User-supplied GSX-80/86 source tree

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
