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

## Bonus follow-up — does MAME assert Ready on mode entry at all?

A closer re-read of Sections 4.2, 4.3, and 5.0 raises a separate
question that does **not** affect the validity of the fix above, but
is worth recording so the analysis isn't lost:

- Section 4.2 specifies when Ready goes high: *"With Mode 0 active,
  **a data write** from the CPU causes the Ready handshake line of
  that port to go High to notify the peripheral that data is
  available."*  The wording emphasises data writes, not control-word
  (mode-set) writes.
- Section 4.3 last paragraph says preloading the output register
  before mode select *"allows the port output lines to become active
  in a user defined state"* — describing the output drivers becoming
  active, but silent on Ready behaviour.
- Section 5.0's Figure 5-1 Output Mode timing diagram shows Ready
  going high after `/WR*` rising + next Φ falling, but the figure
  depicts a **data** write while already in Mode 0, not the mode-set
  itself.

The plausible real-silicon reading is that Ready goes high only on
data-port writes while Mode 0 is active.  A Mode 0 entry with a
preloaded output register would make the output lines active
*without* asserting Ready; the peripheral would then need to wait
for a subsequent data write before strobing.

MAME's `set_mode(MODE_OUTPUT)` does both `m_out_pX_cb()` and
`set_rdy(true)` unconditionally on mode entry.  If the manual reading
above is correct, MAME is spuriously announcing data-available on
mode entry.

**This does not affect the validity of the fix in this ticket.**
Even if real silicon does raise Ready on mode entry (i.e. MAME's
interpretation is correct), the Φ-clock gating between `/WR*` rising
and Ready going high (≥125 ns at 4 MHz) plus peripheral GPIO
propagation makes the strobe-back race electrically impossible
either way — that's the argument above.

Resolving the Ready-on-mode-entry question definitively needs a
logic-analyser capture from real silicon (e.g. probe BRDY across a
Mode 1→Mode 0 transition without any subsequent data write, see if
BRDY goes high).  Recorded as a comment on ravn/mame#11; not filed
as a separate issue without harder evidence.

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
