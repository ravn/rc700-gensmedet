# rcbios-in-c — tasks index

Last triaged: 2026-06-15.

## Active references

| File | State | Purpose |
|---|---|---|
| [`finishing-checklist.md`](finishing-checklist.md) | live | The "what's left to call rcbios finished" master list.  Refreshed 2026-06-15 with current sizes (5462 / 6091). |
| [`todo.md`](todo.md) | live | Phase tracker — chronological work log + current follow-ups (e.g. `[ ] RXTHLO=240 RX-ring hysteresis`). |
| [`lessons.md`](lessons.md) | live | Cross-session lessons that aren't tied to one specific issue (e.g. the `OUT (0x18) PROM disable must run from RAM` lesson). |

## Open feature plans / known issues

| File | State | One-line summary |
|---|---|---|
| [`26-line-status.md`](26-line-status.md) | **PARKED 2026-06-14** | CRT26 + DMA-split status line via ch3 roll function.  Plan recorded; resume when rcbios finishing-checklist is the active workload.  Cross-ref: `docs/dma_ch3_8275_roll_function.md`. |
| [`bios-size-issues.md`](bios-size-issues.md) | OPEN | Size-recovery levers (BSS static-stack reload reduction ~30 B etc.).  Quality, not budget — no breakage risk from size. |
| [`siob-rx-no-stack-switch.md`](siob-rx-no-stack-switch.md) | OPEN (orthogonal) | SIO-B RX ISR stack-switch investigation; current main has a different ISR shape, but the *orthogonal* concerns in the doc may still apply. |
| [`two-port-deploy-script.md`](two-port-deploy-script.md) | OPEN | `deploy.sh` improvement: keep `siob_daemon.py` in-tree, auto-detect single vs dual-port mode.  Operational tooling, not BIOS code. |
| [`mame-danish-keyboard.md`](mame-danish-keyboard.md) | **DEFERRED** | MAME host-to-RC702 Danish keyboard mapping broken (reported 2026-04-17).  Workaround: use the in-MAME keyboard.  Not blocking production. |
| [`test-cases/`](test-cases/) | live test fixtures | Test inputs used by `make conout-test`, `make bgstar-test`, etc. |

## Historical archive

[`history/`](history/) — closed, resolved, superseded, or one-time session reports.  Preserved for context but not part of the active surface.  Browse there if you need rationale for past decisions.

Contents (2026-06-15):

- **Session reports**: `session10-summary.md`, `session10b-summary.md`, `session17-merge-notes.md`, `session17-siob-console.md`, `session18-serial-speed.md`, `session20-sdlc-summary.md`, `session23-sio-flow-control.md`, `session32-llvm-codegen-fixes.md` — chronological snapshots from earlier development phases.
- **Closed items**: `siob-console-dipswitch.md` (DONE), `sio-independent-rates.md` (RESOLVED: not possible — physical limit), `todo-rcbios-sfr-port-io-2026-05-19.md` (CLOSED), `parallel-port-transfer.md` (REJECTED).
- **Resolved investigations**: `stack_corruption_investigation.md` (2026-03-08; symptoms gone since BIOS boots to `A>`).
- **Bench-side**: `sdlc-hw-test.md` (physical hardware SDLC bench notes).
- **Superseded plans**: `cpnos-rom-plan.md`, `cpnos-issues.md` (cpnos-rom was parked; cpnos-in-c is the current target — these belong with cpnos-in-c history, kept here for git-log continuity).

## Conventions for new task files

- One file per coherent concern.  If a file has multiple unrelated items, split.
- First line: title.  Second/third line: status (e.g. `> **STATUS: PARKED 2026-06-14.**`) so it's visible without opening the file.
- When closed/done/parked, add a status line then either keep in `tasks/` (if active reference) or `git mv` to `tasks/history/`.
- Update this README when adding/moving files.
