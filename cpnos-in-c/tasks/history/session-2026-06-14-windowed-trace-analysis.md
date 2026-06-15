# Session 2026-06-14 — windowed-trace analysis of stage 25 (L PRIMES load)

First trace produced by the new `cpnos-polypascal-test-trace-window`
target (workspace `fb6f683`).  Window covers stage 25 (entry of
`L PRIMES` command to detection of post-load `>>` prompt), 723 sim ms
on a clang prom1-lineprog (`-z80-enable-cse=false`, dual PIO+SIO).

Test PASSed end-to-end (50.5 sim sec, 320 % real-time average) — the
windowed approach keeps mpm-net2 in sync.  The all-trace variant
(`-trace`, no window) wedges mpm-net2 ~14 sim sec in; this confirms
the boot + PPAS-load phase is the part that overruns master's
wall-clock retry budget, not the PRIMES load itself.

## Inputs

- `/tmp/z80_trace.txt` — 132 280 lines, 2.5 MB.
- `/tmp/cpnos_dir_bridge.log` — interleaved into the trace via
  `LOG_BRIDGE 1` (default in cpnet_bridge.cpp).
- Window: t = 28.176 → 28.900 sim sec (slave's PIO clock); first
  bridge event is `rdy_w(0)` at t = 28.176 316 s.
- Frames observed: 12 complete CP/NET frames (`_snios_rcvmsg_c`
  entered 12 times at F434).
- Bytes RX'd from master: 1904 (`_recv_byte_t` at F59A called 1904
  times — exactly one call per protocol byte).
- Bytes TX'd to master: 640 (cpnet_bridge `write(..)` count).
- IRQ acks: 1982 (`(interrupted at ..)` annotations).  Of these,
  ~1900 are PIO-B parallel RX (one per byte); the remaining ~80
  are VRTC `_isr_crt` (~50 Hz × 723 ms ≈ 36) + PIO-A kbd ISR fires.

## Cycle distribution

Total Z80 instructions executed in the window (visible + compressed
loops) ≈ 808 K.  Three loop bodies dominate:

| Loop                                  | PCs            | Calls                       | Instr (% of 808K) |
|---------------------------------------|----------------|-----------------------------|-------------------|
| `_transport_pio_recv_byte` busy-poll  | F2CE..F2DC     | 1980 iter (~1.04/byte)      | ~37 K   ( 4.6 %)  |
| `_isr_pio_par` ISR body (CP/NET RX)   | EEEC..EF0B     | 1982 fires × 18 instr       | ~36 K   ( 4.4 %)  |
| `_impl_conin` busy-poll (idle/kbd)    | F1A6..F1B1     | bulk of compressed time     | ~600 K  (~75 %)   |

The ISR-drop path `_isr_pio_par_drop` (EF07) is hit **0 times** —
the 256-byte SPSC ring never overflows under flow-controlled CP/NET.

## Findings

### F1 — slave per-byte ISR cost IS the bridge throughput ceiling (corrected 2026-06-14)

Initial read of this trace concluded `_transport_pio_recv_byte`
busy-poll spinning ~1.04 iter/byte meant the slave had spare CPU.
**That was wrong.**

The bridge's STB cycle is gated by the chip's BRDY rising-edge
callback (`cpnet_bridge::rdy_w`), which fires only AFTER the Z80
ACKs the previous byte by completing `_isr_pio_par`.  So the burst
rate is set by the slave's ISR cycle time, not by mpm-net2.

Measured intra-burst spacing (1834 read events from the trace):

| Gap bucket (us) | Count |
|-----------------|-------|
| 50..59          | 1541  |
| 60..69          | 71    |
| 70..89          | 144   |
| <50 (outliers)  | 46    |
| mean            | 54.6  |

`_isr_pio_par` body = 183 T-states + Z80 IRQ-ack ~19 T = ~200 T =
50 us at 4 MHz.  The 54.6 us measured spacing IS the ISR cycle —
the slave is essentially at 100 % CPU during bursts.  The busy-poll
doesn't spin because the ring drains as fast as it fills, and that
shared rate IS the ceiling.

**Per-byte CPU breakdown during bursts:**

| Source                    | T-states | us/byte | Bridge rate |
|---------------------------|----------|---------|-------------|
| ISR body + IRQ ack        | ~200     | 50      | ~20 kB/s    |
| Hypothetical INIR loop    | ~21      | 5       | ~190 kB/s   |

**Window time accounting:**

- Intra-burst transfer time: 1834 byte gaps × 54.6 us = 100 ms = 14 % of window
- Inter-frame idle time: 623 ms = 86 % of window (slave in conin, see F2)

Per-byte CPU savings under INIR = ~90 % of intra-burst time = ~12 %
of stage-25 wall-clock.  That's a measurable speedup of L PRIMES
load itself.

**More importantly:** lifts the per-byte ceiling from ~20 kB/s to
~190 kB/s, which is necessary for real Pi/Pico bridge hardware
(task #11) where the bridge could otherwise push bytes faster than
the slave can drain them — a regime where the current ISR-based
design would silently lose bytes (chip's m_input overwritten before
Z80 reads it).

**Action:** INIR refactor (#115) is justified on per-byte CPU cost
AFTER ALL.  The pitch is correct as originally framed; my initial
read of the busy-poll fanout was the error.  Re-prioritise #115
to track this measured ceiling explicitly.

### F2 — Inter-frame idle hides in `_impl_conin`, ~86 % of window

~600 K of the window's ~808 K instructions are compressed loops
preceded by `_impl_conin` PCs (F1A6..F1B1) — BDOS's idle loop
between CP/NET responses.  This is the ~30 ms inter-frame gap × 12
frames = ~360 ms, plus some during the initial wait for the first
frame.

This is the EXPECTED CP/M behaviour — BDOS-CONST polls during
network waits so the user can still type ahead.  The win here would
require a structural BDOS change (HLT until IRQ + smarter CONST gate),
NOT addressable by the INIR refactor.

**Action:** out of scope for #115.  Mention in task #21's
cross-correlation: a no-CP/NET stage-3 window should show ~100 %
conin (every IRQ between VRTC fires = pure idle), which would
confirm conin is the slave's universal idle loop, not specifically
a CP/NET-induced cost.

### F3 — Frame cadence: 12 frames in 723 ms = 60 ms/frame

Each frame is ~30 ms of active byte transfer + ~30 ms inter-frame
gap.  Inter-frame gap is mpm-net2 processing the prior request and
issuing the next response.  This is mpm-net2-bound, not slave-bound.

**Action:** worth verifying on real Pi/Pico bridge hardware that
inter-frame gap shrinks proportionally to the host's network latency
(task #11).

### F4 — ISR ring sizing margin is huge (zero drops)

Trace evidence justifies retiring the explicit drop-path log in
isr_pio_par for code-size if INIR refactor pursues that path.
Already noted in `cpnos-in-c/tasks/pio-input-busy-wait-and-inir-2026-06-12.md`;
this trace confirms with empirical zero in the L PRIMES window.

### F5 — All bridge logs come INTERLEAVED in the trace correctly

The `LOG_BRIDGE 1` lines appear in chronological order with the
Z80 instructions, which means the bridge-side events can be
cross-correlated to slave PC without external timestamp matching.
The `[NNNNNNN us]` microsecond timestamps (commit `4ade365`) are
sim-time, identical to MAME's PIO chip clock.  This is the right
diagnostic surface for any race investigation; no other tooling
needed.

## Tasks raised

See harness TaskList for tracking — entries created in this session:

- T-A (REVISED): Update #115 narrative with the measured ~50 us/byte
  ISR ceiling.  Pitch is correct as originally framed -- per-byte
  CPU IS the bottleneck.  Add measured numbers (20 kB/s vs 190 kB/s
  ceiling) so the priority is visible.
- T-B: Document the windowed-trace pattern in `cpnos-shared/docs/`
  so future race investigations don't re-derive it.
- T-C: Cross-correlate against a no-CP/NET stage-3 window — should
  show conin even MORE dominant (no RX bursts at all), confirming
  conin is the universal idle loop.

## Not raised

- Mpm-net2 wall-clock-sensitivity workaround: NOT pursued.  The
  windowed-trace pattern bypasses it.  Production path (without
  trace) is unaffected.
- Sound-card SIGPIPE: already addressed by `-sound none` default in
  mame_capture.sh (commit `63d0dfc`).
- Daisy IRQ annotation: already shipped in ravn/mame `390ebf4` and
  exercised by this trace (1982 annotations).
