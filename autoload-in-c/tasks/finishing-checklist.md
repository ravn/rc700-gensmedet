# autoload-in-c — finishing checklist (2026-06-03; updated 2026-06-04)

What's left to call this component "finished" per the four-component
long-term goal (`tasks/memory/project_finishing_firmware_components.md`).
Round 1 audit; pair with the other three component checklists.

## STATUS 2026-07-01 — size re-baselined; growth root-caused; one headroom decision open

Re-measured on a clean `make prom` with current clang (build-macos):
**1909 / 2048 B = 139 B free** (raw payload 2282 B, ZX0 1730 B).  Boot gate
**PASS** — `make floppy-boot-test` reaches `A>` on the unpatched
`SW1711-I8.imd` (frame 175 / 3.5 s), banner `RC700 56k CP/M vers.2.2 rel. 2.3`.

**Headroom regressed 388 → 139 B free since 2026-06-23.**  Root-caused (not a
compiler regression): commit `a7a7293` (2026-06-28, "unify SW1 switch; cross-
version boot-matrix gate") added a **SIO-B polled debug-output facility**
(`sio_b_*` in `rom.c` + the `rom.c:779-793` boot dump), ~200 B raw, gated only
at runtime by SW1 bit 0 — never compiled out.  Filed **ravn/rc700-gensmedet#118**
(add a `-DAUTOLOAD_SIO_DEBUG` build-time gate to recover ~200 B for production).
The remaining ~50 B is the SW1-unification overhead.

**All size docs were stale and are being refreshed this pass:** `clang/STATUS.md`
(said 2453 B, pre-ZX0!), `README.md`, this checklist, and the workspace CLAUDE.md
(said 1660 B / 388 free).

**Open finishing items now:** (a) #118 headroom decision (gate SIO-B debug or
accept 139 B); (b) SDCC parity probe — was Docker-blocked, now runnable (Docker
up + native SDCC at `z88dk/src/sdcc-build/bin`).  (c) DONE this pass — banner
confirmed auto-generated (known-bug #2 RESOLVED, was stale-marked OPEN).

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
