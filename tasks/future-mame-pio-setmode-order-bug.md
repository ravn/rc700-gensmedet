# MAME z80pio set_mode order bug — answered by Zilog manual

Originally a parking ticket to verify on real hardware whether the
MAME `z80pio.cpp` `set_mode(MODE_OUTPUT)` order issue we found has a
real-silicon analogue.  **The Zilog Z80 PIO User's Manual answers
this without needing a logic analyser.**  The answer is no — the
race is purely a MAME simulation artefact.

## The MAME bug

`src/devices/machine/z80pio.cpp` `set_mode(MODE_OUTPUT)` fires the
output callback (`m_out_pb_cb`) BEFORE updating `m_mode = mode`.  A
peripheral that strobes back into the chip via `m_slot->strobe_w()`
from inside its `write()` callback dispatches against the prior mode
(`MODE_INPUT` after a recv→send transition) instead of the new one.
The strobe-back fires `m_in_pb_cb()` (= `bridge.read()` in our case)
and pollutes `m_input` with stale state.  Filed at
[ravn/mame#11](https://github.com/ravn/mame/issues/11).

## Why real silicon doesn't have this race

From Zilog Z80 PIO User's Manual, Section 5.0 (Output Mode), page 13:

> "The rising edge of the /WR* pulse then raises the Ready flag
> **after the next falling edge of Φ** to indicate that data is
> available for the peripheral device."

The peripheral cannot strobe back until it sees Ready (ARDY/BRDY) go
high, and Ready cannot go high until the next falling edge of Φ
following /WR* rising — at least ½ Φ cycle, ≥125 ns at 4 MHz CPU
clock.

Strobe pulse width minimum (A.C. Characteristics, `tw(ST)`) is 150 ns.
Peripheral GPIO setup time adds at least another 100-200 ns on any
realistic implementation (Pi/Pico, FPGA, real Mode-0 device).

Total minimum delay between mode change taking effect and a
peripheral strobe-back arriving at the chip: **~275 ns + peripheral
setup time** — many CPU clock cycles.  The mode register is fully
settled long before any possible strobe arrives.

The race exists ONLY in MAME because MAME models `set_mode()` as a
straight-line C++ function call with no Φ-clock gating; the output
callback fires synchronously inside the same call stack as the mode
update, and `m_mode = mode` happens textually after the callback
chain.  Real silicon has Φ-clock-synchronous gating that makes this
ordering electrically impossible to observe.

## What the fix does

Setting `m_mode = mode` BEFORE the output callback restores MAME's
behaviour to match real silicon — by the time any peripheral
strobe-back arrives at the chip, the mode register reflects the new
mode, just as it does on real hardware.

## Status

- Bug filed at [ravn/mame#11](https://github.com/ravn/mame/issues/11)
  with the Zilog-manual evidence.
- Fix verified locally to eliminate the m_input pollution in our
  cpnet_bridge use case.
- Real-hardware logic-analyser verification no longer required —
  the Zilog manual is the canonical source, and Figure 5-1 plus
  the Section 5.0 text together close the question.
- Upstreaming to `mamedev/mame` is the next step (filed at
  fork-of-record first; will propose upstream after maintainer ack).

## References

- Zilog Z80 PIO User's Manual: http://www.z80.info/zip/z80piomn.pdf
  (Section 5.0, Figure 5-1, page 13.)
- floooh/chips reference emulator (already does mode update before
  output callback):
  https://github.com/floooh/chips/blob/master/chips/z80pio.h
- `mame/src/devices/machine/z80pio.cpp` — the file with the fix.
- `mame/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp` — the
  device whose synchronous strobe-back exposed the bug.

## Related

- [`future-pi-bridge-timing-validation.md`](./future-pi-bridge-timing-validation.md) — Pi/Pico timing validation
  is still needed (separate from this question; it's about whether
  the Pi/Pico can strobe within the slave's INIR-iter budget on
  real hardware, regardless of MAME).
- [`cpnos-in-c/tasks/session-2026-06-13-phase4-inir-and-mame-findings.md`](../cpnos-in-c/tasks/session-2026-06-13-phase4-inir-and-mame-findings.md) — full session
  writeup.
