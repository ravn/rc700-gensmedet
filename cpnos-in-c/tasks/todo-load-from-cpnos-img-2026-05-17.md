# cpnos-in-c: load tables + SEM702 font from cpnos.img at boot

**Status:** TODO (planned, not started).  Filed 2026-05-17 during the
post-dual-transport feature-completion push (session 73j).

Replaces / extends the earlier
`todo-translation-tables-2026-05-17.md`.

## Goal

User-stated: "translation i/o tables could be loaded from the cpnos.img
file too and put in their correct place (same as rcbios). ... also the
full ROA327 content could be loaded from cpnos.img and used to program
sem702."

Reframe the static-content problem: instead of trying to fit
translation tables + a full 2 KB ROA327 font INSIDE the PROM1
lineprog, ship them in the **cpnos.img** master-side file that the
slave fetches over CP/NET during cold-init.  The slave then
unpacks them at the correct addresses in RAM (translation tables
at 0xF680 cluster, sextant glyphs into SEM702 RAM via 0xD1/0xD2/0xD3).

PROM1 stays at the 2 KB cap with just the bootstrap + dual-transport
+ resident code; the heavy content rides the network.

## Two parts

### Part A -- input/output translation tables (locale)

Mirror rcbios's `outcon` / `inconv` layout (0xF680 cluster, see
`rcbios-in-c/bios.c:779,934,1372`).  Source tables live in
`rcbios-in-c/locale/*_tables.h`.

The slave reserves the address range in resident RAM (zero-init at
cold-boot), opens a known file on the master ("CONFI.SYS" or similar),
and reads bytes into the reserved slots.  CP/NET file I/O via SNIOS
already works -- this is just a different filename + destination
address.

Default to ASCII pass-through if the file is absent (so a cpnos.img
without the table file boots fine).

### Part B -- full ROA327 -> SEM702

Today `autoload-in-c/rom.c::define_sextants()` programs only the 64
sextant glyphs into SEM702 RAM (codes 0x20-0x3F, 0x60-0x7F).  The
remaining 64 ROA327 glyphs (line-drawing 0x00-0x1F + shared A-Z
0x40-0x5F + the 32 odd patterns at 0x40-0x5F that ROA327 doesn't use)
are blanked.

For a SEM702-equipped machine to render the full ROA327 character set,
the cpnos slave can read the 2 KB ROA327 bytes from cpnos.img during
cold-init and stream them through ports 0xD1/0xD2/0xD3 -- same
protocol the autoload uses, just with a complete font instead of
the 64-sextant subset.

This is independent of Part A and gracefully degrades: cpnos.img
without the font file means the SEM702 keeps the autoload-programmed
subset (already useful: blanks + sextants).

### Part C -- BSS reservation in resident

Both parts need RAM space:
- translation tables: probably 256 B at 0xF680
- ROA327 staging buffer (optional, since we can stream directly to
  SEM702 without a buffer): 0 B if streaming, 2048 B if buffered

If streaming: zero additional resident RAM cost.

## Concrete sub-tasks

1. **Reserve `outcon` / `inconv` BSS** at 0xF680 in resident.c with
   defaults matching rcbios's `_conv_tables` boot-init values.
2. **cpnos.img file-fetch helper** in cpnos-in-c -- open a named file
   via SNIOS, stream bytes into a destination address.  Likely a few
   dozen bytes of code; reuses existing SNIOS frame primitives.
3. **Wire fetch into `cpnos_cold_entry`** after `netboot_mpm` but
   before final NDOS handoff.  Two calls: one for the locale table,
   one for the ROA327 image.
4. **Master-side cpnos.img builder** -- include the table file and the
   ROA327 image as files in the netboot virtual filesystem.  May
   already work via existing cpnos.img build pipeline; needs verification.
5. **Smoke test** -- boot the slave, run an utility that prints a
   character requiring locale translation, confirm correct glyph
   appears.

## Cost class

Medium.  No new transport protocol -- everything rides existing CP/NET
file I/O.  Main work is the BSS reservation + file-fetch glue +
master-side file inclusion.

## When

Pick up once the PROM1 budget is stable.  Currently 1999 B / 2048 B
(48 B free) -- this work doesn't grow the PROM1 image, it shrinks
it if anything (no embedded font/tables).
