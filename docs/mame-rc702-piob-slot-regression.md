# MAME bug report — `rc702`: ~~any slot wrapper on PIO-B blocks guest IM2 IRQs~~

> **CLOSED as not-a-bug** 2026-04-27.  Original ravn/mame-rc702-rc759-rc750#6 was a
> misdiagnosis; the slot infrastructure on PIO-B works correctly.
> The actual cause of every "black screen / cpnos-rom hang" symptom
> was `prom1.ic65` not being loaded into the `prom1` ROM region.
> Resolution committed as `9ff362da529` "rc702: ROM_LOAD_OPTIONAL
> for prom1.ic65 (CP/NOS resident helpers)" on master.  See
> [`cpnet_slot_work_history.md`](cpnet_slot_work_history.md) for the
> full timeline including the misdiagnosis and how it was caught.
>
> This file is kept for historical context — the original report is
> below the rule.  All subsequent claims about "empty slot also
> breaks cpnos" or "card on PIO-B causes IM2 failure" are
> invalidated.  Don't act on them.

---

# (historical) MAME bug report — `rc702`: any slot wrapper on PIO-B blocks guest IM2 IRQs

> **Originally filed as [ravn/mame-rc702-rc759-rc750#6](https://github.com/ravn/mame-rc702-rc759-rc750/issues/6)** on
> 2026-04-26.  Closed as not-planned on 2026-04-27 after verification
> showed slot+card boots cpnos cleanly when prom1.ic65 is loaded.

## Title

`rc702`: cpnos-rom guest fails to complete initialization when the
`RC702_PIO_PORT` slot wrapper is present on PIO-B — even with no card
plugged in.  Autoload-PROM CP/M boot from floppy is unaffected because
it doesn't use PIO-B's IM2 IRQ vector; cpnos-rom does (for `isr_pio_par`)
and stalls at `PC=0x0039` before its first SIO-A transmit.

## Summary

On `ravn/mame-rc702-rc759-rc750:cpnet-fast-link`, the RC702 driver exposes both halves of
its single Z80-PIO chip (`m_pio`, ports A and B) as
`rc702_pio_port_device` slots — see
`src/devices/bus/rc702/pio_port/`.  PIO-A defaults to the `keyboard`
card; PIO-B's default is `nullptr` (empty).  With `-piob` left unset,
the guest (cpnos-rom) initializes fully — VRTC interrupts fire, the CRT
renders text, NDOS coldst completes, CCP loads and prints `A>`.  With
`-piob` set to **any** card from the option list (`keyboard` or
`cpnet_bridge`), guest initialization stalls before
`enable_interrupts()`.  No interrupts fire (the CRT-VRTC counter at
`0xEC30` does not increment past its uninitialized BSS value); the
screen stays black; the CCP never loads.

The regression appears to be in MAME (not in the guest) because:

- The same guest binary (`cpnos.bin`) boots correctly with `-piob`
  unset, regardless of which netboot responder is used
  (`netboot_server.py` proxy, or stock z80pack `mpm-net2` MP/M).
- The regression is independent of the `cpnet_bridge` card's behaviour:
  it persists when the card's `read()` / `write()` / `rdy_w()` and the
  polling timer are gutted to no-ops, and when the timer is removed
  entirely.  Replacing `cpnet_bridge` with the existing `keyboard`
  card on `-piob` produces the same failure.

I have not located the specific cause inside MAME, but I confirmed
that **no other driver in `src/mame/` exposes both ports of a single
Z80-PIO chip via slot devices simultaneously.**  This is plausibly an
unexercised code path; the bug may be in the slot infrastructure, in
the rc702 driver wiring, or in the Z80-PIO model when both port halves
drive peripheral chains.

## Environment (factual)

- Repo: `ravn/mame-rc702-rc759-rc750`, branch `cpnet-fast-link`, top of branch
  `9291063ccc7` plus a revert/un-revert pair (current HEAD
  `ae827fd92f5`).
- Host: macOS arm64.  Build:
  `make SUBTARGET=regnecentralen SOURCES=src/mame/regnecentralen/rc702.cpp REGENIE=1 OSD=sdl TOOLS=0 NO_USE_PORTAUDIO=1 NO_USE_PULSEAUDIO=1`.
- Guest: `cpnos-rom` from `ravn/rc700-gensmedet` (PROMs auto-installed
  via `make cpnos-install` into
  `~/git/mame/roms/rc702/{roa375.ic66,prom1.ic65}`).

## Driver wiring of interest (factual)

`src/mame/regnecentralen/rc702.cpp`, around line 526:

```cpp
m_pio->out_int_callback().set_inputline(m_maincpu, INPUT_LINE_IRQ0);
m_pio->in_pa_callback().set(m_pio_a,  FUNC(rc702_pio_port_device::read));
m_pio->out_pa_callback().set(m_pio_a, FUNC(rc702_pio_port_device::write));
m_pio->out_ardy_callback().set(m_pio_a, FUNC(rc702_pio_port_device::rdy_w));
m_pio->in_pb_callback().set(m_pio_b,  FUNC(rc702_pio_port_device::read));
m_pio->out_pb_callback().set(m_pio_b, FUNC(rc702_pio_port_device::write));
m_pio->out_brdy_callback().set(m_pio_b, FUNC(rc702_pio_port_device::rdy_w));

RC702_PIO_PORT(config, m_pio_a);
m_pio_a->set_default_option("keyboard");
m_pio_a->out_strobe_handler().set(m_pio, FUNC(z80pio_device::strobe_a));
RC702_PIO_PORT(config, m_pio_b);
m_pio_b->out_strobe_handler().set(m_pio, FUNC(z80pio_device::strobe_b));
```

Daisy chain (line 439): `{ "ctc1" }, { "sio1" }, { "pio" }`.

The `rc702_pio_port_device` slot wraps a
`device_single_card_slot_interface<device_rc702_pio_port_interface>`
and forwards `read()`, `write(uint8_t)`, `rdy_w(int)` to the plugged-in
card; a card asserts STB into the chip via `m_slot->strobe_w(int)`
which routes to `m_strobe_handler` (= `z80pio_device::strobe_a` /
`_b`).

This pattern is modelled on `tatung/einstein.cpp`'s
`einstein_userport_device` slot.

## Reproduction (factual)

A guest that prints "RC702 CP/NOS v1.2" + `A>` once netboot completes;
the test harness needs only `mame_boot_test.lua` and an MP/M responder.

Working baselines (confirmed PASS):

```
make cpnos-mame                 # -bitb1 file, no -piob, -seconds_to_run 8 -> PASS at frame 320
make cpnos-netboot              # -bitb1 socket netboot_server.py, no -piob -> PASS, A> at row 3
mame -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
     -autoboot_script mame_boot_test.lua  -seconds_to_run 15
                                # MP/M = z80pack mpm-net2, no -piob -> PASS, A> at row 3
```

Failing case (PIO-B has any card):

```
mame -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
     -piob cpnet_bridge -autoboot_script mame_boot_test.lua -seconds_to_run 15
        # -> no result file, no A>, screen black, crt_ticks unchanged from uninit BSS

mame -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
     -piob keyboard     -autoboot_script mame_boot_test.lua -seconds_to_run 15
        # -> same failure
```

Inside MAME `error.log` when `-piob cpnet_bridge` is set, the bridge's
listener thread reports it received the test bytes and the chip pulled
them via `read()`:

```
[:piob:cpnet_bridge] cpnet_bridge: listening on 127.0.0.1:4003
[:piob:cpnet_bridge] cpnet_bridge: listener got 6 bytes was_empty=1
[:piob:cpnet_bridge] cpnet_bridge: poll_tick strobing (FIFO non-empty, BRDY high)
[:piob:cpnet_bridge] cpnet_bridge: read() -> 0x55 (remain 5)
[...repeats for 0xAA, 0x42, 0x00, 0xFF, 0x10 in order...]
```

So `m_slot->strobe_w(0); m_slot->strobe_w(1)` does cause
`z80pio_device` to call back into the chip's `in_pb_callback()`, which
dispatches to the slot's `read()`, which dispatches to the card.  The
bytes flow through that path correctly.

But **no PIO interrupt is observed**: the Z80 PC never reaches the
`isr_pio_par` entry at `0xEF8E` (verified by a Lua read-tap), the
`_pio_par_count` byte at `0xEA3C` stays at its uninitialized BSS
contents, and the **CRT-VRTC ISR's tick counter at `0xEC30` likewise
never increments** past its uninitialized value — confirming that
**no IRQ at all reaches the Z80**, not just the PIO one.  (Aside on the
uninitialized BSS: this MAME build appears to leave guest RAM with an
alternating `39 00 39 00 ...` pattern at boot.  cpnos-rom does not
zero its BSS.)

Without `-piob`, the same Lua tap shows `crt_ticks = 101` at 7
emulated seconds in the proven-working `cpnos-netboot` recipe; with
`-piob <any>`, it stays at the uninitialized value.

## What is established (factual)

1. The cpnos-rom guest binary used in the failing case is
   **identical** to the one in the passing cases (verified by SHA1 / by
   re-using the same `clang/cpnos.bin`).
2. The MAME binary used in the failing case is **identical** to the
   one used in the working `cpnos-netboot` cross-check (same
   `regnecentralend` produced by one build).
3. The only command-line difference between PASS and FAIL is the
   presence/absence of `-piob <card>`.
4. The failure persists when the `cpnet_bridge` card's chip-side
   callbacks (`read`, `write`, `rdy_w`) are replaced by no-ops.
5. The failure persists when the bridge's `emu_timer`-based polling is
   removed entirely (no `timer_alloc` call).
6. The failure also occurs with `-piob keyboard` — the existing card
   type already used by PIO-A.
7. The Z80 daisy chain configuration is unchanged between PASS and FAIL.
8. Other interrupt sources (CTC channel 2 driving the CRT VRTC ISR)
   also fail to fire in the failing case — i.e. it is **not** a
   PIO-B-specific interrupt issue.  The failure mode is "**no IM2 IRQ
   at all**".

## What I have not established (guesses, marked as such)

- I have **not** reduced the failure to a minimal MAME patch.  I do
  not know whether the bug is in `device_slot_interface` lifecycle, in
  the rc702 driver's wiring, in `z80pio_device`'s reset/start ordering
  when both port-input callbacks point at slot wrappers, or in the
  daisy-chain interaction with PIO when both halves are
  non-default-routed.
- **Guess:** The default behaviour of an **empty** `RC702_PIO_PORT`
  slot's `read()` is to return `0xff`, while the default behaviour of
  a **populated** slot's `read()` is to delegate to the card (which
  returns `0xff` from the empty-FIFO path of `cpnet_bridge`, or
  whatever `keyboard` returns by default).  These two `0xff` paths
  look identical to me but I have not confirmed they are bit-equivalent
  at the chip's view of the input register.
- **Guess:** The Z80-PIO chip's behaviour in IM 2 with both ports
  having interrupt-eligible peripherals may differ from the
  no-second-peripheral path in some way I have not traced —
  particularly around BRDY initial state and INT line gating during
  reset.
- **Guess:** Slot-device `device_start` ordering when `option_replace`
  is in effect on a non-default-default slot may interact badly with
  the chip's `device_start` if the chip captures callback bindings
  before the slot has resolved its card.
- **Guess:** I have not checked whether the issue reproduces with
  **only** PIO-A using the slot pattern (i.e. PIO-A as a slot, PIO-B
  wired directly with no slot wrapper) and a card forced via
  `-pioa`.  If that also breaks, the bug is in the slot-on-Z80-PIO path
  generally; if it does not, the bug is specific to having both halves
  in slot mode.

## Topology survey across `src/mame/` (factual)

I surveyed every driver instantiating `Z80PIO`.  Filtering for those
that wire **both Port A and Port B inputs of a single chip** (the
closest analogue to RC702 — multi-chip drivers where each chip uses
only one port are a different topology):

- **Direct function callbacks on both ports, no slot:**
  `xerox/xerox820.cpp` (`kbpio`), `skeleton/attache.cpp`,
  `altos/altos5.cpp`, `cantab/jupace.cpp`, `tiki/tiki100.cpp`,
  `merit/meritm.cpp`, `kyber/kminus.cpp`, several `ddr/*` drivers.
- **One port via slot, other port direct:** `tatung/einstein.cpp`
  (Port A direct -> centronics, Port B -> `einstein_userport_device`
  slot — proven to work), `wavemate/bullet.cpp` (Port A -> centronics,
  Port B direct).
- **Both ports of a single Z80-PIO via slot devices simultaneously:**
  **`regnecentralen/rc702.cpp` only.**

I did not find any precedent in MAME that exercises the same code
path.  This is consistent with — but does not prove — the hypothesis
that the issue lies in an unexercised slot/PIO interaction.

## Multi-slot per chip — the proven-working pattern (factual)

For comparison, every chip in MAME that successfully exposes multiple
peripheral connection points as slot devices uses **per-channel
`device_t` subdevices**:

| Chip | Subdevice class | Drivers using both channels as slots |
|---|---|---|
| **Z80-SIO / DART** | `z80sio_channel` | `rc702.cpp` (ours), `kaypro.cpp`, `bullet.cpp`, `osbexec.cpp`, `attache.cpp`, `tiki100.cpp`, `bw12.cpp`, `apricotf.cpp`, `ampro.cpp` … (>20 drivers) |
| **Z80-SCC** (8530) | `z80scc_channel` | similar |
| **scnxx562** DUART | per-channel subdevice | similar |
| **upd765a / wd17xx** | each drive is a `floppy_connector` slot | every floppy-equipped driver |

RC702 itself uses this pattern successfully for `sio1` (rs232a +
rs232b slots, no issues).

**Z80-PIO is the only multi-channel-callback chip in MAME without
per-channel subdevices.**  In `src/devices/machine/z80pio.h` (lines
47-68) all seven port-side callbacks (`m_in_pa_cb`, `m_out_pa_cb`,
`m_out_ardy_cb`, `m_in_pb_cb`, `m_out_pb_cb`, `m_out_brdy_cb`,
`m_out_int_cb`) are flat members of `z80pio_device`.  An internal
`pio_port` struct in `z80pio.cpp` holds per-port state but is **not**
a `device_t` — it has no `device_start`/`device_reset` of its own and
is `start()`ed/`reset()`ed from the parent's lifecycle methods.

The bug almost certainly sits at this seam: two slot wrappers binding
callbacks on the same flat `z80pio_device` hits a path nobody else has
tested, while the Z80-SIO path is well-trodden because each slot
binds to its own channel subdevice.

### Two-channels vs two-slots — what is and isn't supported

It is worth being precise about what the Z80-PIO emulation does and
doesn't anticipate, because the answer is not "one channel only" and
not "two channels via two slots is supposed to work":

- **Two channels on a Z80-PIO chip: intended, supported, well-tested.**
  The chip model has per-port `pio_port` state structs, the API
  exposes seven distinct port-side bindings, and >20 MAME drivers
  successfully wire up both ports directly (`xerox820/kbpio`,
  `attache`, `altos5`, `jupace`, `tiki100`, `meritm`, `kminus`,
  several DDR machines, …).  This pattern has worked since the chip
  model was first written.

- **Two channels each routed through a MAME slot wrapper on a single
  Z80-PIO: never tried before RC702.**  Z80-PIO predates the modern
  `device_slot_interface` / `device_single_card_slot_interface`
  pattern by years.  When the chip author wrote it, "either port can
  be wired to a peripheral" assumed the peripheral was **direct** —
  a function, an `output_latch_device`, a centronics interface —
  known at machine-config time, no late-binding.

- **Slot infrastructure grew up against chips that already had
  per-channel `device_t` subdevices** (Z80-SIO with `z80sio_channel`,
  Z80-SCC with `z80scc_channel`, scnxx562, upd765a/wd17xx with
  `floppy_connector`).  When `option_replace` resolves a slot at
  machine_start, it composes naturally with per-channel subdevice
  start order.  No one wrote a driver that connected two slots to
  the same flat-model chip.

So the missing case is not "the author forbade two channels" and not
"two-channel-via-slot is supposed to work but is broken" — it is the
unswept seam between two abstractions that grew up at different
times: a flat chip model from the pre-slot era, and a slot mechanism
that's only been validated against chips with per-channel
subdevices.  Einstein's "PIO-A direct + PIO-B userport slot" topology
exercises the **one-slot-per-Z80-PIO** composition (one slot, one
direct), and that works.  RC702 is the first driver to push to **two
slots per Z80-PIO**, and that's where the regression lives.

### Historical note (factual, from upstream `mamedev/mame` history)

| Date | Event |
|---|---|
| 2007-12-17 | `z80pio.cpp` present at MAME 0.121 initial checkin (`7b77f12186…`); predates the modern slot infrastructure.  Renamed `.c → .cpp` in 2015. |
| 2010-06-15 | Image-device infrastructure ported from MESS to MAME (`791a3515b9b`). |
| 2011-05-04 | **`device_slot_interface` introduced into MAME** by Miodrag Milanovic (`eeff4d51337`, `92ce55d23ca`). |
| 2012-08-21 | Einstein driver merged from MESS into MAME (pre-existed in MESS). |
| 2014-10-28 | Centronics consolidated into shared device list. |
| 2015-09-30 | **MESS sources merged into MAME** (`1fc48ce120a`). |
| 2017-10-31 | **First slot wrapper around a Z80-PIO port:** `einstein_userport_device` added by Dirk Best (`908529aa32`).  Wraps PIO Port B only.  PIO Port A stays direct to centronics. |
| 2026-04-25 | **Second slot wrapper around a Z80-PIO port:** `rc702_pio_port_device` (this driver).  Wraps both Port A and Port B. |

Two further notes:

- **`z80pio.cpp` itself has never been modified to add slot support.**
  The chip API has been callback-based since 2007 and that's all the
  slot wrappers need.  Slot-related work lives entirely in
  `src/devices/bus/<machine>/...`, bound to the chip's existing
  `in_p[ab]_callback` / `out_p[ab]_callback` / `out_[ab]rdy_callback`
  / `strobe_[ab]` API.
- **The userport-slot-on-Z80-PIO design was not pre-existing in MESS,
  and not part of the 2015 merge.**  It was introduced in unified
  MAME in 2017 — slot infrastructure was 6 years old by then, but
  Z80-PIO had no slot consumers until Einstein got one.

So 6 and a half years passed between the first slot-on-Z80-PIO
(Einstein, single port) and the second (RC702, both ports).  It is
not surprising that the two-wrappers-on-one-flat-chip composition
wasn't exercised before — Einstein, the only prior consumer of this
slot-wrapping idiom, only does the one-port case.

Looking at the diff in `908529aa32`:

```
# Before
MCFG_Z80PIO_OUT_PA_CB(DEVWRITE8("cent_data_out", output_latch_device, write))
MCFG_Z80PIO_OUT_PB_CB(DEVWRITELINE("centronics", centronics_device, write_strobe))

# After
MCFG_Z80PIO_OUT_PA_CB(DEVWRITE8("cent_data_out", output_latch_device, write))   // unchanged
MCFG_Z80PIO_OUT_ARDY_CB(DEVWRITELINE("centronics", centronics_device, write_strobe))
MCFG_Z80PIO_IN_PB_CB(DEVREAD8("user", einstein_userport_device, read))
MCFG_Z80PIO_OUT_PB_CB(DEVWRITE8("user", einstein_userport_device, write))
MCFG_Z80PIO_OUT_BRDY_CB(DEVWRITELINE("user", einstein_userport_device, brdy_w))
```

Port A stayed wired direct to the centronics interface (fixed
peripheral on real Einstein hardware — no reason to make it
runtime-configurable).  Port B was promoted to a slot because the
physical "user port" on the Einstein is, by definition, a
runtime-pluggable connection point — the slot abstraction matches
the real hardware, and the peripherals added in the same commit
(speech cart) and later (mouse) are the cards that plug into it.

So **Einstein having only one slot port is incidental, not
deliberate.**  Nobody decided "max one slot per Z80-PIO" — the
Einstein simply has one fixed-wiring peripheral (centronics) and
one slot-shaped port (the user port) at the hardware level.  RC702
is the first machine where both ports of a single Z80-PIO are
slot-shaped on the real hardware (PIO-A is J4/keyboard, PIO-B is
J3/expansion — both physical connectors with runtime-pluggable
peripherals), and so it is the first driver to push two slots
through the same flat-model chip.

## Two fix paths

1. **Refactor `z80pio_device` to introduce a `z80pio_channel`
   subdevice.**  Architecturally correct — matches every other
   dual-channel chip in MAME — but touches a widely-used chip model.
   Probably needs upstream MAME review even on the `ravn/` fork.
2. **Avoid the unexercised path in `rc702.cpp`.**  Wire PIO-A's
   keyboard directly (no slot wrapper), keep PIO-B as a slot for
   `cpnet_bridge`.  Matches the proven Einstein topology (one PIO
   chip, one slot port + one direct port).  Localized; loses the
   never-exercised "PIO-A keyboard as runtime slot card" property.

Path 2 is the minimum-disruption workaround.  Path 1 is the
upstream-quality fix.

## Suggested workaround (not a fix)

Match the proven Einstein topology: keep PIO-B as a slot for the
`cpnet_bridge` peripheral, but wire PIO-A's keyboard **directly** in
the rc702 driver instead of via a slot.  This would restore the unique
RC702 use case (cpnet_bridge as a runtime-pluggable peripheral)
without depending on the unexercised "both halves as slots" code
path.  I have not yet attempted this rewrite.

## Files to look at first (suggestion only)

- `src/mame/regnecentralen/rc702.cpp` — the only call site of
  `RC702_PIO_PORT` for both PIO halves.
- `src/devices/bus/rc702/pio_port/pio_port.{cpp,h}` — the slot wrapper
  itself (modelled on `bus/einstein/userport/userport.cpp`).
- `src/devices/machine/z80pio.{cpp,h}` — the chip model, especially
  BRDY initial state and the interaction between the two
  `out_*rdy_callback` chains.
- `src/emu/diserial.cpp` / `src/emu/diimage.cpp` / slot-related
  `device_t` lifecycle code — if the bug is in slot-device init
  ordering.

I am happy to run additional tests against this configuration to
narrow it further if you can suggest a probe.
