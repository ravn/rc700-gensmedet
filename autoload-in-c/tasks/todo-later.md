# autoload-in-c — to do later

Parked ideas with notes, not active work.  When picking one up,
move its entry into a session log or task file.

## Semigraphics QR code at boot

**Idea:** render a small QR code on the autoload boot screen using
the ROA327 character generator's semigraphics characters (6-bit
block patterns mapped to character codes 0x20..0x5F and 0x60..0x7F).
Targets the existing 80x25 text display -- no graphics-mode chip
work required, just choosing the right character per cell.

**Prior groundwork (already in the tree):**
- `gen_qr.py` -- Python generator that uses the `qrcode` library
  with `version=2`, error_correction=L; converts each 2x3 module
  block into the corresponding semigraphics code via
  `pattern_to_charcode()`.  Currently outputs `clang/qr_data.h` and
  uses URL `github.com/ravn/rc700-gensmedet` as the encoded payload.
- `SEM702_FONT_COMPRESSION.md` -- prior analysis of how to fit a
  custom font in PROM when the SEM702 RAM-based character generator
  is used (alternative to a ROA327 ROM-based char gen).  Includes
  three compression schemes ranging from "skip unused scan lines"
  (1408 B) down to "skip blank chars + delta-encode" (~700 B).

**Open questions to resolve before implementing:**

1. **PROM0 budget:** autoload PROM is currently 1846 / 2048 B (202 B
   free).  A version-2 QR code is 25x25 modules; rendered with
   2x3-module character cells that's 13x9 = 117 cells, each
   stored as one byte.  So ~120 B of QR data plus the draw routine
   (~40 B) plus a position lookup.  Within budget if we keep the
   compressed-font approach in PROM1 separate (or skip it).

2. **PROM1 is irrelevant for the font (current baseline):** the
   RC702 we target has NO SEM702 RAM-based character generator
   board installed.  The font is in IC82 (the character-generator
   chip socket), which on a stock RC702 holds a ROA327 ROM.  The
   CRT reads characters from IC82 directly -- nothing in PROM1 is
   consulted to render text.  So we can keep cpnos-in-asm in
   PROM1 AND still get semigraphics characters on screen from
   IC82, without any font-load step.

   `load_chargen()` (gated on SW1 bit 1, currently commented out)
   only matters if a SEM702 ever appears in IC82 -- then PROM1
   would need to hold the font backup the SEM702 RAM is loaded
   from.  Until then it's a parked option, not a constraint.

3. **Display placement:** QR is 13x9 cells.  Row 0 has banner +
   SW1 status; row 1 blank; row 2 halt messages.  Natural QR
   placement is rows 3..11 (or 16..24, bottom half).  Bottom-left
   probably gives the cleanest scan since the operator's phone
   camera doesn't have to clear the banner text.

4. **Payload to encode:** `gen_qr.py` currently uses
   `github.com/ravn/rc700-gensmedet`.  Worth deciding if that's
   the long-term content (project URL) or something more useful
   (build-info QR with date + hash so a scanned phone immediately
   identifies which firmware is running).

**Status:** not started.  Task #61 tracks this.

## ZX0-compress the CODE section in PROM0

**Idea:** the autoload `.text` section (1742 B) currently lives in ROM
at LMA=0x0068 and is copied verbatim to RAM at 0x6000 by `_start` via
LDIR.  Replace the LDIR with a ZX0 decoder call and store `.text`
ZX0-compressed instead.

**Measured numbers (HEAD a358bb0, 2026-05-17):**
- raw `.text`: 1742 B
- ZX0-compressed `.text`: 1331 B
  (`z88dk-zx0 v1.5` optimal mode, delta 3)
- decoder: 68 B (`dzx0_standard` by Einar Saukas)
- compression saving: 411 B; net after decoder: **~343 B**
- prom0 today: 1846 / 2048 B (202 B free)
- prom0 projected: **~1503 / 2048 B (~545 B free)**, 2.7x more headroom

**Prior groundwork:**
- `cpnos-in-asm/src/prom1.asm` already embeds the same Standard ZX0
  decoder to decompress its SNIOS payload (session 73f).  Same
  in-source comment style, identical decoder bytes.  New autoload
  integration is essentially a copy of that pattern.
- `clang/rc700_prom.ld` already separates `.boot` (fixed at 0x0000)
  and `.nmi` (fixed at 0x0066) from `.text` (LMA in ROM, VMA in RAM
  0x6000).  No structural linker change needed beyond the LMA
  offset bump.

**Implementation sketch:**
1.  Build: after first link, extract `.text` via `llvm-objcopy -O
    binary --only-section=.text`, compress with `z88dk-zx0`, re-link
    with the compressed blob as an `incbin` plus `--defsym
    __zx0_size=...`.  Mirrors the `cpnos-rom` data-driven relocator
    pattern from session 47.
2.  Boot stub: replace the LDIR in `_start` with `call dzx0_standard`
    (`HL`=compressed source, `DE`=0x6000).
3.  Linker script: insert a `.zx0_decoder` section between `.nmi`
    (ends 0x0068) and the compressed `.text` blob (starts ~0x00AC,
    i.e. 0x0068 + 68 B decoder).

**Open questions before starting:**
1.  **Two-pass vs. single-link build.** Compression needs the linked
    `.text` bytes, but `_start` needs the compressed blob's size at
    link time.  Two-pass via `--defsym` matches project precedent
    (cpnos-rom relocator).
2.  **Decoder placement.** 68 B doesn't fit between `.boot` end
    (0x004D) and the NMI vector at 0x0066 (only 25 B free).  Put
    the decoder AFTER the NMI handler in a new `.zx0_decoder`
    section; `.text` LMA bumps from 0x0068 to ~0x00AC.
3.  **Stack at decode time.** `_start` must set SP before calling
    `dzx0_standard` (Standard decoder uses BC/DE/HL/AF and call/ret).
    Same constraint the existing LDIR has -- already satisfied.
4.  **Headroom forecast is soft.** 411 B saving is on today's
    `.text`.  Future code compresses at a similar ratio, so adding
    100 B of source typically eats ~65 B of PROM, not 100 B.
5.  **Build dep on `z88dk-zx0`.** Compressor binary already exists
    at `/Users/ravn/z80/z88dk/src/zx0/z88dk-zx0`.  Either reference
    it via the workspace layout or vendor it under `tools/` like
    `rc700-gensmedet/zmac/`.

**Status:** DONE 2026-05-17 (clang side).  PROM0 1846 -> 1509 B
(saves 337 B; .text 1742 -> 1330 B ZX0 minus 68 B decoder).  Files:
`clang/{dzx0_standard.s, text_compressed.s, rc700_prom.ld}` +
boot_rom.c reloc_zx0 swap + Makefile two-pass with z88dk-dzx0
roundtrip-verify.  MAME CP/M boot PASS.  SDCC variant NOT ported
(asymmetric; see [[feedback-symmetric-recipes-per-compiler]] -- the
2 KB ic66 artefact set is still symmetric so no BAD_CHECKSUM risk).
QR-at-boot work now fits inside a ~539 B headroom budget instead
of the tight ~42 B pre-ZX0.

## ID Comal compatibility

**Idea:** make autoload-in-c boot an ID Comal system, not just CP/M
on RC702.  Two constraints distinguish ID Comal from the current
RC702 CP/M target:

1. **Decompression destination must sit above the boot-read sectors.**
   Today autoload's `.text` is ZX0-decompressed to RAM at 0x6000 (see
   `clang/rc700_prom.ld` `> RAM ORIGIN = 0x6000`).  On ID Comal the
   boot-loader reads sectors into a region that overlaps 0x6000, so
   the relocated code clobbers (or is clobbered by) the sector data.
   Move `_code_start` to a higher RAM address that lives above the
   sector-read window.

2. **Screen buffer must be in the correct location.**  Current
   autoload writes the boot banner to display memory at 0x7A00 (see
   `mame_sw1_test.lua` and `display_banner()` in `rom.c`).  ID Comal
   uses a different display-memory base; banner + SW1 status must
   target that base instead.

**Open questions before implementing:**

1.  **What is ID Comal's RAM map?**  Need: sector-read range,
    display-memory base, BSS region, stack location.  Without these,
    pick-the-right-address is guesswork.
2.  **Single PROM or two builds?**  Either keep one autoload that
    detects ID Comal vs. RC702 at runtime (port read?), or build
    two PROMs from the same C sources with different linker scripts
    and banner constants.  Two builds is simpler.
3.  **Display routines are address-sensitive.**  `display_banner`
    and the SW1-status renderer write to a hard-coded base.
    Either parameterize via a `DISPLAY_BASE` macro driven by the
    linker script, or fork per-target.

**Status:** not started.  Low priority.

## Split ZX0 decoder around NMI vector to reclaim pre-NMI padding

**Idea:** the autoload PROM has a 38 B unavoidable 0xFF padding hole
between the end of `_start` + `banner_string` (~0x0040) and the
hardwired NMI vector at 0x0066.  The current 74 B ZX0 decoder lives
entirely after NMI at 0x0068, pushing the compressed payload to
~0x00B3.  Splitting the decoder so the first ~35 B live in the
pre-NMI hole would let the compressed payload start ~35 B earlier
and save that many PROM bytes (1509 B -> ~1474 B; free 539 B ->
~574 B).

**Why this is a real win where naively "compress more" was a loss:**
moving uncompressed data INTO the compressed payload grows the PROM
end-pointer (see banner-move experiment that *added* 28 B of PROM
when banner went from pre-NMI BOOT into the .text compressed blob).
The pre-NMI region's bytes are free; the post-decoder bytes are not.
So the optimization direction is "pack the pre-NMI hole", not
"compress more strings".

**Approach sketch:**
1.  Move banner_string out of `.pagezero.data` IF needed for more
    room (loses ~28 B to compressed payload, gains 31 B pre-NMI ->
    net 3 B; only worth it if the split needs more than 38 B).
2.  Hand-split `dzx0_standard` at a clean instruction/label boundary
    (e.g. just before `dzx0s_new_offset` or before `dzx0s_elias`).
    Prefix runs in pre-NMI region, ends with a 3 B `jp` over the
    NMI vector to the post-NMI suffix.
3.  Linker script gains a `.zx0_decoder_pre_nmi` section placed
    before NMI (e.g. at 0x0040 or as `> ROM` after .boot with an
    ASSERT keeping it below 0x0066), and a `.zx0_decoder_post_nmi`
    section after NMI.
4.  Re-verify the byte-exact host roundtrip in the Makefile
    (`z88dk-dzx0` should still reproduce pass-1 .text exactly --
    the split is purely an assembly-layout change, decoder logic
    unchanged).

**Open questions before implementing:**

1.  **Picking the split point.** Want the largest pre-NMI prefix
    that ends at a JP-able label.  Candidates: end of `dzx0s_copy`
    (jr nc to dzx0s_literals reaches; need to keep dzx0s_literals
    on whichever side of NMI the jr can reach), or end of one of
    the elias helpers.  3 B `jp` bridge is the natural tool since
    jr's +/-127 B range may not reach.
2.  **PC-relative jr reachability across the split.** The decoder
    uses several jr's; some may currently span what would become
    the NMI gap.  Audit each jr distance after the split and
    promote to jp where needed (may cost 1 B per promoted jr).
3.  **_reloc_zx0 wrapper placement.** Today the 6 B wrapper
    (ld hl/ld de) falls through to dzx0_standard.  After the split
    it either stays as a 9 B call site (extra 3 B jp at end) or
    moves to be the very first thing in the pre-NMI prefix and
    falls through into the decoder body.

**Expected saving:** ~35 B PROM (1509 -> ~1474 B clang autoload).
On top of the 337 B already saved by ZX0 itself.

**Risk/complexity:** medium.  Linker script changes + hand-split asm
+ careful jr-reachability audit.  Existing roundtrip-verify guard
in the Makefile catches any decoder bug at build time.

**Status:** not started.

