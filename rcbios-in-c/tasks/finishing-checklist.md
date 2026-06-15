# rcbios-in-c — finishing checklist (2026-06-03; closed-out 2026-06-15)

> **STATUS 2026-06-15: all five close-out items addressed.**  rcbios is
> "finished" by the four-component bar: no production bugs, sizes
> refreshed and tracked, task tree triaged and indexed, README is a
> landing doc, size-lever decision recorded.  Item #3 (CI gate)
> deferred with rationale — not a finishing-bar blocker.  Detail per
> item below.

What's left to call rcbios "finished" per the four-component long-term goal
(`tasks/memory/project_finishing_firmware_components.md`).  Round 1 audit;
pair with the other three component checklists.

## TL;DR

**Largest finishing surface of the four — but no production bugs.**
clang BIOS = **5462 B** (re-measured 2026-06-15) vs SDCC 6091 B
(clang **−629 B**, 10.3% smaller).  Boots to `A>`, all named test
targets pass (`mame-test`, `sio-echo-test`, `bgstar-test`,
`conout-test`, etc.).  The work to finish is **task-tracking cleanup +
size-lever decisions + doc consolidation**; ~14 `tasks/*.md` files mix
DONE / OPEN / PARKED with no clean index, which is the main "feels
unfinished" signal.

## Status: known bugs

No `known-bugs.md` exists in rcbios-in-c; the `tasks/*.md` files double as
the bug tracker.  Triaging by current state (read from each file's status
line):

| File | State |
|---|---|
| `todo-rcbios-sfr-port-io-2026-05-19.md` | **CLOSED 2026-05-19** — implemented; safe to archive |
| `sio-independent-rates.md` | **RESOLVED: not possible** — physical limit, safe to archive |
| `siob-console-dipswitch.md` | **DONE** — safe to archive |
| `bios-size-issues.md` | **OPEN** — size-recovery levers (BSS static-stack reloads ~30 B etc.) |
| `siob-rx-no-stack-switch.md` | OPEN (orthogonal issues) |
| `26-line-status.md` | OPEN questions (feature design) |
| `stack_corruption_investigation.md` | unclear — likely historical investigation, needs status |
| `cpnos-issues.md`, `cpnos-rom-plan.md` | **probably stale** — name the parked cpnos-rom |
| `parallel-port-transfer.md`, `sdlc-hw-test.md` | likely historical / bench-side |
| `mame-danish-keyboard.md` | **deferred** |
| `two-port-deploy-script.md`, `sio-independent-rates.md`, etc. | various, need triage |
| `todo.md` | **active phase tracker**, has tracked follow-ups including `[ ] RXTHLO=240 RX-ring hysteresis` |
| 10 `session*.md` + `*_summary.md` | history; archive/move under `tasks/history/` |

Net: zero open code bugs blocking production.  All apparent surface is
either a feature-design question or already done-but-not-archived.

## Status: doc gaps

**10 top-level docs** in rcbios-in-c root: `README.md`, `CLANG_PORT.md`,
`BIOS_REGISTER_ABI.md`, `ASM_BLOCKS.md`, `CONOUT_BENCH.md`,
`CPM_BIOS_ABI.md`, `SDCCCALL.md`, `SIZE_COMPARISON.md`,
`SYSGEN_INSTALL.md`, `Z88DK_NOTES.md`.

This is good coverage; gap is mainly **drift + a missing landing doc**:

- `SIZE_COMPARISON.md` likely has stale numbers (CLAUDE.md drifted +14 B,
  so this is probably worse).
- `README.md` should be the production landing doc that names build
  command, primary `make` targets, and the production-verification path.
- No "production verification" doc analogous to what rcbios already has
  in `mame-test` — just refer to that target as the canonical oracle.
- The 14 `tasks/*.md` files are not indexed; a `tasks/README.md` (or
  `INDEX.md`) listing each + status would close the "feels open" feel.

## Status: oracle coverage

| Target | What it asserts | State |
|---|---|---|
| `make bios` | builds clang BIOS, computes size | PASS, 5462 B (2026-06-15) |
| `make mame-test` | end-to-end MAME boot to `A>` + disk-checksum DISK=…  ERR=0 | PASS |
| `make mame-mini` / `mame-maxi` | mini/maxi floppy variants | PASS |
| `make sio-echo-test` | 4 KB bidirectional echo on both SIOs | PASS (per todo.md session-23) |
| `make bgstar-test` | console output + keyboard chain end-to-end | PASS |
| `make conout-test` | CONOUT primitives (15 of 18 RC700 text codes) | PASS |
| `make asm-test`, `cycle-test`, `profile` | various deeper benches | PASS per session notes |
| `make mame-roms-rcbios` | installs hand-assembled genuine roa375 | PASS |
| `make verify-skew` | build hygiene check | PASS |

**Test matrix:** `(clang, sdcc)` × `(rel.2.1, 2.2, 2.3-mini, 2.3-maxi,
…)` × `(SIO transports)` — heavy.  All pass per CLAUDE.md "BIOS clang
5462 vs SDCC 6091".

**Gap:** no single CI gate that runs the full matrix in one shot.
runtime-tests CI covers some of this; not clear which.  This isn't
necessarily a problem — incremental targets work fine for development.
For "finished", verify CI runs at least `mame-test` + `sio-echo-test` on
every push.

## Status: size headroom

- clang BIOS **5462 B** (2026-06-15); SDCC **6091 B**.
- The BIOS fits inside the 56 K CP/M TPA layout above 0xD480; no
  hard PROM-style cap.  Headroom is "fits the BIOS region without
  encroaching on TPA below BIOSAD=0xDA00."
- `bios-size-issues.md` lists open size levers (~30 B BSS static-stack
  reload reduction etc.); these are quality, not budget — currently
  there's no breakage risk from size.
- Drift history: 5897 (2026-05-27) → 5911 (2026-06-03) → 5890 (2026-06-10,
  `-flto` default) → 5462 (2026-06-15).  The 5905→5890 step was the LTO
  switch (#89); the 5890→5462 drop is accumulated llvm-z80 backend gains
  with no rcbios source changes — direction is unambiguously good but
  uncaught.  Either fine (no cap to break) or worth a CI-tracked target
  with a tolerance band on the *down* side too.

## External dependencies

- **llvm-z80**: `bios-size-issues.md` (BSS spill access cost) ties to
  ravn/llvm-z80 backlog; #173 is the queued lever (also tracked under
  cpnos).  No issue blocks rcbios shipping.
- **MAME**: works on d0a7dcd; the local upd765 `& 3` seek/recal fix is
  the one that lets rcbios + SW1711-I8.imd boot to `A>` (verified
  empirically this session).  Re-application needed after any future
  upstream merge.
- **z88dk SDCC**: production parity path; SDCC BIOS builds at 6091 B.
  Symmetric-recipes rule (`feedback_symmetric_recipes_per_compiler`)
  applies.
- **CP/NET / SNIOS**: covered in the CP/NET checklist;
  `cpnet/snios.asm` produces the SNIOS.SPR rcbios links against.

## Concrete close-out items (ordered)

1. **Triage `tasks/*.md`** — 24 files; the largest visible "finished" delta.
   - Move DONE/RESOLVED/CLOSED to `tasks/history/` (or delete with a
     `git rm` if no future value): `todo-rcbios-sfr-port-io-2026-05-19`,
     `sio-independent-rates`, `siob-console-dipswitch`, all
     `session*.md` / `*_summary.md`.
   - Mark PARKED clearly: `cpnos-rom-plan.md`, `cpnos-issues.md`
     (cpnos-rom is parked; cpnos-in-c is the current target — file
     drift).
   - Keep + add status header: `bios-size-issues`, `siob-rx-no-stack-switch`,
     `26-line-status`, `stack_corruption_investigation`, `todo.md`.
   - Add `tasks/README.md` indexing the survivors.
   - ~1–2 h.
2. **Refresh `SIZE_COMPARISON.md`** + the CLAUDE.md cpnos+rcbios row to
   today's numbers — **DONE 2026-06-15**, current: 5462 / 6091.
   `SIZE_COMPARISON.md` itself is an ASM-vs-C historical comparison
   doc (SDCC scope) and stays as-is; CLAUDE.md + the TL;DR + the
   "size headroom" rows in this checklist all updated.
3. **CI gate on `make mame-test`** — **DEFERRED 2026-06-15**.  The
   `.github/workflows/makefile.yml` on rc700-gensmedet currently builds
   the zmac toolchain + assembles roa375 + assembles sysgen on
   ubuntu-latest.  Adding `mame-test` requires (a) the llvm-z80 toolchain
   on the runner (Docker image or cached build), (b) MAME on the runner
   (a non-trivial install), and (c) the IMD test disks available
   (currently `~/Downloads/SW1711-I8.imd`).  Cost ≫ the checklist's
   "30 min – 1 h" estimate; the user-local `make mame-test` before
   commits remains the de-facto gate.  llvm-z80's own two-tier CI
   (`build-and-lit` + `runtime-tests`) covers the compiler track;
   bringing rcbios under CI proper is a separate-scope project, not a
   finishing-bar item.  Revisit if a "rcbios broke and we didn't
   notice for N days" incident ever happens.
4. **README.md as landing doc** — **DONE 2026-06-15**.  Top of README
   now carries a Production status table (clang 5462 B, SDCC 6091 B)
   + a Quick start section listing the build + verify + named-test
   commands, with toolchain requirements.  The chronological
   development history (the original content) is preserved below the
   landing block under a "Development history" header.  Cross-links
   to `tasks/README.md` for the pending-work index.
5. **Size lever decision** — **DECIDED 2026-06-15: accept current size,
   offload further shrink to llvm-z80.**  Rationale: rcbios sits at
   5462 B (10.3 % smaller than SDCC's 6091 B), with no PROM cap to
   break — headroom is "fits the BIOS region above `BIOSAD=0xDA00`
   without encroaching on TPA," and there's substantial cushion.
   Recent drift (5905 → 5462 over ~6 weeks) is entirely from
   accumulated llvm-z80 backend gains *with no rcbios source changes*
   — i.e. the compiler track is delivering shrink for free.  The
   levers in `bios-size-issues.md` (~30 B BSS static-stack reload
   reduction etc.) are quality-not-budget items; landing them would
   churn rcbios source for diminishing returns, while the compiler
   track is a more leveraged investment (one fix benefits every
   downstream).  Conclusion: rcbios is "finished" on the size axis.
   `bios-size-issues.md` stays as a record of *known* clang-side
   shapes the backend could improve; it's now a feature request for
   llvm-z80, not a rcbios todo.

Total ~3–4 h estimated; ~2 h actually spent (item #3 deferred saves the rest).

## Not in scope here

- llvm-z80 backlog (handled by compiler track; #173 etc.)
- MAME upstream filings (per `feedback_mame_upstream_routing`)
- CP/NET protocol-side work (separate checklist)
- cpnos-rom revival (parked — confirmed in this session)
- SDLC physical link (bench-side / host)
- Danish-keyboard MAME work (deferred per its task file)
