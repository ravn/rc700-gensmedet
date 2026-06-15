# Session 10 Summary (2026-04-04)

## Goals

1. Investigate Clang vs SDCC BIOS gap analysis
2. Investigate 26-line CRT display from ravn/rc702-bios
3. Transfer BIOS to physical RC700 via serial

## Completed

### 26-line CRT display investigation

Analyzed the ravn/rc702-bios assembly BIOS to understand how it
achieves 26 lines on the Intel 8275 CRT controller:

- **CRT26 mechanism**: `SUB 0x3F` on 8275 PAR2 (0x98→0x59) reduces
  vertical retrace by 1 row and adds 1 display row simultaneously
- **Status line**: 26th row at 0xFFA0 shows clock (DD/MM HH:MM),
  driven by callback system (STATL.MAC), keyboard menu (KEYINT.MAC)
- **DMA split approach**: Instead of contiguous display memory, use
  ch2 (2000B from DSPSTR) + ch3 (80B from BSS buffer) to feed the
  8275. Confirmed by datasheet: 8275 has single DRQ, ch2/ch3 split
  works via Am9517A priority arbitration.

### Intel 8275 datasheet transcription

Downloaded and transcribed the full 24-page 1984 Intel 8275 datasheet
via Docker poppler (minidocks/poppler). Key findings documented:

- Reset command: 4 parameter bytes defining screen geometry
- PAR2: bits 7:6 = VRTC row count, bits 5:0 = rows/frame - 1
- Single DRQ output — not separate character/attribute DMA channels
- Special codes: End of Row, End of Screen, Stop DMA variants
- Field attributes embedded in character stream (MSB=1), not via DMA
- Transparent vs non-transparent mode is global (PAR4 bit F)

### kox.pas transcription

Transcribed a Turbo Pascal CRT display breaker program from a
photograph of the RC700 screen. The restore block reveals the machine
used 13 lines/char (PAR4=0xCD) — taller than any standard BIOS variant.

### MAME 8275 compatibility

Confirmed MAME's 8275 emulation already supports dynamic row count
changes — `recompute_parameters()` calls `screen().configure()` with
computed dimensions. The RC702 driver's initial `set_size(544, 232)`
is large enough for 26 rows (208 pixels). Should work without driver
modifications.

### Serial transfer to physical RC700

- Identified FTDI dual-port on `/dev/cu.usbserial-FT4SXZNY1`
- Established communication at 19200 baud via `screen`
- Generated `cpm56.hex` with CCP+BDOS+BIOS and split checksum
  validator (skips gap between side 0 and side 1)
- Split hex file into 4 parts under 14KB each (CP/M extent size limit)
- Successfully wrote BIOS to disk on the physical RC700
- Checksum validator failed due to gap issue — fixed in mk_cpm56.py

### Serial flow control problem

Buffer overruns during PIP serial transfer caused by incorrect cable
wiring. The RC700 SIO-A uses Auto Enables (CTS gates TX, DCD gates RX).
The current cable (9-25 with mini adapter) maps RC700 RTS to FTDI
DCD+DSR but connects FTDI CTS to ground — no hardware flow control.

Documented proper cable wiring and identified `pyftdi` DSR-based flow
control as a solution (RC700 RTS → FTDI DSR, use DSR/DTR handshaking
in libftdi). Requires Linux machine with pyftdi for implementation.

## Files created/modified

### New files
- `rcbios-in-c/tasks/26-line-status.md` — Full plan with DMA split approach
- `rcbios-in-c/docs/intel_8275_datasheet.md` — 8275 datasheet transcription
- `rcbios-in-c/docs/kox_pas_crt_explorer.md` — Pascal CRT breaker program
- `rcbios-in-c/docs/serial_cable_wiring.md` — FTDI ↔ RC700 cable pinout
- `rcbios-in-c/tasks/session10-summary.md` — This file

### Modified files
- `rcbios-in-c/mk_cpm56.py` — Split checksum (skip gap), validator in hex
- `tasks/prompts.md` — Session 10 prompts recorded

### Generated artifacts (not committed)
- `clang/cpm56.hex` — Full CCP+BDOS+BIOS hex file (641 records)
- `clang/cpm56_{1-4}.hex` — Split hex files under 14KB each
- `clang/cpm56.com` — Patched CPM56.COM with new BIOS + validator
- `clang/sysgen_bios.hex` — BIOS-only hex file for SYSGEN

## Open problems

1. **Serial flow control**: Need pyftdi DSR-based flow control on Linux
   to prevent buffer overruns. Current cable cannot be modified.

2. **Checksum validator untested with fix**: The split checksum
   (skipping gap) has not been verified on the physical RC700.

3. **BIOS gap analysis deferred**: Clang vs SDCC BIOS size comparison
   was started but interrupted by the 26-line investigation. Current
   gap: Clang 5635B vs SDCC 5558B (+77B, +1.4%). Function-level nm
   data collected but not analyzed.

4. **26-line implementation not started**: Plan complete, needs coding.

5. **Light pen**: Not available on RC702 hardware (LPEN not wired).
