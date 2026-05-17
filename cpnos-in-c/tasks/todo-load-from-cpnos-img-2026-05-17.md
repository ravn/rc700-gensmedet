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
(49 B free) -- this work doesn't grow the PROM1 image, it shrinks
it if anything (no embedded font/tables).

## Investigation 2026-05-17 (session 73j-late, branch
   locale_tables_via_img_prefix; not merged)

Attempted the "prepend tables to cpnos.img, LDIR at boot" approach
suggested by the user.  Architecture works in principle:

  Master:  cpnos.img = locale_prefix(N) + cpnos.com
  Slave:   loads at IMG_BASE - N (so prefix lands just below NDOS,
           cpnos.com lands at the expected NDOS load address);
           after EOF, LDIR the prefix from below-NDOS to its
           runtime home; JP to NDOS as usual.

Three real constraints surfaced that blocked landing:

1. **`pio_rx_buf` occupies 0xF700**.  rcbios puts `inconv[256]` at
   0xF700; placing it there on cpnos overwrites the PIO-B IRQ ring,
   breaking CP/NET frame reception.  Symptom: slave reached `E>`,
   but PPAS load timed out (file fetch failed) because the SNIOS
   layer couldn't drain incoming bytes.

2. **Stack workspace is at 0xF621..0xF6FF**.  rcbios puts
   `outcon[128]` at 0xF680; on cpnos that overlaps the stack
   working area.  Stack pushes would corrupt outcon and vice versa.

3. **Two-PROM cpnos scratch_bss is 270 B**, vs the PROM1-only
   variant's ~256 B.  Moving `pio_rx_buf` to 0xEC00 (inside the
   SCRATCH region) requires shrinking SCRATCH from 0x200 to 0x100,
   which underfits the two-PROM build by 14 B.

What the investigation *did* confirm:

  * The LDIR-from-prefix mechanism itself is sound -- single 384 B
    LDIR (`ld hl, src; ld de, 0xF680; ld bc, 0x180; ldir`) cleanly
    moves a contiguous outcon+inconv block if the layout cooperates.
  * The Makefile concatenation (`cat locale_prefix.bin cpnos.com >
    cpnos_with_locale.img`) and cpmcp install path work end-to-end.
  * `gen_locale_prefix.py` extracts the correct bytes from
    `rcbios-in-c/locale/danish_tables.h` (US-ASCII identity outcon
    + Danish inconv lower-identity + upper-overrides).

Path forward (next session):

A. **Audit two-PROM scratch_bss for 14 B of shrink**.  llvm-nm shows
   the `__sframe_*` static-stack frames are the bulk of usage; some
   may be combinable or eliminable via attribute changes (e.g. making
   some functions reuse a common scratch frame).  Once that 14 B is
   freed, the layout surgery (pio_rx_buf -> 0xEC00, stack_top ->
   0xF680, contiguous tables at 0xF680..0xF7FF) becomes viable.

B. **Accept non-rcbios addresses**.  outcon @ 0xEC80 (in scratch_bss
   free area, ~237 B available), inconv @ 0xF600..0xF6FF if stack
   shrunk below; CONFI.COM-style address compat breaks but the
   functional behaviour (Danish keyboard + US-ASCII output) works.
   Two LDIRs instead of one.

C. **Skip outcon, ship inconv only** at non-rcbios address.  Drops
   the user's "both tables always" requirement; defers outcon until
   layout permits.

Recommendation: A (audit) if user wants the full rcbios layout;
otherwise B for a working compromise.  The user-confirmed pick was
A ("1" in the session 73j-late thread) but the audit work itself
wasn't started.
