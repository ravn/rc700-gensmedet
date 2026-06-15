# Session 17: SIO-B Shadow Console + Baud Rate Investigation

## Date: 2026-04-17

## Summary

Implemented SIO-B as a shadow console for the RC700, allowing a host to
control the machine over SIO-B (ttyUSB1) while SIO-A (ttyUSB0) remains free
for RDR:/PUN: data transfers (HEX uploads). Also investigated maximum baud
rates achievable on SIO-A.

## BIOS Changes (branch: sio-b-test-console)

### 1. SIO-B console probe at cold boot (bios_hw_init.c)

New `siob_console_probe()` function in BOOT_CODE (overwritten after boot, no
resident cost). Sends ENQ (0x05) on SIO-B TX, polls RR0 for ~300 ms for any
reply byte. If host responds, sets `iobyte = IOBYTE_DEFAULT_SIOB` (0x96,
CON:=BAT). Otherwise falls back to `IOBYTE_DEFAULT` (0x97, CON:=UC1).

Probe runs with interrupts disabled, polls SIO-B directly (ISR not active).

### 2. IOB_BAT = keyboard + SIO-B joined console (bios.c, bios.h)

Repurposed the CON:=BAT IOBYTE mode to mean "console on SIO-B":

- **CONIN (bios_conin):** polls both keyboard ring buffer AND SIO-B ring
  buffer (rxbuf_b). First source with data wins.
- **CONST (bios_const):** checks both keyboard and SIO-B ring for data ready.
- **CONOUT (bios_conout_c):** sends to SIO-B via polled TX (`siob_conout`),
  PLUS echoes to the CRT display. Both local user and remote host see output.

Keyboard encoding changed from `(con & 1)` to `(con != IOB_TTY)` so keyboard
works in BAT mode (was previously keyboard-disabled for BAT).

### 3. Polled SIO-B TX (siob_conout)

New `siob_conout()` function replaces `list_lpt()` for CON:=BAT output.
Uses polled I/O (checks RR0 bit 2 for TX empty) instead of interrupt-driven
TX via `prtflg`. **Critical fix:** `list_lpt()` spins on `while (!prtflg)`
which requires the SIO-B TX ISR, but the cold-boot signon banner is printed
before `EI` — causing a deadlock. Polled TX works with interrupts disabled.

### 4. IOBYTE_DEFAULT_SIOB constant (bios.h)

`#define IOBYTE_DEFAULT_SIOB 0x96` — same as IOBYTE_DEFAULT (0x97) but with
CON field changed from UC1(3) to BAT(2). RDR:, PUN:, LST: unchanged.

### Sizes

| Compiler | Before | After | Delta |
|----------|--------|-------|-------|
| Clang    | 6021   | 6108  | +87   |
| SDCC     | 6049   | —     | —     |

The +87 bytes are from siob_conout, expanded conin/const logic, and CRT echo
code in bios_conout_c. The probe itself is in BOOT_CODE (free).

## Host-Side Tooling

### SIO-B console daemon (/tmp/siob_daemon.py)

Python daemon that holds ttyUSB1 open, reads serial → stdout + log file
(`/tmp/siob_console.log`), reads command FIFO (`/tmp/siob_cmd`) → serial.
Auto-responds to ENQ probe at boot. Runs detached via `nohup`.

### Dual-port deploy flow

Successfully deployed BIOS using SIO-B for console and SIO-A for HEX:
1. PIP CPM56.HEX=RDR: (console command on SIO-B)
2. HEX data streamed on SIO-A (RDR: default = PTR = SIO-A)
3. MLOAD, verify, SYSGEN all driven through SIO-B console

No more blind spots — console visible throughout the entire deploy.

## Baud Rate Investigation

### Clock sources

Two clock sources feed the CTC for SIO baud generation:
- **614400 Hz external oscillator** → CTC counter mode → 614400/N
- **4 MHz CPU clock** → CTC timer mode (prescaler /16) → 250000/N

The SIO supports x1, x16, x32, x64 clock multipliers. In x16 mode the SIO
oversamples 16× and finds the center of each bit. In x1 mode it samples
once per bit on the clock edge — no oversampling.

### Z80A SIO theoretical limit

From Zilog Z80 SIO Product Specification (Feb 1980): "Data rates of 0 to
800K bits/second with a 4.0 MHz clock (Z80A SIO)."

### TX vs RX asymmetry

TX (Z80→host) at x1 250000 baud: **8192 bytes, 0 errors, 23 KB/s.** The
transmitter generates its own timing and works perfectly at x1.

RX (host→Z80) at x1 mode: has inherent framing errors for continuous data
(see below).

### Definitive RX sweep (2 stop bits, DI, SIO auto-RTS, 8KB per rate)

Tested all achievable baud rates on clean-booted hardware. Both with and
without SIO Auto Enables (WR3 bit 5 = hardware RTS/CTS flow control).
Results were identical — flow control doesn't help because the Z80 poll
loop reads faster than data arrives, so the 3-byte FIFO never fills and
RTS never drops.

| Baud    | Clock source     | SIO  | FTDI err | RX    | Errors | Rate  |
|---------|------------------|------|----------|-------|--------|-------|
| **38400**   | **ctr/1**    | **x16** | **0.16%** | **8192** | **0** | **0.0%** |
| 41667   | tmr16/6          | x1   | 0.00%    | 8192  | 46     | 0.6%  |
| 50000   | tmr16/5          | x1   | 0.00%    | 8192  | 56     | 0.7%  |
| 62500   | tmr16/4          | x1   | 0.00%    | 8192  | 58     | 0.7%  |
| 76800   | ctr/8            | x1   | 0.16%    | 8192  | 167    | 2.0%  |
| 83333   | tmr16/3          | x1   | 0.00%    | 8192  | 92     | 1.1%  |
| 125000  | tmr16/2          | x1   | 0.00%    | 8191  | 897    | 10.9% |
| 153600  | ctr/4            | x1   | 0.16%    | 8190  | 3765   | 46.0% |
| 250000  | tmr16/1          | x1   | 0.00%    | 8187  | 6531   | 79.8% |

### Root cause of x1 RX errors

In x16 mode the SIO counts 8 clock edges from the start bit's falling edge
to find the **center** of each bit, then samples every 16 clocks. In x1
mode, data is sampled directly on clock edges which land at **bit
boundaries** — not bit centers. For isolated bytes with idle gaps the start
bit detection works. For continuous streams the sampling point cannot
re-center and framing errors cascade.

Key evidence:
- Timer mode (clean square wave from 4 MHz) and counter mode (from 614400
  Hz oscillator) give the same error pattern — not a waveform quality issue
- 0.00% FTDI baud match (250000) fails just as badly as 0.16% (153600) —
  not a clock mismatch issue
- SIO Auto Enables (hardware RTS/CTS) doesn't help — not a buffer overflow
- Channel reset before WR4 change makes no difference
- DI (no ISR interference) makes no difference
- Single isolated bytes work at all rates up to 614400 — the SIO hardware
  CAN clock at these speeds, just not for continuous async data

### Split TX/RX baud rates — not possible on RC702

Investigation (2026-04-18) confirmed that each SIO channel's TX and RX
clock pins are driven by a single CTC channel output (CTC ch0 -> SIO-A
TxC+RxC, CTC ch1 -> SIO-B TxC+RxC). All four CTC channels are allocated
(ch0=SIO-A, ch1=SIO-B, ch2=CRT, ch3=FDC), so there is no spare CTC
channel to clock TX and RX independently. The 250000 baud TX success and
38400 baud RX ceiling are both at the same clock rate — the asymmetry is
purely a SIO receiver limitation (x1 mode framing), not a split-speed
configuration. MAME's rc702.cpp driver correctly models this shared wiring.

### Conclusion

**38400 x16 is the maximum reliable continuous RX rate** with the RC700's
614400 Hz oscillator and Z80 SIO in asynchronous mode. No software or
adapter change can fix the x1 mode framing problem — it's a fundamental
limitation of the SIO's x1 async clock recovery.

Paths to faster inbound data:
- Replace the 614400 Hz oscillator with a higher frequency (PCB mod)
  so x16 mode gives a higher baud (e.g., 1.2288 MHz -> 76800 x16).
  Max SIO TxC/RxC clock input: 4 MHz (250 ns min cycle, Z80A SIO
  datasheet AC characteristics) -> 250000 baud x16 theoretical max.
- Use synchronous mode (see analysis below)
- Use the parallel PIO port instead of serial
- J8 bus expansion connector with polled I/O or DMA (see
  `docs/j8_bus_expansion.md`)
- Accept 38400 and optimize the protocol (fewer round-trips)

### Synchronous mode analysis (2026-04-18)

The SIO's x1 mode was designed for **synchronous** protocols (SDLC, HDLC,
bisync) where an external clock wire is phase-aligned to the data by the
transmitter. No clock recovery is needed — every clock edge = one data
bit. It also works for async if the clock is phase-locked to the incoming
data (e.g., via a DPLL or external bit-sync circuit), but the RC702 has
neither.

**~~SIO built-in DPLL (WR14)~~:** CORRECTION (2026-04-18): the Z80-SIO
does NOT have a DPLL or BRG. WR10-WR15 are features of the Z85C30
SCC (Serial Communications Controller), a later and different chip.
The SIO only has WR0-WR7 and RR0-RR2. The "SIO/2" designation means
"bonding option 2" (sacrifices SYNCB for DTRB), not "version 2 with
more features." Verified from Zilog um0081.pdf (Z80 Family CPU
Peripherals User Manual) which defines no registers beyond WR7.

**Sync mode on the RC702 — the clock wire problem:** the CTC clock output
drives the SIO's TxC+RxC internally on the motherboard. These clock
signals are **not routed to the DB-25 RS-232 connectors** (J1/J2). The
DB-25 carries only TxD, RxD, and handshake lines (DTR/RTS/CTS/DCD).
There is no way to get a clock signal to or from an external device
via the serial ports without a PCB modification.

**Revised approach — SDLC with CTC external clock (2026-04-18):**
Since the SIO has no DPLL, self-clocking NRZI is not possible.
However, SDLC mode with the existing CTC clock should work at x1
because synchronous mode has no start-bit detection problem — every
clock edge is a data bit, no framing ambiguity. The CTC at 250 kHz
(timer mode, divisor 1) gives 250 kbaud SDLC bidirectional. The SIO
handles SDLC framing (0x7E flags, zero-insertion, CRC-CCITT) in
hardware. The host FTDI receives at matching baud rate. See
`cpnet/SPLIT_CHANNEL_TRANSPORT.md` for the CP/NET transport plan.

MAME fix required: rc702.cpp uses `z80dart_device` but the real
hardware is Z80A-SIO/2 — filed as ravn/mame#3, fixed locally.

### Inter-character gap experiment

Hypothesis: adding idle gaps between characters gives the SIO x1 mode time
to cleanly detect the next start bit. Tested by sending one byte at a time
from Python with busy-wait delays between writes.

Results (4KB, 2 stop bits, SIO auto-RTS, rtscts=True):

| Baud    | Gap    | Errors | vs no-gap | Eff. B/s |
|---------|--------|--------|-----------|----------|
| 83333   | 0µs    | 35 (0.9%) | —      | 2156     |
| 83333   | 200µs  | 18 (0.4%) | 2× better | 1554  |
| 125000  | 0µs    | 81 (2.0%) | —      | 2396     |
| 125000  | 50µs   | 26 (0.6%) | 3× better | 2104  |
| 153600  | 0µs    | 161 (3.9%) | —     | 2491     |
| 153600  | 100µs  | 75 (1.8%) | 2× better | 1873  |
| 250000  | 0µs    | 1375 (33%) | —     | 2672     |
| 250000  | 200µs  | 40 (1.0%) | 34× better | 1554 |

**Finding:** gaps DO reduce x1 errors significantly — confirms the SIO
resync hypothesis. But per-byte USB writes are capped at ~1000–2700 B/s
by USB full-speed frame overhead (~1ms per transaction), making all spaced
results **slower than 38400 x16 continuous** (3840 B/s).

To exploit this, gaps would need to be created at the FTDI wire level, not
via per-byte USB transactions. Possible approaches not yet tested:
- Small chunk writes (4–8 bytes per USB transaction, USB frame gap between)
- FTDI bit-bang mode for precise wire-level timing
- Custom protocol with CRC/retry to tolerate the ~1% residual errors

### Standard PC serial port (16550, 1.8432 MHz) — NOT useful

Cannot produce any rate the RC700 uses above 38400. Even the Nuvoton
NCT6681D high-speed mode (24 MHz) misses: 24M/16/N doesn't hit 153600 etc.

## Bugs Found and Fixed

### Deadlock: list_lpt at cold boot (FIXED)

**Symptom:** machine hung after probe succeeded — no signon, no A>.
**Root cause:** `bios_conout_c` IOB_BAT case called `list_lpt()` which spins
on `while (!prtflg)`. The `prtflg` flag is set by `isr_sio_b_tx`, but
interrupts are disabled during the cold-boot signon banner. Deadlock.
**Fix:** replaced with `siob_conout()` using polled TX (RR0 bit 2 check).

### DDT test program stuck (FIXED in test program)

**Symptom:** baud rate test program's SIO-B exit key not recognized.
**Root cause:** SIO-B RX ISR consumed the byte before the polling loop saw it.
**Fix:** added DI at program start (the test uses polled I/O for everything).

## Future Work

- [ ] Make SIO-B console conditional on a DIP switch (similar to SW1 #7
      mini/maxi), instead of ENQ probe — user request
- [ ] Formalize deploy.sh for two-port mode (console on SIO-B, HEX on SIO-A)
- [ ] Investigate faster inbound data paths: oscillator change, PIO parallel
      port, or synchronous SIO mode with MPSSE host interface
- [ ] FT2232H adapter would NOT help RX speed (x1 mode is the bottleneck,
      not FTDI clock mismatch) — but would enable 250000 baud TX (Z80→host)

## FTDI Adapter Upgrade — Hardware Purchase Notes

### Status: adapter upgrade NOT needed for RX speed

The baud rate investigation conclusively showed that the SIO's x1 async mode
has inherent framing errors at all rates, regardless of FTDI clock accuracy.
An FT2232H (48 MHz) would NOT improve inbound (host→Z80) transfer speed —
38400 x16 is the ceiling due to the SIO, not the FTDI.

An FT2232H WOULD enable 250000 baud TX (Z80→host) with exact clock match
(currently the FT2232D matches 250000 exactly too, so this is already fine).

The current FT2232D adapter is adequate for all practical use cases.

### Standard PC serial port (16550 UART) — NOT useful

1.8432 MHz crystal cannot produce 153600, 307200, or 614400 at any integer
divisor.  Even the Nuvoton NCT6681D high-speed mode (24 MHz) misses: 24M/16/N
doesn't hit any of these rates.  Only matches RC700 at 38400 and below.

### Recommended adapters

**Quick — Danish stock (Proshop.dk):**
Two × StarTech ICUSB2321F (264 kr each, FT232RL, single DB9, in stock,
next-day delivery). One for SIO-A (fast data), one for SIO-B (38400 console).
FT232RL has 48 MHz internal clock — confirmed capable of 307200/614400.
StarTech's "max 115.2 kbps" is conservative marketing; the chip does 3 Mbaud.
https://www.proshop.dk/Netvaerksadapter-netkort-printserver-mv/StarTechcom-1-Port-FTDI-USB-to-Serial-RS232-DB9/2350285

**Cheaper — Amazon.de (2-5 day delivery to DK):**
AYA FT2232H dual DB9 cable (~€20-25). Single USB, two DB9, confirmed FT2232H.
https://www.amazon.de/Serial-RS232-Konverter-Adapter-FT2232H-Linux/dp/B0798HQ6DV

**Avoid:**
- Plexgear/unbranded adapters that don't specify chipset — likely PL2303 or
  CH340 with 12 MHz clock or poor non-standard baud support on Linux.
- Any adapter listing only "FT2232" without the "H" suffix — may be FT2232D
  (12 MHz), same limitation as current adapter.

### Wiring notes

The RC700 has DB-25 RS-232 connectors. Current setup uses a straight DB-9 to
DB-25 cable with a mini null-modem adapter (see `docs/serial_cable_wiring.md`).
New adapter(s) would use the same cable/wiring — only the USB end changes.

SIO-B stays at 38400 (CTC1 count=1, SIO x16) regardless of adapter.
SIO-A speed upgrade requires both the new adapter AND reprogramming CTC0+WR4
to x1 clock mode (done at transfer time, restored after).
