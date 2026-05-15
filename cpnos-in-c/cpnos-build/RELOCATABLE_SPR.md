# Relocatable CP/NOS monolith — design note

## Problem

Moving `BIOS_BASE` (the address of cpnos-rom's BIOS jump table) is currently
painful because `cpnos-build/d/cpnos.com` is statically linked with fixed
addresses baked into every module: data at 0xCC00, code at 0xD000, and
cross-boundary references into cpnos-rom's resident BIOS JT resolved at
LINK time (currently `BIOS_BASE = 0xED00`).

Any change to `BIOS_BASE` requires re-linking `cpnos.com` in lockstep with
cpnos-rom and refreshing every disk image that carries `cpnos.com`.  This
couples two otherwise-independent codebases at address level, and makes
experimentation with the memory map expensive.

Phase 1/2A/2B (April 2026) cut down the cross-boundary surface:
ABI shims migrated from cpbios.asm into `cpnos-rom/resident.c`, the
cpnos.asm entry stub was eliminated, and PROM-side references *into*
cpnos.com (BDOS dispatch entry) are now generated from `cpnos.sym` via
`clang/cpnos_addrs.h`.  The remaining baked direction is cpnos.com's
references *into* cpnos-rom's BIOS JT.

## Observation

The DRI `.SPR` ("Self-Relocating Program") format used by stock `CCP.SPR` /
`NDOS.SPR` is designed exactly for this case.  Its format:

```
[0..128)              parameter sector: hdr[1..2]=code_len LE,
                                        hdr[4..5]=data_len LE
[128..256)            ignored sector (DRI quirk — always zero in practice)
[256..256+code_len)   code image linked at virtual origin 0x0000
[..)                  data_len bytes (no relocation applied)
[..)                  code_len/8 bytes relocation bitmap, MSB-first:
                        bit (7-(i&7)) of bitmap[i>>3] flags code byte i
                        as the high-half of an absolute 16-bit address
                        needing a +base_page adjustment
```

`netboot_server.py:spr_relocate` implements the loader side: apply the
bitmap to produce an image that runs at a caller-chosen page-aligned base.

We've never used this machinery for our own monolith.  We've been
generating a flat binary via `objcopy -O binary` and loading it at the
baked-in addresses.

## Generalization path

### (1) Build cpnos-build as an SPR

Replace the current ELF→flat conversion with ELF→SPR:

1. Link cpnos-build's modules at virtual origin 0 (no baked-in absolute
   addresses for intra-module calls).  `ld.lld --emit-relocs` already writes
   every `R_Z80_16` into the ELF — we just aren't consuming it.
2. Add a small Python post-processor (~80 lines): read the ELF's
   `.rela.text`, walk every `R_Z80_16` relocation, set the corresponding
   bit in a bitmap.  Emit the DRI SPR layout above.
3. cpnos-rom's `netboot_mpm.c` applies inbound SPR relocation at load time
   using the existing `spr_relocate` logic (from `netboot_server.py`,
   ported to Z80).  Entry address becomes `load_base + code_offset`.

This decouples cpnos-build's address layout from cpnos-rom's.  Any
future memory-map move is one symbol in cpnos-rom; the monolith doesn't
need re-linking.

### Snag: cross-boundary references

`cpndos.asm` and `cpbdos.asm` reference cpnos-rom's resident BIOS JT at
`BIOS_BASE` (currently 0xED00) — DRI LINK resolves these at link time
against the EQU exposed by a small shim like `cpnios-shim.asm` does for
NIOS.  Those addresses are **outside** the monolith.  SPR relocation
can't help because its bitmap only describes *intra-monolith* addresses.
The external references stay baked.

Three ways to resolve:

#### (a) Single-variable patching — MINIMUM VIABLE

Introduce one 2-byte variable in the monolith, say `BIOS_JT_BASE`,
written once by the loader.  Replace each direct `JP BIOS+N` call site
with an indirect-through-`BIOS_JT_BASE` sequence.

Trivially simple; trivially fixed.  Adds a handful of bytes per BIOS
call site in indirection overhead.

#### (b) Move BIOS into the monolith — CLEANEST LONG-TERM

Absorb the RC702 hardware code (`impl_conout`, `impl_conin`, CRT scroll,
SIO polling, keyboard ring, ISR) from cpnos-rom's `resident.c` into a
new `cpbios_rc702.c` linked into the monolith.  cpnos-rom's role
shrinks to: PROM bootstrap + transport layer + netboot_mpm.  Monolith
owns every RC702 port.

- No cross-boundary calls at all — the whole BIOS is inside the monolith.
- cpnos-rom's `.resident` region shrinks dramatically; RAM map gets simpler.
- Biggest short-term lift: rewrites hardware-facing code in a different
  build environment.  May need new build-system glue between the C and
  asm toolchains in cpnos-build.

#### (c) Explicit external-reference table

Post-processor emits a side table of "patch here with symbol X" entries.
`netboot_mpm.c` walks the table after relocation, looking up each symbol
in cpnos-rom's export table.

More general than (a), less invasive than (b).  But we only have one such
external: the BIOS JT base.  Building a general mechanism for a one-entry
table is over-engineering.

## Recommendation

**(a)**.  One variable, one patch, decouples the two builds at address
level without restructuring either.

Work estimate, focused session: 1 day.
- 1-2 hours: ELF→SPR post-processor in Python
- 1-2 hours: rewrite BIOS call sites against `BIOS_JT_BASE`
- 2 hours: inbound relocation in Z80 inside `netboot_mpm.c` (or have the
  Python server pre-relocate before sending — skips the Z80 work entirely)
- rest: testing + fix-up

## Parked until needed

Current workflow (baked addresses + `grep -n 0xF200`) is painful but
viable for occasional moves.  Generalization pays off when we start
experimenting with memory map variants — e.g., a PCB530 real-hardware
build with 2 KB PROMs, or an RC703 variant with different BIOS space.

## References

- `cpnet-z80/dist/doc/` — DRI CP/NET 1.2 documentation (if present)
- `cpnos-rom/netboot_server.py:spr_relocate` — reference SPR loader
- `cpnos-rom/cpnos-build/` — current statically-linked monolith build
- `cpnos-rom/cpnos-build/src/cpnios-shim.asm` — example of the `EXTRN`-via-shim
  pattern that BIOS_JT_BASE would follow
- `cpnos-rom/cpnos_rom.ld` — cpnos-rom linker script with the fixed
  `_bios_boot == 0xED00` ASSERT

## History

Written 2026-04-22 during cpnos-rom session 33 follow-up.  Originated
from a user question: "CP/NET binaries are relocatable; you baked them
together — can this be generalized?"  Answer: yes, and here's how.
