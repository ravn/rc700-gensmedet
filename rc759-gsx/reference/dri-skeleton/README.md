# DRI GSX-86 monochrome/color memory-mapped-screen skeleton (retrieved copies)

Retrieved 2026-10-31 from retroarchive.org's "unofficial" CP/M archive (17-disk
GSX-86 v1.3 CP/M-86 distribution, individually zipped per disk). Candidate
matches by filename/header content for the skeleton described in
[`../lth-writing-drivers/monmmskc.html`](../lth-writing-drivers/monmmskc.html)
(mono guide, 17 Sept 1983) and
[`../lth-writing-drivers/colrskel.html`](../lth-writing-drivers/colrskel.html)
(color guide, 9 Nov 1983). Retained unchanged (original line endings, DRI
copyright boilerplate intact); no file edited.

## Source URLs and hashes

Index: `http://www.retroarchive.org/cpm/archive/unofficial/binary.html`
("GSX v1.3 for CP/M-86 ... 17 CP/M-86 diskettes").

| Archive | URL | SHA-256 | Disk |
|---|---|---|---|
| `mono.zip` | `.../download/mono.zip` | `800088e9e6b0b563a60887ac6a3b49fb62c85453e69ff21c618680eb725250ab` | "Monocrome Screen Skeleton", disk 10/14 |
| `color.zip` | `.../download/color.zip` | `7a3b189a9278c392d3e63e7267c21044b9c54ea13caafacf56891e0917320b8a` | "Color Memory Mapped Memory Skeleton", disk 8/14 |

Zips kept at `../../scratch/dri-skeleton-search/{mono,color}.zip`. Every file
below was re-verified byte-for-byte against a fresh `unzip` of its archive
immediately before this README was finalized.

## Inventory

`mono/` and `color/` zip-internal timestamp is 1998-07-07 (retroarchive.org's
packaging date, not DRI's authoring date).

`mono/` — `BWMMSKCP.A86` 23,424B (`GSX-86 V1.3 28 Dec 83`, CP/M-86 &
CCP/M-86 device-specific skeleton, `monmmskc.html:85-95`) · `BWMMSKMS.A86`
19,456B (MS-DOS counterpart, secondary) · `MONOMMRE.A86` 25,984B (optimized
common routines) · `MON1MMOB.A86` 31,104B / `MON2MMOB.A86` 25,472B (see
"Packaging differences") · `FONT.A86` 8,192B (guide names compiled
`FONT.OBJ`) · `READ.ME` 896B (`Copyright (c) 1984, Digital Research Inc.`).

`color/` — `COLMMSK.A86` 20,224B (`GSX-86 V1.2 24 Oct 83`, device-specific
skeleton, `colrskel.html:120-146`) · `COLMMRE.A86` 26,496B (optimized common
routines) · `COLMMOB1.A86` 30,976B / `COLMMOB2.A86` 25,216B (see "Packaging
differences") · `FONT.A86` 8,320B (distinct from mono disk's `FONT.A86`,
different size) · `READ.ME` 896B (same copyright boilerplate).

## Authenticity caveat

The DRI 1984 copyright strings are not independent proof of unmodified
provenance — carried through whoever imaged these disks in 1998. Support:
exact filename match to the 1983 guides, in-source build-recipe comments
matching guide prose, matching routine names/conventions. Treat as strong
circumstantial match, not verified chain of custody.

## Packaging differences — do not assume exact equivalence

Guides name compiled objects `MONOMMOB.OBJ`/`COLMMOB1.OBJ`
(`monmmskc.html:85-95`, `colrskel.html:120-146`); disks instead contain
linkable **assembly source** split across two files each
(`MON1MMOB.A86`+`MON2MMOB.A86`, `COLMMOB1.A86`+`COLMMOB2.A86`). An in-file
history comment confirms the same logical component under an earlier
internal name ("four files needed to assemble driver: 1.skelobj1.obj
2.font.obj 3.devspec 4.reasm.a86", `mono/MON1MMOB.A86:9-19`) — a
packaging/version difference, not a proven byte-identical artifact. Date
mismatch: mono guide Sept 1983 vs in-source `28 Dec 83`; color guide Nov
1983 vs in-source `24 Oct 83` — close snapshots, not confirmed exact.

## Test-suite disks: anomaly observed, not retained here

`test_v1/2/3.zip` (disks 12-14, kept only in
`../../scratch/dri-skeleton-search/`, not copied here) were inspected for
`MODETEST.CMD`/`TESTGIOS.CMD`/`SCRN*.CMD`
(`../lth-writing-drivers/tstsuite.html`, 1 Nov 1983). `test_v1.zip`'s
`SCRN*.CMD`/`.SUB` files look intact. `test_v3.zip`'s `MODETEST.CMD` is
14,336 bytes per its zip directory but only 2,959 bytes are non-zero (first
non-zero at offset 928); `TEST3.SUB`/`RUBAND.DOC` extract as binary noise
rather than text. Cause not determined (zip corruption, bad source image, or
upload error are all possible) — not asserted.

## Oracle role (per project directive)

These sources are used as a **semantic oracle** for H1 static-source
comparison: ground truth for GSX GIOS routine names, algorithms, data
layouts, and intended behavior — independent of whether this exact zip
traces byte-for-byte to a DRI master disk. Three things to keep distinct:
(1) the hardware-independent GSX/GDOS contract (register conventions,
escape-dispatch protocol) is oracle-grade regardless of device; (2)
device-specific algorithm bodies (e.g. `concat`'s byte-addressable scanline
formula) are only an oracle for a device sharing that memory layout — H1's
actual pixel layout is independently documented in the PICCOLINE hardware
manual (word-oriented, 16 pixels/word, `notes/03-xios-interrupt-abi.md:74-84`,
`notes/04-gsx11-source-comparison.md:143-150`), which differs from this
skeleton's byte-oriented layout; this is a known RC759 hardware difference,
not an open question; (3) point-release snapshot differences mean routine
names/contract are stable, but exact offsets/tables are snapshot-specific.
No runtime behavior has been exercised anywhere in this work.

Full bounded symbol-level comparison (escape dispatch, concat/line-draw,
glyph rendering, trig table) is in
[`../../notes/06-dri-skeleton-oracle-comparison.md`](../../notes/06-dri-skeleton-oracle-comparison.md).

## Local documentation links

- [`../lth-writing-drivers/monmmskc.html`](../lth-writing-drivers/monmmskc.html) / [`.pdf`](../lth-writing-drivers/monmmskc.pdf)
- [`../lth-writing-drivers/colrskel.html`](../lth-writing-drivers/colrskel.html)
- [`../lth-writing-drivers/tstsuite.html`](../lth-writing-drivers/tstsuite.html) / [`.pdf`](../lth-writing-drivers/tstsuite.pdf)
- [`../../notes/05-dri-skeleton-guides.md`](../../notes/05-dri-skeleton-guides.md) — prior H1-vs-guide naming correspondence
- [`../../notes/06-dri-skeleton-oracle-comparison.md`](../../notes/06-dri-skeleton-oracle-comparison.md) — full symbol comparison
- [`../seasip/README.md`](../seasip/README.md) — separate, disassembled GSX1.1 package (not original DRI source)
