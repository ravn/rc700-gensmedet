# CP/NET Fast Host Link — Design

> **Status:** MAME-side implemented 2026-04-25 on branches
> `ravn/mame-rc702-rc759-rc750:cpnet-fast-link` (slot infrastructure + bridge slot card)
> and `ravn/rc700-gensmedet:cpnet-fast-link` (Z80 stub +
> Python+Lua harness).  Pi 4B host hardware not yet acquired; the
> production Pi+Pico path stays deferred.  MAME-side bring-up
> (host -> Z80 byte path inside MAME) is testable today via
> `make cpnet-mame-test` once a CP/NET netboot server is up.
>
> Supersedes the Mode 2 plan in
> [`rcbios-in-c/docs/parallel_host_interface.md`](../rcbios-in-c/docs/parallel_host_interface.md).

## Goal

Fast, reliable host<->RC702 transport sized for CP/NET + CP/NOS protocol
traffic. Replaces today's 38400-baud async-serial CP/NET path (~3.8 KB/s).

**Long-term shape (clarified 2026-04-25):** a small always-on server
(Raspberry Pi 4B or 3B, optionally fronted by Pi Pico(s)) sits next to the
RC702 and bridges it to the outside world via CP/NET. The link described
here is the wire between that server and the RC702.

## Scope

Hard constraints (load-bearing, will not be revisited without the user
saying so):

1. **CP/NET + CP/NOS only** on this channel. Not a console, terminal,
   file-transfer (RDR/PUN/LST), or printer path.
2. **Physical RC722 keyboard remains attached and functional in
   production.** J4 / PIO-A is reserved for the keyboard.
3. **No PCB modifications.** Cables are user-fabricated; signals must
   already be routed to a connector.
4. **J8 bus expansion is out of scope** for this iteration.

## Verified hardware facts

Pinned from `RC702_HARDWARE_TECHNICAL_REFERENCE.md`,
`docs/schematics/MIC07_pinout.md`, and bench notes through 2026-04-25.

| Fact | Source | Status |
|---|---|---|
| J4 (keyboard, DSUB-25) carries PA0..PA7 + ASTB. ARDY chip pin **not routed** to any connector. | MIC07 schematic | verified |
| J3 (parallel, DSUB-25) carries PB0..PB7 + BSTB (pin 2) + BRDY (pin 12). Full handshake. | MIC07 schematic | verified |
| J1/J2 (SIO-A/B) carry RxD/TxD/RTS/CTS/DTR/DCD. TxC/RxC pins 15/17 **not connected**. | RC702-RC703 manual fig. 13 | verified |
| Z80-SIO/2 has no on-chip DPLL — fast SIO RX impossible without external clock pin. | Zilog datasheet | verified |
| PIO-A Mode 1 input + ASTB strobe works on this exact RC702. | `ravn/cbl923` Pico keyboard rig | bench-verified |
| SIO-A bit clock at ÷1 = ~614 kbaud works in TX direction. | bench, framing layer (SDLC vs monosync vs ...) **uncertain** | partially verified |
| PIO-B + BSTB/BRDY handshake on this board. | electrically symmetric to PIO-A but never bench-tested | **unverified** |
| J3 pins 3/13/14 are GND, J4 pins 3/13/14 are +12V. Keyboard cable cannot be plugged into J3 without an adapter (would short +12V to GND). | MIC07 schematic | verified |

## Decision rationale

This section documents the reasoning behind picking Option P and
rejecting every alternative, evaluated against the load-bearing
constraints in "Scope". It exists so that a future reader (including
future-Claude) can see why the design space collapsed to a single
viable choice without having to re-derive it from the raw hardware
notes.

**TL;DR.** Option P was the only option that simultaneously satisfied
all six load-bearing constraints (CP/NET-only, no PCB mods, keyboard
on PIO-A, SIO-A keeps RDR/PUN/LST, Pi as production target, machine
usable normally with link unplugged) while delivering at least an
order-of-magnitude speed improvement over the current 38400-baud async
path. Option H is held in reserve as the planned long-term comparison
target — not as a fallback, but as a benchmark: ship P, measure, then
decide whether the additional response-side throughput H offers
justifies its cost.

### Decision criteria (load-bearing constraints, in priority order)

1. **CP/NET + CP/NOS only.** Channel does not need to carry console,
   terminal, RDR/PUN/LST, or printer traffic. Stated by user
   2026-04-25.
2. **Physical RC722 keyboard remains attached and functional.**
   Production deployment cannot remove or relocate the keyboard.
   Stated by user 2026-04-25 ("the machine can be used normally").
3. **No PCB modifications.** Cables are user-fabricated; signals must
   already be routed to a connector. Long-standing project rule.
4. **SIO-A retains its existing IOBYTE roles** (RDR, PUN, LST under
   most IOBYTE presets, per `rcbios-in-c/bios.h:185-195`). Backwards
   compatibility for existing CP/M software. Stated by user
   2026-04-25.
5. **Production target is a small Pi sidecar** (Pi 4B / Pi 3B,
   optionally fronted by Pico). Implies the host side must run on
   ARM Linux without specialist hardware (FT2232H etc. add cost and
   single-source-vendor risk).
6. **Out of scope: J8 bus expansion**, until further notice. Stated
   by user.

A seventh property — *machine usable normally with the link
unplugged* — is implied by constraints 2 + 4 and is called out
separately because it constrains how invasive the BIOS additions can
be (anything that breaks boot-without-link is rejected).

### Options considered, with verdicts

The matrix below lists every option that surfaced during the
investigation. Speed estimates are back-of-envelope unless marked
"bench-verified". "Constraints violated" lists which of the six
criteria above the option fails.

| Option | Description | Speed (each direction) | HW verified? | Constraints violated | Verdict |
|---|---|---|---|---|---|
| **P** | PIO-B half-duplex via J3 | 30 in / 50 out KB/s | PIO-B port: no; PIO-A symmetric: yes (cbl923) | none | **Chosen** |
| **H** | PIO-B in + SIO-A sync TX out at 614 kbaud | 30 in / 70 out KB/s | SIO-A bit clock: yes (framing tbd); PIO-B: no | #4 (SIO-A consumed) | Future comparison target |
| **H'** | Like H but SIO-A reconfigured per-frame between async-38400 and sync-÷1 | 30 in / 70 out KB/s during burst, async otherwise | partial | #4 partially (in flight only) | Mentioned as escape hatch for H if #4 truly load-bearing |
| Mode-2 bidir on PIO-A / J4 | Z80-PIO Port A in Mode 2 with full hw handshake | 25-30 KB/s | impossible | #2 (PIO-A locked to keyboard); also ARDY chip pin not routed to any connector — would require PCB mod | **Rejected** |
| K (PIO-A keyboard cable + SIO-A sync TX) | Reuse `ravn/cbl923` rig as the host->Z80 path; SIO-A for Z80->host | 30 in / 70 out KB/s | both halves verified individually | #2 (Pico would have to replace or pass-through the RC722 keyboard); #4 (SIO-A consumed) | **Rejected** (post 2026-04-25 keyboard constraint) |
| A1 (status quo) | SIO-A or SIO-B async at 38400 | 3.8 KB/s | yes | none — but doesn't meet the goal | Fallback; remains available |
| A2 | SIO async at 76.8 / 115.2 / 250 kbaud | 8-25 KB/s | n/a | #3 — needs 74LS393 ÷16 tap, PCB modification | **Rejected** |
| A3 | SDLC TX 250-614 k + async-38400 RX, SIO-A only | 28-70 down / 3.8 up | TX yes; RX async fine | #4 (SIO-A consumed) | Dominated by P; not seriously considered |
| A4 | SDLC TX 614 k + async-RX, **with FT2232H host adapter** | 70 down / 3.8 up | n/a | #5 (host stack adds vendor-specific adapter); #4 | Dominated by H; rejected on host-cost grounds |
| B-only variants (PIO-B Mode 0/1/3 with various polling/ISR shapes) | various sub-options of "PIO-B as the only fast channel" | 25-100 KB/s peak | no | varying | Collapsed into P (which is the cleanest of these) |
| C (PIO-B bulk + SIO-A async control plane) | Use SIO-A async as a control-plane wire alongside PIO-B for bulk | 30-50 KB/s | no | #4 (SIO-A async consumed for control) | Rejected — control plane is not needed; CP/NET frames carry their own length and sequencing |
| C2 (data diode: PIO-B in + SIO-A async TX out) | Each direction is its own dedicated channel, no switching | 30 in / 3.8 out | partial | #4; also slow on response side | **Rejected** — slower than P on the bandwidth-dominant side |
| Y-cable into J3 + J4 emulating Mode 2 | Custom Y-cable picks BSTB/BRDY from J3, data + ASTB from J4 | 25-30 KB/s | no | #2 (still uses J4); ARDY still missing -> fragile fixed-delay timing on host | **Rejected** — fragile, no real win over P |
| Move keyboard physically to J3, use J4 for CP/NET | Free up J4 / PIO-A for fast link | 30 in / ?-out | no | #2 (changes keyboard wiring); also J3 pins 3/13/14 GND vs J4 +12V — would short the supply unless an adapter is built | **Rejected** — supply-damage risk; fails #2 |
| J8 bus expansion (for completeness) | Full Z80 bus exposed on expansion connector; DMA channel 0 free | 150-1000 KB/s | yes (Centronics-style hard-drive boards already use it) | #6 (out of scope by user) | **Out of scope** |

### Per-option analysis (rejected options)

What follows is a fuller treatment of each non-trivially-rejected
option, in case a future reader needs to revisit one because a
constraint changed.

#### Mode-2 bidirectional on PIO-A / J4

The "obvious" plan in the original design (`rcbios-in-c/docs/parallel_host_interface.md`).
Z80-PIO Port A's Mode 2 gives full bidirectional handshake on a single
8-bit data bus with ASTB + ARDY. *Looks* like exactly what we want.

Killed by the schematic reading (`docs/schematics/MIC07_pinout.md`,
session 16, 2026-04-08): ARDY (PIO chip pin 28) is not routed to any
external connector. The original RC702 designer needed strobed *input*
from the keyboard and left ARDY dangling. Without ARDY, Mode 2 cannot
complete its handshake; the host has no way to tell the Z80 "I've
taken your byte". Workarounds (open the case, run a wire from PIO pin
28 to a spare J4 pin) violate constraint #3.

Even if ARDY were patched in, constraint #2 (RC722 keyboard remains on
J4) would now block this independently. Two separate kills; recovery
would need both constraints to relax.

#### Option K — PIO-A keyboard cable + SIO-A sync TX

The most attractive *alternative* until the keyboard constraint
landed. Each half of K had been bench-verified separately on the
user's RC702: the `ravn/cbl923` Pico-as-keyboard rig demonstrated
PIO-A Mode 1 input over J4, and the user has bench-confirmed SIO-A bit
signaling at the ÷1 clock. Hardware risk on K was lower than on P.

The cost: the Pico/Pi sits where the RC722 currently plugs in. Either
the keyboard is removed (breaks #2), or the Pico passes the keyboard
through (Pico has to receive RC722 signaling and re-transmit it;
significant firmware complexity), or a Y-cable splices both onto J4
(electrically fragile — two TTL drivers contending on the data lines).
None of these are acceptable in a "machine usable normally" production
deployment.

K is viable only if the user later relaxes #2 (e.g., a USB keyboard
plugged into the Pi replaces the RC722 entirely). Not currently on the
table.

#### A2 — SIO async at higher baud

The 614400 Hz baud rate clock on the RC702 is generated by dividing
the 19.6608 MHz memory clock by 32 (two cascaded 74LS393 ÷2 + ÷16).
Tapping the chain one stage earlier doubles the clock to 1.2288 MHz,
giving 76800 baud max. Tapping further could in principle reach
1.92 MHz / 120000 baud, but with significant clock-skew engineering.

Killed by constraint #3: any tap requires either a wire bodge on the
PCB or replacing the divider chain. PCB modification is excluded.

The trace point exists and the wire would be short, so this becomes
attractive again only if #3 is ever relaxed for a one-off lab setup.

#### A3 / A4 — SIO-only SDLC

A3 (SDLC TX at 250 k + async RX at 38400 over SIO-A) and A4 (the same
at 614 k with an FT2232H host adapter) are asymmetric: fast Z80->host,
slow host->Z80. They consume SIO-A entirely (constraint #4) and don't
solve the bandwidth question on the request side.

Even if #4 were relaxed, P beats A3 on aggregate throughput and Q4 on
host-stack simplicity (A4 needs an FT2232H, raising host BOM and
introducing a single-source-vendor dependency, vs P's ability to run
on a stock Pi 4B GPIO header).

#### Y-cable into J3 + J4

A Y-cable picks up BSTB+BRDY from J3 (Port B's connector) and data +
ASTB from J4 (Port A's connector), connecting both into a single
host-side cable. The PIO chip then sees Port A data on PA0..7 +
"borrowed" handshake lines from Port B's side.

Multiple problems:
- ARDY is *still* missing (it's not on either connector).
- The host has to insert a fixed delay where ARDY would normally tell
  it to advance — fragile timing.
- Constraint #2: J4 is still in use, so the keyboard has to share the
  Y-cable too, putting two TTL drivers on the data lines.
- The cable itself is non-standard, harder to fabricate cleanly than
  P's straight-through J3 cable.

No throughput advantage over P. Rejected on every axis.

#### Move keyboard physically to J3

If we want PIO-A / J4 free for CP/NET, the keyboard could in principle
move to J3 / PIO-B. But:
- J3 pins 3/13/14 are signal ground. J4 pins 3/13/14 are +12V (the
  keyboard cable carries +12V on those pins).
- Plugging a stock keyboard cable into J3 would short +12V to ground
  on three pins. That's likely to damage the +12V supply regulator.
- Moving the keyboard requires fabricating a J4-to-J3 adapter that
  re-routes power and signals correctly. Counts as a "soldered cable
  artefact" — not technically a PCB mod, but a permanent rewire of
  the keyboard.

Rejected for the supply-damage risk and the loss-of-RC722-keyboard
property (constraint #2). Also unnecessary now that PIO-B / J3 is the
chosen channel and the keyboard stays on J4.

### Why Option P specifically

P is the choice because, against the matrix above, it is the only row
with no constraint violations and a non-trivial speed improvement
(8-13× over status quo). Concretely:

- **Constraint #1** (CP/NET only): satisfied — the J3 link is
  dedicated to CP/NET frames; nothing else is multiplexed on it.
- **Constraint #2** (keyboard preserved): satisfied — PIO-A / J4 is
  not touched; RC722 plugs in and works as today.
- **Constraint #3** (no PCB mods): satisfied — J3 is already a
  factory-installed connector with all required signals routed.
- **Constraint #4** (SIO-A roles preserved): satisfied — neither SIO
  channel is touched. RDR, PUN, LST all keep their current physical
  port assignments.
- **Constraint #5** (Pi as production target): satisfied — Pi 4B
  hosts z80pack and the Python bridge; a Pi Pico over USB-CDC drives
  the J3 cable (the same Pico used during dev). No specialist host
  hardware needed; no level shifter required (cbl923 rig has empirically
  proven 3.3V GPIO drives Z80 PIO directly).
- **Constraint #6** (no J8): satisfied trivially.
- **Implied constraint** (machine usable normally with link
  unplugged): satisfied — without the J3 cable the BIOS still boots,
  the keyboard works, both serial ports work, all CP/M programs run.

The cost paid: Option P is half-duplex (one direction at a time),
which is acceptable because CP/NET is intrinsically request/response.
The mode-switch overhead per packet boundary is one Z80 OUT (~3 µs at
4 MHz), negligible against a 5-150 ms protocol round-trip.

### Long-term: full-speed SIO TX comparison

User goal stated 2026-04-25: ship Option P, then **compare against
full-speed SIO TX (Option H)** to determine empirically whether the
response-side throughput improvement justifies the additional cost.

The comparison is a future bring-up step, not a fallback. Specifically:

1. **Ship P first**, including the Pi-side bridge and the BIOS
   additions. Bench-measure actual sustained CP/NET round-trip
   throughput on representative workloads (cold-boot a CP/M image,
   run a directory listing, copy a 50 KB file, run a few ZORK turns).
2. **Build an H prototype** alongside, sharing the PIO-B Mode 1 input
   path with P. The only delta is a second transport for Z80->host
   that uses SIO-A in sync mode at the ÷1 clock instead of PIO-B
   Mode 0 output.
3. **Bench H** on the same workloads. Measure response-side
   throughput, total round-trip latency, and CPU overhead (T-states
   spent on transport, since the Z80's CPU is the scarce resource).
4. **Decide** whether to promote H to default, hold P as default, or
   build H' (SIO-A reconfigured per-frame between async-38400 and
   sync-÷1 to preserve RDR/PUN/LST when not in use).

Decision criteria (provisional, refine after bench data exists):

- If H gives >2× response-side speedup at no software-complexity cost
  beyond what's already needed for the SIO sync-mode work the user
  has previously prototyped, **promote H**.
- If H gives <50% speedup or breaks RDR/PUN/LST in unrecoverable
  ways, **hold P**.
- In between, build H' and let real workloads decide.

The framing layer for SIO-A sync mode (SDLC vs monosync vs bisync)
will be settled as part of the H prototype work — the user's previous
bench-verification confirmed only the bit-rate signaling at ÷1, not
the framing register configuration.

## Architecture: Option P (committed)

PIO-B half-duplex via J3, direction-switched at CP/NET frame boundaries.

```
            outside world
                  |
            (LAN / Internet / SSH / HTTP)
                  |
         +----------------+
         | Pi 4B (or 3B)  |   <- z80pack as CP/NET master,
         | always-on      |      runs natively on Linux
         +----------------+
                  |
       J3 cable (custom 11-wire DSUB-25M -> Pi GPIO)
                  |
         +----------------+      +----------------+
         | RC702 J3 / PIO-B |    | RC702 J4 / PIO-A |
         |  CP/NET frames   |    |  RC722 keyboard  |
         +----------------+      +----------------+
                  \                    /
                   \                  /
                    \                /
                  +-------------------+
                  |   RC702 mainboard |
                  |   Z80A-PIO + SIO  |
                  +-------------------+
```

### Why Option P

- **Keyboard stays put** on J4 / PIO-A. RC722 plugs in and works as today.
- **PIO-B / J3 is the only connector** that exposes both a strobe-in
  (BSTB) and a ready-out (BRDY). Hardware handshake in either direction.
- **Half-duplex maps 1:1 to CP/NET.** Master sends a request; slave
  responds. Direction switching is a single OUT to the PIO-B control
  register (~3 µs at 4 MHz Z80) at packet boundaries.
- **SIO-A and SIO-B remain free** for terminal / printer / debugging.
- **Cable count: one new cable** (J3 to Pi GPIO).

**Net effect: the RC702 can be used exactly as it is today — keyboard,
serial terminals, printer, all CP/M programs unchanged.** The fast link
is purely additive on a previously-unused connector. Plug the J3 cable
in to use it; unplug it and the machine still boots and runs normally.

### IOBYTE / RDR / PUN / LST preservation

Concretely (per `rcbios-in-c/bios.h:185-195`), the existing CP/M device
mapping under Option P is **unchanged**:

| IOBYTE preset | CON | RDR | PUN | LST |
|---|---|---|---|---|
| IOB_TTY (0) | SIO-B | **SIO-A** | **SIO-A** | SIO-B |
| IOB_CRT (1) | CRT | **SIO-A** | **SIO-A** | CRT |
| IOB_BAT (2) | batch | SIO-B | SIO-B | **SIO-A** |
| IOB_UC1 (3) | SIO-B+CRT | SIO-A | SIO-A | SIO-A |

SIO-A continues to serve RDR + PUN + LST (data port). SIO-B continues
to serve CON (console). Option P touches neither chip — it adds a new
device on PIO-B that operates in parallel.

Option H, in contrast, would consume SIO-A for the 614 kbaud TX path
and **would break RDR + PUN + LST until SIO-A is dynamically
reconfigured per use** or those devices are migrated to SIO-B. That's
one more reason to default to Option P and only revisit H if the
response-side throughput is measurably insufficient.

### Speed envelope

| Direction | Mechanism | Estimate | Limit |
|---|---|---|---|
| host -> Z80 | PIO-B Mode 1 input, BSTB-strobed, ISR-driven | ~25-30 KB/s | Z80 ISR overhead (~30 µs/byte vector dispatch + push/pop + RETI) |
| Z80 -> host | PIO-B Mode 0 output, OTIR loop, BRDY/BSTB-handshaked | ~50-80 KB/s peak, ~30-50 KB/s sustained across BIOS dispatch | OTIR (~21 T-states/byte) bounded by per-byte handshake roundtrip |
| Mode-switch | one OUT to PIO-B control + one host-side mode acknowledge | ~5 µs | one PIO control word write |

For a 133-byte CP/NET response (5-byte SCB header + 128-byte payload):
~3-4 ms TX + ~5 ms RX = ~8-10 ms round-trip. Compare current async at
38400: ~70 ms. Speedup: ~7-9x. Bootloading a CCP+BDOS image (~12 KB) goes
from ~3 s to ~0.5 s.

## Architecture: Option H (long-term comparison target)

PIO-B Mode 1 input only (host->Z80) + SIO-A sync-mode TX at 614 kbaud
(Z80->host).

- Pros: ~70 KB/s response throughput vs Option P's ~30-50; no direction
  switching; SIO-A's bench-verified ÷1 bit clock is utilised.
- Cons: SIO-A consumed for output (breaks RDR/PUN/LST per
  `bios.h:185-195` unless migrated to SIO-B); two cables instead of
  one; Pi-side firmware grows a sync-mode receiver (SDLC bit-stuff or
  monosync byte-align).

**Plan: build P first, ship and benchmark; build an H prototype
sharing P's PIO-B input path; bench-compare on representative CP/NET
workloads; decide.** Decision criteria are spelled out in the
"Long-term: full-speed SIO TX comparison" subsection of "Decision
rationale" above. H is held as a comparison target, not a fallback —
P is the production deployment until/unless H demonstrates a
worthwhile speedup.

The H' variant (dynamically reconfigure SIO-A between async-38400 and
sync-÷1 per CP/NET frame, to preserve RDR/PUN/LST when not in use) is
the escape hatch if H wins on throughput but the SIO-A consumption
turns out unacceptable for legacy software. Sketched only — designed
in detail when bench data exists to motivate it.

## Z80 side

Both `cpnos-rom` and `rcbios-in-c` need symmetric additions.

### PIO-B initialisation (boot-time)

```
PORT_PIO_B_CTRL <- 0x22   ; interrupt vector (slot 17, vec 0x22)
PORT_PIO_B_CTRL <- 0x4F   ; Mode 1 input (default state)
PORT_PIO_B_CTRL <- 0x83   ; enable interrupts
PORT_PIO_B_CTRL <- 0x00   ; interrupt mask follow-up byte
```

Existing scaffold:

- `cpnos-rom/init.c:46-103` port_init table — extend with PIO-B init
  triplet.
- `cpnos-rom/hal.h:36-38` `PORT_PIO_B_DATA` / `PORT_PIO_B_CTRL` already
  defined.
- IVT slot 17 (vec 0x22) currently wired to `isr_noop` in
  `cpnos-rom/init.c`. Re-route to a new `isr_pio_net`.
- `rcbios-in-c/bios_hw_init.c:96-150` already has a `KBD_PIO_B`
  conditional that sketches Mode 0/1 toggling — repurpose its
  `isr_pio_par` symbol for the network side, retire the toggle.

### Frame structure on the wire

CP/NET / CP/NOS frames carry their own length and addressing in the SCB
header. The Z80 ISR reads the header first, then knows exactly how many
more bytes to expect — no software framing on top is needed.

```
[ NID | DID | SID | FNC | SIZ | DATA ... ]
        ^^^^^^^^^^^^^^^^^^^^^^^
               header (5 bytes)         payload (SIZ + 1 bytes per CP/NET spec)
```

Receive ISR is a tiny state machine:
- state HEADER: count 5 bytes, then read SIZ to learn payload length.
- state PAYLOAD: count SIZ + 1 bytes, then signal "frame ready".
- state IDLE: signal back, switch PIO-B to Mode 0, response writer takes
  over.

Optional: append a 1-byte XOR checksum at end-of-frame on both sides for
sanity. Cheap; catches stuck-bit hardware faults that the handshake
alone won't catch.

### Direction switch

```
;; RX -> TX
ld a, 0x0F          ; Mode 0 = output
out (PORT_PIO_B_CTRL), a
;; ... OTIR response bytes ...

;; TX -> RX
ld a, 0x4F          ; Mode 1 = input
out (PORT_PIO_B_CTRL), a
;; back to receive loop
```

Host side mirrors: after each direction-switch from Z80, host detects
the BRDY edge change and switches its own GPIO direction.

### Interrupt priority

Z80A-PIO Port A has higher daisy-chain priority than Port B by default.
Keyboard interrupts (rare, human-paced) on PIO-A pre-empting CP/NET
receive (busy, packet-bursts) on PIO-B is acceptable: PIO-B's BRDY auto-
deasserts during the keyboard ISR, so the host stalls and no bytes are
dropped. Worst-case keyboard ISR latency adds ~30 µs to the per-byte
handshake budget — within tolerance.

## Cable specification

J3 -> Pi 4B GPIO (or Pico GPIO for dev):

| J3 pin | Z80 PIO signal | Direction (Z80 view) | Host GPIO |
|---|---|---|---|
| 17 | PB0 | bidir | data 0 |
| 18 | PB1 | bidir | data 1 |
| 19 | PB2 | bidir | data 2 |
| 20 | PB3 | bidir | data 3 |
| 21 | PB4 | bidir | data 4 |
| 22 | PB5 | bidir | data 5 |
| 23 | PB6 | bidir | data 6 |
| 24 | PB7 | bidir | data 7 |
| 2 | BSTB | input (host drives) | strobe-out (host) |
| 12 | BRDY | output (Z80 drives) | ready-in (host) |
| 3, 13, 14 | GND | — | GND (any/all) |

Total: 11 conductors (8 + 2 + 1 GND minimum; can wire all three GND pins
for return-path quality on a long cable).

**No power on J3.** The connector has no +5V or +12V rail (unlike J4,
which powers the keyboard from pins 25 and 3/13/14). The Pico and Pi
must be powered separately — both are USB-powered in our topology, so
this is a non-issue. The J3 cable is signal + ground only.

**Voltage levels — no level shifter chip needed.** Empirical: the
`ravn/cbl923` Pi Pico keyboard rig already drives the Z80 PIO (Port A,
Mode 1 input + ASTB strobe) directly from 3.3V Pico GPIO without level
shifting, and the Z80 reads it cleanly. Z80 PIO TTL VIH min is 2.0V, so
3.3V is comfortably above threshold.

The reverse direction (Z80 drives, Pico reads) is borderline rather
than proven: Z80 PIO output VOH is typically ~3.5-3.7V (datasheet min
2.4V), and the RP2040 datasheet specs absolute max input at 3.63V.
Standard practice in the vintage-computing community is to add a
**series 470 Ω - 1 kΩ resistor** on each Pico-side input pin —
current-limits the protection-diode clamp without needing a level
shifter chip. Adds ~$0.10 of resistors total; does not perturb the
output direction (Z80 PIO inputs draw negligible current).

So the cable BOM is: 11 wires + 9 series resistors (8 data + BRDY).
No TXS0108E / 74LVC245 / shifter board needed.

**Cable note (do NOT trip on this):** J3 pins 3/13/14 are GND, but on
the J4 side they carry +12V. A keyboard cable plugged into J3 would
short +12V to GND on three pins. The J3 cable described above is
*not* keyboard-cable-compatible — it's a brand-new, J3-only harness.
Don't reuse a keyboard cable.

## Host side

### Production: Topology B (Pi 4B + Pi Pico)

```
Pi 4B running Linux
  +- z80pack-as-CP/NET-master (compiled native, listens on TCP :4002 internally)
  +- pi_cpnet_bridge.py (this repo) — bridges TCP :4002 <-> USB-CDC to Pico
  +- (optional) outside-world services: SSH, HTTP frontend, file shares, etc.
       all built on top of CP/NET access
       |
       USB-CDC
       |
Pi Pico running Pico-SDK firmware
  +- USB-CDC <-> J3 cable bridge
  +- PIO state machines for the BSTB/BRDY handshake
```

The Pi 4B never touches the J3 cable directly. A Pi Pico — the same
chip used in dev (Topology A below) — handles the cable side. SSH
into the Pi for remote control of the whole stack; the Pi delegates
GPIO timing to the Pico over USB-CDC.

Why Pi+Pico instead of Pi GPIO direct:

- The cbl923 rig has already proven Pico GPIO drives Z80 PIO without
  level shifting. Reusing the same firmware in production is one less
  thing to bring up.
- Pi 4B GPIO (3.3V, not 5V tolerant) would face the same series-resistor
  question as the Pico anyway, plus need its own GPIO timing code.
- One firmware codepath covers both dev and production. Topology A
  and B differ only in which Linux box owns the USB-CDC endpoint.
- Failure isolation: a cable mishap can damage a $5 Pico, not a $60 Pi.

### Development: Topology A (Mac + Pico)

```
Mac running macOS
  +- z80pack-as-CP/NET-master
  +- mac_cpnet_bridge.py — bridges TCP :4002 <-> USB-CDC to Pico
       |
       USB-CDC
       |
Pi Pico running Pico-SDK firmware
  +- USB-CDC <-> J3 cable bridge
  +- PIO state machines for the BSTB/BRDY handshake
```

Same wire protocol on both topologies. Pico-side and Pi-side bridges
are functionally interchangeable.

### Languages

| Layer | Language | Reason |
|---|---|---|
| Z80 BIOS additions (cpnos-rom) | C, clang-z80 | matches existing codebase |
| Z80 BIOS additions (rcbios) | C, both clang-z80 and z88dk | matches existing codebase, both compilers required per CLAUDE.md |
| Pi 4B / Mac host bridge | Python 3 | matches `ddt_deploy.py`, `sdlc_receiver.py` precedent |
| Pico firmware (dev only) | C with Pico SDK + PIO state machines | throughput beyond MicroPython's comfort zone; existing `cbl923/ascii.py` MicroPython rig retained as smoke test, not extended |
| MAME bridge | C++ | only choice |
| Build glue | Make (top), cmake (Pico SDK) | conventions |

## MAME side

The MAME RC702 driver lives at
`mame/src/mame/regnecentralen/rc702.cpp` (~555 lines, original author
Robbbert 2016). User maintains `ravn/mame-rc702-rc759-rc750` fork. Recent CP/NET-related
work in that fork: ravn/mame-rc702-rc759-rc750#1 (rs232b null_modem default + DCD
wiring), ravn/mame-rc702-rc759-rc750#3 (z80dart_device -> z80sio_device migration).

For Option P bring-up we want a fourth patch — but the right framing
is **not** "wire CP/NET into the driver". It's "expose the PIO ports
the way the rs232 ports are exposed: as generic slot devices with
peripherals attached at MAME-config time". The CP/NET bridge then
becomes one peripheral choice among several, selected at the
command line only when the payload running in MAME wants it. Other
software running on the same MAME executable (the original RC702
CP/M, BASIC, COMAL, anything historical) sees PIO-B as an idle
parallel port — exactly as on real hardware.

**Status (2026-04-25):** implementation landed on branch
`ravn/mame-rc702-rc759-rc750:cpnet-fast-link`, commit `0e6ee52260d`.  All four patches
described below are committed; `mame -validate rc702` passes,
`-listdevices` and `-listslots` show the slot system working.  The
Z80-side stub (`isr_pio_par` byte counter) lives on
`ravn/rc700-gensmedet:cpnet-fast-link` (commit `bcdb181`); the
Python+Lua test harness in `tests/cpnet_bridge/` (commit `a71d7c1`)
exercises the host -> Z80 byte path end-to-end inside MAME.  The
end-to-end PASS gate requires a CP/NET netboot server up so cpnos-rom
actually loads — see `tests/cpnet_bridge/README.md` for prerequisites.

**Blocker (2026-04-26):** any card plugged into PIO-B (`-piob keyboard`
or `-piob cpnet_bridge`) prevents the cpnos-rom guest from completing
its IM2 IRQ initialization — no interrupts fire, the screen stays
black, the CCP never loads.  PIO-A (with default `keyboard` card) and
PIO-B (empty) both work individually; only the "card on PIO-B"
configuration regresses.  The bridge byte path itself is verified —
6 test bytes flow through listener -> chip `read()` in order — but the
Z80 ISR never enters because no IRQ reaches the CPU.  Tracked in
**[ravn/mame-rc702-rc759-rc750#6](https://github.com/ravn/mame-rc702-rc759-rc750/issues/6)** with full
reproduction + topology survey;
[`docs/mame-rc702-piob-slot-regression.md`](mame-rc702-piob-slot-regression.md)
mirrors the issue body for offline reference.

The original "what we'll build" spec is preserved below for reference.

### Correcting a misreading from 2016

The current `rc702.cpp` has a comment along the lines of "Printer
(PIO port B commented out)". This is **incorrect** — the original
2016 author misunderstood the RC702's I/O mapping. The serial
printer on this machine is on a SIO channel (per the hardware
reference: SIO-A as LST in some IOBYTE presets; per the current
`rcbios-in-c` BIOS: SIO-A as LST in IOB_BAT and IOB_UC1, SIO-B as
LST in IOB_TTY). PIO-B has always been a **generic 8-bit parallel
I/O port** with full handshake — not a printer port and not
purpose-built for anything in particular. The factory RC702
shipped with PIO-B unpopulated at the connector level too (J3 has
no power rails); it was always an expansion port awaiting a
peripheral.

So the patch should not bake "this is the CP/NET bridge port" into
the driver. PIO-B is a slot. CP/NET bridge is just one of many
peripherals that *can* be plugged into that slot.

### Current state in `rc702.cpp`

What's there today (per project notes through 2026-04-25):

- Z80-PIO device instantiated; **Port A hardcoded to keyboard input**
  (KEY_DAT on port 0x10), ASTB strobed by the keyboard model.
- **Port B is instantiated but its data lines and BSTB/BRDY handshake
  are not wired to anything externally** — no slot, no peripheral.
  The misleading "Printer" comment sits next to this dead code.
- Z80-SIO/2 (post-ravn/mame-rc702-rc759-rc750#3) wired with both channels exposed as
  `rs232_port_device` slots. SIO-A -> rs232a, SIO-B -> rs232b.
  Both rs232 slots default to `null_modem` and accept `-bitb1` /
  `-bitb2` command-line options for socket / pipe / stdio backends.
- IM2 daisy chain: CTC -> SIO -> PIO (priority order). PIO-A
  interrupts already routed; PIO-B INT line free since Port B is dead.
- IVT slot 17 (vector 0x22) is what the Z80 BIOS will use for PIO-B
  per the Z80-side design above.
- No generic "8-bit + STB/RDY" slot device exists in MAME upstream
  (verified by source survey 2026-04-25):
  - `centronics_device` is a slot but unidirectional/Centronics-shaped
    (data + strobe one way; busy/ack/perror/select/fault the other)
    — wrong topology for a Z80-PIO port.
  - `cg_parallel_slot_device` (Colour Genie) exposes pa_r/pa_w/pb_r/
    pb_w but **no** STB/RDY handshake.
  - **`einstein_userport_device`** (Tatung Einstein, in
    `src/devices/bus/einstein/userport/`) is the closest match —
    a `device_single_card_slot_interface` that exposes `read()`,
    `write(uint8_t)`, and `brdy_w(int)` to plug-in cards. Tagged
    Einstein-specific by location but the *shape* is exactly what
    we want.
- **MODE-change is not observable through the PIO callback API.** The
  z80pio_device class has no `out_mode_callback()` or equivalent —
  peripherals cannot watch a Mode 0 <-> Mode 1 switch through the
  device interface. (Verified from `src/devices/machine/z80pio.h`.)
  This **mirrors real hardware**: the physical Z80-PIO chip has no
  external pin that signals a mode change either; per-port external
  signals are only data + STB + RDY + INT (verified from Zilog
  datasheet). The CP/NET bridge handles this the way real
  peripherals do — by following the higher-level wire protocol —
  not by observing chip mode. See "Direction tracking" in the
  bridge spec below.

### Patch scope (generic-slot pattern, Einstein-userport-modelled)

Four changes, all in `ravn/mame-rc702-rc759-rc750`. The first three are RC702-generic
infrastructure; only the fourth is CP/NET-specific. The slot
infrastructure is a deliberate clone of the Tatung Einstein
userport pattern (`src/devices/bus/einstein/userport/`), which is
the closest existing precedent in upstream MAME for an 8-bit-with-
handshake Z80-PIO peripheral slot.

**(1) Define a slot device class for the PIO ports.**

Working name: `rc702_pio_port_device`. Location:
`src/devices/bus/rc702/pio_port/pio_port.{cpp,h}` — a fresh bus
namespace under `bus/rc702/`. RC702-scoped initially. Promotable to
`bus/z80pio_port/` later if other Z80-PIO drivers adopt the pattern.

Class shape (modelled on Einstein userport + rs232_port_device):

```cpp
class rc702_pio_port_device :
    public device_t,
    public device_single_card_slot_interface<device_rc702_pio_port_interface>
{
    // outbound (port -> Z80 PIO chip)
    auto out_strobe_callback();   // calls m_pio->strobe_b() or strobe_a()
    auto in_data_callback();      // PIO data input handler (chip pulls)
    auto out_data_callback();     // PIO data output handler (chip pushes)
    auto out_brdy_callback();     // BRDY edges propagate to card
    // ...standard MAME boilerplate (device_start, device_reset)
};

class device_rc702_pio_port_interface : public device_interface
{
public:
    virtual uint8_t read() = 0;          // chip is reading: card produces a byte
    virtual void write(uint8_t data) = 0;// chip wrote: card consumes a byte
    virtual void brdy_w(int state) = 0;  // BRDY edge from chip
    // card asserts STB into chip via the port's out_strobe_callback
};
```

The Einstein userport already has exactly `read()`, `write(uint8_t)`,
and `brdy_w(int)` as its interface methods (verified from
`src/devices/bus/einstein/userport/userport.h`). We mirror that
verbatim. The Einstein userport is tagged Einstein-specific by
location only; the *shape* is generic.

**(2) Define the slot option list.**

A function `rc702_pio_port_cards(device_slot_interface &device)`
populates the slot's option list, mirroring `default_rs232_devices`
in `src/devices/bus/rs232/rs232.cpp`:

| option | card | notes |
|---|---|---|
| `keyboard` | RC702 keyboard, lifted out of the driver | natural fit for PIO-A |
| `cpnet_bridge` | new — see (4) | natural fit for PIO-B; CP/NET only |
| (future: `printer`, `tape`, expansion peripherals) | — | open |

Each card derives from `device_rc702_pio_port_interface` and a
`device_t` of its own (multiple-inheritance pattern, same as
`device_rs232_port_interface` cards).

The slot's "empty" state is **not** a named card — MAME's idiom is
to pass `nullptr` as the slot's default-card argument when no card
should be plugged in by default. (The Einstein userport does the
same.) Don't invent a "null_pio" no-op card analogous to
`null_modem` — that would be misleading: `null_modem` actually
*does* something (forwards bytes to a host bytestream via
bitbanger). Empty rs232 slots aren't `null_modem` either; they're
just `nullptr`.

**(3) Refactor the driver to use slots for both PIO ports.**

In `rc702.cpp` `machine_config`:

```cpp
RC702_PIO_PORT(config, "pioa", rc702_pio_port_cards, "keyboard");
RC702_PIO_PORT(config, "piob", rc702_pio_port_cards, nullptr);
m_pio->in_pa_callback().set("pioa",
    FUNC(rc702_pio_port_device::read));
m_pio->out_pa_callback().set("pioa",
    FUNC(rc702_pio_port_device::write));
m_pio->out_ardy_callback().set("pioa",
    FUNC(rc702_pio_port_device::brdy_w));
// (pioa's out_strobe_callback wired to m_pio->strobe_a)
// symmetric block for piob
```

Defaults match today's behaviour: PIO-A=keyboard, PIO-B=disconnected
(slot empty). No command-line argument required to reproduce factory
state.

The current inline keyboard wiring in `rc702.cpp` is lifted into the
new `keyboard` slot card. Removing the keyboard from PIO-A and
putting it on PIO-B is now a one-line config change. Two paths,
depending on how MAME's command-line slot semantics treat empty:
either `-pioa "" -piob keyboard` (some MAME versions accept empty
string for unplug) or just `-piob keyboard` (with `pioa` left at
default `keyboard` — both ports active, redundant but harmless if
nothing else cares which port the keyboard is on). Either way, no
`#ifdef KBD_PIO_B` needed.

Drop the misleading "Printer (PIO port B commented out)" comment
in the same diff. PIO-B was never the printer port; the printer is
on a SIO channel per the hardware reference and per
`rcbios-in-c/bios.h:185-195`. The 2016 author misunderstood RC702's
I/O mapping.

**(4) Implement the `cpnet_bridge` slot card.**

A new device class implementing `device_rc702_pio_port_interface`,
scoped to the `ravn/mame-rc702-rc759-rc750` fork. Working name:
`rc702_cpnet_bridge_device`. Location:
`src/devices/bus/rc702/pio_port/cpnet_bridge.{cpp,h}` (next to the
slot definition, like rs232 cards live under `bus/rs232/`).

Responsibilities:

- **PIO-facing side:** implement `read()`, `write(uint8_t)`, and
  `brdy_w(int)`. Use the port_device's `out_strobe_callback` to
  pulse STB into the chip when host bytes arrive.
- **Host-facing side:** open a Unix domain socket (or TCP) on a
  configurable address. Default `socket.localhost:4003`, sibling to
  the existing `:4002` z80pack CP/NET TCP port. Speak the same
  byte-stream wire protocol that the Pi+Pico bridge will speak in
  production — see "Wire protocol" below. Address overridable via
  the slot option string: `-piob cpnet_bridge:localhost:4003`.
- **Direction tracking — bridge does not observe chip mode at all.**
  The physical Z80-PIO chip has no mode-signal pin, so real
  peripherals can't observe mode either; they cope by being
  fixed-mode (printer, keyboard) or by following the higher-level
  protocol over the wire. The CP/NET bridge takes the latter route:

  - The bridge implements both `read()` and `write()`. The chip
    only fires the one that matches its current mode (in Mode 1 it
    pulls via `read()`; in Mode 0 it pushes via `write()`). The
    chip routes the event automatically based on its own internal
    mode state; the bridge doesn't need to know which mode is
    active.
  - The bridge maintains two unidirectional FIFOs: `host_to_z80`
    (drained by `read()`) and `z80_to_host` (filled by `write()`).
    Bytes get routed to the right FIFO automatically by which
    callback fires.
  - The bridge asserts STB after each `read()` (signals "new data"
    in Mode 1) and after each `write()` (signals "I took it" in
    Mode 0). Both go through the same `out_strobe_callback`.
    BRDY edges from the chip gate flow regardless of direction.

  Direction state on the **socket-facing** side (which is real and
  needed) lives in the wire protocol: the bridge counts bytes
  against CP/NET SCB length fields to know when a frame ends and
  the protocol's logical "direction" flips. That's a property of
  CP/NET, not of the PIO chip.

  No port-0x13 sniff. No upstream `out_mode_callback()` patch.
  No control-word parser inside the bridge. The chip's own mode
  routing does the heavy lifting; the bridge is purely event-
  driven on the data + handshake callbacks.

### Default and command-line shape

Default config (no command-line PIO arguments):

```
mame rc702
  # PIO-A: keyboard (matches real hardware)
  # PIO-B: nothing  (matches factory)
  # SIO-A, SIO-B: rs232 ports with null_modem (existing behaviour)
```

CP/NET in MAME (Option P, this branch's bring-up target):

```
mame rc702 -piob cpnet_bridge:localhost:4003
```

Other historical exercises that don't touch CP/NET (CP/M, COMAL,
BASIC, the original test PROMs) just run with the default config.
PIO-B is empty, no socket, no daemon required.

### Wire protocol (MAME bridge <-> external client)

This is the same protocol the production Pi-side daemon will speak
to the Pi Pico over USB-CDC. By making MAME speak it identically,
the host-side Python code is unchanged between dev and production.

Bytes on the socket carry CP/NET frames in both directions. Framing
matches the Z80-side ISR's expectations: each frame is a CP/NET SCB
(5-byte header carrying length, then payload) — no extra envelope
needed. Direction is implicit: if the bridge is in "host -> Z80"
state (Z80's PIO-B is in Mode 1), socket-received bytes go to PIO-B;
if in "Z80 -> host" state (Mode 0), PIO-B-produced bytes go to the
socket.

Edge events (mode switches, RDY/STB edges) are not transmitted over
the socket — the protocol relies on the receiver counting bytes
against the SCB length field, just like the Z80-side ISR does. This
keeps the wire protocol minimal: it's a pure bidirectional byte
stream with frame boundaries derivable from the payload itself.

If we later need out-of-band events (resync, reset, error notif) we
can borrow MAME's existing pattern of escape sequences — but until
empirical bring-up shows a need, keep it byte-stream-pure.

### Testing harness

A new top-level make target, mirroring the existing `make
sio-echo-test` shape:

```
make cpnet-mame-test
  -> launches MAME with -piob cpnet_bridge:localhost:4003
  -> runs a Python harness that:
       - connects to :4003
       - sends a known CP/NET request frame (e.g. console-status)
       - waits for the RC702 response
       - asserts the bytes match expected
       - exits 0 on PASS
```

Same harness reused later against the Pi+Pico bridge — only the
endpoint changes. The Python bridge daemon (`pi_cpnet_bridge.py`)
already proxies TCP <-> USB-CDC, so the test harness sees a uniform
TCP interface in both topologies.

### What gets filed against ravn/mame-rc702-rc759-rc750

When implementation opens, file one tracking issue (working title:
"RC702: generic PIO slot devices + CP/NET bridge peripheral"). The
issue body is essentially this subsection plus a link back to
`docs/cpnet_fast_link.md`. Implementation lands as a series of
commits on a `pio-slots` branch in `ravn/mame-rc702-rc759-rc750`. Note: framing the
patch as "generic slots" — not "CP/NET bridge" — is what makes it
a credible upstream candidate later. CP/NET-specific code lives in
the bridge peripheral, which can stay in the fork.

### Sequencing

The MAME bridge is the first concrete bring-up step — it does not
need the Pi 4B, the J3 cable, or the second Pico. It only needs a
working `ravn/mame-rc702-rc759-rc750` build (already maintained by the user) and the
Z80-side BIOS additions to be at least at "PIO-B init + a stub
isr_pio_par that increments a byte counter" level.

Dependencies (in order from most independent first):

1. Z80-side stub: PIO-B init in `cpnos-rom/init.c` port_init table,
   `isr_pio_par` set to a trivial byte-counter ISR. ~10 lines of C.
2. MAME refactor — items (1)-(3) above (generic PIO slots, keyboard
   moved to a slot peripheral, default config preserves today's
   behaviour).
3. MAME peripheral — item (4) above (cpnet_bridge implementation).
4. Integration: Python test harness + `make cpnet-mame-test` target.
5. Iterate the wire protocol against (1)-(4) until a CP/NET console-
   status round trip works.
6. Real-hardware bring-up — replace MAME bridge with Pi+Pico+cable;
   nothing else changes.

Steps (2) and (3) can be split into separate commits / PRs. (2) is
a clean refactor that's a candidate for upstream MAME on its own
merits; (3) carries the CP/NET-specific code and stays in the fork.

### Open questions for implementation phase

- ~~MODE-change event delivery~~ — **closed at design time**: the
  bridge does not observe chip mode at all; it relies on the chip's
  own callback routing (Mode 1 fires `read()`, Mode 0 fires
  `write()`) plus protocol-level direction tracking on the
  socket-facing side. Mirrors how real hardware peripherals work.
- Whether to expose protocol-level direction state on the socket
  as a diagnostic (escape byte), or rely purely on byte counting
  derived from CP/NET SCB. Default to the latter; revisit if
  debugging gets painful.
- Default socket address `localhost:4003` chosen to sit next to
  z80pack's `:4002`. If a production Pi sidecar exposes the bridge
  over LAN, the address scheme generalises.
- Whether the *generic PIO slot infrastructure* (steps 1-3) gets
  promoted from `bus/rc702/pio_port/` to `bus/z80pio_port/` and
  proposed upstream after bench-validation. Likely yes — the shape
  is verbatim Einstein userport (which is itself
  driver-namespaced), and a generic sibling is a small, defensible
  upstream contribution. Defer the rename until the abstraction has
  taken its first non-RC702 user, real or hypothetical.
- Whether to slot-ify PIO-A's keyboard during the same patch (per
  step 3 default) or leave PIO-A's wiring inline as a smaller diff.
  Default: do both, since the slot abstraction is identical and the
  payoff (one-line keyboard relocation, future expansion-card test
  fixtures) is real.

## Bring-up sequence (deferred until hardware available)

When the user obtains a Pi 4B (and the existing Pi Pico from the cbl923
rig is repurposed as the cable bridge), the bring-up order is:

1. **PIO-B input bench.** Mirror the cbl923 rig setup but on J3. Pi/Pico
   strobes BSTB; verify Z80 ISR fires and reads the byte correctly.
   This is the only currently-unverified hardware claim and the
   load-bearing risk for Option P. Mirrors the cbl923 rig's PIO-A
   verification but for PIO-B.
2. **PIO-B output bench.** Z80 OTIR loop; host reads via BRDY edge,
   strobes BSTB to ack. Verify byte-perfect round-trip.
3. **Direction-switch bench.** Z80 toggles Mode 1 <-> Mode 0; host
   detects the switch via BRDY edge timing; verify cleanly.
4. **End-to-end CP/NET frame test.** Smallest possible CP/NET request
   (e.g. console-status query); verify request -> response over the
   link. Same test runs in MAME against the virtual host bridge.
5. **MAME parity.** rc702.cpp patch wires PIO-B + virtual host bridge.
   All future protocol iteration runs in MAME by default.
6. **Pi 4B native deployment.** Move from Mac+Pico (Topology A) to Pi
   4B (Topology B). Same Python bridge, different GPIO library backing.
7. **Outside-world services on Pi.** SSH, HTTP, etc. Out of scope for
   this doc.

## Open questions / decisions deferred

- Z80 PIO output VOH on this specific RC702: scope or DMM check
  during the first PIO-B output bench. If VOH stays under ~3.7V with
  the 470 Ω - 1 kΩ series resistor on the Pico input, the no-shifter
  cable is good. If VOH spikes higher (out-of-spec PIO chip, weak GND
  reference, etc.), fall back to a small TXS0108E breakout. The
  cbl923 rig only proves the Pico-drives-Z80 direction empirically;
  Z80-drives-Pico is the unverified half.
- Series-resistor value choice for Pico inputs (470 Ω vs 1 kΩ): pick
  during bring-up after measuring real edge times against the
  resistor + Pico-input-capacitance RC. Probably 1 kΩ is fine for
  30-50 KB/s; 470 Ω as a hedge if edges look slow.
- Optional XOR checksum at frame end: yes/no decision after Step 4.
- Pi-side z80pack invocation: in-process Python binding vs subprocess
  with TCP loopback. Defer.
- Whether to add a CP/NET frame *gathering* layer in the Z80 BIOS
  (concatenate small frames into one OTIR) vs feeding bytes directly.
  Probably premature optimisation.
- Pico firmware language: locked as C/Pico-SDK; does not affect Pi-only
  production deployments.

## What this supersedes

- `rcbios-in-c/docs/parallel_host_interface.md` — Mode 2 PIO-A
  bidirectional plan. Ruled out by ARDY-not-wired finding (session 16,
  schematic MIC07). Will receive a deprecation banner pointing to this
  doc.

## What this does NOT change

- The existing `ravn/cbl923` Pi Pico keyboard rig stays as-is. It
  becomes a development tool for keyboard injection during testing,
  separate from the CP/NET link. Production keyboard input is the
  physical RC722 keyboard plugged into J4.
- 38400-baud async CP/NET via SIO-A or SIO-B remains available as a
  fallback transport. The fast link is opt-in per build.
- Existing CP/NOS architecture (BDOS fns 0-12, no SELDSK/READ/WRITE) is
  untouched — only the transport layer changes.
