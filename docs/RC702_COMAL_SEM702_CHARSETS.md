# RcComal80 disk (Bits:30003268) — SEM702 char-sets, MAME boot & `.CHR` format

Analysis of the **COMAL 80 rev 1.07 education disk** ([Bits:30003268](https://datamuseum.dk/bits/30003268),
"COMAL 80 rev.1.07 opgaver + Tegngenerator", author *Tommy Borch, FAG, 1983*),
2026-07-02.  It boots RcComal80 and ships **SEM702 custom character sets** — the
"Tegngenerator" of the title.  Confirmed **not** a VPB701 graphics-card user
(cross-check: `docs/RC702_VPB701_GRAPHICS.md`).

## Booting & running programs in MAME

- **Machine: `rc702mini`** (5.25" DD, 250 kbps).  Convert the raw `bits/` image to
  IMD first: `python3 rcbios/bin2imd.py disk.bin disk.imd` (auto-detects RC702
  mini).  See the boot-recipe table in `docs/DATAMUSEUM_RC700_ARTIFACTS.md`.
  ```bash
  mame/regnecentralend rc702mini -rompath mame/roms -window -skip_gameinfo -flop1 comal.imd
  ```
- **The boot menu is the `logon` program** — it just wants a **program name**
  (prompt: *"Hvilket program ønskes? (Tast navnet uden gåseøjne)"*).  It launches
  the name via COMAL `CHAIN`.
- **Graphics programs prompt `skal grafen på skærmen (j/n)`** — answer **`j`** to
  get the drawing.  (This was the missing step: without `j`, no graphics appear.)
  Example: `turtle.eks` → `j` draws an axed function graph in **RC700 semigraphics**
  (block/sextant characters in the standard font — no SEM702 or VPB701 needed).
- **`.PRG` files fail with `AT 0110 / error: 0214`** = *CHAIN to invalid program*.
  Confirmed for graphics AND text `.PRG` alike (`RACE.PRG`, `TEGNGEN.PRG`, and the
  plain-text `VEJLED.PRG` all 214), and `LOAD "x.prg"` from COMAL command mode
  gives 214 too — so the menu's CHAIN mechanism simply can't launch the `.PRG`
  files on this rev-1.07 system; it is **not** a graphics/hardware error.

## The `.CHR` SEM702 character-set format

`DIVERSE.CHR` and `HESTE.CHR` are **SEM702 RAM char-generator glyph sets** (the
user-definable characters `TEGNGEN.PRG` edits and `CHRHENT.EXT` loads).  Decoded
byte layout (2048 B each):

- **157 records × 13 bytes.**  Each record = `[0x0b][0x00][11 scan-line bytes]`.
- `0x0b` (=11) is a constant per-record marker (the 8275 character cell is 8 px
  wide × **11 lines** tall — matches the CONFI.COM 8275 param `0x7A`, underline 7
  + 11 lines/char).  Byte 1 is a constant `0x00`.
- Bytes 2–12 are the **11 scan-lines** of an **8×11** glyph (bit 7 = leftmost px;
  the RC700 cell effectively uses 7 columns).

So it is **not** a raw 256×8 SEM702 image (an earlier wrong assumption from the
2 KB size).  Visualised as 8×11 tiles:

- **`DIVERSE.CHR`** — a "miscellaneous" tile set: **trees/plants, houses/buildings
  with windows, fences**, and assorted symbols (the richer of the two).
- **`HESTE.CHR`** — a **horse** tile set: fewer defined glyphs, the pieces of a
  horse figure that a program assembles on-screen.

### Which programs use these char-sets

Searching the raw image for the `.CHR` names outside the directory (COMAL stores
file names as strings in the tokenised code) pins the consumers:

- **`HESTE.CHR` ← `RACE.PRG`** (block 85) — a **horse race** (`hest` = horse).
- **`DIVERSE.CHR` ← `FUTTOG.PRG`** (block 84) — a toy **train** (`futtog`), whose
  landscape (trees / houses / fences) is exactly the DIVERSE tile set.
- Both load their set through **`CHRHENT.EXT`** (block 82), the COMAL
  character-fetch external — `CHRHENT` is referenced from both `FUTTOG.PRG` and
  `RACE.PRG` (plus a few other files' blocks).

Caveat: `RACE.PRG`/`FUTTOG.PRG` are `.PRG` files, so they hit the `error 0214`
wall (see next section) and can't be launched from the `logon` menu on this
rev-1.07 system — the char-set/consumer pairing is established from the binaries,
not from a live run.

## Why the `.PRG` apps fail: COMAL80 version / external procedures

The `.PRG` files (`RACE`, `FUTTOG`, `TEGNGEN`, `VEJLED`, `PRINTER`) are **tokenised
COMAL programs**, byte-structurally identical to the programs that *do* run
(`turtle.eks`, `opgaveNN`, `logon` all share the `09 81 … 31 2F "1/"<name>` header
and the same token stream) — the `.PRG` extension is **not** a different binary
kind, and they are not machine code (0 × `CALL`/`RET`/`JP`).

They fail because this **COMAL80 rev 1.07 cannot load them**: `LOAD "race.prg"`
returns `error 0214` just like `CHAIN` does, whereas `LOAD "turtle.eks"` loads and
`LIST` detokenises it cleanly (proven live in MAME).  Detokenising `logon` shows
the `AT 0110 error 0214` is its own line `0110 CHAIN program$` failing on the
typed name.

The reason is a **language-version gap**.  The COMAL80 reference manual
(*Comal80 Programmerings vejledning*, RCSL 42-I-1758, Jørgen Hansen, Dec 1981,
[Bits:30000018](https://datamuseum.dk/bits/30000018)) documents the base language
keyword-by-keyword and has **no `CHAIN` and no `EXTERNAL`/`.EXT`** entry.  So:

- Base COMAL80 (1981): no CHAIN, no external procedures.
- rev 1.07 (this 1983 disk): added `CHAIN` (logon uses it); runs plain programs.
- `RACE.PRG`/`FUTTOG.PRG`: use **external procedures** — they reference
  **`CHRHENT.EXT`** (the char-set loader external, block 82).  External-procedure
  support is absent from base COMAL80 and un-loadable by rev 1.07, so these apps
  need a **newer COMAL80 that supports `.EXT` externals**.

The newer manual confirms this: **RcComal80 Brugervejledning**, RCSL 42-I-2339,
Niels Bach, **June 1983** ([Bits:30008320](https://datamuseum.dk/bits/30008320))
documents **external procedures** in **§8.5 "Externe procedurer" (p. 76–77)** —
absent from the 1981 edition.  It states an external procedure *"skal altid
erklæres CLOSED"*, lives in **its own program file** on the disk, is declared by
which file it is in, and lets the user build a *"procedurebibliotek"* — exactly
`CHRHENT.EXT`'s role.  (§8.6 documents the `HANDLER` error structure.)  So the
`.PRG` apps target the external-procedure-capable **RcComal80** line, not the
disk's older `comal80 rev 1.07`.  A cross-version test (boot RcComal80,
`LOAD "2:race.prg"` from a second drive) would show it running.

The tiles are building blocks; the finished picture is laid out by the program
placing tiles in a screen grid, not stored assembled in the `.CHR` file.  To
display them with correct glyphs in MAME you need the SEM702 RAM char-gen
(`m_has_sem702`), currently only on the 8" `rc702sem702` machine — a `rc702mini`
+ SEM702 variant would be needed to run these 5.25" disks with live custom chars.

## How the `.CHR` bytes were extracted (robust route)

The education disk is a **standalone COMAL80** system (boots directly into
COMAL, its own disk format) with a **CP/M-like directory with non-standard filenames** (dots
inside the 8-char name field, e.g. `DIVERSE.`/`CHR`, `HESTE.CH`/`R`), which makes
`cpmcp` refuse them ("illegal CP/M filename") and mis-read on bulk copy.  Extracted
reliably by:

1. **FDC sector trace in MAME** (`upd765a` port taps on 0x04/0x05, à la
   `autoload-in-c/mame_fdc_log.lua`): dropped to COMAL command mode and issued
   `LOAD "diverse.chr"`; the FDC Read-Data commands showed the directory being read
   at **cyl 3, head 0, sectors R = 1,3,5,7** (physical) → raw `0x6000/6400/6800/6C00`.
2. That matches CP/M de-blocking with **`boottrk 4`, `sectrk 9`, `seclen 512`,
   `blocksize 2048`, 2:1 skew `0,2,4,6,8,1,3,5,7`** on the 5.25" mini image (track 0
   = 6144 B mixed-density boot area, stripped).  Block→raw:
   `raw = 0x1800 + (4 + L//9)*4608 + skew[L%9]*512`, `L = B*4 + i` (4 sectors/block).
   Validated: block 0 reproduces the directory.
3. Directory entries are standard CP/M (`byte 15` = record count, `byte 16` = first
   block): **`DIVERSE.CHR` = block 83**, **`HESTE.CHR` = block 86**, each 16 records
   (2048 B / 1 block).  De-blocking those two blocks yields the correct file bytes.

(Renderings produced during analysis: `scratch/logo-src/{diverse,heste}_final.png`
— not committed; regenerate from the disk via the steps above.)
