# cpnos-in-c — finishing checklist (2026-06-03; refreshed 2026-06-15)

> **STATUS 2026-06-04: PARKED — awaiting physical Z80-PIO parallel cable.**
> All MAME oracles are green (cpnos-polypascal-test PASS clang ×
> {PIO, SIO}; PROM1 **2015 / 2048 B = 33 B free (1.6 %)** as of
> 2026-06-15; PPAS confirms +256 B TPA via Data top 0xDA86).  The
> remaining "finished" gate — real-hardware confirmation of the PIO
> transport on the user's RC702 — needs a physical cable to a CP/NET
> master.  Until the cable arrives, do NOT chase further cpnos
> compiler/code shrink (33 B PROM headroom + 46 B payload-grow budget
> make blind churn risky, and MAME already says PASS).
>
> Out of scope for the park: cpnos dependencies (llvm-z80 backend, z88dk
> sdcc) keep advancing.  In scope: the cpnos source tree, cpnos-specific
> docs, the polypascal-test harness, anything gated on PIO real-hardware
> behavior.
>
> Unpark trigger: user signals the cable arrived.  Memory rule:
> `tasks/memory/project_cpnos_parked_awaiting_parallel_cable.md`.

> **2026-06-28 housekeeping pass:** PROM1 size re-measured **2014 B /
> 34 B free**; CLAUDE.md + this checklist synced to it (the old 2027/2022
> figures corrected).  Item #3 (todo-* triage) DONE — 9 active files
> classified (1 shipped, 2 in-play, 6 deferred, 1 blocked); see item #3
> below.  Item #2 (headroom recovery) narrowed: #173 and #172 both
> verified ~0 cpnos yield today, so `BOOT_MARK_ENABLED=0` (~67 B) is the
> only measured lever left and needs a user go-ahead.  Items #1 (CI
> size-cap gate, now also needs a Docker compiler-baseline image first —
> user 2026-06-28) and #5 (isr_pio_par speed) remain behind the
> cable-park / infra-prereq.

> **2026-06-15 polish pass:** task tree triaged (23 files moved to
> `tasks/history/`, 13 active references kept) and indexed at
> [`tasks/README.md`](README.md).  PROM1 size today is 2015 B —
> 12 B better than the 2027 B recorded just below; headroom grew
> from 21 B to 33 B from accumulated llvm-z80 backend gains since
> 2026-06-04 with no cpnos source changes (same effect seen in
> rcbios).  Items #1 (CI size-cap gate), #4 (CLAUDE refresh) and #6
> (README polish) addressed in this pass.  Items #2 (headroom
> recovery to ≥ 50 B), #3 (todo-* triage) and #5 (isr_pio_par speed)
> remain behind the cable-park.

What's left to call cpnos "finished" per the four-component long-term goal
(`tasks/memory/project_finishing_firmware_components.md`).  Round 1 audit;
pair with the other three component checklists.

## TL;DR

**Works in production, but size headroom is the single fragile thing
about it.**  Current PROM1 = **2014 / 2048 B = 34 B free (1.7 %)** as
of 2026-06-28 (drifted within ±1 B over the past month from llvm-z80
backend gains, no cpnos source change).  Any future compiler/code change
can still blow the cap silently and break shipping.  Closing this
component means: (1) make
the size cap a hard CI gate, (2) widen headroom to a sustainable
margin (≥ 50 B), (3) triage `tasks/todo-*.md` — **DONE 2026-06-15**,
see [`tasks/README.md`](README.md) for the current 13-active +
23-archived index.  No active code bugs.

## Status: known bugs

No `known-bugs.md` file exists.  Working from the tree, recent history,
and CLAUDE.md:

| Topic | State |
|---|---|
| Two-PROM build | **REMOVED 2026-06-03** (see `tasks/TWO_PROM_PARKED.md`).  Production = autoload (PROM0) + cpnos-in-c PROM1-only.  Default `make` now builds `prom1-lineprog` cleanly. |
| PROM1-only lineprog | **production-target; PASSES** `cpnos-polypascal-test` in ~51 s (clang × {PIO, SIO}) |
| SDCC PROM1-only | builds at 2201 B (over 2 KB cap; MAME-only via 4 KB mode), polypascal-test PASS |
| #150 / SP-relative spill family | closed during 73s; no live bug |
| any open code bug | **none found.** |

Net: zero open code bugs.  The fragility is structural (size), not bug.

## Status: doc gaps

- **CLAUDE.md size numbers** — REFRESHED 2026-06-28 to the current
  measured **2014 B / 34 B free** (was 2013 B / 35 B on 2026-06-23; the
  older "2022 B / 26 B" record this note used to flag is long superseded).
  CLAUDE.md and this checklist are now in sync at 2014 B.
- ~~**Default `make` target** runs the parked two-PROM build~~ —
  RESOLVED 2026-06-03 by the two-PROM removal; `make` now builds
  `prom1-lineprog` cleanly.
- **`README.md`** — should name the production topology (autoload PROM0 +
  cpnos PROM1-lineprog) up front, with the canonical `make` command.
- **No production-verification doc.**  `cpnos-polypascal-test` is the oracle
  but it isn't documented as the single source of truth.  One page noting
  command + expected duration + canonical screenshot would close this.
- **17 `tasks/todo-*-2026-05-17.md` files** — most have `Status: TODO`
  (planned-not-started), `DEFERRED`, or DONE-but-noted.  This is task-tracking
  rot: needs a triage pass (close / kill / keep), ideally into a single
  short "open items" list.

## Status: oracle coverage

| Target | What it asserts | State |
|---|---|---|
| `make prom1-lineprog` | builds + size ≤ 2048 B hard cap (`CPNOS_PROM1_CAP`) | **PASS** (2014 B, 34 B free, 2026-06-28) |
| `make cpnos-polypascal-test` | end-to-end CP/NET via MP/M, PolyPascal compiles + runs, prints primes | **PASS ~50.65 s clang** |
| `make sio-smoke` | SIO transport smoke test | per session 73s-cont2 PASS |
| `make pio-irq-netboot` / `pio-irq-smoke` | PIO-IRQ transport | per session 73s PASS |
| `make cpnet-smoke` | basic CP/NET ping | per session, PASS |

**Test matrix:** (clang, sdcc) × {PIO, SIO} all pass per CLAUDE.md.  No
production-side oracle gap I can see — what's missing is the **CI gate**
on the size cap so a future cap-breaking commit fails at build, not at
boot.

## Status: size headroom — the central issue

- **2014 / 2048 B = 34 B free (1.7 %)** (re-measured 2026-06-28).
  Smallest margin of the four components.  Drifted within ±1 B over the
  last month from accumulated llvm-z80 backend gains with no cpnos source
  change (2018 B post-73s-cont2 → 2015 B 2026-06-15 → 2013 B 2026-06-23 →
  2014 B 2026-06-28).  Compiler density levers for further shrink are
  TAPPED OUT (verified 2026-06-28): #173 cross-MBB spill peephole and #172
  A-pin both yield ~0 cpnos bytes; gf_log/M1 is off cpnos's path.
- The cap is hardware-set (`feedback_no_undocumented_default` /
  `project_rc702_2kb_prom_hard_limit`): user's RC702 has no A11 bridge,
  PROM is physically 2 KB.  Cannot widen the cap.
- **Available shrink levers** (cost / yield):
  - ~~**ravn/llvm-z80#173** — 8-bit BSS spill via A push/pop peephole~~ —
    **CLOSED 2026-06-28, ~0 cpnos yield.**  Same-MBB part already shipped
    (cpnos −1 B); cross-MBB remainder re-catalogued on current binaries =
    0 cpnos bytes.  Not a shrink lever.
  - ~~**#172 A-pin**~~ — re-validated 2026-06-28: AES +1 B, cpnos
    byte-identical.  Not a shrink lever.
  - **`BOOT_MARK_ENABLED=0`** — disable cold-init visual diagnostic
    markers; recovers ~67 B per the 73j shrink-investigation; default
    OFF currently, ON would lose dev visibility.  **This is now the ONLY
    measured headroom lever left**; needs a user go-ahead.
  - **ZX0 reclaim follow-up** — per session 76, seed-order reordering
    saved 1 B; similar peephole sweeps may yield single-digit B each.
  - ~~**`tasks/zx0-prom1-only-plan-2026-05-17.md`**~~ — SHIPPED; that plan
    IS the current production PROM1-only-ZX0 topology.  STALE as a lever
    (banner added to the file 2026-06-28).
- **No CI gate on the cap.**  Makefile errors at build if exceeded, but
  only when `make prom1-lineprog` is run.  CI (test-runner job) doesn't
  currently build this target afaict — verify and wire it.

## External dependencies

- **llvm-z80**: backlog #173 is the relevant shrink lever.  Other open
  issues (#214/#213/#212/#211/#207/#206) don't directly affect cpnos.
- **MAME**: works on d0a7dcd ravn/mame; local upd765 `& 3` fix protects
  cpnos's transport-PIO + SIO test runs against the head-bit leak (bug B)
  if any FDC seek were in play (cpnos is diskless, so this is incidental).
- **z88dk**: SDCC builds + boots over the 2 KB cap at 2201 B; tolerated
  via 4 KB MAME-only mode.  Production = clang.
- **MP/M (z80pack mpm-net2)**: needs to be up + clean for
  cpnos-polypascal-test (memory rule `feedback_session_start_kill_daemons`).

## Concrete close-out items (ordered by leverage)

1. **Size-cap CI gate.**  Add `make prom1-lineprog` (clang, default
   transport) to the CI runtime-tests job, so any commit pushing the
   binary over 2048 B fails at CI build.  Also fix the default `make`
   target so it doesn't hit the parked two-PROM error.  ~30 min.
   *(Default-target fix DONE 2026-06-03 as part of the two-PROM removal;
   CI-gate part is still open.)*
   **PREREQUISITE (user 2026-06-28):** building `prom1-lineprog` in CI
   needs the llvm-z80 clang, and CI must NOT rebuild the whole compiler
   each run.  Before wiring this gate, stand up a **Docker baseline image**
   that ships a warm compiler build (object tree / sccache cache) so each
   CI run only recompiles the few changed Z80-backend TUs.  Today's CI
   (`.github/workflows/z80-ci.yml`) relies on `hendrikmuhs/ccache-action`
   (2 G GHA cache) which still does a full configure + cold-miss rebuilds
   on eviction.  The Docker-baseline approach (periodically-refreshed
   prebuilt image, delta-only ninja) is the intended fix.  Deferred — do
   the compiler-baseline-image work first, then add the size-cap gate.
2. **Headroom recovery to ≥ 50 B (~2.4 %).**  Choose ONE:
   (a) ~~Implement ravn/llvm-z80#173 (estimated 5–10 B; 3–4 h)~~ —
   **STALE/CLOSED 2026-06-28.**  #173's cheap same-MBB peephole already
   shipped (session 73p, since unified under #203), worth only cpnos
   −1 B; the remaining cross-MBB extension was re-catalogued on current
   binaries (2026-06-28) and still yields **0 cpnos bytes** (the one
   residual 8-bit spill bracket is the bare-store/cross-MBB shape the
   peephole deliberately skips).  Path C (#172 A-pin) also re-validated
   the same day: AES +1 B, cpnos byte-identical.  **Neither lever can
   recover cpnos headroom** — both verified, both parked.  Do NOT budget
   #173 as a shrink lever.
   (b) Flip `BOOT_MARK_ENABLED=0` for production (~67 B; user
   directive needed — costs dev diagnostic).  This is now the ONLY
   measured headroom lever left for cpnos; needs a user go-ahead.
3. **Triage `tasks/todo-*-2026-05-17.md`** — **DONE 2026-06-28.**  9 active
   todo/plan files classified (the "17" was pre-2026-06-15; 23 already
   moved to `tasks/history/` in the 06-15 pass).  Verified each against
   current reality — note `cpnos.img` is STILL live (CP/NET-served slave
   image, 21 Makefile refs), so the img-related todos are genuine deferred
   enhancements, NOT superseded by the two-PROM removal:

   | File | Class | Note |
   |---|---|---|
   | `zx0-prom1-only-plan` | **SHIPPED** | IS the current production topology; banner added |
   | `todo-56k-tpa` | **DEFERRED-blocked** | needs CODE_BASE ≥ 0xE080; further TPA grow eats the scarce 34 B payload headroom — blocked by the 2 KB cap |
   | `todo-prom1-compression-to-restore-bootmark` | **IN-PLAY** | directly tied to the BOOT_MARK_ENABLED=0 headroom decision (item #2) |
   | `todo-cpnos-img-zx0-compression` | **DEFERRED** | cpnos.img live; CP/NET-transfer speed enhancement |
   | `todo-cpnos-relocatable` | **DEFERRED** | cpnos.img live; not blocking |
   | `todo-load-from-cpnos-img` | **DEFERRED** | cpnos.img live; tables+font-at-boot enhancement |
   | `todo-translation-tables` | **DEFERRED** | not blocking anything live (per its own file) |
   | `todo-dma-dual-buffer` | **DEFERRED-experiment** | user-flagged risky ("will ruin 0xF800 layout") |
   | `todo-polypascal-no-mirror-stage4` | **DEFERRED-experiment** | primary polypascal-test (MIRROR_SIOB=1) is fine; only the no-mirror stage-4 ">>" detection is incomplete |
   | `todo-mame-build-binary-name` | **IN-PLAY (low-pri)** | `mame` vs `regnecentralend` binary-name drift; Makefile/doc cleanup |

   Net: 1 shipped, 2 in-play (1 low-pri), 6 deferred, 1 deferred-blocked.
   No DONE-but-open or kill candidates remain — all are either shipped or
   legitimately deferred with a reason.
4. **CLAUDE.md size refresh** — **DONE 2026-06-28.**  CLAUDE.md cpnos line
   and this checklist refreshed to the current measured **2014 B / 34 B
   free**; the stale 2027 B / 2022 B figures corrected throughout.
5. **Optimize isr_pio_par for speed** (throughput-critical; user-flagged
   2026-06-04).  Currently 184 T-states / ~46 µs body, capping CP/NET RX
   at ~19.6 kbyte/s; cpnos-polypascal-test (~51 s end-to-end) is
   approximately linear in 1 / ISR latency.  Three identified candidates
   (avoid `push af` stash, combine head/tail load, keep old_head in
   register) total ~−40 T ≈ 25 % steady-state improvement.  Discipline:
   measure happy-path T-states before AND after each change; preserve
   shadow-register-safety constraint.  Full analysis at the speed-budget
   section of `cpnos-in-c/src/transport_pio.c`.  ~2-4 h.
6. **DONE 2026-06-04 — TPA-grow $100**: cpnos slave shifted up $100 (BIOS
   0xED00→0xEE00, NIOS 0xED33→0xEE33, cpnos.sys NDOS 0xDD80→0xDE80).
   CFGTBL packed into IVT-page tail to free upper-region space.  Net
   user-visible: BDOS dispatch 0xE716→0xE816 = **+256 B TPA** for user
   programs.  Trade-off: payload growth budget halved 92 B → 46 B.
   PROM1 sizes byte-identical (clang 2029 B, SDCC 2148 B).  Production
   oracle PASS (cpnos-polypascal-test 51.37 s).  **Independent witness:**
   PolyPascal-80 V3.10 reports `Data: 15013 bytes (9FE1-DA86)` for
   PRIMES.PAS — Data top 0xDA86 is exactly +0x100 above the pre-grow
   value (0xD986), tracking the BDOS-dispatch shift.  PPAS reads the
   warm-boot vector at 0x0006 to find top-of-RAM, so the new ceiling
   is visible to every user program without recompile.  Files:
   payload.ld, bootstrap.s, cpnios-shim.asm, cpnos-build/Makefile
   (DATA_BASE=DDA80, CODE_BASE=LDE80, build artefact renamed
   cpnos.com→cpnos.sys), sections.asm (SDCC), bootstrap.asm (SDCC),
   cpnos-in-c/Makefile IVT-guard + init-vs-cpnos overlap guard.
6. **README.md polish** + production verification doc + canonical
   snapshot.  ~45 min.

Total ~3–6 h depending on which (2) is chosen.

## Not in scope here

- Two-PROM build revival (parked by user directive)
- SDCC 2 KB target (filed as a future follow-up; not blocking
  production)
- General llvm-z80 backlog work — handled by the compiler track
- MAME upstream filings — handled per
  `tasks/memory/feedback_mame_upstream_routing`
