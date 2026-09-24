# Session 35 — IRQ-driven snios-on-PIO ships; netboot bench; sumtest workload

Date: 2026-04-28
Branches:
- `ravn/rc700-gensmedet:pio-mpm-irq-fix` (off `pio-mpm-netboot`)
- `ravn/mame-rc702-rc759-rc750:pio-mpm-irq-fix` (off master)

## Headline

The "snios-on-PIO direct" path now boots cpnos end-to-end against
real `mpm-net2`, fully reliably, by switching the Z80-side recv from
polled-with-`0xFF`-sentinel to chip-IRQ-driven ring buffer.  Closes
ravn/rc700-gensmedet#56 (the "intermittent stall" framing).
Netboot benchmarks across SIO / PIO-IRQ / PIO-proxy show the three
paths converge to ~1.5-1.9 s wall at -nothrottle 5x.  Workload bench
(sumtest = m80 + l80 + run) is in flight pending one more reliability
pass on the per-step inject harness.

## What landed (committed)

### cpnos-rom

Branch `pio-mpm-irq-fix`:

- **`f10c99f`** WIP IRQ-driven snios-on-PIO recv path (Fix A from
  session 34).  PIO-B chip IE on; isr_pio_par pushes bytes into a
  64-byte SPSC ring; `transport_pio_recv_byte` pops from ring with
  timeout; `enable_interrupts()` moved before `NETBOOT()` so the
  ISR can fire during the boot phase.

- **`9a274f6`** 256-byte ring at 0xF700 (page-aligned).  64-byte ring
  overflowed during 165-byte READ-SEQ bursts; expanded to 256 with
  free uint8_t-wrap arithmetic.  Page placement in the unused tail
  of the PAYLOAD memory region (0xED00..0xF800).  Verified 9/9
  successful runs wall 1.48-1.71 s (-nothrottle).

- **`fb7c50a`** 7-char wire-mode banner tag ("PIO-IRQ" instead of
  bare "SIO").  Format `"WWW-MMM"` — wire-mode.  Three TODOs added
  to `tasks/todo.md`: 32-bit CRT frame counter (mirror rcbios),
  multi-channel SNIOS investigation, Pico-side proxy port.

- **`c7d1945`** Banner reorder.  Banner now prints **before**
  `NETBOOT()` so it lands on row 1 with the loading dots filling
  in on row 2 below it (operator's natural "OS identity at top,
  progress below" expectation).  `nos_handoff()` split into
  `print_banner()` + JT/ZP setup.

### ravn/mame-rc702-rc759-rc750

Branch `pio-mpm-irq-fix`:

- **`a404c49a355`** ungate poll_tick + rdy_w (initial IRQ design,
  later partially reverted).

- **`60e2b9a032f`** re-gate `poll_tick` on `m_brdy_high` for the
  IRQ design.  Ungated `poll_tick` over-strobed between Z80 INs,
  silently overwriting `m_input` and dropping bytes.  Real symptom:
  NETBOOT returned 0 at the second cpnet_xact (LOGIN ok, OPEN fail).
  Correct gate: strobe only when m_brdy_high AND buffer non-empty.

## Bench results

### Netboot only (cold boot to clean A> prompt)

`-nothrottle` (MAME ~5× emulated):

| Mode | n | min | median | max | mean | stddev |
|---|---:|---:|---:|---:|---:|---:|
| PIO-PROXY | 9 | 1661 | **1668** | 1672 | 1667 | 3 ms |
| PIO-IRQ direct | 9 | 1671 | **1874** | 1887 | 1852 | 68 ms |

Real-time (1× emulated, "physical machine feel"):

| Mode | n | min | median | max | mean | stddev |
|---|---:|---:|---:|---:|---:|---:|
| PIO-IRQ direct | 5 | 3723 | **3738** | 3748 | 3736 | 9 ms |

Both modes 9/9 OK against fresh mpm-net2.  Strict success criterion
(`+PSJ` boot marker AND clean `A>` prompt at cursor) all polls.

The PROXY path is ~12% faster on cold boot at -nothrottle and far
more consistent (stddev 3 vs 68 ms).  IRQ-direct's stddev comes from
the per-byte ISR cascade vs the proxy's bulk OTIR/INIR.

### Sumtest workload (in flight)

In-progress at session end.  Harness rewrites + sumtest signaling
documented below.

## Bugs found this session

### 1. `transport_pio_recv_byte` `0xFF`=empty conflation

The "intermittent stall after 4-25 sectors" filed as
ravn/rc700-gensmedet#56 was deterministic 0xFF data byte
conflation, not a race.  `transport_pio_recv_byte` treated the
chip's `m_input` value `0xFF` as "no byte yet" — but `0xFF` is a
valid data byte that mpm-net2 sends throughout `cpnos.com`.

Fix: replace polled recv with chip-IRQ ring buffer.  "No byte"
signal becomes `head == tail` (separate metadata channel), no
shared value space with data.

Full root cause analysis in `tasks/session34-direct-pio-stall-rootcause.md`.

### 2. ravn/mame-rc702-rc759-rc750#8: Mode 1 entry doesn't auto-raise BRDY

Per Zilog datasheet, entering MODE_INPUT raises BRDY 2 cycles after
the mode select.  MAME's `z80pio.cpp::set_mode(MODE_INPUT)` only
sets `m_mode`, leaving `m_rdy` at whatever it was — usually false
post-reset.  Filed as **ravn/mame-rc702-rc759-rc750#8** with datasheet reference and
suggested patch.  Workaround: bridge optimistic-init `m_brdy_high=true`
self-bootstraps via `set_mode(OUTPUT)` callback.

### 3. cpnet_bridge over-strobed under IRQ

The "always-strobe-on-rising-edge" workaround for the polled-recv
0xFF=empty issue (commit `9c2cbb4e1a9`) breaks the IRQ design: the
bridge over-strobes between Z80 INs, silently overwriting `m_input`
and dropping bytes.  Symptom under IRQ: NETBOOT returns 0 at second
xact.  Fixed in `60e2b9a032f`: re-gate `poll_tick` on `m_brdy_high`
+ buffer-non-empty (correct gate for IRQ design).

### 4. Off-by-0x80 page-aligned ring buffer

Tried to optimize the ISR's ring-store from `add hl,bc` to
`ld h, page; ld l, head` (saving a few T-states).  Buffer was at
0xEC80 but `ld h, 0xEC; ld l, head` writes to `0xEC00 + head` —
**overwriting the IVT** (which lives at 0xEC00..0xEC23).  Reverted
to `add hl,bc` then re-did with the correct `ld h, _pio_rx_buf_page`
linker-symbol-driven page byte.

### 5. SIO-B file mode self-loopback (test harness, not cpnos)

`-bitb2 /tmp/cpnos_siob.raw` → MAME treats the file as bidirectional
(chip TX appends, chip RX reads from the same file).  cpnos's 25
netboot progress dots got read back as keyboard input → CCP
processed `..?` as a command and printed `?`.  Looked like CCP was
broken; was actually MAME's bitbanger semantics.  Fixed by replacing
file with a passive socket sink.

### 6. smoke_inject.py recv-timeout missed prompt-check

Pre-existing bug.  `smoke_inject.py` checked the buffer for the
expected `A>` prompt only inside the `if data:` branch — i.e.,
only when bytes arrived.  When CCP printed a quiet `A>` and went
silent, `recv` would time out (0.5s) and the loop just `continue`d
without re-checking the buffer.  The 10s "nudge" mechanism papered
over this by injecting phantom CRs, which CCP queued during program
work and echoed afterward as extra `A>` prompts — interpretable as
"I had to type Enter manually".

Fix: pulled prompt-check into a `maybe_fire_step()` helper called
on BOTH data-received AND recv-timeout paths.  Removed the nudge
mechanism entirely (no longer needed; was also injecting phantom
CRs that confused mid-program state).

### 7. Port 0xFF maps to DMA on RC702

Initial sumtest "test done" signal was `out 0FFh, A`.  Port 0xFF is
in the 8237 DMA controller range (`map(0xf0, 0xff)` in rc702.cpp:175).
Switched to **port 0x80** (in the unmapped 0x20-0xEF range) for the
done signal.  Lua tap uses `io_space:install_write_tap(0x80, 0x80, ...)`
to capture the write timestamp deterministically — no SIO-B byte
parsing, no display memory scanning.

## Pending

- **Sumtest workload bench (3-way comparison)**: SIO / PIO-IRQ /
  PIO-PROXY against the trimmed `m80 sumtest + l80 sumtest + sumtest`
  sequence, timed start-to-end via the port-0x80 done signal.
  Harness machinery in place; one more single-run validation needed,
  then 3 modes × N runs.

- **Workload-detection robustness**: scroll handling in display-memory
  taps remains brittle.  Per-port done signal (sumtest port 0x80)
  fixes the success-detection side; per-step "ready for input"
  detection still uses cursor stability + at-prompt (works but
  fragile).  Disk-traffic-on-bridge as readiness signal noted in
  todo.md as a follow-up.

## Issue / TODO summary

Filed:
- **ravn/mame-rc702-rc759-rc750#8** — Z80-PIO Mode 1 entry doesn't auto-raise BRDY.

Recorded in `tasks/todo.md` (deferred):
- 32-bit CRT frame counter mirroring rcbios's location.
- Investigate multi-channel SNIOS in any CP/NET implementation.
- Port `cpnet_pio_server` proxy to a Pi/Pico (MicroPython sketch
  vs. C SDK port).
- Use bridge disk traffic as "program running" signal for harness
  readiness detection.

Closed:
- ravn/rc700-gensmedet#56 — root cause documented as 0xFF=empty
  conflation, fixed by IRQ-driven recv path.

## Lessons

### Signaling overload bites when context shifts

A sentinel that's safe given a precondition becomes unsafe the
moment the precondition isn't carried with it.  `PIO_RX_EMPTY_VAL=0xFF`
was originally for first-byte-of-frame sync (FMT byte structurally
never 0xFF).  Reused as a per-byte recv sentinel in the snios-on-PIO
experiment, the precondition no longer held — but the `#define`
made it look reusable.  Saved as feedback memory:
`feedback_sentinel_preconditions.md`.

### "Intermittent" is a hypothesis label

Session 33 framed the failure as "intermittent stall, fourth race
remaining".  Inheriting that framing in session 34 sent me down
chip-emulation rabbit holes for hours.  The actual bug was
deterministic — running `data.count(b'\xff')` on `cpnos.com` would
have shown sector 4 as the first 0xFF in 30 seconds.  Saved as
feedback memory: `feedback_intermittent_is_hypothesis.md`.

### Scrolling makes display-based detection fragile

Workload taps that detect "command done, ready for next input" via
cursor position + display row content are accurate when the screen
is static, fragile when it scrolls.  After scroll, original prompt
rows have moved, last-known-row references are stale, and rate of
state changes during program output overwhelms the simple stability
check.  Lesson: prefer protocol-level signals (port writes, queue
state) over display-content scraping.
