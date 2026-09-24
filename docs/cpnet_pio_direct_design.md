# CP/NET PIO-B direct bridge — design (no slot)

> **OBSOLETE — historical reference only (2026-04-27).**
>
> This design existed to sidestep ravn/mame-rc702-rc759-rc750#6, which suspected a real bug
> in MAME's slot infrastructure on Z80-PIO ports.  Subsequent investigation
> traced the symptom (cpnos hangs at PC=0x0039 with `-piob cpnet_bridge`)
> to a missing `prom1.ic65` in the rc702 rom region — the slot mechanism
> itself was never broken.  See `docs/cpnet_slot_work_history.md` for the
> full post-mortem.
>
> The slot-based path on `ravn/mame-rc702-rc759-rc750:cpnet-fast-link[-remerge]` is now the
> canonical Option P bring-up.  It was end-to-end verified 2026-04-27:
> 6 TCP bytes round-trip from `:4003` through the bridge slot card to
> the Z80 `isr_pio_par` ISR, counter advances 0->6, last byte preserved.
>
> The implementation never started — only this design doc and the
> Python harness tweak that dropped `-piob cpnet_bridge`.  The harness
> tweak is reverted in the same commit that adds this header.  Kept
> here as a reference for the design-space exploration.

> Branch: `cpnet-pio-direct` (in both `ravn/mame-rc702-rc759-rc750` and `ravn/rc700-gensmedet`).
> Status: design proposed 2026-04-26, **superseded 2026-04-27** —
> ravn/mame-rc702-rc759-rc750#6 was a misdiagnosis; slot path works fine.

## Goal

Get bytes flowing from an external process to the Z80 inside MAME's
`rc702` driver via the Z80-PIO port B, **without any slot/card
infrastructure**.  Sidesteps ravn/mame-rc702-rc759-rc750#6.  Function over elegance.

## Why this can work where the slot path failed

ravn/mame-rc702-rc759-rc750#6 is triggered when a `device_t` is constructed under
`device_single_card_slot_interface` on the Z80-PIO chip.  In this
design there is **no separate device** — the socket and its bookkeeping
live as private members of `rc702_state` (the driver class), and the
PIO-B chip callbacks point directly at driver-class methods.  This is
identical to how PIO-A keyboard wiring already works in upstream
rc702.cpp, which is known good.

## Components

```
+-------------------+       socket.127.0.0.1:4003
|  external client  |  <----------------------------> osd_file::ptr m_cpnet_socket
+-------------------+        (osd_file, non-blocking)        |
                                                              | read()/write() on emu thread
                                                              v
                              emu_timer m_cpnet_rx_timer  ---+--->  std::deque<uint8_t> m_cpnet_rx_queue
                                  (1 ms cadence, drains kernel)               |
                                                                              | pop_front() when BRDY high
                                                                              v
                              uint8_t m_cpnet_pb_data    --in_pb_callback-->  Z80-PIO chip
                                                                              |
                                                                              | strobe_b(0); strobe_b(1)
                                                                              | -> chip latches, IRQ, BRDY low
                                                                              |
                              out_brdy_callback        <---------------- BRDY edges
                                  -> m_cpnet_brdy_high
```

TX path (Z80 -> host) is symmetric and simpler — chip writes via
`out_pb_callback`, we forward to the socket immediately.

## Data flow — RX (host -> Z80)

1. **Polling timer** `m_cpnet_rx_timer` fires every 1 ms on the emu thread.
2. Reads up to 256 bytes non-blocking from `m_cpnet_socket->read(buf, 0, 256, actual)`.
   - On `errc::operation_would_block` (no data): no-op.
   - On disconnect / error: closes the file, schedules a re-listen.
3. Appends received bytes to `m_cpnet_rx_queue` (single-threaded, no mutex).
4. Appends raw bytes to `/tmp/cpnet_pio_rx.bin` (`std::ofstream` opened in
   `machine_start`, append mode).
5. If `m_cpnet_brdy_high` and queue non-empty:
   - Pop byte to `m_cpnet_pb_data`.
   - Pulse `m_pio->strobe_b(0); m_pio->strobe_b(1);`.
   - Mark `m_cpnet_brdy_high = false` until we see the rising edge.
6. **`out_brdy_callback`** (`pio_b_brdy_w`) maintains `m_cpnet_brdy_high`.
   On rising edge with queue non-empty, immediately strobes the next byte
   (so the timer doesn't have to wait 1 ms between consecutive bytes).

## Data flow — TX (Z80 -> host)

1. Z80 writes to PIO-B data port (Mode 0 output): `out_pb_callback` fires.
2. `pio_b_write(uint8_t data)` is called on the emu thread.
3. Appends byte to `/tmp/cpnet_pio_tx.bin`.
4. Calls `m_cpnet_socket->write(&data, 0, 1, actual)`.
   - On `errc::operation_would_block`: byte is dropped (TX kernel buffer full
     would mean the host is wedged; for bring-up we accept this loss and
     log it).  If real backpressure becomes a problem we add a queue.

## Lifecycle

- **`machine_start()`**: open `osd_file` listening socket, alloc emu_timer,
  open both `.bin` log files (truncate on open).
- **`machine_reset()`**: drain RX queue, set `m_cpnet_brdy_high = true`.
- **`machine_stop()`** *(or destructor)*: close socket, close files.

The osd_file class is reference-counted via `unique_ptr`; closing happens
automatically on driver state destruction.  `machine_stop` only needs to
flush log files and set the timer to `attotime::never`.

## State (private members of `rc702_state`)

```cpp
osd_file::ptr            m_cpnet_socket;       // listening + per-client
emu_timer *              m_cpnet_rx_timer = nullptr;
std::deque<uint8_t>      m_cpnet_rx_queue;
uint8_t                  m_cpnet_pb_data = 0xff;
bool                     m_cpnet_brdy_high = true;
std::ofstream            m_cpnet_rx_log;
std::ofstream            m_cpnet_tx_log;
static constexpr int     CPNET_PORT = 4003;
```

No mutex — RX queue is touched only on the emu thread (timer callback).
No `std::thread` — `osd_file` is non-blocking; no worker needed.

## PIO chip wiring (rc702.cpp `rc702_base`)

```cpp
m_pio->in_pa_callback().set(FUNC(rc702_state::kbd_r));            // existing
m_pio->in_pb_callback().set(FUNC(rc702_state::cpnet_pb_r));       // new
m_pio->out_pb_callback().set(FUNC(rc702_state::cpnet_pb_w));      // new
m_pio->out_brdy_callback().set(FUNC(rc702_state::cpnet_brdy_w));  // new
```

No `m_pio_b` finder, no `RC702_PIO_PORT(config, ...)`, no slot device.
This is the **only** machine_config change relative to the pre-merge
rc702.cpp.

## Logging files

- **`/tmp/cpnet_pio_rx.bin`** — every byte received from the TCP socket
  in arrival order, raw.
- **`/tmp/cpnet_pio_tx.bin`** — every byte the Z80 wrote to PIO-B (pushed
  to socket), in chip-write order, raw.
- Both files are append-write (truncated at machine_start).
- No timestamps in the bin files — they're for replay / diffing.  If a
  text trace turns out to be needed for debugging, we add it later.

## Test fixture changes (rc700-gensmedet branch)

- `tests/cpnet_bridge/harness.py` — drop the `-piob cpnet_bridge` arg
  (no slot anymore), keep TCP connect to `localhost:4003`.
- `tests/cpnet_bridge/tap.lua` — unchanged (still polls
  `_pio_par_count` BSS).
- New: `tests/cpnet_bridge/dump_logs.sh` — quick one-liner to hex-dump
  `/tmp/cpnet_pio_rx.bin` and `/tmp/cpnet_pio_tx.bin` for inspection
  after a run.

## Files touched

- `mame:src/mame/regnecentralen/rc702.cpp` — add ~80 lines of socket
  bookkeeping + 4 callback methods, drop slot/card refs.  Net change
  vs `master`: smaller (slot wrapper code goes away).
- `mame:src/devices/bus/rc702/pio_port/` — **deleted entirely**.  No
  longer used.
- `rc700-gensmedet:tests/cpnet_bridge/harness.py` — drop one `-piob` arg.
- `rc700-gensmedet:tests/cpnet_bridge/dump_logs.sh` — new.

## Acceptance test

End-to-end with the existing harness (with the `-piob` removal):

1. `make cpnos-install` (rebuild PROM and install on disk).
2. Launch MAME, harness sends a fixed test pattern over TCP to :4003.
3. cpnos-rom's `isr_pio_par` increments `_pio_par_count`; `tap.lua` logs
   each increment.
4. Verify `/tmp/cpnet_pio_rx.bin` matches the bytes the harness sent.
5. **Mandatory: capture a screenshot of the MAME window** and Read it
   to confirm the screen is not black (per
   `feedback_screenshot_to_verify`).

PASS = round-trip count matches AND screen shows the cpnos-rom banner
AND `/tmp/cpnet_pio_rx.bin` matches the sent test pattern.

## Risks / open questions

- **What if `osd_file` listening socket conflicts with port 4003 in use?**
  Port 4003 is the same port the slot-based bridge used; the harness
  drops `console 4` from `mpm-net2` config to free it.  Re-uses the
  existing `free_bridge_port_in_mpm_conf()` machinery.
- **Mode 1 input handshake from Z80-PIO when BRDY drops mid-strobe:**
  The chip's strobe semantics (z80pio.cpp:451-512) are clear — `strobe_b(0)`
  reads via callback, `strobe_b(1)` latches+IRQ.  The chip's own BRDY
  bookkeeping handles re-arm; we don't need to delay between strobes.
- **What if no TCP client is connected?**  `osd_file::read` returns
  `errc::operation_would_block` while the listener is up but no client.
  No bytes flow, no harm.
- **Strict single-shot rule:** writing this once means the design above
  has to be right.  If something doesn't work, **investigate before
  changing the implementation** — don't iterate.

## Sign-off

Once approved, the implementation is a single edit pass on rc702.cpp +
a small harness tweak.  Build once, run once, verify once.
