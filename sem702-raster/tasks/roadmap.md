# sem702-raster -- roadmap

Subproject goal: simulate higher CRT resolution on RC702 by reprogramming
SEM702 character-generator RAM at frame boundaries, racing the 8275 beam.
Theoretical pixel ceiling = **128 unique 8x11 glyphs = 11264 pixels visible
at once** (regardless of refresh rate).

## Status (2026-06-05, session opening this subproject)

* **`raster.asm` (DONE)** -- minimum-viable demo.  4 SEM702 glyphs cycle
  through 4 distinct animation patterns at 50 Hz; MAME run captured in
  `snap/raster_{1,2,3}.png` shows distinct motion.  Validates the full
  pipeline: ISR install + chain-JP to BIOS handler, GPA0 field attribute,
  HALT/EI/RETI frame sync, OUT D1/D2/D3 latch-write sequence.
* **`bench.asm` (BUILD-READY, MAME RESULTS MEANINGLESS)** -- bench loop
  measures effective T-states/OUT under display contention.  MAME's 8275
  model is functional, not cycle-accurate, and the SEM702 add-on is not
  modelled at all -- the bench is the artefact ready to run on physical
  hardware once `[[project-sem702-request-chip-photo]]` clears.

## Open items

### A. `reprogram_64_fast.s` -- unrolled hot path for variant A

The current rolled inner loop costs ~670 T per glyph; 64 glyphs = ~10.7 ms,
**which does not fit variant A's Phase 2 window of 8.35 ms** (lower-half
scan).  Need a hand-rolled unrolled version that hits ~500 T per glyph,
giving 32 000 T = 8.0 ms per 64-glyph reprogram.  Workable templates:

* ACHAR set once, ALINE as immediate value per line (no DJNZ overhead) ->
  ~462 T per glyph + ret/call overhead.
* OUTI is not a clean win here (it requires juggling C between D2/D3 ports;
  per-line overhead ~62 T, worse than the immediate-per-line unroll).

Validation: MAME render-correctness check (variant A's invariant -- upper
half uses codes 0..63, lower half uses codes 64..127, neither block ever
sees an in-flight glyph rewrite of the OTHER block's codes).

### B. Variant A end-to-end demo

Once (A) is in place, write `variant_a.asm` that does the full 64x176 px
pseudo-bitmap with a non-trivial animation (e.g., a scrolling sine wave or
a Mandelbrot tile fed via a precomputed table).  Verify:

* 50 Hz full refresh sustained (lua check: tick counter advances 50 per
  wall-second, no missed frames).
* No visible tearing in MAME (renders cleanly because MAME's 8275 reads
  chargen atomically per cell).
* `wait_until_row12()` calibration -- the bridge between Phase 1 and Phase
  2 currently uses a placeholder DJNZ count.  Measure beam position vs.
  IRQ-tick via a MAME-side scanline tap and adjust.

### C. Physical-hardware verification (BLOCKED on
`[[project-sem702-request-chip-photo]]`)

* Run `bench.com` on physical RC702; record results table from RAM via
  MP/M debug link or hexdump.
* Compare mode 0 vs mode 1 deltas -- if mode 1 > mode 0 in frame count,
  there are wait-states; quantify T/OUT.
* Inspect `preload_glyph65`'s 0xAA stripe pattern visually with line 5
  hammered -- look for tearing, flicker, or stable "latest-write"
  semantics.  Tells us whether race-the-beam disjoint-glyph timing is
  needed, or whether SEM702 already arbitrates cleanly.
* Test ALINE auto-increment: write ACHAR once, AWR repeatedly without
  ALINE; if successive AWR writes land in consecutive lines, the chip
  auto-increments and our per-glyph cost halves.

### D. Reduced-resolution variants

If variant A's 8.35 ms Phase 2 is too tight even after (A) is unrolled, a
fallback layout exists:

* **Frame-interlace (25 Hz full bitmap)** -- even frames use codes 0..63,
  odd frames use 64..127; 20 ms per reprogram, trivially fits.  Tradeoff:
  visible flicker at 25 Hz on motion-heavy content.
* **Per-row alternation with sparse glyph updates** -- 5-7 glyphs per row
  gap, ~168 updates/frame, animation-only (not full bitmap refresh).

Both are derivable from the same primitives; only the schedule changes.

## Cross-references

* `[[project-sem702-request-chip-photo]]` -- physical hardware blocker
* `[[project-cpnos-parked-awaiting-parallel-cable]]` -- likely co-occurs
  with next physical-hardware session
* CLAUDE.md "Race-the-beam" discussion in the live chat that birthed this
  subproject (sessions on 2026-06-04..05)
* GitHub `ravn/rc700-gensmedet#101` -- IVT-slot table doc fix that cost us
  30 min of debugging
* GitHub `ravn/rc700-gensmedet#102` -- chip-photo + identification ask
