# Future: validate Pi/Pico bridge timing for bare-INIR CP/NET

Parking ticket — captured during #115 Phase 4 (2026-06-13) while
moving cpnos-in-c to bare-INIR CP/NET on PIO-B.

## The premise

The Phase 4 slave-side design (no ring, no ISR, chip IE permanently
off, bare INIR for all PIO-B receives) relies on the chip's Mode 1
handshake gating each INIR iteration on the peer producing the next
byte:

1. Slave's INIR iter N does `IN A,(0x11)`.  Chip toggles /BRDY
   false-then-true after the read.
2. Peer (Pi/Pico bridge in production) sees /BRDY rising, asserts
   /STB with the next byte on the data lines.
3. Chip latches /STB rising edge → m_input updated.
4. Slave's INIR iter N+1 reads the fresh m_input.

For this to be 8-bit clean, the peer MUST strobe /STB BEFORE the
slave's next IN reads m_input.  If the peer is slower than the
slave's INIR iteration rate (~5 µs at 4 MHz Z80), the slave reads
stale m_input — silent byte corruption (no sentinel can save it
because every value 0x00..0xFF is valid data).

## What needs validating

On the real Pi/Pico bridge that production uses (not MAME's
cpnet_bridge, which is a TCP-backed simulation that's
fundamentally too slow for this), measure the worst-case
/BRDY-rising → /STB-rising latency under realistic load.

Required: latency < INIR iter time (~5 µs at 4 MHz).

If the Pi/Pico can't reliably meet this, the slave-side bare-INIR
design needs to be backed out and replaced with a synchronous wait
(e.g., bring back the ring + ISR for single-byte recv, or extend
the bridge to expose a "byte ready" status the slave can poll
non-destructively).

## How to validate

1. Logic analyser on /BRDY, /STB, D0..D7.
2. Trigger on /BRDY rising edge.
3. Measure time to next /STB rising edge.
4. Sample N = 10000 transitions across a mixed CP/NET workload
   (LOGIN, OPEN, READ-SEQ, large file read).
5. Histogram the latency.  Worst case must be < 5 µs.

If a real Pi (Pi 4 or similar with bare-metal C / RP2040 PIO)
can't beat 5 µs reliably, the slave design must change.

## What's known today

- 2026-06-13 session: MAME's cpnet_bridge cannot meet this timing
  (TCP latency is ms-scale, not µs).  Bridge has been modified to
  block in `read()` until TCP delivers, which preserves correctness
  on the simulator but is irrelevant to real-hardware behaviour.
  See cpnet_bridge.cpp commit log.
- Per ravn/mame#8: MAME's chip emulation does not auto-raise BRDY
  on Mode-1 entry, so the bridge has to bootstrap its BRDY-tracking
  state at the first SEND-flip-RECV cycle.  Production hardware
  uses the Zilog datasheet semantics, where this isn't an issue.

## Related

- `cpnos-in-c/src/transport_pio.c` — slave side of the bare-INIR design.
- `mame/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp` — MAME's
  simulator-side bridge; the blocking `read()` modification.
- ravn/mame#8 — MAME PIO BRDY-on-Mode-1-entry quirk.
