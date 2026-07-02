# RC703_DIV_ROA disk — RC700 PROM source & ROM-image inventory

Analysis of the datamuseum disk **`RC703_DIV_ROA.bin`**
([Bits:30003296](https://datamuseum.dk/wiki/Bits:30003296), provenance Peter
Heinrich), investigated 2026-07-02.

- Media: 5¼" floppy, **raw binary**, `rc703-qd` format (80 cyl × 2 heads × 10
  sec × 512 = 819 200 B), sha256 `c9934ac08acb8d0f12ac5d7d63112beab957e65514407cfa79bdccc913e6cd5a`.
- **Data-only** — no bootable CP/M system tracks (this is why
  `rcbios/extracted_bios/README.md` lists `RC703_DIV_ROA.imd` under "Non-bootable
  images skipped").  Label: *"Diverse kildekode i assembler til RC700"*.
- Extract: `cpmcp -f rc703-qd RC703_DIV_ROA.bin '0:*.*' <dir>` (rc703-qd diskdef
  in `rcbios/diskdefs`).

## File inventory (user area 0)

| File | Size | What it is |
|------|------|-----------|
| `phe358a.mac` | 27 KB | RC702E autoload source (see below) |
| `phe358a.{bak,prn,rel,com}` | — | backup, listing, .REL, assembled — of PHE358A |
| `rob358.mac` | 27 KB | RC703 autoload source (M80 original; see below) |
| `rob358.com` | — | assembled ROB358 |
| `stc001.32` | 4 KB | **RC702E Autoload Version 3.0** PROM image (= assembled PHE358A) |
| `rob584.32` | 4 KB | **RC350 / "MIC VER0"** PROM (different machine — off RC700 scope) |
| `roe114.128` | 16 KB | **non-Z80 ROM** (unidentified — see analysis) |
| `roe115.128` | 16 KB | **non-Z80 ROM** (paired with roe114) |

(User area 1 holds a temp/scratch file `~=bem5.~sj`; user 5 a stray entry.)

## What matches what we already have

- **`phe358a.mac` is byte-identical** to `roa375/PHE358A.MAC` (our copy came from
  here).  See `PHE358A_ANALYSIS.md` — banner `RC702E  Autoload Version 3.0`,
  memory-disk boot + SEM702 character-generator loading (Stig Christensen).
- **`stc001.32`** (4 KB PROM image) is the **assembled PHE358A** — its strings are
  the RC702E autoload v3.0 boot messages (English): `* DISKETTE ERROR *`,
  `* PLEASE INSERT DISKETTE AND PRESS RESET *`, `* NO SYSTEM FILES *`,
  `* INSERT DISKETTE IN DRIVE A *`, and the `RC702E Autoload Version 3.0` banner.
  So it corroborates, but adds nothing beyond the source+analysis we already have.
- **`rob358.mac`** is the **M80 original** of the RC703 autoload; our
  `roa375/rob358.mac` is the **zmac-adapted port** of the *same* code, not a
  different revision.  The only differences are assembler-dialect edits:
  `.PHASE 0A000H` → `PHASE 0A000H`, the port symbol `DMAMODE` → `DMAMOD`,
  `.DEPHASE` → `DEPHASE`, and `REPT FMOVE-(POS$-BEGIN)` rewritten as
  `REPT FMOVE-($ - BEGIN)` (with "zmac doesn't like …" comments).  (Autoload runs
  phased at 0xA000.)

## New / off-scope artifacts

- **`rob584.32`** — 4 KB PROM signing on as `RC350` / `/2 MIC VER0`.  For the
  **RC350** machine (or a MIC "micro interface" card), not RC700.  Off scope for
  the RC702/703 firmware work; recorded for completeness.
- **`roe114.128` / `roe115.128`** — two 16 KB ROMs (ROE series), see below.

## ROE114 / ROE115 are NOT Z80 (analysis)

These two 16 KB ROMs do not fit any Z80 interpretation.  Evidence gathered:

| Test | Result |
|------|--------|
| Z80 character-generator (16 B/glyph, 8 px, MSB-left) | renders as noise |
| Z80 code (z80dasm) | incoherent — scattered `rst 38h` (0xFF bytes as opcodes), no CALL/RET structure, no prologues |
| 6502 reset/IRQ/NMI vectors at top | RST = `0x0000` (implausible) |
| 8051 reset jump at offset 0 | byte0 = `0x2d`/`0x6c`, not `0x02` (LJMP) or AJMP/SJMP |
| Structure | ~27 % is `0x00`/`0xFF` padding; entropy ≈ 6.3 bits/byte (first 256 B ≈ 3.6–3.95); the two ROMs share a byte sequence `14 05 02 01 03 10` |

**Conclusion: Z80 is effectively ruled out.**  ROE114/115 are either
1. **data** (a character generator / graphics set / lookup tables) in an unknown
   layout — the paired 16 KB size + heavy padding fit a char/graphics set, or
2. **firmware for a peripheral microcontroller** — RC's "smart" peripherals
   (keyboard RC721, printer, line selector) carry their own CPUs; the sibling
   disk `RC703_8051ASM` ([Bits:30003294]) shipped 6502/8048/8051 cross-assemblers,
   and `rob584` on this disk is a "MIC" (micro-interface/microcontroller) PROM.

The exact target chip was not identified in this pass (would need a multi-arch
disassembler, or knowing which RC peripheral uses ROE-series ROMs).  What is
certain is that they are **not Z80 firmware for the RC702/703 CPU**, so they are
not part of the autoload / BIOS reconstruction work.

**Graphics-card connection — CORRECTED (2026-07-02).**  The RC700 graphics/colour
extension is the **VPB701 board**, and its coprocessor is a **NEC µPD7220 GDC**
(see `docs/RC702_VPB701_GRAPHICS.md`, RCSL 42-i-2164 / Bits:30005363).  The
µPD7220 is a **fixed-function controller with no program ROM**, so ROE114/ROE115
are **NOT** its firmware (my earlier "coprocessor firmware" guess was wrong).
The µPD7220 *can* do character display via an external char generator, so the two
16 KB non-Z80 ROMs *might* be the VPB701 graphics/colour char-gen — but this is
now speculative and unconfirmed.  (`rob358.mac` does carry a conditional COLOR
CRT autoload variant, confirming firmware awareness of colour.)

## Net verdict

Bits:30003296 is largely the **PHE358A source disk** (identical to our copy) plus
the M80 original of ROB358 (which our zmac port derives from).  It adds no new
RC702/703 Z80 firmware knowledge on the autoload/BIOS critical path.  The genuinely
new items — `rob584` (RC350/MIC) and the `roe114/roe115` non-Z80 ROMs — are
peripheral/other-machine artifacts, catalogued here but out of scope.
