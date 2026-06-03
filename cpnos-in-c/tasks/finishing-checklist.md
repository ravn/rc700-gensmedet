# cpnos-in-c — finishing checklist (2026-06-03)

What's left to call cpnos "finished" per the four-component long-term goal
(`tasks/memory/project_finishing_firmware_components.md`).  Round 1 audit;
pair with the other three component checklists.

## TL;DR

**Works in production, but the size headroom is the single fragile thing
about it.**  Current PROM1 = **2027 / 2048 B = 21 B free (1.0 %)**, down
from 26 B in CLAUDE.md.  Any future compiler/code change can blow the cap
silently and break shipping.  Closing this component means: (1) make the
size cap a hard CI gate, (2) widen headroom to a sustainable margin (≥
50 B), (3) triage the 17 open `tasks/todo-*-2026-05-17.md` files (most are
parked / deferred / done — clean the inventory).  No active code bugs.

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

- **CLAUDE.md size numbers are stale.**  Records 2022 B (26 B free); actual
  today is 2027 B (21 B free).  Drifted +5 B since last update.
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
| `make prom1-lineprog` | builds + size ≤ 2048 B hard cap (`CPNOS_PROM1_CAP`) | **PASS** (2027 B, 21 B free) |
| `make cpnos-polypascal-test` | end-to-end CP/NET via MP/M, PolyPascal compiles + runs, prints primes | **PASS ~50.65 s clang** |
| `make sio-smoke` | SIO transport smoke test | per session 73s-cont2 PASS |
| `make pio-irq-netboot` / `pio-irq-smoke` | PIO-IRQ transport | per session 73s PASS |
| `make cpnet-smoke` | basic CP/NET ping | per session, PASS |

**Test matrix:** (clang, sdcc) × {PIO, SIO} all pass per CLAUDE.md.  No
production-side oracle gap I can see — what's missing is the **CI gate**
on the size cap so a future cap-breaking commit fails at build, not at
boot.

## Status: size headroom — the central issue

- **2027 / 2048 B = 21 B free (1.0 %).**  Smallest margin of the four
  components.  Up +9 B vs the 2018 B post-73s-cont2 baseline; up +5 B vs
  the 2022 B last recorded in CLAUDE.md.
- The cap is hardware-set (`feedback_no_undocumented_default` /
  `project_rc702_2kb_prom_hard_limit`): user's RC702 has no A11 bridge,
  PROM is physically 2 KB.  Cannot widen the cap.
- **Available shrink levers** (cost / yield):
  - **ravn/llvm-z80#173** — 8-bit BSS spill via A push/pop peephole;
    queued; estimated 5–10 B cpnos shrink; 3–4 h compiler work.
  - **`BOOT_MARK_ENABLED=0`** — disable cold-init visual diagnostic
    markers; recovers ~67 B per the 73j shrink-investigation; default
    OFF currently, ON would lose dev visibility.  Default-OFF would let
    headroom jump to ~88 B free.
  - **ZX0 reclaim follow-up** — per session 76, seed-order reordering
    saved 1 B; similar peephole sweeps may yield single-digit B each.
  - **`tasks/zx0-prom1-only-plan-2026-05-17.md`** — "planned, not
    started."  Was the path that already DID land (got us to 2018 B).
    Likely STALE.
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
2. **Headroom recovery to ≥ 50 B (~2.4 %).**  Choose ONE:
   (a) Implement ravn/llvm-z80#173 (estimated 5–10 B; 3–4 h);
   (b) Flip `BOOT_MARK_ENABLED=0` for production (~67 B; user
   directive needed — costs dev diagnostic).  Recommend (a) for
   correctness/sustainability; (b) if (a) yields too little.
3. **Triage `tasks/todo-*-2026-05-17.md`.**  17 files.  Close DONE
   ones; mark DEFERRED with explicit owners or kill; keep only items
   actually in play.  ~1 h.
4. **CLAUDE.md size refresh.**  Update "PROM budget watch" line + the
   cpnos-in-c row in the per-component summary to today's 2027 B.
   ~10 min.
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
