# cpnos-in-asm — pure Z80 assembly CP/NOS slave

**Status: phase 2a alive — boots through autoload-in-c, satisfies the
PROM1 " RC702" signature, stamps banner to CRT (DSPSTR_ADDR=0x7A00)
and streams it on SIO-B.  Phase 2b+ pending.**

## Architecture

PROM0 socket holds `../autoload-in-c/clang/prom0.ic66` (the production
autoload).  PROM1 socket holds `cpnos-in-asm/build/prom1.bin` (this
project).  autoload programs all hardware (DMA, 8275 CRT, CTC, PIO),
tries floppy boot, fails, then calls `prom1_if_present()`:

  1. Reads `" RC702"` at PROM1 offset 0x0002 to authenticate.
  2. Jumps via `*(word *)0x2000` (the jump-target stored at PROM1 byte 0).

`prom1.asm` lays out the contract bytes in `prom1_header` then runs.
SIO is the only hardware we (re)init — autoload does not program it
during cold boot.

## Goal

Implement a CP/NOS slave in pure Z80 assembly that fits in **PROM1
(2 KB)** with the autoload PROM occupying PROM0 (also 2 KB) jumping
to it at cold boot.  Same wire-protocol contract as
[cpnos-in-c/](../cpnos-in-c/) (see [CPNET wire protocol spec](../cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md)).

## Why split out from cpnos-in-c?

The C version (2003 B clang resident as of session 73b/c) is a moving
target driven by compiler improvements.  It serves as a testbed:
every clang/llvm-z80 byte saving on this code shape lands first as a
size delta on `cpnos-in-c/`, and the binary is read against
SDCC parity for behavior.

The asm version has a fixed target:
- **Resident <= 2048 B** so it lives entirely in PROM1
- No payload-relocation step at cold boot (asm targets PROM1 directly)
- Same MAME test harness, same 4-cell polypascal-test value oracle
- Same wire protocol contract (`cpnos-shared/include/payload_header.h`,
  `CPNET_WIRE_PROTOCOL.md`)

Both variants ship to the same end users.  The asm version is the
production fallback when the C version doesn't fit a particular
constrained environment.

## What it shares with cpnos-in-c

Everything in `../cpnos-shared/`:

- `include/payload_header.h`, `include/cfgtbl.h` — binary contracts
  (loaded by asm via `INCBIN`-style include with byte-offset constants)
- `ld/payload.ld`, `ld/cpnos_rom.ld` — link scripts (may need an
  asm-specific variant if zmac/sjasm doesn't speak the lld syntax)
- `docs/CPNET_WIRE_PROTOCOL.md`, `docs/MEMORY_MAP.md`,
  `docs/PORT_OUTPUTS.md` — the protocol and hardware specs
- `mame/polypascal_test.lua` — the value oracle (must PASS post-asm-bring-up)
- `scripts/pad_rom.py`, `scripts/build_prom_image.py` — image stitching
- `testutil/` — DRI CP/M tools, smoke-injection utilities
- `e_drive_seed/` — test data for polypascal-test

## Bring-up plan

1. **Stub slave that boots in MAME** — DONE (phase 1, session 73e).
   First cut had its own minimal PROM0 (`src/prom0.asm`, deleted in
   phase 2a) doing DMA+CRT init then `JP 0x2000`.  See
   `snap/cpnos_asm_phase1.png` for the historical screenshot.

2. **Transport echo** — IN PROGRESS.
   - **2a (DONE):** SIO-B transmit.  After autoload jumps to us, init
     CTC ch1 + SIO-B, then stream banner via polled-TX.  Verified by
     `make cpnos-siob-test`.
   - **2b:** SIO-B receive (poll, echo bytes back).  Needed for any
     duplex test.

2. **Transport echo** — read a byte from PIO-A/B (or SIO depending
   on TRANSPORT), echo it back.  Pre-CP/NET-frame work.

3. **CP/NET frame parser** — minimal SNDMSG/RCVMSG state machine
   parsing the 7-byte CP/NET header + payload.  Echo received
   frames back to the host.

4. **NDOS dispatch** — implement BDOS function 105 (NDOS call entry)
   that hands off requested operations to the master.

5. **Full NDOS** — all 50 CP/NOS functions per the DRI spec.

6. **PROM1 fit verification** — must be <= 2048 bytes resident.

## Toolchain

- **Assembler**: `zmac` (already in `../../zmac/`, built from source)
- **Linker**: zmac's built-in linker, OR an external `lld`-format
  linker script (TBD during bring-up)
- **Build script**: this directory's `Makefile`, structurally
  parallel to `cpnos-in-c/Makefile` (will share boilerplate with
  cpnos-shared/common.mk once that's extracted in a follow-up commit)

## Open design questions

- **Init code**: cpnos-in-c has rich cold-init (clear screen, init
  CTC/PIO/SIO, set up IVT).  Can the asm variant share a generated
  init blob from autoload-in-c, or does it need its own?  Probably
  needs its own — the resident slave runs WITHOUT autoload's init
  helper (PROM disable happens before payload runs).

- **Linker script**: lld may not work well with zmac output.  May
  need a thin lld-compatible variant of `payload.ld` or a different
  link strategy (zmac's `LIBR`/`LINK` directives).

- **SDCC parity**: cpnos-in-c maintains SDCC dual-compile as the
  parity oracle.  Asm version compares directly against zsdcc-built
  cpnos-in-c bytes if we want a regression baseline, but the design
  is to track DRI's reference NDOS implementation (`testutil/acid/`).

## See also

- Parent project's CLAUDE.md goal: "fix llvm-z80 codegen until CP/NOS
  fits in PROM 1 (2 KB)" — cpnos-in-asm is the asm-side complement
  to that compiler-side push.
- `../cpnos-in-c/README.md` — sibling C variant
- `../cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md` — protocol spec
  (authoritative; both variants conform)
