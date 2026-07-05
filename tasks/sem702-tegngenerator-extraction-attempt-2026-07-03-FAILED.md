# SEM702 "Tegngenerator" extraction attempt — FAILED / parked (2026-07-02..03)

**Status: FAILED.** Confirmed by the user (2026-07-05): this was "et forsøg der
mislykkedes på at få kode der programmerede SEM702 i luften" — an attempt that
failed to get code that programmed the SEM702 chargen board live/interactively.

This document is a **best-effort reconstruction from file archaeology**, not a
verified first-hand account — the original working session ran out of context in
a prior agent and left no notes-in-progress inside the directory. Everything
below is inferred from the scratch directory's contents (scripts, disk images,
scanned manual pages, one partial memory dump) plus the surrounding project
context (SEM702 RAM-backed chargen, `sem702-qr-test/`). Treat causal claims
("why it failed") as unverified unless stated otherwise.

## What was being attempted

Recover, understand, or reproduce the original Danish educational RC702
software package that let a user program custom character sets into the
**SEM702** chargen extension board and use them interactively — e.g. to draw
graphics/animations built from custom glyphs (turtle-graphics-adjacent, hence
the directory name `logo-src`). Evidence for this specific target:

- A recovered menu fragment (see below) is literally titled **"RC702
  TEGNGENERATOR"** (Danish: character/sign generator) with entries
  `Tegngenerator`, `Vejledning` (manual/guide), `Demoprogram 1`,
  `Demoprogram 2`, `Stop`.
- Files named `heste.chr` ("horses", a custom character set), `race.prg` /
  `s_race.prg` (a horse-race style demo program), and `hoejdxy.dis`
  (height/xy data) suggest one of the demo programs was a small animated
  horse-race built from custom SEM702 glyphs.
- `diskdefs` defines a custom floppy geometry named `logo5` (512 B sectors,
  70 tracks, 9 sec/track, 2048 B blocks) — presumably needed to read one of
  the source floppies with a non-standard format.

## Approach taken

1. **Gathered COMAL-80 floppy disk images** in several formats (`.imd`,
   `.raw`, `.mfi`) and versions (`comal20`, `comal83`, `comal108[_nl]`,
   `comal113`, `comal117`, `c3572*`, `c3986*`, `save_test*`) — apparently
   trying multiple COMAL releases/variants to find one that shipped with, or
   could load, the Tegngenerator software.
2. **Scanned the original paper documentation**: `comal_manual.pdf` (9.8 MB),
   `comal83.pdf` (19 MB), `extdoc.pdf` (13 MB, likely the RC702 I/O
   *extension* documentation most relevant to SEM702 register access),
   `rc701doc.pdf` (0.6 MB) — backed by ~440 individual page-scan PNGs (e.g.
   `pg-*.png`, `ext64-*.png`, `cal-*.png`). One captured page (`p14_ports.png`,
   manual p.14) is the RC702 port-number table (screen/8275, floppy/765,
   SIO, PIO) — general RC702 I/O reference, not SEM702-specific detail.
3. **Tried to OCR/text-extract the scans** (`comal_manual.txt`, `comal83.txt`,
   `ext.txt`, `p14.txt`) — all four came back as **just page-feed characters
   (`\f`/`0x0C`) with no actual text**, i.e. `pdftotext`-style extraction
   failed because the scans have no OCR text layer. Dead end.
4. **MAME automation via Lua** (28 scripts) to boot the disk images headless
   and drive them like a real user:
   - Keystroke injection via `manager.machine.natkeyboard:post_coded(...)`
     to type COMAL commands / menu selections (`run_seq.lua`, `run_comal.lua`,
     `run_prog.lua`, `findscreen.lua`, version-specific `t3572.lua`/`t3986.lua`).
   - Periodic screenshotting (`vid:snapshot()`) to observe results frame-by-frame.
   - A memory-scanning technique (`findscreen.lua`) that walks the Z80
     `program` address space (`0x4000`–`0xF000`) looking for a marker string
     (`"DIM program"`) to try to locate a loaded BASIC/COMAL listing in RAM
     without needing a working `LIST`/formatting path.
   - A tracing variant (`runtrace.sh` + `load_trace.lua`) that logs memory
     reads around a `LOAD` operation to `/tmp/comal_reads.txt`, presumably to
     reverse-engineer the on-disk/in-RAM program format.
5. **Shell wrappers** (`runmame.sh`, `runtrace.sh`, `run1.sh`, `runc.sh`,
   `trace2.sh`, `xrun.sh`, `listrun.sh`) drove the above against
   `../../mame/regnecentralend` with the `rc702mini` machine and various
   `-flop1` images, iterating across the ~2 days of file timestamps
   (2026-07-02 20:xx through 2026-07-03 02:xx/03:xx).

## What was actually recovered

One partial artifact survives: `out/tegnlogo.n` (1024 bytes, raw memory or
track dump). It contains recognizable plaintext fragments including the
`RC702 TEGNGENERATOR` menu text and its five entries, interleaved with
what looks like BASIC/COMAL line-pointer binary data — i.e. the boot/menu
screen was successfully reached and captured, but this is **not** a clean,
re-loadable program listing or a working extraction of the Tegngenerator's
actual SEM702-driving code.

No decompiled/reassembled source, no working standalone demo, and no
documented understanding of the SEM702 programming sequence came out of
this attempt.

## Why it failed (unverified guess)

Most likely: the combination of (a) many COMAL disk-image variants of
uncertain provenance/compatibility with the `rc702mini` MAME machine, and
(b) no OCR'd manual text to consult programmatically, meant the automation
scripts were essentially guessing keystroke sequences and RAM offsets
blind, with only screenshots and one partial memory scan to go on — an
iteration loop too slow/unreliable to converge before the session ran out
of budget. This is a plausible reconstruction, not a confirmed root cause.

## Disposition

The `scratch/logo-src/` directory (58 MB: 4 scanned-manual PDFs, ~440 page
PNGs, ~15 floppy disk images, 28 Lua scripts, 7 shell scripts, one 1 KB
partial memory dump) has been deleted after writing this summary. Nothing
in it was judged individually reusable enough to rescue (contrast with the
`gdb-z80` cleanup, where two small hand-authored glue files were kept) —
the Lua automation scripts are specific to this failed attempt's guesswork
and the disk images/manual scans are bulk reference material, not authored
work product.

If this is revisited, the two most useful starting points are: (1) get an
actual OCR pass on `extdoc.pdf` (RC702 extension/I/O documentation) since
that's most likely to contain the real SEM702 port/protocol details, rather
than re-scanning; and (2) check whether `rc700-gensmedet/sem702-qr-test/`
(an already-working, committed subproject that paints QR codes via SEM702
sextants) already documents enough of the SEM702 addressing scheme to skip
the reverse-engineering step entirely.
