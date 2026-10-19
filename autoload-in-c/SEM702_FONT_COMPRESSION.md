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

## Current implementation and ZX0 Compression Findings (2026-10-19)

### 1. Full ROA327 vs Sextants Only in ZX0
- **Full ROA327 replica (128 glyphs x 11 dot-lines = 1408 B):**
  When stored line-major in `sem702_font[]` (`clang/sem702_font.h`), it compresses
  down to **~377 B** with ZX0 (in the `.text` payload). This includes line-drawing
  graphics (0x00..0x1F), punctuation/digits, uppercase ASCII (0x20..0x5F), and the
  sextants (0x60..0x7F).
- **Sextants only (64 glyphs x 11 dot-lines = 704 B):**
  Because sextants have only 4 distinct scanline patterns (`0x00`, `0x0F`, `0x70`, `0x7F`)
  repeated over fixed line spans (lines 0..3, 4..6, 7..10), ZX0 compresses the 704 raw
  bytes down to **32 bytes**!
- **Procedural code vs ZX0 compressed table:**
  Generating sextants procedurally on the fly requires nested loops and bit-manipulation
  taking ~120-190 bytes of compiled Z80 machine code. Storing the ZX0-compressed sextant
  table takes only **32 bytes** of data plus a ~25-byte transpose loop (~57 bytes total).
  Therefore, **ZX0 compression is smaller than procedural generation**.

### 2. Hardware Trade-off & 2 KB PROM Budget
- If the hardware configuration requires the SEM702 board (IC82) to supply all alphanumeric
  characters while active, the full 128-glyph table (377 B in ZX0) is mandatory.
- If only sextants (for QR-code display) are required in SEM702 RAM (because IC81 ROA296
  handles standard alpha text), pruning `sem702_font[]` to sextants only frees
  **~345 bytes** in the autoload PROM, easily keeping firmware within the 2048 B limit.
