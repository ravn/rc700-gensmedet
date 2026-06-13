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

### F1 — recv_byte is already near-optimal as-is

`_transport_pio_recv_byte` spins ~1.04 loop iterations per byte on
average.  The ISR pre-fills the ring before the mainline pop happens
in 96 % of cases.  Eliminating the ring + ISR would save the busy-
poll cost (~37 K instr in this window — 4.6 % of total CPU), AND the
ISR cost (~36 K, also 4.4 %).  Combined ~9 % CPU win, NOT the
99 % win that an "ISR-free INIR" framing might suggest.

**Action:** when scoping INIR (#115), don't sell it on per-byte
recv cost — that's not the bottleneck.  The win is in `snios_rcvmsg`
control flow (no per-byte ISR latency, no head/tail bookkeeping)
and in code size (ring + ISR + busy-poll all go away).

### F2 — Dominant CPU sink is `_impl_conin`, not the RX path

~75 % of the window's instructions hide inside `_impl_conin`'s
busy-poll (compressed as `(loops for ~11132 instructions)` between
VRTC IRQs).  This is BDOS's idle loop while waiting for the next
CP/NET response — between F_READ requests, control returns through
BDOS-CONST/CONIN which scans `kbd_head/kbd_tail` and the SIO-B
status port.

**Action:** any "speed up CP/NET RX" investigation needs to
distinguish RX-active CPU (~10 %) from BDOS-idle CPU (~75 %).  The
INIR refactor (#115) addresses the former.  The latter is a
CP/M-architectural concern (BDOS calls CONST during idle waits) and
isn't fixable without restructuring the wait path — likely out of
scope.

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

- T-A: INIR refactor scoping update — re-frame the win as control-flow
  + code-size, NOT per-byte CPU.  Update issue #115 narrative.
- T-B: Document the windowed-trace pattern in `cpnos-shared/docs/`
  so future race investigations don't re-derive it.
- T-C: Cross-correlate the conin busy-poll cost against a longer
  trace (full PRIMES execution stage 3, no CP/NET) to confirm F2's
  CP/M-architectural framing — should see same ~75 % conin even
  without CP/NET activity.

## Not raised

- Mpm-net2 wall-clock-sensitivity workaround: NOT pursued.  The
  windowed-trace pattern bypasses it.  Production path (without
  trace) is unaffected.
- Sound-card SIGPIPE: already addressed by `-sound none` default in
  mame_capture.sh (commit `63d0dfc`).
- Daisy IRQ annotation: already shipped in ravn/mame `390ebf4` and
  exercised by this trace (1982 annotations).
