# SEM702 Font Compression Options

The full SEM702 font is 128 characters × 16 dot lines × 1 byte = 2048 bytes.
This won't fit in the PROM alongside the boot code (currently 1829 bytes)
within the 2KB limit. With the 4KB solder bridge closed, compressed font
data could be embedded directly in the PROM, eliminating the need for a
separate font ROM in the PROM1 socket.

## Compression approaches

### 1. Skip unused scan lines (31% savings)

The 8275 is configured for 11 lines per character (PAR3), so lines 11–15
are always zero. Store only 11 bytes per character.

- **Size:** 128 × 11 = 1408 bytes
- **Decompressor:** trivial — write 11 stored bytes, then 5 zeros per char
- **Complexity:** minimal

### 2. Skip blank characters (additional ~20%)

Control characters 0–31 and DEL (127) are typically all-zero. Store a
128-bit presence bitmap (16 bytes) indicating which characters have data.

- **Size:** ~96 chars × 11 bytes + 16 byte bitmap = ~1072 bytes
- **Decompressor:** check bitmap bit, write 11 stored bytes or 11 zeros
- **Complexity:** low

### 3. Per-line presence bitmask (best general compression)

For each character, store a 16-bit (or 11-bit) mask of which lines are
non-zero, followed by only the non-zero data bytes.

- **Size:** ~96 chars × (2 byte mask + ~8 data bytes) = ~960 bytes
- **Decompressor:** for each char, read mask, write data or zero per bit
- **Complexity:** moderate

### 4. Column trimming (diminishing returns)

Most characters are 5–7 pixels wide. Store per-character left-shift and
width, pack only the active columns. Significant complexity for ~15% gain.

- **Not recommended** — complicates the bit-reversal logic and the
  decompressor needs shift operations per line.

## Status (2026-05-17): obsoleted by `define_sextants()` + 2 KB hard limit

This document was written under two assumptions that no longer hold for
the current target hardware:

1. **A full ROA327 font replica was the goal.**  Superseded -- the
   autoload PROM now calls `define_sextants()` (rom.c) which
   programmatically generates the 64 2x3 sextant glyphs at boot,
   blanking other codepoints.  ROA296 (in IC81) still provides the
   alpha font.  See session 73j in `tasks/timeline.md`.

2. **4 KB PROMs (2732) were a real escape hatch.**  Not on the user's
   physical RC702 -- the A11 solder bridge that the schematic shows is
   a **later-model** feature and is **not present** on this machine.
   Both PROM0 and PROM1 are therefore hard-capped at 2048 B each.
   Any "fits 4 KB" row in the table below is theoretical for the
   broader RC702 family; for current hardware it's "no fit".

The original analysis is preserved below for historical interest /
applicability to later-model RC702 machines that did get the A11 bridge.

## Fit analysis (historical)

| Approach | Font size | Boot code | Total | Fits 2KB? | Fits 4KB (later-model only)? |
|----------|-----------|-----------|-------|-----------|-------|
| Uncompressed | 2048 | 1829 | 3877 | No | Yes |
| Skip scan lines | 1408 | ~1850 | ~3258 | No | Yes |
| + Skip blanks | ~1072 | ~1880 | ~2952 | No | Yes |
| Per-line mask | ~960 | ~1920 | ~2880 | No | Yes |

Boot code size increases slightly due to the decompressor (~20–60 bytes).
None of these approaches fit in 2 KB.  For the user's hardware that
means a full ROA327 replica is not on the table at all without
adopting one of the routes below.

## Prerequisite (historical, applies to later-model RC702 only)

The 4KB PROM solder bridge on the PCB must be closed (connecting A11 to
the PROM sockets). See docs/PROM_SCHEMATICS.PNG and the hardware
technical reference for details.  **User's machine does not have this
bridge**; treat 4 KB PROMs as unavailable in any planning.

## Current implementation (2026-05-17 onward)

`autoload-in-c/rom.c:define_sextants()` runs unconditionally and
programs the 64 sextant glyphs (codes 0x20-0x3F + 0x60-0x7F) into
SEM702 RAM with the bit layout documented in
`ROA327_CHARACTER_ROM.md:155-194` -- no PROM1 font load, no font
table embedded in the PROM, and no bit-reversal needed (data is in
8275-native bit-0-leftmost format).  Cost: ~147 B of code, no data.
Non-sextant codepoints are blanked; line-drawing characters
(ROA327 0x00-0x1F) are not currently provided in the SEM702 path.
