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
