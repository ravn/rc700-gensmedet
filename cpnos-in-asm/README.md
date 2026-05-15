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
What we reconfigure once autoload hands over:

  - **Display moves from 0x7A00 to 0xF800.**  Autoload places its
    framebuffer at `DSPSTR_ADDR=0x7A00` (its own ROM is hard-wired
    there — we cannot move it, or the floppy-boot path would break).
    After handoff we disable CTC ch2's interrupt (autoload's VRTC ISR
    keeps re-pointing DMA at 0x7A00) and reprogram DMA ch2 to autoinit
    mode pointing at 0xF800.  TPA from 0x7A00 upward is then free for
    cpnos.com / NDOS / programs, and the display lives at the
    CP/M-canonical location.
  - **SIO + CTC ch1.**  Autoload does not program SIO during cold
    boot, so we run a port table that does the CTC ch1 (SIO-B baud)
    and SIO-B WR0..WR5 sequence cpnos-in-c uses.

### Code lives in PROM1 — no payload relocation

cpnos-in-c copies its "payload" out of PROM into RAM at 0xED00 because
clang's resident code is position-dependent and BSS has to live in
RAM.  cpnos-in-asm does NOT replicate that scheme: the slave executes
in place from PROM1.  Even the cold-init port-table walk that runs
exactly once stays in PROM1 — there's no value in copying it to RAM
just to throw the bytes away, and the saved 2 KB of TPA space below
matters more.

Concretely:

  - All code (init, transport, NDOS dispatch) runs from PROM1
    addresses 0x2000..0x27FF.
  - State that needs to be written (ring buffers, slave-side NDOS
    flags) lives in RAM somewhere below 0x7A00, allocated by `equ` /
    `org` directives in prom1.asm rather than by a payload-header
    relocation step.
  - No payload header, no relocator stage, no `--defsym` plumbing.

The cpnos-in-c "payload" model exists because the C compiler forces
it; the asm slave is free of that constraint and uses it.

### Size policy: make it work first, then make it fit

The hard target is **resident <= 2048 bytes** so the binary lives
entirely in the physical PROM1 socket (2 KB EPROM).  During phase
development that target is treated as a SOFT limit: it's OK to
exceed 2048 B while bringing up a new feature, and shrink-work
follows once the feature is correct.

The build wires this in:

  - `make cpnos` WARNS over 2048 B and continues, padding prom1.bin
    up to the next 2 KB boundary (max 4 KB).  cpnos.bin is then
    stitched as (2 KB autoload PROM0) + (2 KB or 4 KB prom1.bin).
  - Hard fail at 4096 B for prom1.bin (the cpnos.bin file-format
    limit when over-sized PROM1 is doubled to 4 KB).
  - autoload-in-c's `make prom` follows the same rule (warn > 2048,
    fail > 4096).

The warning line includes the byte overrun so the shrink job is
quantified: e.g. "exceeds 2048 B PROM1 socket by 312 B" means we
need to recover 312 B before burning.

This relaxes the previous hard fail at 2048 B.  Burning a real
EPROM still requires the binary to fit in the socket; the warn-only
build is for MAME-side iteration.

### PROM1 must be disabled before any TPA program runs

PROM1 occupies 0x2000..0x27FF, which is **inside the CP/M TPA**
(0x0100 .. NDOS - 1).  Any .COM larger than ~7.9 KB will load into
the PROM1 range and either be shadowed (the bytes go to underlying
RAM but reads return PROM bytes) or fail outright -- nothing in TPA
above 0x2000 works while PROM1 is mapped.

The PROM disable is the same port for both EPROMs:

  OUT (0x18), A   ; RAMEN: disable PROM0 and PROM1 simultaneously,
                  ; exposing the RAM underneath at 0x0000..0x0FFF
                  ; and 0x2000..0x27FF.

Two consequences for the asm slave:

  - **Defer the disable until absolutely necessary.**  As long as no
    TPA program is running, PROM1 can stay enabled and the slave
    keeps executing from 0x2000..0x27FF.  Phase 2a/2b code runs
    happily with PROM1 mapped, and the netboot fetch of cpnos.com
    targets the NDOS region (around 0xDE80..0xE9FF), well above
    PROM1.  Only the moment a user .COM is about to load into TPA
    does the disable have to happen.
  - **The disabler instruction must live in RAM.**  The OUT to
    port 0x18 takes effect immediately; if the next fetch happens
    from 0x2000..0x27FF it picks up whatever RAM is there, not our
    PROM1 code.  A small "tail" stub copied to a known RAM address
    will run the OUT and then `JP` to NDOS COLDST (or wherever
    control needs to go next).  Same trick autoload-in-c uses for
    its own PROM disable at 0x7000.

These details are deferred work for phase 4 (NDOS dispatch) or
later -- nothing in phases 1..2b touches the TPA.

**TODO when phase 4 lands:** later RC703 models had a more advanced
PROM enable/disable scheme than the RC702 single-port RAMEN
mechanism described above.  Before settling on the disabler-stub
implementation, audit `../rc703-div-bios-typer/` (the original RC703
BIOS sources extracted from disk) for the actual hardware contract
on those later boards and make sure the asm slave's disable path
works on both RC702 and RC703 hardware.  Track in task #55.

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
   - **2b (CODE DONE, integration test deferred):** SIO-B receive
     and echo.  Polled RX -> TX loop after the banner stream.  Full
     byte-injection test waits on a socket-backed `null_modem`
     harness.

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

- **Linker script**: lld may not work well with zmac output.  May
  need a thin lld-compatible variant of `payload.ld` or a different
  link strategy (zmac's `LIBR`/`LINK` directives).

- **SDCC parity**: cpnos-in-c maintains SDCC dual-compile as the
  parity oracle.  Asm version compares directly against zsdcc-built
  cpnos-in-c bytes if we want a regression baseline, but the design
  is to track DRI's reference NDOS implementation (`testutil/acid/`).

## Resolved design questions

- **Init code placement (2026-05-15):** stays in PROM1, runs
  in-place.  No payload relocation -- see "Code lives in PROM1"
  above.  Settles the earlier open question about whether to share
  an init blob with autoload-in-c.

## See also

- Parent project's CLAUDE.md goal: "fix llvm-z80 codegen until CP/NOS
  fits in PROM 1 (2 KB)" — cpnos-in-asm is the asm-side complement
  to that compiler-side push.
- `../cpnos-in-c/README.md` — sibling C variant
- `../cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md` — protocol spec
  (authoritative; both variants conform)
