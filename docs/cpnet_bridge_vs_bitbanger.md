# `cpnet_bridge` vs. a plain bitbanger

Question that came up 2026-04-28: PIO-B is wired to mpm-net2 via the
custom MAME slot device `rc702_pio_cpnet_bridge_device` (in
`mame:src/devices/bus/rc702/pio_port/cpnet_bridge.{cpp,h}`).  Could a
stock bitbanger do the same job?

Short answer: **only for some sub-paths**.  Mode-1 IRQ-driven receive
needs explicit STB strobing; a bare bitbanger doesn't drive STB and so
the PIO chip never raises an interrupt.  Mode-0 transmit and Mode-1
polled receive (`INIR` busy-poll) would work with a thin bitbanger
wrapper because they don't depend on strobes.

## What `cpnet_bridge` actually does

Three behaviours layered on top of a bitbanger sub-device:

1. **STB pulses to the PIO chip's strobe input.**  Mode 1 input
   requires the peripheral side to drive STB low/high to signal "byte
   ready."  On the falling edge, the chip latches `m_input`, raises an
   interrupt (with IE on), and drops `BRDY`.  A bare bitbanger has no
   notion of strobe — it just exposes byte-level read/write.

2. **`rdy_w` callback wired to the chip's BRDY output.**  When the
   chip raises BRDY (after the Z80 read drained the input latch), the
   bridge's `rdy_w` fires and decides whether to send the next strobe.
   The decision is **gated on `m_brdy_high && input_buffer_non_empty`**
   — that gate is the fix in `60e2b9a032f` on
   `ravn/mame-rc702-rc759-rc750:pio-mpm-irq-fix`.  Without it, IRQs never fire (or fire
   too early and the chip latches stale `m_input`), and the IRQ ring
   on the slave never gets bytes.

3. **A 1 ms `poll_tick` timer** to handle the case where BRDY is
   already high when a byte just arrived from TCP — there's no BRDY
   edge to trigger `rdy_w` so we'd otherwise miss it.  The timer
   re-checks `(m_brdy_high && input_buffer_non_empty)` and strobes if
   so.  Same gate as `rdy_w`.

For Mode 0 (output, slave→host) the bridge does almost nothing
custom: chip's `data_write` calls `out_pb_callback` with the byte,
bridge forwards to TCP, then pulses STB to release BRDY (the Mode-0
output ack semantic).  The STB pulse here is symmetric with the
input direction's chip-strobe.

## What sub-paths a plain bitbanger could handle

| PIO sub-path | Bitbanger alone? | Why |
|---|---|---|
| Mode 0 TX (`OTIR` or polled `OUT`) | yes, in principle | each Z80 OUT calls `out_pb_callback` with the byte; bitbanger absorbs |
| Mode 1 RX, **polled** (tight `INIR` busy-poll) | yes | chip's `data_read` calls `in_pb_callback` per IN, fetching one byte per Z80 read; doesn't need STB strobes from peripheral |
| Mode 1 RX, **IRQ-driven** (slave's IRQ ring path) | **no** | needs STB pulses to fire chip IRQs; without strobes the chip never raises INT |

So the only path that genuinely requires a custom slot device is the
**IRQ ring receive** — the path that lets the slave's mainline run
freely while bytes arrive in the background.

## Trade-off if we drop `cpnet_bridge`

Replacing `cpnet_bridge` with a plain bitbanger (wired to PIO-B's
`in_pb_callback` / `out_pb_callback`) would require switching the slave
to Mode-1 polled receive (`INIR` busy-poll) instead of the IRQ ring.

Saves on the MAME side:
- ~140 LoC of `cpnet_bridge.cpp` (read/write/rdy_w/poll_tick/timer/buffer)
- the `m_brdy_high` gate fix
- `ravn/mame-rc702-rc759-rc750#8` (BRDY-not-auto-raised on Mode-1 entry) — the
  optimistic-init-then-`set_mode(OUTPUT)` workaround was driven by
  the IRQ path's bootstrap requirements

Saves on the slave side:
- 256-byte IRQ ring buffer (`pio_rx_buf` at 0xF700)
- `pio_rx_head` / `pio_rx_tail` BSS
- `isr_pio_par`'s ring-write asm (~30 bytes)
- `transport_pio_recv_byte`'s ring-pop loop

Costs:
- The slave's recv loop becomes a tight `INIR` busy-poll, monopolising
  the CPU during transfers.  That's fine for a bench (bandwidth is
  the bridge's pacing, not the slave's), but means the slave can't
  do useful work concurrently with reception.  In CP/NOS terms: you
  can't have CRT VRTC IRQs running CPU-side cursor updates while
  netboot is in progress.

For the PIO-PROXY transport mode this is already what the slave does
(`pio_recv_msg` uses `INIR` over Mode 1).  PIO-IRQ direct mode is
specifically the *not-busy-polled* alternative, optimised for
"slave can do other work while bytes arrive."

## Why we kept `cpnet_bridge` anyway

The IRQ-driven path more closely mimics how the RC702's PIO-B was
designed to be used — Mode 1 input with hardware handshake and
peripheral-driven IRQs.  It's the wire architecture you'd build in
hardware for a real J3 expansion board.  Keeping the IRQ path means
the slave-side firmware (cpnos's `isr_pio_par` + ring) is exercising
the same paths it would on physical hardware, which has bugs the
polled path wouldn't expose (e.g., `ravn/mame-rc702-rc759-rc750#7`'s stale-prefix on
Mode-1→Mode-0 transition, which the IRQ path bumped into and the
polled path doesn't).

The bridge gate fix (`m_brdy_high && input_buffer_non_empty`) is the
only really branch-specific extra MAME code; everything else is
generic PIO Mode-1-handshake plumbing.
