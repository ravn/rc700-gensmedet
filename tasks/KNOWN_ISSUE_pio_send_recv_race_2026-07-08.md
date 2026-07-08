# KNOWN ISSUE — CP/NET PIO SEND→RECV mode-flip race (2026-07-08)

**Status:** open, root-caused, parked. Not on the critical path — production
(cpnos-in-c PIO) works 6/6 without depending on this.

**Symptom:** the rcbios CP/NET PIO polypascal test
(`cpnet/polypascal_pio_test.sh`) reaches `H>` cleanly and starts loading
`H:PPAS.COM` over CP/NET, but the multi-record transfer **stalls partway
through** (deadlock — MAME alive but emulated clock frozen, cpmsim spinning
at ~100 % CPU waiting for a slave response that never comes). The stall
point is **non-deterministic** (observed at ~41 % and ~82 % of PPAS.COM in
different runs), which is the fingerprint of a low-probability timing race
that a long transfer eventually trips.

This is **independent of the 8-bit-clean bridge change** (ravn/mame
`12ea19d0`) — it reproduces identically on the prior 0xff-sentinel bridge.
It is a property of the PIO handshake + the slave's non-atomic mode flip.

## Root cause — SEND→RECV mode-flip race

The CP/NET framing is half-duplex: the slave receives a record, then flips
PIO-B to **output** to send an `ACK` (0x06), then flips back to **input**
to receive the next record. The input-flip in `cpnet/snios.asm`
`PIO_TO_INPUT` (mirrored in `cpnos-in-c/src/transport_pio.c` lines 180-184)
is four separate `OUT (PIO_B_CTRL)` writes:

```
OUT (ctrl), 0x4F   ; Mode 1 input          <-- PIO now samples on STB
OUT (ctrl), 0x97   ; ICW: IE enable + mask follows
OUT (ctrl), 0x00   ; interrupt mask = none
OUT (ctrl), 0x83   ; IE enable             <-- interrupts actually live here
```

Between the **first** OUT (mode = input) and the **last** OUT (interrupts
enabled) there is a window of ~30 T-states where the PIO is in input mode
but the STB→interrupt path is not yet armed.

On the MAME side, `cpnet_bridge`'s 1 ms `poll_tick` strobes a waiting byte
whenever it sees `m_brdy_high` (BRDY high). If that strobe lands in the
window above:

1. `strobe_w(0)` latches the byte (`read()` consumes one FIFO byte —
   the byte is now committed/consumed).
2. `strobe_w(1)` calls `z80pio::trigger_interrupt()` + `set_rdy(false)`
   (BRDY drops).
3. But the slave hasn't armed input-mode interrupts yet → **the interrupt
   is lost**, the consumed byte never reaches `PIO_RING` via `ISR_PIO_RX`.
4. BRDY is now low, so `poll_tick`'s gate (`m_input_index < m_input_count
   && m_brdy_high`) blocks further delivery, and `rdy_w` won't fire again
   until the chip raises BRDY — which only happens on a Z80 `data_read`
   that never comes (the slave is busy-waiting on `HEAD != TAIL` for a byte
   that was silently dropped).

Deadlock: slave waits for a byte it will never get; bridge won't deliver
more because BRDY is stuck low.

### Why MAME's PIO makes this reachable

`z80pio.cpp::set_mode(MODE_INPUT)` (line ~419) sets `m_mode` **without**
touching the ready line — unlike `set_mode(MODE_OUTPUT)` which asserts
BRDY. So Mode-1 entry gives the bridge no `rdy_w` edge to synchronise on;
the bridge is left guessing via the 1 ms poll, and the poll can fire mid-
reconfiguration. See the `ravn/mame#8` note already in
`cpnet_bridge.cpp::poll_tick` ("MAME doesn't auto-raise BRDY on Mode-1
entry per Zilog datasheet").

### MEASURED root cause (2026-07-08 instrumentation)

A targeted `logerror` was added to `z80pio.cpp::check_interrupts()` that
fires only when port B wants to interrupt (`ie && ip`) but the shared IRQ
line stays CLEAR — i.e. B is blocked — dumping both ports' daisy state.
Result at the stall (and throughout):

```
[:pio] [NNN us] PIO-B IRQ BLOCKED  A(ie=1 ip=0 ius=0)  B(ie=1 ip=1 ius=1)
```

Two conclusions, both from direct measurement:

1. **The "two ports A+B interfere" theory is REFUTED.** Port A (the
   keyboard channel) shows `ip=0 ius=0` at *every* blocked event — it never
   has a pending or in-service interrupt during the test (keyboard input
   comes over SIO-B, not PIO-A). It is not the blocker.

2. **Port B is blocked by its OWN stuck in-service bit.**
   `check_interrupts()` computes `ius = A.ius || B.ius`; with `B.ius=1` the
   line is forced CLEAR, so B can never take its next (pending) interrupt.
   `m_ius` is set in exactly one place — `z80daisy_irq_ack` when the CPU
   accepts the interrupt — and cleared only by `z80daisy_irq_reti` (RETI).
   So the CPU *accepted* a B interrupt (B.ius←1) but **no RETI ever cleared
   it**, and it happens right at the `write(06)` ACK-send / output→input
   mode flip. From then on every strobed byte sets B.ip=1 but is suppressed.

The firmware side is correct: `ISR_PIO_RX` ends with `EI` + `RETI`, and
`PIO_TO_INPUT` matches cpnos-in-c `transport_pio.c` (which passes 6/6). So
the stuck `B.ius` is a **MAME z80pio interrupt-model artifact** around the
Mode-0(send)→Mode-1(recv) excursion — the accept/reti bookkeeping loses a
RETI for a B interrupt that was acknowledged during the flux. A real Z80
PIO clears IUS via the daisy IEO chain on the ISR's RETI, so **this is not
expected to reproduce on real hardware.**

### Real-hardware implication

Because both the refuted (two-port) and the confirmed (stuck B.ius)
mechanisms are MAME emulation deficiencies, and the firmware ISR/RETI +
mode-flip sequence are correct, a real RC702 + Pi/Pico bridge is the
decisive validation: if PPAS loads over CP/NET on iron, the firmware is
proven correct and this stall is MAME-only (nothing to fix in the
firmware). This mirrors the parked INIR path, which likewise can only be
hardware-verified (`feedback_ring_shrink_inir_coupled`).

## How to reproduce / observe

```bash
cd rc700-gensmedet
# Build MAME with -log capture (error.log lands in cwd):
( cd /tmp && MAME_DIR/regnecentralend rc702 ... -log -piob cpnet_bridge -bitb3 socket.127.0.0.1:4002 )
# error.log carries the full bridge trace (read()/write()/rdy_w/strobe).
```
`cpnet/polypascal_pio_test.sh` drives the whole flow. The stall shows as
the error.log freezing (byte count + last `[NNN us]` timestamp stop
advancing) while the MAME process stays alive and cpmsim pegs a core.

The last healthy events before a stall are always the same shape:
`write(06)` (slave ACK) → `poll_tick refill` (next frame arrives) →
`rdy_w(0)` (poll_tick strobed one byte) → **freeze**.

## Fix options (none applied — parked)

1. **MAME z80pio (cleanest, correct-hardware):** on `set_mode(MODE_INPUT)`
   assert BRDY (`set_rdy(true)`) so the bridge gets a proper `rdy_w(1)`
   edge at input-mode entry, AND verify `trigger_interrupt` holds the
   interrupt pending across the later IE-enable so no byte is lost. This is
   z80pio correctness work affecting all PIO consumers, not just rc702.
2. **Bridge-side:** stop `poll_tick` from proactively strobing; deliver
   only on `rdy_w` rising edges plus a single guarded kick-start. Less
   invasive but unproven — without a mode-entry BRDY edge the kick-start
   still guesses.
3. **Slave-side:** cannot make `PIO_TO_INPUT` atomic (the four OUTs are
   inherent to the Z80 PIO ICW sequence); could mask the race by draining
   any already-latched byte after arming interrupts, but that fights the
   IRQ-ring design.

**Revised after the 2026-07-08 measurement:** the primary defect is the
stuck `B.ius` (a RETI lost for a B interrupt acknowledged during the
send→recv flip), so the real MAME fix targets the daisy accept/reti
bookkeeping (option 1's interrupt half) — assert-BRDY-on-Mode-1 (option 1's
BRDY half) is secondary. But since the firmware is correct and this is a
MAME-only artifact, **real-hardware validation (below) is the higher-value
next step** than fixing MAME's PIO model.

## Why parked

- Production CP/NET runs on **cpnos-in-c PIO**, which passes polypascal
  6/6 — its test loads PPAS from a path that doesn't stress the 222-record
  bulk CP/NET transfer the way `H:PPAS` over rcbios CP/NET does, so it does
  not trip the race in practice.
- The rcbios CP/NET PIO PPAS-over-the-wire test is secondary validation.
- The deeper fix is MAME z80pio chip work, a larger investment than the
  8-bit-clean transport cleanup that motivated this session.

Related: `tasks/session34-direct-pio-stall-rootcause.md` (the older 0xff
sentinel stall), `cpnos-in-c/tasks/KNOWN_ISSUE_polypascal_alternation_2026-07-07.md`
(the SIO-side parked flake).

## Speed analysis — why the MAME test still takes ~750 s wall (2026-07-08)

The z80pio `check_interrupts` fix (ravn/mame `2eb88cea`) eliminates the
stuck-IUS deadlock.  The transfer now flows continuously (28 436+ bytes
delivered), but the test harness needs ~20 minutes wall time.

Root cause of slowness: **z80pack's 10 ms I/O poll cycle.**  z80pack
(mpm-net2) throttles itself to real Z80 speed via `sleep_for_us(10000 -
tdiff)` every 40 000 T-states (`simz80.c` line ~645).  Each CP/NET frame
exchange requires at least one z80pack poll cycle (10 ms wall) for the
slave's request to be seen, plus one more for the response.  With ~5 frame
exchanges per 128-byte record and 222 records, theoretical minimum is
~22 s wall — but actual is ~750 s, indicating the server-side Z80 code
uses many T-state cycles per record.

**What was tried and ruled out:**
- `-video none -sound none`: no effect (MAME CPU unchanged, ~84%)
- z80pack `-f0` (unthrottled): **worse** (0.3x vs 4.3x) — suspected TCP
  socket polling issue in z80pack's tight loop; CPU is not the contention
  (MAME holds ~85% regardless).
- Reduce poll_tick 1 ms → 0.1 ms: marginal (first-byte delay < 1% of
  total time once pipeline is running).

**The only path to a fast test:** replace z80pack with a native CP/NET
server (Python/Rust) that responds to READ requests in < 1 ms without Z80
emulation overhead.  Estimated transfer time with native server: < 10 s
wall.
