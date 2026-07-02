# RcComal80 SEM702 char-set disk — extracted files

Files extracted from the **COMAL 80 rev 1.07 education disk**
([datamuseum Bits:30003268](https://datamuseum.dk/bits/30003268), "COMAL 80
rev.1.07 opgaver + Tegngenerator", *Tommy Borch, FAG, 1983*), 2026-07-02, so the
programs and SEM702 character sets can be loaded onto **other RcComal80 systems**.

Full analysis of the disk, the `.CHR` format, and why the `.PRG` apps need a newer
RcComal80: **`../docs/RC702_COMAL_SEM702_CHARSETS.md`**.

## Layout

- **`charsets/`** — SEM702 RAM char-generator glyph sets (user-definable 8×11
  characters).  Format: **157 records × 13 bytes** = `[0x0b][0x00][11 scan-lines]`.
  - `DIVERSE.CHR` — miscellaneous tiles (trees, houses, fences, symbols).
  - `HESTE.CHR` — horse-figure tiles.
- **`programs/`** — tokenised RcComal80 programs (`09 81 … 31 2F "1/"<name>`
  header; **not** machine code).
  - `CHRHENT.EXT` — the **external procedure** that loads a `.CHR` into the char-gen.
  - `RACE.PRG` — horse race (uses `HESTE.CHR` via `CHRHENT.EXT`).
  - `FUTTOG.PRG` — toy train (uses `DIVERSE.CHR`).
  - `TEGNGEN.PRG` — the character-set **editor**.
  - `TEGNLOGO.N`, `VEJLED.PRG`, `PRINTER.PRG` — logo demo, guide, printer helper.
- **`comal-sources/`** — the COMAL exercise/example programs (`opgaveNN`,
  `eksN.N`, `turtle.eks`, `quicksort`, `horner`, `cardano`, `funktion`, `logon`
  menu) and the `SYSTEM` runtime image.  Also tokenised (except `SYSTEM`).

## Important: these need external-procedure support

`RACE.PRG` / `FUTTOG.PRG` / `TEGNGEN.PRG` use COMAL **external procedures**
(`CHRHENT.EXT`).  The disk's own `comal80 rev 1.07` **cannot** load them
(`LOAD`/`CHAIN` → `error 0214`); external procedures are documented only from the
newer **RcComal80** (RCSL 42-I-2339, June 1983, §8.5, [Bits:30008320](https://datamuseum.dk/bits/30008320)).
To run them, load onto a **RcComal80 that supports `.EXT` externals** (and, for the
custom glyphs to display, the SEM702 RAM char-gen hardware — MAME's `rc702sem702`).

## Provenance / regeneration

These are byte-exact extractions via CP/M de-blocking validated against the FDC
sector trace (`boottrk 4`, 2:1 skew `0,2,4,6,8,1,3,5,7`; see the analysis doc).
The disk uses a CP/M directory with non-standard filenames (dots inside the name
field), so `cpmcp` cannot copy them directly — hence the custom extractor.
Re-fetch the raw disk any time from the Bits URL above.
