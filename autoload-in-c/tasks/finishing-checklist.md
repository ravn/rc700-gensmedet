# autoload-in-c — finishing checklist (2026-06-03; updated 2026-06-04)

What's left to call this component "finished" per the four-component
long-term goal (`tasks/memory/project_finishing_firmware_components.md`).
Round 1 audit; pair with the other three component checklists.

## STATUS 2026-07-01 (QR-at-boot SHIPPED) — v2 QR + full ROA327 font both fit; 14 B free

**2034 / 2048 B = 14 B free.**  Boot gate PASS; new **`make qr-test` PASS**.

A version-2 (25x25) QR of `github.com/ravn/rc700-gensmedet` now renders on the
no-diskette error screen (rows 15..23), alongside the full ROA327 SEM702 font.
Getting BOTH into 2 KB took a chain of measured, non-glyph savings (the full font
is mandatory — SEM702 is a direct 1:1 ROA327 chip replacement, so no glyph may be
dropped, and it must be self-contained: we cannot rely on reading the char PROM on
the real machine):

- **QR renderer** rewritten to a flat byte-copy (s in BC, d in HL, no memcpy/IY
  shuttle); **0x80 reset dropped** (everything after the QR is blank, renders
  identically in both fonts).
- **QR mask forced to pattern 3** (gen_qr.py) — of the 8 valid masks it
  ZX0-compresses smallest (108 vs 110 B).
- **display_sw1_status**: `(sw>>i)&1` (variable-shift-by-IV -> O(n^2) `srl;djnz`
  loop) rewritten to `(sw&1); sw>>=1` -> −5 B.  A real Z80 codegen gap — recorded
  as **B22** in llvm-z80 known-suboptimal + the CLAUDE.md "LSR is Harmful" note.
- **load_chargen_font line-outer** (the decisive −17 B): iterate line-outer /
  char-inner so the line-major table is a pure `*p++` sequential walk, ALINE set
  once per line.  Safe: SEM702 forms its RAM address from independent char/dot
  latches at the data write (verified in MAME rc702.cpp `sem702_data_w`), so the
  reordered OUT sequence yields byte-identical RAM.  Eliminates the B21 waste.

**Build-process fix:** the size ASSERT is now gated on `--defsym FINAL_LINK=1`
(pass 2 only).  Previously an over-budget compressed blob failed *pass 1* too,
wedging the build (pass1.elf never regenerated, no fix measurable).  QR content is
constrained to v2 (117 cells); the URL is byte-mode lowercase (fits v2's 32-byte
cap).  QR verified by `make qr-test` (no-disk boot; asserts field attr 0x84 +
byte-exact match of the 13x9 region against qr_data.h + the error message).

---

## STATUS 2026-07-01 (later still) — SEM702 font upgraded sextant-subset → FULL ROA327; headroom 463 → 115 B

**1933 / 2048 B = 115 B free**.  Boot gate **PASS**.

`sem702_font[]` now holds a **full ROA327 replica** (all 128 glyphs: line-drawing
0x00..0x1F, sextants, shared uppercase), not just the sextant subset.  Sourced by
transposing `mame/roms/rc702/roa327.rom` into **line-major, 11 defined dot-lines**
(lines 11..15 are blank on every glyph → dropped; `load_chargen_font()` writes 0
for them).  ZX0 measurement that drove the layout: char-major/16-line 534 B →
line-major/16-line 382 B → **line-major/11-line 377 B** (delta transforms tested,
all worse).  Dropping the 5 blank lines saved only 5 B PROM (ZX0 already crushed
the zero-run) but shrank the decompressed RAM table 2048 → 1408 B, so the RAM
image is actually *smaller* than the sextant version (ends 0x6D03, ~2.8 KB below
the 0x7830 framebuffer).  Function renamed `define_sextants` → `load_chargen_font`.

**Net cost +348 B PROM** (1585 → 1933).  This is the deliberate "full font"
choice (user 2026-07-01): all ROA327 glyphs available on the SEM702 machine, at
the price of headroom.  **Remaining 115 B is the budget for the "slank QR" goal**
— a version-1 (21×21) QR renders to 11×7 = 77 pre-computed cell bytes + a small
positioned-copy routine (~fits); a version-2 (25×25 = 13×9 = 117 cells) does NOT
fit.  QR content therefore constrained to short data (build date+hash or a short
URL), not the full project URL.  See `todo-later.md` QR section.

---

## STATUS 2026-07-01 (later) — SEM702 sextant font moved into ZX0 payload; headroom 405 → 463 B

**1585 / 2048 B = 463 B free** (clean `make prom`, current clang).  Boot gate
**PASS** (`make floppy-boot-test` reaches `A>`).

`define_sextants()` was rewritten from an on-the-fly computed routine (~192 B
code + a `half[]` LUT) into a **transpose-copy** from a **line-major** font
table (`clang/sem702_font.h`, `sem702_font[2048]`).  The line-major layout was
chosen because it **ZX0-compresses to ~44 B** inside the `.text` payload (vs
~207 B char-major) — so the 2 KB uncompressed table costs almost nothing in
PROM, and the copy loop is smaller than the old arithmetic.  Net **−58 B PROM**
(1643 → 1585).  OUT sequence to SEM702 (0xD1/0xD2/0xD3) is **byte-identical** to
the old verified routine (same `expand()` logic, index `(line<<7)|ch` =
line-major lookup).

**RAM barrier checked:** decompressed image ends at **0x6F75** (font at 0x6712),
framebuffer at **0x7830** → **~2.2 KB clearance**.  Both the 2 KB PROM cap and
the RAM/framebuffer barrier are clear with margin.

The freed headroom (463 B) now covers the **QR-code-at-boot** feature (est.
~160 B) that the sextant glyphs exist to serve — see `todo-later.md`.

**Codegen note (llvm-z80):** the inner transpose loop is *correct but not
optimal* — a missed stride-N induction-variable strength reduction makes clang
recompute `line<<7` each iteration, cascading to an IY invariant-shuttle
(`push iy/pop hl`) + a counter spill.  Registered as **B21** in
`llvm-z80/tasks/known-suboptimal-codegen.md` (ZeroYield: boot-only one-shot
code).  Includes the user's SP-is-inviolable follow-up.  Not a blocker here.

---

## STATUS 2026-07-01 — SIO-B debug removed; headroom restored to 388 B

**1660 / 2048 B = 388 B free** (clean `make prom`, current clang).  Boot gate
**PASS** — `make floppy-boot-test` reaches `A>` on the unpatched `SW1711-I8.imd`
(frame 175 / 3.5 s), banner `RC700 56k CP/M vers.2.2 rel. 2.3`.

**Headroom-regression resolved by removal.**  A temporary SIO-B polled-debug
facility was added 2026-06-28 (`a7a7293`) while debugging a no-start; it shipped
in production gated only at runtime (SW1 bit 0) and dropped headroom 388 → 139 B.
The user confirmed it is no longer needed (a better debug path will be built
later), so it was **removed 2026-07-01** — the `sio_b_*` block + the
`autoload_bios_loaded_bp` MAME-bpset hook in `rom.c`, the SIO-B port defs/macros
in `rom.h`, and the two call sites.  Removing it recovered exactly 249 B
(1909 → **1660 B**, back to the 388 B baseline).  **ravn/rc700-gensmedet#118
closed** (removed rather than gated).  Production unaffected otherwise (boot
byte-flow identical; only the removed debug code differs).

**Size docs refreshed this pass:** `clang/STATUS.md` (was grossly stale at
2453 B, pre-ZX0), this checklist, workspace CLAUDE.md.

**Open finishing items now:** (a) SDCC parity probe — was Docker-blocked, now
runnable (Docker up + native SDCC at `z88dk/src/sdcc-build/bin`).  (b) the
"better debug path" the user wants to build later (the gdb-z80 stub in
`tasks/gdb-z80/`, or a cleaner serial facility) — parked feature, not a blocker.
Banner cosmetic bug (#2) RESOLVED this pass — auto-generated from build date +
git hash.

---

## STATUS 2026-06-04 — close-out items 1-3 + 5 LANDED

All five originally-identified close-out items are addressed.  Three are
DONE this session; one is BLOCKED on infrastructure.  Component is
shippable on the floppy production path; cpnos production path is parked
on its own checklist.

| # | Item | State |
|---|---|---|
| 1 | `make floppy-boot-test` Makefile target | **DONE 2026-06-04**.  Uses in-tree `test-disks/SW1711-I8.imd`; asserts `A>` at 0xF800 via fixed `mame_boot_test.lua`.  Verified PASS at frame=200 (4.0s emulated). |
| 2 | README polish — refresh sizes, clang-primary framing | **DONE 2026-06-04**.  Sizes 1843→1658 B, ZX0 history added, clang made primary, SDCC declared parity-only.  Production-verification doc cross-linked. |
| 3 | Banner regen (rcbios pattern) | **DONE 2026-06-04**.  `clang/banner.h:` now has `FORCE` dep + cmp dance, mirroring rcbios/builddate.h.  Banner reflects build moment; verified `2026-06-04 01.52 8e231cf/ravn`. |
| 4 | SDCC parity probe | **BLOCKED 2026-06-04 on infrastructure** (Docker daemon not running).  Documented as Docker-gated / parity-only in README; clang remains production.  Probe deferred until next session that has Docker up. |
| 5 | Production verification doc | **DONE 2026-06-04**.  `docs/production-verification.md` — names both production paths + the `make` targets + canonical screenshot. |

## TL;DR (pre-session-baseline)

**Closest of the four to finished.**  Both production paths boot to `A>`
(cpnos via PROM1-lineprog; floppy CP/M via DRI rel.2.3 BIOS on
`SW1711-I8.imd`), verified 2026-06-03 by screenshot.  PROM at 1658 / 2048 B
= **390 B free (19 % headroom)** — comfortable.  Known-bugs page has only
one active entry (cosmetic), all others RESOLVED or FIXED.  Three small
polish items remain; none are blockers.

## Status: known bugs

| # | Title | State |
|---|---|---|
| 1 | C autoload hangs in FDC detect, never hands off to BIOS | **RESOLVED 2026-06-03** (was a harness limit; not codegen) |
| 2 | Banner string hardcoded + stale (`"RC700 CL 2026-04-15 12.15/ravn"`) | **RESOLVED 2026-06-04** (verified 2026-07-01): banner auto-generated from build date + git hash; fresh build stamps `RC700 ROA375 CL <date> <hash>/ravn`. |
| 3 | MAME path was wrong (workspace restructure) | **FIXED 2026-05-04** |

## Status: doc gaps

- `README.md` "Current status" line 12 reports **1843 B** — stale; current is
  1658 B (post-ZX0).  PROM-size history table stops 2026-03-21; doesn't
  reflect the 337 B ZX0 saving.  Touch up to reflect today's numbers.
- `README.md` first line refers to "z88dk with sdcc backend" — but the SDCC
  path is not the current production target (clang is).  Clarify that the
  SDCC build is parity-only / parked.
- `BOOT_SEQUENCE.md` exists; should be re-read to confirm it matches the
  current rom.c + boot_rom.c flow.
- Missing: a one-page "production verification" doc that names the
  two production paths (cpnos via PROM1, floppy CP/M) + the make targets
  that verify them.  Today's session put a canonical screenshot in
  `snap/autoload_sw1711_boot.png` — that should live in the doc as proof.

## Status: oracle coverage

| Path | Target | What it asserts | State |
|---|---|---|---|
| Build size cap | `make prom` | clang ≤ 2 KB hard | PASS (1658 B) |
| Autoload banner | `make mame` | banner matches + boot to `A>` (now scans 0xF800 too) | PASS this session |
| SW1 status line | `make sw1-test` | SW1 status on row 0 of autoload framebuffer | PASS this session |
| FDC trace | `make fdc-log` | record + decode µPD765 transactions during boot; flag bugs A/B | tooling only (new) |
| **Floppy boot via DRI BIOS** | — (manual) | autoload + UNPATCHED SW1711-I8.imd reaches `A>` | **VERIFIED 2026-06-03 by screenshot; not yet a `make` target** |
| **ID-COMAL boot** | — (manual) | autoload + `test-disks/RC700_Comal.imd` reaches COMAL `*` prompt (interactive) | **✅ USER-APPROVED 2026-07-01.**  VERIFIED by screenshot + byte-compare (load 98.6% match, boots interactive).  Program RUN blocked by MAME rc702 port-0x14 motor bug (ravn/mame#12), not autoload — out of autoload scope. |

**Gap:** no committed `make` target asserts the floppy-boot end-to-end on
the unpatched `SW1711-I8.imd`.  `make mame` uses an out-of-tree default
(`$(FLOPPY) = ~/Downloads/SW1711-I8.imd`) and we now have the disk in-tree
at `test-disks/SW1711-I8.imd`.  Cheapest fix: a `make floppy-boot-test`
target that uses the in-tree disk + the fixed `mame_boot_test.lua`,
asserting `A>` appears at 0xF800.  Closes the gap and gives a CI hook.

## Status: size headroom

- 1658 / 2048 B → 390 B free (19 %).  Sustainable.
- Parked headroom-recovery items in `tasks/todo-later.md`:
  - Split ZX0 decoder around NMI: ~35 B savings (parked, low priority)
  - QR code at boot: ~160 B cost (consumer, not saver)
  - ID Comal compat: parked, low priority

Headroom is not at risk; no compiler-tracking gate needed here (unlike
cpnos, which IS at risk per its checklist).

## External dependencies

- **llvm-z80**: no open issue is blocking autoload-in-c.  The closed-as
  -not-reproduced ravn/llvm-z80#215 was the last live concern.
- **MAME**: works on the d0a7dcd ravn/mame submodule.  The local upd765
  `& 3` seek/recal fix protects autoload (and rcbios) from the bug-B head-
  bit leak; this fix would need to be re-applied after any upstream merge.
  Upstream rc702 in `mamedev/mame` is the 2016 skeleton — not usable; the
  fork's rewrite (rejected as PR #15032) is what we ship.
- **z88dk**: SDCC parity path status uncertain — `make sdcc` hasn't been
  exercised this session.  Worth a one-run check; if it builds and boots,
  it's "for parity"; if it's broken, declare parked (per
  `project_cpnos_clang_only` precedent) so the symmetric-recipes rule
  doesn't dog us.

## Concrete close-out items (ordered)

1. **`make floppy-boot-test`** — add a Makefile target that boots
   autoload-in-c on `test-disks/SW1711-I8.imd` and asserts `A>` via the
   fixed `mame_boot_test.lua`.  Closes the oracle-coverage gap.  ~15 min.
2. **README polish** — refresh the size numbers (1658 B post-ZX0), re-frame
   as clang-primary, drop the stale 2026-03-21 history claim that's still
   showing as "current", point at the canonical screenshot.  ~20 min.
3. **Bug #2 (banner)** — regen build-date from `builddate.h` like rcbios,
   OR drop the date entirely.  Pick one.  ~30 min.
4. **SDCC parity probe** — one `make COMPILER=sdcc prom` run; document
   result (works / parked).  ~10 min.
5. **Production verification doc** — one page naming the two production
   paths + the `make` targets + the canonical screenshot.  ~30 min.

Total ~2 h of focused work to call this component finished.

## Not in scope here

- QR code at boot (parked feature, not a finishing item)
- ID Comal compat (parked feature)
- Split-decoder 35 B win (cosmetic; not a finishing item)
- Any llvm-z80 backlog work — handled by the compiler track
- MAME upstream filings — handled separately per
  `tasks/memory/feedback_mame_upstream_routing` (HARD: user-direction
  required to file)
