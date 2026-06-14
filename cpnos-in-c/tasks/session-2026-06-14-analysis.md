# Session 2026-06-14 — analysis + follow-ups

Companion to `session-2026-06-14-inir-step-0-1-shipped.md` (which
documents the work shipped) and `session-2026-06-14-windowed-trace-analysis.md`
(which captured the ISR throughput-ceiling measurement that motivated
the work).  This file is the post-mortem: what the session changed
about our understanding, and what follow-ups it surfaced.

## What we knew at session start

- Per-byte ISR cost was the PIO RX ceiling (measured: ~50 us/byte,
  20 kB/s) from the 2026-06-14 windowed trace.
- INIR could lift the ceiling to ~5 us/byte (190 kB/s).
- Variant H (drain + bare INIR, no chip-IE bracket) had been tried
  2026-06-13 and failed at PPAS.ERM load.
- Adding a `DI` bracket would fix the ISR-mid-INIR race, but would
  freeze display refresh — the 50 Hz VRTC ISR wouldn't run, the
  DMA channel would dormant on terminal count, the screen would
  garble after ~10 ms.
- cpnos already had DMA mode `0x5A` (autoinit ON) in `init.c:224-225`,
  but the ISR was still re-programming addr/count every VRTC.

## What we learned this session

### 1. The autoinit programming was inert until Step 0

User flagged it: "rcbios and cpnos have different implementations."

Investigation showed three components with three layouts:

| Component        | DMA mode | Autoinit? | ISR re-programs per VRTC? |
|------------------|----------|-----------|---------------------------|
| autoload-in-c    | 0x4A     | No        | Yes (addr + count)        |
| rcbios           | 0x4A     | No        | Yes (addr + count)        |
| cpnos-in-c (pre) | **0x5A** | **Yes**   | **Yes (addr + count)**    |

cpnos's `0x5A` was set in `init.c` but the `isr_crt` reload was running
anyway.  The ISR's explicit reload happened BEFORE the chip's autoinit
reload would have, so autoinit was masked / inert.  Net behavior was
indistinguishable from a non-autoinit setup.

**Why:** likely an oversight when the ISR was originally written
(SDCC era?) — `0x5A` was programmed expecting autoinit to carry, but
the ISR was copy-pasted from an autoload pattern that did per-frame
reload.  Both paths "worked" so the redundancy went unnoticed.

**Step 0** removed the redundancy: stripped the ISR reload, leaving
autoinit alone to handle refresh.  Verified by video capture (5 frames
across full polypascal-test) — display stays crisp.

### 2. Step 0 enables a `DI` bracket cheaply

With the ISR shrunk from ~180 T to ~30 T AND not driving display, a
`DI` block holds the VRTC IRQ pending without consequence:

- Display refresh: 8237 autoinit reloads its base regs on terminal
  count, continues fetching from 0xF800.  Self-sustaining.
- Frame counter: ticks halt during DI.  ~1.5 ms = 0.075 frames lost
  per max-size data block.  Negligible.
- 8275 cursor: deferred update happens at next VRTC after EI.
  Cosmetic delay only.

This is the structural enabler for any future bulk-RX work that
needs DI (INIR, real-hw bulk DMA-to-mem, etc.).  Step 0 ships
independently and is the "minimum viable change" even if #115 stalls.

### 3. Step 2+4 hit the 2 KB PROM cap

The wire-up cost (`transport_pio_recv_block` C + `transport_uses_pio`
flag + snios_c.c branch + post-block CKS fold) was +232 B raw, +176 B
post-ZX0 compression — 176 B over the 2 KB PROM cap.

This is the recurring code-density tax on the cpnos PROM1 line program.
We've been spending headroom on protocol robustness (snios_c.c retries,
error handling) and the 2 KB cap is hard (no A11 on user's hardware).

**Two paths forward** (documented in task #28):
- Hand-rolled asm `transport_pio_recv_block` (~40 B vs ~70 B C).
  Saves ~30 B; tight fit but works.
- Bundle with PIO_RX ring shrink (256 → 16, frees ~240 B in PIO_RX
  region) + TPA-grow.  Cleanest architecturally; one layout
  migration vs two.

### 4. The 2026-06-14 windowed-trace baseline may now be stale

The trace measured 54.6 us mean inter-byte gap, with isr_pio_par
~184 T / 46 us.  That left ~8 us unaccounted for — probably CTC tick
+ isr_crt firing 1-2 times during a typical 100 ms burst window
(50 Hz × 100 ms = 5 VRTC fires × 180 T = 0.9 ms of isr_crt CPU = 9 us
spread).

**After Step 0:** isr_crt is ~30 T per VRTC.  5 fires × 30 T = 150 T =
1.5 us spread.  Steady-state intra-burst gap should drop by ~7 us to
~47 us mean.

This is testable (task #26).  Result determines how much remaining
gap is recoverable by INIR vs how much is isr_pio_par-bound.

### 5. cpnos isn't trivially safe to refactor with rcbios

The rcbios/cpnos divergence is intentional given the DMA mode
difference.  Sharing isr_crt requires either:
- Bring rcbios to mode `0x5A` autoinit (and verify floppy-load DI
  windows still work — rcbios DOES do floppy access)
- Bring cpnos back to mode `0x4A` non-autoinit (regress Step 0)
- Parametrize the shared isr_crt with a build-time autoinit flag

Task #22's scope just got more concrete: the shared layer needs an
autoinit-on/off configuration option.

## Risks/edge cases noted

### PIO-A keyboard input during DI window

Tracked as task #29.  ~1.5 ms DI per max-size frame.  Two consecutive
keystrokes within the DI window: only the latter latches; the first
is lost (PIO Mode 1 input on A doesn't queue; new strobe overwrites
m_input).  In CP/NET file load (PRIMES, PPAS source) the user is
expected to wait — but if they're typing-ahead, characters could be
silently dropped.

Mitigation options (task #29):
- Sub-block INIR: chunk the data block into N×64-byte INIRs, EI
  between, so PIO-A ISR can fire.  Costs an EI/DI pair per chunk
  (~24 T × N chunks) and reopens a smaller race window.
- Accept the limitation, document in CPNET_WIRE_PROTOCOL.md.

### Function-pointer vs JT-trampoline dispatch

The current `xport_send_byte` / `xport_recv_byte` dispatch goes
through 3-byte JP-NN trampolines patched at install_transport().
Adding a third dispatch slot for `xport_recv_block` would mirror the
pattern but adds 3 B + setup cost.  Simpler: a single `transport_uses_pio`
flag (1 B + 1 B comparison) read in snios_c.c.

Going with the flag for Step 2+4 retry.  Don't carry the JT-trampoline
pattern further; the runtime-flag pattern is cheaper at this scale.

## Follow-ups raised (TaskList)

- #19 (updated) — Update #115 narrative with measured per-byte ISR
  ceiling AND post-Step-0 re-measurement.
- #26 (new) — Re-measure intra-burst byte gap on post-Step-0 build
  to refine the INIR pitch.
- #27 (new) — Audit autoload-in-c for autoinit re-adoption.
- #28 (new) — PIO_RX ring shrink 256→16 + TPA-grow bundle to
  unblock #25's size cap.
- #29 (new) — Document DI window's effect on PIO-A keyboard input.

## Candidate GitHub issues NOT filed

Per `feedback_explain_before_filing` (HARD): no upstream filings
without explicit per-filing user go-ahead.  Candidates to surface:

- **ravn/rc700-gensmedet#115 update** — narrative refresh with
  measured ceiling + Step 0 ship + re-measurement plan.  Worth
  filing once #26 has data.
- **ravn/rc700-gensmedet new issue** — "cpnos isr_crt redundant DMA
  reload (autoinit was inert)".  Closed by 9592c2d; could file as a
  closed-issue post-mortem to surface the pattern.
- **ravn/rc700-gensmedet new issue** — "PIO_RX ring sizing post-INIR-
  refactor" (#28 substance).  File when re-attempting #25.

Not filing now.  These are local follow-ups until the user picks one
to externalize.

## Lessons (worth memory rules, candidate)

Three patterns surfaced this session that could become durable
memory rules.  Not saving yet — flagging here for user review:

1. **"Verify DMA mode bytes are load-bearing, not vestigial."**  The
   `0x5A` had been in cpnos for weeks doing nothing.  A diff-from-
   spec audit at session start could have caught this earlier.
   Trigger: any hardware register write at init time — sanity-check
   that the ISR actually depends on the register being in that state.

2. **"Bundle layout migrations even when they're not the immediate
   blocker."**  The PIO_RX shrink was deferred from 2026-06-13 as a
   "later" item; today it became the cap-relief tool.  Doing it
   earlier would have unblocked Step 2+4 without rewriting asm.
   Trigger: when you defer a layout move and the headroom is < 200 B,
   the next workstream is likely to need it.

3. **"Measure visually for display correctness — diffs don't catch
   garble."**  The 5-frame video capture caught nothing wrong but
   was the only thing that could have caught wrong.  ASSERTs in
   linker scripts catch sizing; video catches behaviour.  Trigger:
   any change to ISR / DMA / 8275 / display memory path needs a
   visual capture verification.

These are candidates only — surface to user before saving.

## Closing state

Steps 0 + 1 shipped, MAME PASS, video verified.  Step 2+4 paused with
two concrete paths forward.  Five follow-up tasks tracked.  rc700
sub-repo + workspace pointer both pushed to origin (rc700 main
`294420c`, workspace main `e081e53`).

This is a good place to start a new session.
