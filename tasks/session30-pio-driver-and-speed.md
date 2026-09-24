# Session 30 — Parallel-port driver + throughput bench

Date: 2026-04-27

## Headline

- Closed ravn/mame-rc702-rc759-rc750#6 as **misdiagnosis** — slot infrastructure on
  Z80-PIO works fine; the cpnos hang at `PC=0x0039` was caused by
  missing `prom1.ic65` in the rc702 rom region.
- **0xCAFE checksum** in cpnos-rom catches missing/corrupt prom1
  within ~1 s emulated.
- **`transport_pio.c` + `isr_pio_par`** parallel-port driver — both
  directions verified end-to-end through `cpnet_bridge`.
- **CP/NET frame round-trip** — 10-byte SCB (FMT/DID/SID/FNC/SIZ +
  payload + CKS) request/response with sum-to-zero checksum
  validated.
- **Throughput bench** — four variants measured at MAME 100% (wall
  ≈ Z80 emulated):

  | Direction | Mechanism | Throughput |
  |---|---|---|
  | Z80 → host | C-loop (`transport_pio_send_byte`) | 22 KiB/s |
  | Z80 → host | inline `OTIR` | **156 KiB/s** |
  | host → Z80 | ISR-driven (counter wrap) | 15 KiB/s |
  | host → Z80 | inline `INIR` (IE off, busy-poll) | **148 KiB/s** |

  Both directions are wire-bound at ~150 KiB/s with the right Z80
  instruction.  ~40× faster than the current SIO baseline at 38400
  baud.  Full results at
  [`docs/cpnet_pio_speed_results.md`](../docs/cpnet_pio_speed_results.md).
- **Compiler bug found and filed** — ravn/llvm-z80#82 (static-stack
  uint16_t loop counter desync between live BC register and a
  never-written frame slot).  XFAIL lit test pushed to
  `ravn/llvm-z80:rc700-gensmedet-1`.

## Commits

### `ravn/mame-rc702-rc759-rc750:cpnet-fast-link-remerge` (slot work re-introduced)
- `03231d1de94` revert-the-revert: PIO slot infrastructure restored
  on a separate branch (master untouched per user instruction).

### `ravn/rc700-gensmedet:cpnet-pio-direct`
- `c8ab4a9` cpnet_bridge harness: re-add `-piob cpnet_bridge`;
  retire no-slot design doc as obsolete.
- `847c3b8` cpnos: PIO-B parallel-port transport driver (Option P).
- `19b4001` cpnet_bridge harness: 10-byte CP/NET frame round-trip.
- `e1d6476` cpnet_bridge: PIO-B speed tests (TX C-loop, TX OTIR,
  RX ISR).
- `210633e` cpnet_bridge: INIR busy-poll RX speed test (~10× ISR).
- `2517ba0` docs: PIO-B throughput report.

### `ravn/llvm-z80:rc700-gensmedet-1`
- `054323512fe3` test: XFAIL lit test for static-stack loop-counter
  desync (#82).

## Architecture findings

### The chip's BRDY toggle drives the bridge synchronously

In MAME's `z80pio.cpp::data_read` for Mode 1 input:
```cpp
case MODE_INPUT:
    if (!m_stb) m_input = m_device->m_in_pb_cb(0);   // re-fetch
    data = m_input;
    set_rdy(false);
    set_rdy(true);
```

Each CPU read of the data port toggles BRDY.  Bridge's `rdy_w(1)` sees
the rising edge synchronously and calls `strobe_w(0); strobe_w(1)`,
which pops the next byte into `m_input`.  This means:

1. The byte path "self-clocks" — no IRQ needed for sustained RX as
   long as Z80 keeps issuing `IN` instructions.
2. With `m_ie = false` (chip IE disabled), `trigger_interrupt()` sets
   `m_ip` per byte but no IRQ fires.  Z80's IFF can stay enabled (CRT
   VRTC IRQ still works) without PIO-B firing.
3. The original `transport_pio_recv_byte` ring-based path **cannot
   sustain high RX rates** — back-to-back ISRs starve the mainline,
   the 32-byte ring overflows.  Use `INIR` busy-poll instead.

### The 0x00 prefix on Mode 1→0 transition

`set_mode(MODE_OUTPUT)` immediately fires `out_pb_callback(m_output)`.
After reset `m_output = 0`, so the very first byte the host sees on
direction switch is 0x00 — before any CPU OUT.  Documented as a
chip-emulation artifact; harness strips it.  CP/NET frames recognised
by SCB header signature, so pre-frame "noise" is naturally discarded
on real hardware too.

### Boot markers
Moved to row 0 cols 60–78 (upper-right corner) so they survive the
`nos_handoff` banner overwrite on row 1.  Whole strip readable as
`INIT OK NILOREC+PS` once netboot completes.  `init.c::init_hardware`
writes `INIT OK` (markers 0..6); `netboot_mpm.c` writes `NILOREC`
(8..14); `cpnos_main.c` writes `+PSJ` (15..18).

## Recommendations for next phase

1. **Adopt INIR busy-poll for sustained RX** — replace the ISR/ring
   path for CP/NET runtime traffic.  The ring can stay for low-rate
   protocols if needed, but bulk reads should use INIR.
2. **Adopt OTIR for sustained TX** — `transport_pio_send_byte` is
   fine for irregular bytes; OTIR for prepared blocks.
3. **Byte-blast frames with sum-to-zero CKS** — the wire is reliable
   (PIO hardware handshake guarantees per-byte delivery).  No need
   for SNIOS's ENQ/ACK envelope when both sides speak Option P.
4. **Half-duplex direction switch** between frames — one PIO-B
   control word OUT (~12 T-states) per flip.  Negligible vs the
   smallest 5-byte CP/NET header (~105 T transfer time at 21 T/byte).
5. **Two transports coexist** — `transport_sio.c` stays for legacy
   CP/NET-over-SIO.  `transport_pio.c` is the new driver.  No
   replacement of one by the other; both compiled in.

## Open follow-ups

### Branch hygiene
- [ ] **Promote `ravn/mame-rc702-rc759-rc750:cpnet-fast-link-remerge` to `ravn/mame-rc702-rc759-rc750:master`** —
      the slot work is verified.  Currently master lacks the
      `-piob cpnet_bridge` slot device, so any cpnos work needs the
      branch checkout.  Decision: when?
- [ ] **Promote `ravn/rc700-gensmedet:cpnet-pio-direct` to `:main`** —
      main lags behind by all of this session's work.  Decision: when?

### Issues filed (ravn/* forks only, per project policy)
- [x] **ravn/llvm-z80#82** — static-stack uint16_t loop-counter
      desync (XFAIL lit test added).
- [x] **ravn/mame-rc702-rc759-rc750#7** — Mode 1→0 transition fires stale-latch byte
      via `out_pX_callback` before any CPU OUT.
- [x] **ravn/rc700-gensmedet#53** — `tap.lua` banner check looks at
      row 0 (decorative stars) instead of row 1 (`RC702 CP/NOS`).
- [x] **ravn/rc700-gensmedet#54** — `transport_pio_recv_byte` ring
      path is unusable for sustained streaming (back-to-back ISRs
      starve mainline; ring overflows).

### Real-hardware bring-up (parked, no Pi 4B yet)
- [ ] Pi 4B + Pi Pico + J3 cable (per `docs/cpnet_fast_link.md`)
- [ ] Re-measure throughput on real HW; expect to match or exceed
      MAME numbers since no emulator overhead

### Production CP/NET integration
- [ ] Wire SNIOS to PIO transport for runtime CP/NET (not netboot).
      Two-driver model: SIO for bootstrap, PIO for runtime.
- [ ] Bridge-side direction tracking — count SCB SIZ bytes to know
      frame boundaries and flip direction.

### Compiler-driven goal (project KPI per CLAUDE.md)
- [ ] Shrink CP/NOS payload to fit single 2 KB PROM.  Currently spans
      both PROM0 (2048 B) and PROM1 (2048 B) — both full.

## Lessons

### Mame chip emulator stresses simulated chip cycles, not just Z80 cycles

At MAME 100% throttle, MAME simulates the Z80 at 4 MHz wall-time-paced.
**But** chip + bridge work happens in the emu thread synchronously
with Z80 instructions.  If chip+bridge per-byte cost (mutex, FIFO,
strobe machinery) exceeds the Z80's per-byte cycle budget, the emu
thread falls behind and MAME slows below 100%.  We saw this on
ISR-driven RX: 270 T/byte observed wall vs 120 T theoretical — MAME
ran at ~45% during the burst.

OTIR/INIR have less per-byte chip work (no IRQ accept, no ISR machine
state), so MAME stays close to 100% — wall ≈ Z80 emulated.  Real HW
won't have this mismatch.

### Static-stack + uint16_t loop counter is a clang Z80 codegen trap

When clang's static-stack pass spills a `uint16_t` loop counter to a
frame slot but the live counter stays in BC, the call-arg use site can
read the never-written slot.  Workaround: split into nested `uint8_t`
loops.  Filed as ravn/llvm-z80#82 with XFAIL test.

### The chip flow-controls itself when CPU drives reads

In Mode 1 input, you don't need an IRQ per byte — the chip's BRDY
toggle in `data_read` is the flow-control.  Disable IE, run `INIR`,
get 21 T/byte (~190 KiB/s theoretical at 4 MHz).  IRQ overhead per
byte (~120 T) goes away entirely.

### MAME at -nothrottle is not measuring Z80 throughput

Wall time at -nothrottle reflects MAME emulator speed, not Z80
clock.  Always use real-time MAME for throughput numbers.

## Files of note

- [`docs/cpnet_fast_link.md`](../docs/cpnet_fast_link.md) — Option P
  design (unchanged)
- [`docs/cpnet_pio_direct_design.md`](../docs/cpnet_pio_direct_design.md)
  — flagged OBSOLETE; preserved as historical context
- [`docs/cpnet_pio_speed_results.md`](../docs/cpnet_pio_speed_results.md)
  — this session's throughput report
- [`docs/cpnet_slot_work_history.md`](../docs/cpnet_slot_work_history.md)
  — ravn/mame-rc702-rc759-rc750#6 misdiagnosis post-mortem (from prior session)
- `cpnos-rom/transport_pio.c` — the parallel-port driver
- `cpnos-rom/cpnos_main.c` — speed test variants 1..4 under
  `#if PIO_SPEED_TEST == N`
- `tests/cpnet_bridge/harness.py` — `--mode={hostsend, loopback,
  speed, speed-otir, speed-rx, speed-rx-inir}`
