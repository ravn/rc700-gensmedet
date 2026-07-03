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

## RESOLVED: why RACE/FUTTOG/CHRHENT won't load on rev 1.07 (2026-07-03)

Root cause found by detokenizing (see `comal_detokenizer.py`) and cross-checking the
RcComal80 manual §8.5 "Externe procedurer" (Bits:30000027 printed p.64):

- **rev 1.07 supports external FUNCtions but NOT external PROCedures.**
- `eks9.4` uses `FUNC k(n,r) EXTERNAL "..."` (statement code **0xD8**) → **loads**.
- `RACE`/`FUTTOG` use `PROC … EXTERNAL "chrhent.ext"` + `EXEC` (statement code
  **0xD5**) → **error 214** (won't load).
- `CHRHENT.EXT` is the external procedure itself, `PROC … CLOSED` (CLOSED = local
  variables, manual p.61-63; external procs must be CLOSED) → also won't load.

So it is NOT a single unknown token (CHRHENT.EXT decodes with none) — it is the
external-PROCEDURE language feature, documented only in the newer RcComal80
(§8.5, RCSL 42-I-2339 / Bits:30008320). That is the "newer save format": the
`.PRG`/`.EXT` apps use external procedures, which the education disk's rev 1.07
runtime cannot load — they need a newer RcComal80.

---

# COMAL80 knowledge summary (parked 2026-07-03)

Consolidated findings from the investigation into why the education-disk `.PRG`
apps (RACE/FUTTOG/TEGNGEN) won't load, plus the `comal_detokenizer.py` tool.

## COMAL taxonomy on RC700

Two *different* COMAL product lines exist — tell them apart by how they boot:

| Boots to… | Product | Disk format | External procs |
|-----------|---------|-------------|----------------|
| **`* ` prompt** | **RC700 comal = ID-COMAL** (SW7501 line, rev 01.13/01.17) | 128-byte FM SD, uniform | **NO** (Bits:30000045) |
| **`1/…` top banner** | **COMAL80 / RcComal80** (rev 1.07 … 2.0) | RC702-mini (mixed-density track 0, 9×512 MFM) | yes |

They cannot read each other's disks (format gap), and ID-COMAL cannot run COMAL80
programs at all.

## Why RACE/FUTTOG won't load — narrowed precisely

`LOAD "race.prg"` → **error 214** on every COMAL80 we could run:

| COMAL80 | Reads the education disk? | Loads race.prg? | Bits |
|---------|:--:|:--:|------|
| rev 1.07 (education disk 30003268; standalone 30003572) | ✅ | ❌ 214 | — |
| rev 1.08 (30003986) | ✅ | ❌ 214 | 30003986 |
| Rev 1.1 (30003317) | — | untested (sysgen-only disk) | 30003317 |
| RcComal80 v2.0 (CP/M-hosted) | ✅ | ❌ "ikke SAVE-fil" | 30009625 |
| ID-COMAL 1.13 | ❌ format | ❌ | 30007375 |

So race.prg was **SAVEd by a newer COMAL80 (> 1.08, i.e. Rev 1.1+)** whose save
format the 1.07/1.08 loaders reject.  It is **not** the external-procedure
*language* feature: rev 1.07 accepts `PROC a EXTERNAL "proc1"` / `EXEC a` typed
live (verified) — it is the saved-file *format*.  (Earlier "1.07 lacks external
PROC" conclusion was wrong; corrected.)  External procedures are documented for
rev 1.07 in Bits:30000027 §8.5 p.64 (`CLOSED` = local variables, p.61-63).

## race.prg content (via `comal_detokenizer.py`)

A **horse-race game** (48 lines):
- `DIM` string arrays; loads movement patterns `"MCCDDMDCMMDM"`, `"PCCDDPDCPPDP"`,
  flags `"FL"/"fl"`, horse `"HEST"`.
- `PROC … EXTERNAL "CHRHENT.EXT"` + `EXEC` → loads the **`HESTE`** SEM702 char-set
  through the external char-loader.
- Draws the track with semigraphic characters (`PRINT "JGJJJ…MCCDDMDCMMDM…GJ"` etc).
- `FOR`/`IF` loop with `RANDOM` horse movement = the race simulation.

`FUTTOG.PRG` is the same shape (toy train, `DIVERSE.CHR`).

## chrhent.ext is a different file *format*

`CHRHENT.EXT` (the external proc module) has an extra per-statement record
`<ascending counter> 26 <byte>` (20+ of them; ad,ae,af,b0…c1) that **no normal
program has** (not even race).  It is the compiled external-procedure/library
format — referenced via `EXTERNAL`/`EXEC`, not `LOAD`ed directly (→ error 214).

## The detokenizer (`comal_detokenizer.py`)

- **Token map** derived from the interpreter's own keyword table in `SYSTEM`
  (offset ~0x1C00; program token = table token − 1; verified vs logon).
- Decodes: line structure (line-number anchors), keyword tokens, string constants
  (perfectly), comments (`//`=0xD3), assignment (`:=`=0xD1), FUNC-def (0xD8),
  external-PROC-def (0xD5), small integers (`7F <v>` → `0x8F−v`), variable refs
  (`<idx> FF` → `vXX`).
- **Not yet decoded** (needs a statement-length-aware structural parser):
  operators, exact numeric floats, variable *names* (symbol-table resolution).
- Oracle methods used: (1) the SYSTEM keyword table; (2) LIST in MAME on programs
  that load (logon, opgave7, eks9.4/9.5) for canonical source; (3) live typing to
  test syntax.  A SAVE-oracle was blocked — MAME can't write IMD, and the
  mixed-density RC702 disk crashes MAME's writable MFI path (`track < tracks`).

## Parked next steps
- To actually LOAD race.prg: run **COMAL80 Rev 1.1** — needs generating a runnable
  system from the 30003317 sysgen, which needs a writable disk (MFI blocker).
- To finish the detokenizer: a statement-length-aware parser for expressions.
