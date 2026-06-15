# Session 18: Serial Speed Limits, SDLC Transport, J8 Bus (2026-04-18)

## Goal

Fastest possible CP/NET block transfers on unmodified RC702 hardware.

## Key Findings

### 1. No split TX/RX baud rates

CTC channel 0 drives a single wire to both TxCA and RxCA on the SIO.
All four CTC channels allocated (ch0=SIO-A, ch1=SIO-B, ch2=CRT, ch3=FDC).
MAME's rc702.cpp wiring is correct. The 250 kbaud TX / 38400 RX asymmetry
from session 17 is a SIO receiver limitation at the same clock rate, not
a split-speed configuration.

### 2. Z80-SIO/2 has NO DPLL or BRG

The initial plan was HDLC over NRZI with the SIO's "built-in DPLL."
This was wrong -- the DPLL (WR14) and BRG (WR12/WR13) are features of
the Z85C30 SCC, a completely different chip. The Z80-SIO only has
WR0-WR7. "SIO/2" means bonding option 2 (sacrifices SYNCB for DTRB),
not a feature upgrade. Verified from Zilog um0081.pdf.

### 3. SDLC with CTC clock -- the viable fast path

The SIO supports SDLC/HDLC framing in hardware (0x7E flags, zero-
insertion, CRC-CCITT). In sync mode, x1 clock should work because
there are no start bits -- every clock edge is a data bit. The async
x1 framing problem (can't re-sync to start bits) does not apply.

**250 kbaud SDLC** is achievable with CTC timer mode (4 MHz / 16 = 250 kHz,
divisor 1). The current FT2232C/D adapter matches 250000 exactly.
Effective throughput after SDLC overhead (~10%): **~28 KB/s, 7x current**.

614.4 kbaud needs an FT2232H adapter (current FT2232C/D has 2.34% error).

### 4. DMA channel assignments corrected

From the technical manual (section 2.3.9, page 32):
- Ch 0: External / J8 expansion (not "WD1000" as previously documented)
- Ch 1: Floppy disk controller
- Ch 2: Display controller (8275)
- Ch 3: Display controller (8275, second channel -- NOT free)

### 5. J8 bus expansion -- fastest path (future)

DMA channel 0 via J8: DREQ0 on J8 pin R28, DACK0 back to J8. The
MEM700 RAM disk is an existence proof. A USB-to-Z80-bus bridge on J8
would give ~500-1000 KB/s with DMA or ~150-286 KB/s with polled I/O.
No PCB modification needed (external board on J8 connector).

### 6. MAME uses wrong device type

rc702.cpp used `z80dart_device` but hardware is Z80A-SIO/2. Fixed
locally to `z80sio_device`. Filed as ravn/mame#3. The DART variant
rejects sync mode programming, blocking SDLC testing in MAME.

## Speed Comparison

| Method | Throughput | vs current | PCB mod? |
|--------|-----------|------------|----------|
| Async 38400 (current) | 3.8 KB/s | 1x | No |
| SDLC 250 kbaud | ~28 KB/s | 7x | No |
| SDLC 614.4 kbaud | ~69 KB/s | 18x | No (needs FT2232H) |
| PIO parallel (polled) | ~150 KB/s | 40x | No |
| J8 polled I/O | ~190 KB/s | 50x | No (external board) |
| J8 DMA channel 0 | ~500-1000 KB/s | 130-260x | No (external board) |

## Pre-requisites Before Implementation

### Verify SIO chip on physical hardware

Before writing any SDLC code, visually inspect the SIO chip on the RC702
motherboard and confirm the exact part number. Expected: Z8442 (Z80A-SIO/2).
Other possibilities:
- **Z8470 (Z80-DART):** async only, no SDLC support. Would kill the plan.
- **Z8440 (SIO/0):** full support, TxCB+RxCB bonded on channel B.
- **Z8441 (SIO/1):** full support, no DTRB (has SYNCB instead).
- **Z8442 (SIO/2):** full support, no SYNCB (has DTRB). Expected.

**CONFIRMED (2026-04-18):** Physical inspection shows **Z8442AB1**.
This is a Z80A-SIO/2 — SDLC plan is valid.

Other chips confirmed: CPU = Z8400A P5 (Z80A), PIO = 8420Y (Z80-PIO),
DMA = P8237-5 (Intel 8237A-5, 5 MHz), DRAM ctrl = Intel D8202A.

## Implementation Plan (approved)

**Phase 1:** Validate SDLC mode on SIO-B at 250 kbaud (safe channel).
Write Z80 test program + host-side receiver. Measure error rates.

**Phase 2:** SDLC transport for CP/NET on SIO-A (dedicated channel).
Each CP/NET message = one SDLC I-frame. SIO CRC replaces DRI checksum.

**Phase 3:** PIO parallel port (independent track, additive throughput).

## Files Modified This Session

- `RC702_HARDWARE_TECHNICAL_REFERENCE.md` -- CTC/SIO wiring, DMA
  channels corrected, SIO/2 chip details added, sync mode analysis
- `docs/j8_bus_expansion.md` -- new: J8 signals, DMA, speed analysis
- `rcbios-in-c/tasks/session17-siob-console.md` -- DPLL correction,
  split TX/RX, revised SDLC approach
- `rcbios-in-c/tasks/sio-independent-rates.md` -- marked RESOLVED
- `cpnet/SPLIT_CHANNEL_TRANSPORT.md` -- open questions resolved,
  HDLC/NRZI section replaced with SDLC+CTC approach, FTDI baud table
- `tasks/prompts.md` -- session 18 prompts
- MAME `rc702.cpp` -- z80dart_device -> z80sio_device (ravn/mame#3)

## Constraints

- No RC702 PCB modifications (cables and external devices OK)
- Current adapter: FT2232C/D (12 MHz, exact at 250 kbaud)
- User willing to buy FT2232H adapter if needed for 614.4 kbaud
- SIO-A acceptable as dedicated CP/NET channel
- Focus: fastest CP/NET block transfers on current hardware
