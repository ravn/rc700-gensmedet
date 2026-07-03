# cpnos-in-c — tasks index

Last triaged: 2026-06-15.

## Active references

| File | State | Purpose |
|---|---|---|
| [`finishing-checklist.md`](finishing-checklist.md) | live | "What's left to call cpnos finished" master list.  Refreshed 2026-06-15 with current PROM1 size (2015 / 2048, 33 B free). |
| [`tpa-compaction-analysis-2026-07-03.md`](tpa-compaction-analysis-2026-07-03.md) | **live** | TPA compaction analysis: TPA ~54.4 KB (near CP/M ceiling); levers = relocatable resident (T6), locale tables (384 B), PIO ring (INIR-parked). |
| [`cpnet-tod-and-netboot-findings-2026-07-03.md`](cpnet-tod-and-netboot-findings-2026-07-03.md) | **live** | Session findings: no-Lua PPAS injector (autoboot breaks PIO netboot), TOD `ff` = stale MPM.SYS, CP/NET SID/login model, tasks T1–T5. |
| [`PIO_INIR_PARKED.md`](PIO_INIR_PARKED.md) | **PARKED 2026-06-14** | `#115` Steps 2+4 (PIO → INIR refactor) waiting on physical RC702 + Pi/Pico bridge. |
| [`TWO_PROM_PARKED.md`](TWO_PROM_PARKED.md) | PARKED | Two-PROM build (cpnos PROM0 + slave PROM1) parked 2026-05-17 — production sole topology is autoload PROM0 + cpnos PROM1-only line program. |

## Open feature plans / experiments

| File | State | One-line summary |
|---|---|---|
| [`circular-scroll-plan.md`](circular-scroll-plan.md) | planned (2026-06-14) | Replace 1920-byte LDIR scroll with ch2/ch3 roll-function circular scroll.  See `docs/dma_ch3_8275_roll_function.md`.  Decisions still open: buffer size, memory layout, ordering vs INIR Steps 2+4. |
| [`conout-graphics-codes-2026-05-17.md`](conout-graphics-codes-2026-05-17.md) | planned | impl_conout: implement RC700 graphics-overlay control codes 0x14 / 0x15 / 0x16. |
| [`todo-dma-dual-buffer-2026-05-17.md`](todo-dma-dual-buffer-2026-05-17.md) | planned | DMA dual-buffer scroll experiment (user-flagged; related to circular-scroll-plan). |
| [`todo-translation-tables-2026-05-17.md`](todo-translation-tables-2026-05-17.md) | planned | Reserve translation-table space + hook default tables. |
| [`todo-load-from-cpnos-img-2026-05-17.md`](todo-load-from-cpnos-img-2026-05-17.md) | planned | Load tables + SEM702 font from cpnos.img at boot. |

## Open size/compression levers

| File | State | One-line summary |
|---|---|---|
| [`todo-cpnos-img-zx0-compression-2026-05-17.md`](todo-cpnos-img-zx0-compression-2026-05-17.md) | planned | ZX0-compress cpnos.img to free more space. |
| [`todo-cpnos-relocatable-2026-05-17.md`](todo-cpnos-relocatable-2026-05-17.md) | planned | Make cpnos.img relocatable (.PRL / .SPR style). |
| [`todo-prom1-compression-to-restore-bootmark-2026-05-17.md`](todo-prom1-compression-to-restore-bootmark-2026-05-17.md) | planned | Compress PROM1 further so `BOOT_MARK_ENABLED=1` can ship. |
| [`todo-56k-tpa-2026-05-17.md`](todo-56k-tpa-2026-05-17.md) | planned | Push TPA from 55 K to 56 K (boot banner reports "56K"). |

## Open infrastructure / tooling

| File | State | One-line summary |
|---|---|---|
| [`todo-polypascal-no-mirror-stage4-2026-05-17.md`](todo-polypascal-no-mirror-stage4-2026-05-17.md) | partial-experiment | polypascal-test-no-mirror stage 4 ">>" detection — primary path works, no-mirror variant has an open detection issue. |
| [`todo-mame-build-binary-name-2026-05-17.md`](todo-mame-build-binary-name-2026-05-17.md) | low priority | MAME build binary naming drift (regnecentralend vs mame).  Doc/Makefile cleanup. |

## Test fixtures (not task files)

| File | Purpose |
|---|---|
| `check_no_frame_ptr_baseline.txt` | Baseline assertion list for the frame-pointer-free check. |
| `check_unreferenced_publics_allowlist.txt` | Allowlist for the unreferenced-publics build check. |
| `sdcc-ix-frame-repro.c`, `sdcc-switch-dead-code-repro.c` | C reproducers kept alongside their writeups (writeups archived to `history/`). |
| `inir-baseline-trace-2026-06-13-partial-watchpoint.log` | Captured trace from the INIR investigation; reference for future INIR work. |

## Historical archive

[`history/`](history/) — closed, resolved, superseded, or one-time session reports.  Preserved for context but not part of the active surface.

Contents (2026-06-15):

- **Session reports** (6): `session-2026-06-13-phase4-inir-and-mame-findings.md`, `session-2026-06-14-{analysis,inir-step-0-1-shipped,inir-step-2-4-blocked-on-size,windowed-trace-analysis}.md`, `session47-analysis-2026-05-08.md`.
- **Historical investigations / planning docs that landed** (10): `compare-clang-vs-sdcc-handoff-2026-05-08.md`, `cpnet-pio-throughput-baseline-2026-06-12.md` (pre-INIR baseline), `cpnos-split-plan-2026-05-15.md` (split landed), `dri-cpnos-source-audit-2026-05-08.md`, `dual-header-plan-2026-05-08.md` (landed), `issue-29-ivt-relocation-plan.md`, `memory-layout-investigation-2026-05-06.md`, `pio-input-busy-wait-and-inir-2026-06-12.md`, `probe-results-2026-05-08.md`, `shrink-investigation-2026-05-17.md`.
- **SDCC investigation / regression / fix records** (5): `sdcc-codegen-gap-2026-05-18.md`, `sdcc-port.md`, `sdcc-prom1only-{netboot-regression,polypascal-fixed}-2026-05-18.md`, `sdcc-switch-dead-code-repro.md`.
- **DONE / DEFERRED-with-measurement** (2): `8237-autoinit-drop-dma-reprogram-2026-05-17.md` (DONE 2026-06-14 as `#115` Step 0, commit `9592c2d`), `todo-cpnos-prom1lineprog-single-chunk-2026-05-17.md` (DEFERRED with measurement, decision made).

## Conventions for new task files

- One file per coherent concern.  If a file accumulates multiple unrelated items, split.
- First line: title.  Second/third line: status (e.g. `**Status:** TODO`, `> **STATUS: PARKED 2026-06-14.**`) so it's visible without opening the file.
- When closed/done/parked, add a status line then either keep in `tasks/` (if active reference) or `git mv` to `tasks/history/`.
- Update this README when adding/moving files.
