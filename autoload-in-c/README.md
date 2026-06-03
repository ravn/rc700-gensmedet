# RC702 ROA375 autoload PROM in C

Full rewrite of the ROA375 autoload PROM (boot ROM) in C.  The ROM
initializes hardware (PIO/CTC/DMA/CRT/SEM702/FDC), auto-detects floppy
disk format, reads Track 0, and boots either the floppy CP/M BIOS or
the cpnos-in-c PROM1 line program.

**Production compiler is clang (llvm-z80).**  SDCC + z88dk is kept as a
parity / parked path; the production binary always ships from clang.

See `BOOT_SEQUENCE.md` for the full invocation order from power-on to
`A>`.  See `ZSDCC_NOTES.md` for SDCC/z88dk quirks (relevant only to the
parity path).  See `docs/production-verification.md` for the canonical
oracle commands + expected screenshots.

## Current status

PROM size: **1658 / 2048 B (390 B free, 19 % headroom)** under clang
with ZX0 compression — comfortably below the hardware-fixed 2 KB cap
(user's RC702 has 2716 sockets, no A11 bridge for 2732).

Two production boot paths verified:

| Path | What it boots | Oracle |
|------|---------------|--------|
| Floppy CP/M | DRI rel.2.3 BIOS on the in-tree `test-disks/SW1711-I8.imd` → `A>` | `make floppy-boot-test` |
| cpnos slave | cpnos-in-c PROM1 line program → CP/NET via MP/M master | `cd ../cpnos-in-c && make cpnos-polypascal-test` |

The autoload banner also displays the SW1 status on its own dispatch
buffer (0x7A00), then the chosen BIOS takes over the canonical RC702
display at 0xF800.  Boot path canonical screenshot:
`snap/autoload_sw1711_boot.png` (2026-06-03).

## PROM size history

```
Date        Size  Change  Description
----------  ----  ------  -----------
2026-03-20  2055          Starting point (pure C rewrite, SDCC)
2026-03-21  1843    -212  Multi-step SDCC shrink (peepholes, dead vars,
                          inlining, BOOT-pad reuse, format-table fold)
2026-04..   1995          clang first build (no ZX0; +152 vs SDCC)
2026-05..   1658    -337  clang + ZX0 compression on text section
                          (production path)
                  ------
                          Net vs starting point: −397 B (−19.3 %)
```

Key SDCC-era techniques captured in this codebase (still useful as
reference): dead-variable removal, DMA Ch3 removal, manual inlining,
BOOT-section pad reuse, 22 custom peephole rules, tail-call
fall-through, split packed bitfields, combined format tables.

clang inherits all of the above structurally and adds **ZX0 text
compression** (the 337 B saving from 2026-05) — text gets streamed
through `dzx0_standard` at boot time before relocation.

## PROM image layout (prom0.ic66 → roa375.ic66)

```
Offset  Size   Section          Contents
------  ----   ---------------  ----------------------------------------
0x0000  ~50    .boot            begin(): DI, SP, ZX0 unpack, JP into CODE
0x0050  ~12    .boot            banner_string (clang-side; SDCC banner lives in CODE)
0x005C  ~10    .boot            0xFF pad
0x0066  ~2     .nmi             RETN at the Z80 NMI vector
0x0068  ~70    .zx0_decoder     dzx0_standard decompressor (clang only)
0x00AE  ~1.5K  .text_compressed ZX0-compressed payload:
                                  IVT (intvec.c), HAL, init (PIO/CTC/DMA/
                                  CRT/SEM702/FDC), boot, ISRs, format
                                  tables, banner_string (SDCC), sentinel
0x067F  pad    —                0xFF fill to 4096 B for roa375.ic66 slot
```

The high 2 KB of the 4 KB roa375.ic66 file is unused (0xFF) on the
user's RC702 — there's no A11 bridge, so the chip is electrically only
the low 2 KB.

## Runtime memory map (after self-relocation)

`begin()` unpacks the ZX0-compressed payload to RAM at 0x7000.  BSS
variables are inside the payload and start zeroed.  After
`prom_disable()` (port 0x18), Track 0 is loaded at 0x0000 and ROM is
no longer accessible.

```
Address         Size   Contents
--------------  -----  -----------------------------------------------
0x0000-0x0CFF   3328   Track 0 data (loaded after PROM disabled)
0x7000-0x701F     32   IVT: interrupt vector table (I=0x70, Z80 IM2)
0x7020-0x76xx  ~1740   C code: boot logic, FDC driver, ISRs, init
                        Read-only data: messages, format tables
                        BSS: boot state variables
                        code_end sentinel
0x7800-0x7F97   1960   Display memory (80×25, Intel 8275 CRT via DMA)
0xBFFF                 Stack top (grows down)
```

## Source files

| File | Section | Description |
|------|---------|-------------|
| `sections.asm` | — | Section ORGs and ordering (linker scaffolding) |
| `boot_rom.c` | BOOT | begin(), banner_string, NMI handler |
| `intvec.c` | CODE | IVT: const function-pointer array |
| `rom.c` | CODE | All CODE-section C: HAL, init, FDC, format, boot, ISRs, SEM702 chargen init |
| `rom.h` | — | Types, constants, port I/O macros, struct defs, declarations |
| `clang/banner.h` | — | Build-stamp header, auto-regenerated each build (clang) |
| `peephole.def` | — | 22 custom SDCC peephole optimization rules (parity path) |
| `clang/dzx0_standard.s` | — | ZX0 decompressor (clang path only) |

## Key design decisions

- **Unity build**: `rom.c` is the single CODE translation unit, enabling
  cross-function optimization, tail-call fall-through, and dead code
  elimination.  `intvec.c` is compiled separately so its
  `#pragma constseg CODE` doesn't propagate.

- **BOOT section padding**: Banner string + ZX0 entry occupy what would
  otherwise be 0xFF gap between `begin()` and the Z80 NMI vector at
  0x0066.

- **SEM702 chargen init runs always**: `rom.c::define_sextants()`
  programs the 64 sextant glyphs into RAM-backed character generator
  ports 0xD1/0xD2/0xD3.  Real ROA327-equipped hardware silently ignores
  these writes (no IC82 RAM to address), so this is a safe no-op on
  baseline machines; no SW1 gating.

- **FDC command + result blocks** are typed structs (`fdc_command_block`,
  `fdc_result_block`) so the 7-byte sequences are contiguous + named
  rather than magic array indices.

- **BSS inside CODE / payload**: BSS lives in the compressed payload.
  The ROM contains zero bytes there; `begin()` unpacks them to RAM, so
  variables start zeroed without explicit init.

- **No recursion**: All ~30 functions form a pure DAG.  File-scope
  globals are safe.  No stack frames needed
  (`--fomit-frame-pointer` on the SDCC path).

- **Banner regeneration**: `clang/banner.h` is rebuilt every `make prom`
  (via the `FORCE` dep), matching `rcbios-in-c/builddate.h`.  A cmp
  dance skips touching the file when neither the date nor git hash
  changed.

- **No A11 bridge → 2 KB hard cap**: build fails the size check above
  2048 B (clang) / 4096 B (SDCC parity path; MAME-only).

## Building

```bash
make                 # build + install prom0.ic66 to MAME (clang)
make prom            # just the build (clang default)
make floppy-boot-test  # end-to-end: autoload + DRI rel.2.3 floppy -> A>
make mame            # boot test with autoload banner check
make sw1-test        # verify SW1 status appears on row 0
make fdc-log         # capture + decode µPD765 transactions during boot
make rc700           # build + launch jbox rc700 emulator
make clean           # remove build artifacts

# SDCC parity path (Docker required; production is clang)
make COMPILER=sdcc prom
```

## Dependencies

- **clang (production)**: native llvm-z80 toolchain at
  `../../llvm-z80/build-macos/bin/` (`make toolchain` in workspace
  root).
- **MAME**: ravn/mame fork submodule at `../../mame/`; rc702 driver.
- **SDCC parity (optional)**: Docker + `z88dk:2.4` image.
