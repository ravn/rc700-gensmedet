# Session 2026-06-13 — #115 Phase 4 INIR refactor + MAME simulation findings

Captured at end of a long session attempting cpnos-in-c #115 Phase 4
(ring + ISR retired, bare INIR for CP/NET RX) and the MAME
modifications needed to test it.  None of the changes shipped.  This
document is the trail of what was learned so the next attempt doesn't
re-walk it.

## Headline

**The slave-side Phase 4 design (bare INIR + chip Mode 1 handshake) is
correct for real RC702 + Pi/Pico bridge hardware, but cannot be
faithfully tested in MAME without significant z80pio.cpp + cpnet_bridge
modifications.**  Several real bugs surfaced in the process, most of
them in the simulator rather than the firmware.

The user's parking note captures the next step:
`tasks/future-pi-bridge-timing-validation.md` — validate on real
hardware that the Pi/Pico can strobe /STB within the slave's INIR-iter
budget (~5 µs at 4 MHz).

## What was attempted

1. **Phase 1 (kept)** — `pio_b_recv_block_body` __naked function +
   `pio_block_dst` / `pio_block_count` BSS globals added to
   `transport_pio.c`.  No call site.  Built clean at 2043/2048 B.
   `cpnos-polypascal-test` passes with byte-identical trace to
   pre-change baseline.  This is the only piece worth keeping from the
   session — strictly additive, no behaviour change.

2. **Phase 2 attempts (variants A–H)** — wire `snios_c.c` step 6 PIO
   branch to call `pio_b_recv_block_body`.  Eight bisect variants
   tested.  Best: **variant H** (drain ring + bare INIR, no chip-IE
   bracket).  Passes `cpnos-dir-test` (small CP/NET load), fails
   `polypascal-test` at PPAS.ERM load (~17 KB file) — exact same
   failure as the historical 2026-06-12 Variant A attempt.  Root cause
   unverified but probable: the ISR fires between INIR iterations and
   races a byte from m_input into the ring, scrambling the data block.

3. **Phase 4 attempt (retired ring + ISR entirely)** — per user
   direction.  `pio_b_set_input` no longer enables chip IE;
   `isr_pio_par` deleted; IVT slot 17 points at `isr_noop`; ring
   variables removed.  `transport_pio_recv_byte` becomes a polling
   loop around 1-iter INIR.  Builds at 2060 B (94 B saved vs variant
   H).  Cannot complete LOGIN exchange in MAME — see "Why MAME makes
   Phase 4 untestable" below.

4. **MAME `cpnet_bridge.cpp` modifications** — added per-byte
   `logerror()` tracing, then a spin-loop in `read()` to make the chip
   handshake effectively synchronous, then per-IN TCP refill in
   `rdy_w()`, then reverted that.  Tracing useful; functional changes
   net-zero.

5. **MAME `z80pio.cpp` modification (KEEP)** — set `m_mode = mode`
   BEFORE the output callback in `set_mode(MODE_OUTPUT)`.  This **is
   a real bug** in MAME: the original order let downstream peripherals
   call back into the chip via `strobe_w()` while `m_mode` still held
   the prior value, routing an output-side strobe to the input-mode
   handler and firing `m_in_pb_cb()` (= bridge's `read()`) with stale
   state, polluting `m_input`.  The Zilog manual confirms real silicon
   does NOT have this race (Section 5.0: Ready is gated on the next Φ
   falling edge after /WR* rising, so peripheral strobes can't arrive
   during the mode change cycle).  Fix verified safe to commit.  See
   [`tasks/future-mame-pio-setmode-order-bug.md`](../../tasks/future-mame-pio-setmode-order-bug.md).

6. **MAME crash** — `dir_test.lua`'s `io_space:install_read_tap` calls
   were causing MAME to SEGV in `lua_gettop(lua_State*)` after the
   first protocol roundtrip.  Backtrace via
   `~/Library/Logs/DiagnosticReports/regnecentralend-*.ips` (macOS
   Crash Reporter).  Disabling the Lua port-taps stopped the crashes;
   reverting them is the cheap fix.  The MAME-side `logerror()` tracing
   in `cpnet_bridge` is sufficient for protocol-level debugging without
   the Lua taps.

## Why MAME makes Phase 4 untestable

Real hardware (RC702 + Pi/Pico bridge) Mode 1 input:

- Slave's INIR iter does `IN A,(0x11)`.  Chip drives /BRDY high.
- Pi sees /BRDY rising edge in a tight (~µs) polling loop, asserts
  /STB with the next byte.
- Chip latches on /STB rising edge.  Slave's NEXT INIR iter reads the
  fresh byte.

This works because the Pi's /BRDY → /STB latency is reliably shorter
than the slave's per-INIR-iter time (~5 µs at 4 MHz Z80).  The chip
handshake gates each INIR iteration on the peer's strobe.

MAME's `cpnet_bridge`:

- `m_stream` is a `bitbanger` connected to a TCP socket → `mpm-net2`.
- TCP roundtrip latency to localhost `mpm-net2` is **ms-scale, not
  µs-scale.**
- `poll_tick` fires every 1 ms emu to refill the FIFO from TCP.
- The chip handshake is honored, but the bridge can't actually strobe
  on time — by the slave's next INIR iter, no fresh byte is in
  `m_input`.

Slave reads stale `m_input` (whatever was last strobed in).  Phase 4
has no sentinel ("`0xFF` means empty" is not 8-bit clean per the
user's hard requirement), so the slave cannot distinguish "real byte"
from "stale leftover."

Attempted workarounds:
- **`bridge.read()` spin loop** — works but only fires when chip
  `m_stb=false`, and our flow keeps `m_stb=true` between strobes.
- **`bridge.rdy_w()` per-IN TCP refill** — fires on every slave IN,
  but the per-IN `m_stream->input()` syscall overhead magnifies emu
  time by orders of magnitude.  Reverted.
- **Slave-side polling loop** with various N (100, 200, 1000, 32768) —
  tradeoff between catching slow `mpm-net2` responses and slave-side
  retry budget overflow.  No single N works for both `dir-test` and
  `polypascal-test`.
- **Change-detection polling** (return when m_input differs from
  baseline) — close to working, but fails when peer sends the same
  byte twice in a row (e.g. master's frame-end ACK followed by
  response-start ENQ is two different bytes and works; master's
  final-ACK followed by same response-ACK is two identical bytes and
  the loop returns the wrong "expected" value to slave's protocol
  layer).

**Conclusion: MAME's cpnet_bridge can't faithfully emulate Pi/Pico
timing without either rewriting the bridge to be synchronous (which
diverges from real hardware semantics) or accepting that Phase 4
testing happens only on real hardware.**

## The MAME bugs found (worth upstreaming or documenting)

### 1. z80pio.cpp `set_mode(MODE_OUTPUT)` callback ordering

`m_out_pb_cb()` fires BEFORE `m_mode = mode`.  Downstream peripherals
that strobe back into the chip during their write callback see the
prior mode and the wrong strobe handler runs.  Reproducer: any device
that calls `m_slot->strobe_w()` from its output callback.

Fix: set `m_mode` first.  Verified against the canonical Zilog Z80
PIO User's Manual Section 5.0 / Figure 5-1: real silicon gates the
peripheral's strobe-back on Ready going high, and Ready only goes
high on the next Φ falling edge after /WR* rising — at least 125 ns
later at 4 MHz CPU clock.  So real silicon has no equivalent race.
The MAME ordering is the outlier; floooh/chips's reference Z80-PIO
emulator already updates the mode register first.

Filed at [ravn/mame#11](https://github.com/ravn/mame/issues/11) with
the canonical-source evidence.  See
[`tasks/future-mame-pio-setmode-order-bug.md`](../../tasks/future-mame-pio-setmode-order-bug.md)
for the full Zilog-quote writeup.

### 2. Lua `install_read_tap` / `install_write_tap` instability

The Lua-installed tap callbacks crash MAME with `EXC_BAD_ACCESS` in
`lua_gettop(lua_State*)` after some number of fires.  Backtrace shows
the path through `sol::basic_protected_function::invoke<>` and the
`tap_helper::do_install` lambda.  Likely a Lua-state lifetime issue
(tap survives the Lua context that registered it, or the closure
captures something with a dangling pointer).

Repro: any autoboot Lua script that installs an io-space tap and
binds a callback that uses `string.format` and writes to a Lua table.
`cpnos-shared/mame/dir_test.lua`'s port-taps trigger this within ~5
emu seconds.

Workaround: don't use Lua taps; use `logerror()` in the device source
instead.

### 3. cpnet_bridge.cpp m_brdy_high startup state

(Mentioned in existing bridge comments, ravn/mame#8.)  Chip doesn't
auto-raise BRDY on Mode-1 entry per Zilog spec; bridge has to bootstrap
its tracking state at first SEND-flip-RECV cycle.  Not new in this
session — preserved for context.

## Test infrastructure built (worth keeping)

- **`cpnos-shared/mame/dir_test.lua`** — fast CP/NET smoke test
  (~10 s, vs polypascal's 50 s).  Boots cpnos, types `DIR`, scrapes
  SIO-B mirror for the staged file names.  Useful for iterating on
  transport-layer changes that don't need PolyPascal's full
  exercise.  Lua port-taps inside have been removed per finding #2.

- **`cpnos-in-c/Makefile` `cpnos-dir-test` target** — Makefile rule
  for the above.

- **`cpnet_bridge.cpp` `logerror()` tracing** in `read()`, `write()`,
  `poll_tick`, `rdy_w` — produces `[NNNN us] write(XX) -> TCP` and
  `read() -> XX (FIFO[i/n])` lines in `/tmp/cpnos_dir_bridge.log`
  (via MAME's `-log` flag, which writes `error.log` in cwd then the
  Makefile copies it).  Indispensable for understanding what's
  actually happening on the wire.

- **macOS crash report harvesting** —
  `~/Library/Logs/DiagnosticReports/regnecentralend-*.ips` are JSON-
  wrapped crash dumps.  Parse with Python: `json.loads(first_line)`
  for metadata, `json.loads(rest)` for the body containing
  `exception`, `faultingThread`, `threads[N].frames` with symbolic
  backtraces.  Symbols include the C++ template instantiations, so
  tap-helper paths are identifiable.

## What was reverted / not committed

- All Phase 2/4 changes to `transport_pio.c`, `snios_c.c`, `init.c`,
  `payload.ld`, `prom1.ld`.
- `cpnet_bridge.cpp` `logerror()` tracing + `read()` spin loop +
  `rdy_w` per-IN refill + `m_rdy_w_count` heartbeat.
- `z80pio.cpp` `set_mode` order fix.
- `dir_test.lua` Lua port-taps (these caused MAME to crash).
- `Makefile` `cpnos-dir-test` target's `-log` flag and `error.log` →
  `/tmp/cpnos_dir_bridge.log` copy.
- The temp PROM/payload ceiling raises (4 KB PROM, 0xF800 stack
  ceiling).

These were all committed locally but should be reverted to the
session-start state for a clean tree.  The information value of the
experiments is captured in this writeup.

## What to keep / commit

- This file (`session-2026-06-13-phase4-inir-and-mame-findings.md`).
- `tasks/future-pi-bridge-timing-validation.md` — real-hardware Pi
  timing validation plan.
- `tasks/future-mame-pio-setmode-order-bug.md` — the MAME `set_mode`
  order finding + real-hardware verification plan.
- The two crash-report-parsing one-liner — recorded here, no need for
  separate file.

## Recommendation for next session

1. **Revert all in-progress changes to a clean tree** (`git restore`
   the working files; the docs in `tasks/` stay).
2. **Don't try to make Phase 4 testable in MAME** until either (a)
   the bridge is rewritten to be synchronous with the chip handshake
   in some clean way, or (b) real-hardware testing is set up.
3. **Variant H is the path forward for any near-term MAME-testable
   PIO speedup**: drain ring + bare INIR for block recv, ring + ISR
   for single-byte recv, chip IE on throughout.  The PPAS-load
   failure (race during INIR) needs a probe to diagnose properly —
   the Phase 0 instrumentation work from session 2026-06-12 is the
   right starting point.
4. **The MAME `set_mode` order fix** is worth upstreaming to
   mamedev/mame regardless of which slave-side path is chosen — it's
   a real bug.
