# Session 33 — PIO ↔ mpm-net2 deep investigation

Date: 2026-04-27
Branch: `pio-mpm-netboot` (off main)

## Headline

CP/NOS over PIO now talks to a real `mpm-net2` master end-to-end.
Two designs were prototyped; the **proxy** is the working production
choice, **direct snios-on-PIO** is functional but flaky pending one
more race.  Three real bugs were found and patched along the way —
two in cpnos-rom, one in MAME's `cpnet_bridge.cpp`.

## What landed

### Proxy mode (production-ready)

`cpnos-rom/cpnet_pio_server.py --upstream HOST:PORT` adds a SIO-envelope
client to the existing PIO frame-server, forwarding non-PING frames
to a real CP/NET master.  The Z80 stays at raw PIO speed
(`transport_pio.c::pio_send_msg/pio_recv_msg` from Phase 25
unchanged); the host pays the envelope round-trip cost.

End-to-end against `mpm-net2` listening on `:4002`:
- Boot strip: `INIT OKPNILOREC+PSJ` (NDOS COLDST entered)
- Total: **1.44 s emulated** for the full netboot
- 60 CP/NET frames; per-frame host wall: recv 1-7 ms, dispatch
  5-10 ms (envelope round-trips with mpm-net2), send 0.01 ms.
- Cumulative host wall: 178 ms recv + 482 ms dispatch = 660 ms
  total host work for the netboot.

vs SIO baseline: ~2 s emulated.  **PIO via proxy beats SIO end-to-end
in MAME** even though the proxy adds the same envelope SIO would
do — because it's done on the host TCP loop, not in the bridge's
emu-thread.  Real-HW projection is unchanged from Phase 25:
~50 ms total netboot, 40× SIO.

### Direct mode (snios-on-PIO; flaky after fixes)

Re-wires `snios.s::SENDBY/RECVBY/RECVBT` to call
`_transport_pio_send_byte/_transport_pio_recv_byte` instead of the
SIO chip primitives.  No proxy; the same SIO envelope flows on the
PIO line.  MAME's bridge connects directly to mpm-net2 :4002.

Initial state: stuck at LOGIN (boot strip `INIT OKPNI`).  After the
three bug fixes below: progresses through LOGIN, OPEN, and several
READ-SEQ iterations; stalls intermittently after 4-25 sectors.
Filed as **ravn/rc700-gensmedet#56**.

## Three bugs the direct path uncovered

These were independent issues stacked on top of each other; each
surfaced only after the previous was fixed.  They all live in code
SIO never exercises in the same way.

### Bug 1 — stale-prefix byte on Mode 1→0 transitions

`mame:src/devices/machine/z80pio.cpp::set_mode(MODE_OUTPUT)`:
```cpp
case MODE_OUTPUT:
    if (PORT_A) m_device->m_out_pa_cb((offs_t)0, m_output);
    else        m_device->m_out_pb_cb((offs_t)0, m_output);
    ...
```

Mode-select fires the output callback with whatever's in `m_output`.
After a recv→send transition, `m_output` holds the previous send's
last byte (or 0 at boot).  Peers see a stale prefix byte before the
real first byte of each new send.

mpm-net2 tolerates one stale 0x00 before ENQ (treats it as line
noise).  But subsequent sends ship `<stale_05> <SOH> <hdr>...`
where the stale byte is now `0x05` (= ENQ from the previous send) —
arriving between ACK and SOH where mpm-net2 will not tolerate it.

**Fix** (`cpnos-rom/transport_pio.c::transport_pio_send_byte`):
write the data byte to `PORT_PIO_B_DATA` *while still in Mode 1*.
The chip's `MODE_INPUT::data_write` latches `m_output` without
firing the callback.  Then flip to Mode 0; `set_mode` now emits
the byte we actually want.

### Bug 2 — PIO-B chip IRQ stealing bytes

`init.c` configured PIO-B with chip-side IE enabled (`0x83`).
`isr_pio_par` (the legacy bring-up ISR from before snios-on-PIO
existed) fires on each byte and reads `PORT_PIO_B_DATA` from inside
the ISR — which clears the chip's `m_ip` *and* consumes the byte
from the chip's input register.  Mainline snios's busy-poll never
gets a chance.

LOGIN's 1-byte payload survived (single ISR fire, snios's poll
caught the chip's next byte).  OPEN's 37-byte payload meant 37
ISRs racing against snios's poll.  Sometimes a byte was lost.

**Fix** (`cpnos-rom/init.c`): `0x83` → `0x03` in the port-init
table (chip IE off at boot).  `isr_pio_par` stays in the IVT slot
to handle any spurious IRQ that escapes (shouldn't happen with IE
off, but it's defense in depth).

### Bug 3 — bridge `rdy_w` skipping strobe on empty buffer

The smoking gun for OPEN.  In `mame:src/devices/bus/rc702/pio_port/
cpnet_bridge.cpp::rdy_w` the strobe was gated on
`m_input_index < m_input_count`:
```cpp
if (m_brdy_high && !was_high && m_input_index < m_input_count) {
    m_slot->strobe_w(0);
    m_slot->strobe_w(1);
}
```

When the bridge buffer drained mid-frame and Z80 kept busy-polling
`PORT_PIO_B_DATA`, no strobe fired.  The chip's `data_read`
returns the cached `m_input`:
```cpp
case MODE_INPUT:
    if (!m_stb)
        m_input = m_device->m_in_pb_cb(0);   // rare path
    data = m_input;
```

`m_stb` is normally 1 (high) outside an active strobe pair, so the
refetch path doesn't run.  `data_read` returns the *last real
byte* — the same one again.  `transport_pio_recv_byte` only loops
on `0xff`; a real byte (even a stale duplicate) returns immediately.
snios's NETIN stored duplicate bytes, sum-to-zero CKS verification
failed, retry exhausted, `0xFF` returned to caller, netboot bailed.

LOGIN's 1-byte payload had no buffer-empty window.  OPEN's 37-byte
payload routinely overran the buffer — fast Z80 polling, slow TCP
delivery to bitbanger, poll_tick refill at 1 ms emulated cadence.

**Fix** (`mame@9c2cbb4e1a9`, `cpnet_bridge.cpp::rdy_w`): drop the
buffer-non-empty gate.  Strobe on every BRDY rising edge.  When
buffer is empty, `read()` returns `0xff`; chip latches `0xff`;
Z80's poll loop correctly skips past it.

## Why SIO works but PIO didn't (the natural question)

SIO uses MAME's stock `null_modem` slot which sits on
`bitbanger_device` + `posix_osd_socket` directly.  The chip
emulation paces bytes at the configured baud rate (38400 here) and
reports availability via the RR0 char-available bit; Z80's
`transport_recv_byte` only reads `PORT_SIO_A_DATA` when that bit is
set, and the chip emulation never caches "the last byte" across a
no-data window.  Every issue listed above is something the SIO
path doesn't expose.

PIO goes through our project-specific `cpnet_bridge.cpp`.  The
Z80-PIO chip emulation caches `m_input` between strobes, the bridge
strobes on edges and timer ticks, and our chip-init was configured
for an earlier IRQ-driven design.  Each layer added a quirk that
the direct snios-on-PIO path tripped over.

## Numbers (MAME -nothrottle, against fresh mpm-net2)

| Path | Boot strip | Time | Status |
|---|---|---|---|
| SIO 38400 baud (baseline) | `INIT OKSNILOREC+PSJ` | ~2.0 s emulated | ✓ robust |
| PIO + proxy | `INIT OKPNILOREC+PSJ` | **1.44 s emulated** | ✓ robust |
| PIO + direct (post-fixes) | `INIT OKPNILOR…` (4-25 sectors) | varies | ✗ stalls (#56) |

Real-hardware projection (Pi+Pico bridge, no MAME bridge between
chip and host): both PIO designs ≈ 50 ms total netboot, ~40× SIO.

## Branch state

### `ravn/mame-rc702-rc759-rc750:master` (1 commit ahead of origin)
- `9c2cbb4e1a9` cpnet_bridge: rdy_w always strobes on rising edge
  — this is a *general improvement* for any PIO-bridge user, not
  just the snios-on-PIO experiment.  The proxy-mode test was
  unaffected because raw OTIR/INIR don't sit between buffer-empty
  windows the way snios's per-byte NETIN does.

### `ravn/rc700-gensmedet:pio-mpm-netboot` (off main)
- `62c2b61` cpnet_pio_server: WIP `--upstream` proxy mode.
- `20d9203` EXPERIMENT: snios speaks PIO byte primitives directly
  to mpm-net2.
- `7a50843` tasks: session 32 — initial comparison report.
- `ba9277c` cpnos init.c: PIO-B chip-side IE off (0x83 → 0x03).
- `4afa036` tasks: deeper investigation of direct snios-on-PIO
  failure (the three-bug breakdown).
- (this doc) tasks: session 33 summary.

## Recommendations / next phase

1. **Wire the proxy into the harness** as `--mode=pio-mpm-netboot`.
   Currently the proxy works manually but isn't a one-command test.
   Spawns mpm-net2, spawns `cpnet_pio_server.py --upstream`,
   launches MAME, asserts boot strip = `INIT OKPNILOREC+PSJ`.
2. **Promote the branch** once the harness mode lands and runs
   green on a fresh tree.  `ravn/rc700-gensmedet:pio-mpm-netboot`
   → main.  `ravn/mame-rc702-rc759-rc750:master` is already in place.
3. **Investigate ravn/rc700-gensmedet#56** (snios-on-PIO
   intermittent stall) when there's appetite for more
   chip-emulation archaeology.  Probably a fourth race.
   Probably never blocks anything that actually ships.

## Files of note

- `cpnos-rom/cpnet_pio_server.py` — proxy.  `--upstream HOST:PORT`
  flag selects between standalone Python responder and proxy
  modes.
- `cpnos-rom/transport_pio.c` — stale-prefix mitigation in
  `transport_pio_send_byte`.
- `cpnos-rom/snios.s` — byte primitives swapped to PIO on this
  branch (experiment); not yet on main.
- `cpnos-rom/init.c` — chip IE off (`0x83` → `0x03`).
- `mame:src/devices/bus/rc702/pio_port/cpnet_bridge.cpp` — rdy_w
  always-strobe fix.
- `tasks/session32-pio-mpm-comparison.md` — initial comparison.
- `tasks/session33-pio-mpm-investigation.md` — this doc.

## Lessons

### Three bugs in a row each looked like the bug

Each of Bug 1, 2, 3 individually plausibly explained the OPEN-stall
symptom, and each had to be fixed before the next one became
visible.  The investigation took several iterations of "this should
work now... why doesn't it... oh THIS is why."  The lesson:
chip-emulation issues stack.  Trace the actual byte sequence on the
wire AND in the chip-bridge AND in the slave's polled reads, all
three, before declaring root cause.

### "Why does X work but Y not" is the right question

The user's question — "why does this work for SIO but not PIO" —
forced a comparison that surfaced the specific PIO-only bridge
bugs.  Without the comparison framing, each bug looked like
"that's just how it is."  With it, "the SIO path doesn't have this
problem because…" became a falsifiable hypothesis pointing at the
right code.

### MAME's bitbanger pattern is a contract not just a refactoring win

When I switched cpnet_bridge to bitbanger in Phase 25, I matched
the *control flow* (emu-thread polled non-blocking I/O) but not all
the *contract* details.  Specifically: if you cache state per chip
strobe, your strobe rules need to match what the chip emulation
expects.  The buffer-non-empty gate looked sensible but broke the
contract that "every IN gets a fresh byte (or 0xff)".
