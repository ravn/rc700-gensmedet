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

Option 1 is the recommended real fix if/when this path is unparked.

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
