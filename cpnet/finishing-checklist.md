# CP/NET — finishing checklist (2026-06-03)

What's left to call CP/NET "finished" per the four-component long-term goal
(`tasks/memory/project_finishing_firmware_components.md`).  Round 1 audit;
pair with the other three component checklists.

CP/NET is a cross-cutting layer: the wire protocol + transport stack used
by **both** rcbios (SNIOS.SPR) **and** cpnos (transport_pio.c /
transport_sio.c).  This checklist covers the protocol-and-transport stack
itself, not the firmware that hosts it (those are in their own checklists).

## TL;DR

**Production-ready and stable; the finishing surface is doc consolidation +
spec-vs-implementation re-verification, not bug fixing.**  Per
`cpnet/CPNET_SYSTEM.md` status = ✅ Production Ready.  All three transports
(PIO-IRQ, SIO, retired-proxy) tested end-to-end via polypascal-test in
both cpnos and rcbios contexts.  **Zero open code bugs.**  One small open
todo (`todo-ppas-sub-direct-vs-proxy-2026-05-19.md`) is documented +
non-blocking.

What needs work: **13 markdown docs in `cpnet/` plus 3 in
`cpnos-shared/docs/`** add up to a sprawling, slightly drifted documentation
estate.  Three of those reference the **parked `cpnos-rom`** rather than
the current production `cpnos-in-c` — that's the most concrete drift to
close.

## Status: known bugs

No `known-bugs.md` exists for CP/NET specifically.  Working from `cpnet/`
contents + session memory + `TEST_RESULTS.md`:

| Topic | State |
|---|---|
| DRI binary protocol (ENQ/SOH/STX/ETX/EOT framing, 2's-complement checksum) | **PRODUCTION; verified by polypascal-test on both transports** |
| Mid-frame busy-wait deviation | **FIXED in C** (session 57 Phase 5+6 of #75) |
| FNC=0xFF/0xFE proxy-only handling | **clarified + scoped** (session 56) |
| `cpnet/todo-ppas-sub-direct-vs-proxy-2026-05-19.md` | **OPEN — documented inline + non-blocking** (PPAS.COM load through proxy works; direct connection times out — likely a transport-tuning issue, not protocol) |
| `proxy` transport | **retired (Phase 51A)** — may still be referenced in stale docs |

Net: zero open code bugs blocking production.

## Status: doc gaps + drift (the main surface)

`cpnet/` carries **13 markdown docs** (last touched May 18–20; quiet for
~2 weeks); `cpnos-shared/docs/` adds **3 more**.  This is a lot to keep
current as the components evolve.

| Doc | Status |
|---|---|
| `cpnet/CPNET_SYSTEM.md` | **canonical landing doc**; production-ready stamp; still the right top-level. |
| `cpnet/TEST_RESULTS.md` | **dated 2026-03-07** — should be re-stamped with current test pass-times (polypascal-test was last measured ~50.65 s clang on session 73s-cont2). |
| `cpnet/CPNOS_SIZING.md` | analysis doc; check for stale references to cpnos-rom. |
| `cpnet/DRI_PROTOCOL.md`, `cpnet/MAME_MPM_WIRE_FORMAT.md`, `cpnet/MPMNET_ANALYSIS.md`, `cpnet/Z80PACK_MPMNET.md` | spec + analysis; production-stable surface — re-read once for consistency, then freeze. |
| `cpnet/PIO_TRANSPORT.md`, `cpnet/SERIAL_PROTOCOLS.md`, `cpnet/PARALLEL_TRANSPORT.md`, `cpnet/SPLIT_CHANNEL_TRANSPORT.md` | transport docs; check for stale `proxy` references. |
| `cpnet/SPR_FORMAT.md` | SNIOS.SPR binary format; production-stable. |
| `cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md` | **authoritative wire spec; lists `cpnos-rom/snios.s + snios_c.c` as the slave** — needs update to `cpnos-in-c/src/snios_c.c + transport_pio.c + transport_sio.c`. |
| `cpnos-shared/docs/MEMORY_MAP.md` | **RESOLVED 2026-06-03.**  Replaced with a 1-page pointer to the new `cpnos-in-c/docs/memory_map.md` (post-two-PROM authoritative version). |
| `cpnos-shared/docs/PORT_OUTPUTS.md` | still references parked cpnos-rom; same treatment recommended (replace stale body with pointer to a current cpnos-in-c port doc, or rewrite). |
| `cpnet/todo-ppas-sub-direct-vs-proxy-2026-05-19.md` | one open todo; resolve or formally park. |

**The single highest-leverage doc fix:** update the three
`cpnos-shared/docs/` files to reference `cpnos-in-c` instead of the parked
`cpnos-rom`.  Without this, the wire-protocol spec points at code that
isn't shipping.

## Status: oracle coverage

| Target | What it asserts | State |
|---|---|---|
| `cpnet/polypascal_pio_test.sh` | end-to-end CP/NET via PIO, rcbios SNIOS | PASS, ~10.50 s clang per CLAUDE.md |
| `cpnos-in-c make cpnos-polypascal-test TRANSPORT=pio-irq` | end-to-end via PIO from cpnos slave | PASS, ~51 s clang |
| `cpnos-in-c make cpnos-polypascal-test TRANSPORT=sio` | end-to-end via SIO from cpnos slave | PASS per session 73s-cont2 |
| `cpnos-in-c make cpnet-smoke` | basic CP/NET ping (sio) | PASS per session |
| `cpnos-in-c make sio-smoke` | SIO-only smoke | PASS |
| `cpnet/chksum_roundtrip_test.sh` | DRI checksum implementation roundtrip | PASS |
| `cpnet/run_test.sh` | broader CP/NET regression suite | PASS per Mar 2026 TEST_RESULTS.md |

**Matrix:** (cpnos, rcbios) × (PIO, SIO) — four cells, all passing.

**Gap:** No single CI gate that runs the full CP/NET matrix; today it's a
mixture of per-component `make` targets exercised by hand or by the
runtime-tests job indirectly.  Worth confirming the runtime-tests CI
actually covers all four cells; if it doesn't, that's a "finishing" item.

## Status: size headroom

Not the limiting axis here.  SNIOS.SPR was 1664 B (12 sectors) per session
73k after the PIO transport landed; that's allocated space, not a hard
cap.  cpnos's transport_pio.c / transport_sio.c contribute to cpnos's
2 KB cap, which is tracked in the cpnos checklist.

## External dependencies

- **z80pack mpm-net2 master**: required for any end-to-end test.  Memory
  rule `feedback_session_start_kill_daemons` covers the daemon hygiene.
- **MAME**: needs `cpnet_bridge` slot device (in `ravn/mame:bus/rc702/`)
  for the PIO transport.  Local to the fork; not upstream.  `ravn/mame#6`
  (z80pio drops IM2 IRQs with two slot devices) was the original gate;
  workarounds failed per `project_ravn_mame_6_workarounds_failed.md`.
- **rcbios SNIOS.SPR build**: hand-assembled, dual-density layout
  (DRI bitmap technique) — see `cpnet/SPR_FORMAT.md`.
- **llvm-z80**: no open issue specific to CP/NET.

## Concrete close-out items (ordered)

1. **Update cpnos-shared/docs/ to reference cpnos-in-c instead of cpnos-rom.**
   Three files: `CPNET_WIRE_PROTOCOL.md`, `PORT_OUTPUTS.md`,
   `MEMORY_MAP.md`.  The wire spec is the load-bearing one.  ~30 min.
2. **Re-stamp `cpnet/TEST_RESULTS.md`** with current test pass-times (clang
   polypascal-test 10.50 s rcbios / 50.65 s cpnos).  Drop or annotate
   stale March 2026 numbers.  ~15 min.
3. **Sweep `cpnet/*.md` for stale `proxy` transport references.** The proxy
   was retired Phase 51A; should be marked retired everywhere it appears.
   ~30 min.
4. **Resolve or formally park** `cpnet/todo-ppas-sub-direct-vs-proxy-2026-05-19.md`.
   Either fix the direct-connect path or document as "use proxy for SUB
   workloads, by design."  ~30 min – several hours depending on which.
5. **Confirm CI coverage of the 4-cell test matrix** (cpnos+rcbios) ×
   (PIO+SIO).  If runtime-tests doesn't already, file an issue or wire
   it.  ~30 min.

Total ~2 h baseline + #4 cost.

## FN 105 gettod path for rcbios — scope correction 2026-06-11

**Reframed:** the original "add BDOS-105 forwarding to rcbios's NDOS"
framing was a category error. **This project uses CP/NET 1.2 only**
(see `tasks/memory/feedback_cpnet_12_only.md`), and BDOS-105 ("Get
Date & Time") is a CP/M 3 / MP/M II native call that CP/NET 1.2
predates entirely. Upstream `cpnet-z80/src/ndos3.asm:504` correctly
reflects this: `db 0 ; 105 - GET DATE & TIME - can't support here,
use SEND NW MESG`. Nothing CPNETLDR installs understands BDOS-105,
and under CP/NET 1.2 nothing *can*.

The wire-level path is identical on both slaves: build an FN-105
vendor-extension message frame, send it via BDOS-66 (NSEND), receive
the reply via BDOS-67 (NRECV). Upstream NDOS3 already dispatches
those at `ndos3.asm:518` (`fsdnw`) and `:519` (`frvnw`). So the same
`cpnet/todget/TODGET.COM` binary that works on cpnos **runs
unmodified on rcbios+CPNETLDR** — no rcbios change needed for the
gettod path itself.

**What replaces the original work item:** a regression harness that
proves it. `cpnet/todget_rcbios_test.sh` mirrors `polypascal_pio_test.sh`:
patches rcbios into a fresh disk, injects CPNETLDR/LOGIN/TODGET into
the autoexec, launches MAME against the rebuilt mpm-net2 master,
captures SIO-B CONOUT to file, asserts a `YYYY-MM-DD HH:MM:SS` line
appears. Build the harness before running; needs `--install` of the
rebuilt MPM.SYS so the master-side FN-105 handler is live.

**Knock-on, retired 2026-06-11:** the original plan was to delete
rcbios's 32-bit CTC-tick counter once FN-105 was working. That's now
**wontfix** (closed #111): the `0xDA56` vendor-extension entry is
part of the rcbios BIOS jump-table ABI, and any compiled CP/M program
that calls into it would break — including the "stub returns 0xFF"
shape, since callers expect counter semantics. The counter and ISR
stay; FN-105 over BDOS-66/67 is a purely additive **recommended**
path for new programs that want wall-clock time. Time on rcbios is
two concepts (local counter + FN-105 wire) by design.

**Memory rule context:** decision walkthrough — long-uptime-drift
vs. per-call round-trip latency — in 2026-06-10 chat. Short version:
RC702 in this project never operates disconnected from the master,
so per-call round-trip beats counter-state correctness risk.

**Explicitly deferred:** "BDOS-105 as a *native intercepted call*
inside the slave NDOS" only makes sense on cpnos's project-owned C
NDOS (where we control the dispatch); on rcbios the dispatcher is
upstream-locked CP/NET-1.2 asm and out of scope. Track as a cpnos
follow-up only.

## Not in scope here

- ravn/mame#6 (PIO-B slot regression) — separate `project_ravn_mame_6`
  tracking; workarounds known to fail.
- SDLC physical link (`sdlc-hw-test`) — host-side / bench; not the
  production transport.
- Wire-protocol changes — protocol is DRI-spec frozen since 1980;
  changes are off-limits.
- llvm-z80 backlog — handled by the compiler track.
