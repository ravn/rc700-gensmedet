# cpnos-in-c: DMA dual-buffer scroll experiment

**Status:** TODO (planned, not started; user-flagged as
"experiment as it will ruin the 0xF800 memory layout").  Filed
2026-05-17 during session 73j.

## Goal

User-stated: "investigate whether it is feasible to have the DMA
controller feed the CRT two sets of data so the LDIR to move the
screen can be avoided".

Today, when the slave scrolls the display, `scroll_lines` (113 B in
the resident -- one of the larger functions; see
`shrink-investigation-2026-05-17.md`) does an `LDIR` over 1920 B of
display memory (80 cols x 24 rows).  Per-scroll cost ~14400 T at
4 MHz = ~3.6 ms, which is noticeable when CCP / programs stream
output that overflows the screen.

If the AMD Am9517A-4 DMA controller (channels 2/3) can be programmed
to feed the 8275 from a different RAM base per frame, the slave can
double-buffer: write new content into a second 80x24 region, swap
the DMA source address at vsync, and skip the LDIR entirely.  The
8275 doesn't know or care where its bytes come from.

## Why "ruins the 0xF800 memory layout"

The current convention: display memory is at 0xF800..0xFFCF (1920 B,
80x24).  CP/M utilities + diagnostic tools assume that layout
(write a byte at 0xF800+row*80+col to put it on screen).  Direct-poke
code in third-party CP/M software would break if the slave moved
the framebuffer.

Mitigations to consider:
- Keep the LOGICAL framebuffer at 0xF800 (for software compat) but
  scroll by adjusting DMA's starting offset within that range modulo
  2048.  Requires display memory to be in a ring-buffer style with
  the DMA wrap-around handled by the 8275 controller config.
- Or: take the breaking change and document it.  Software that
  direct-pokes 0xF800 already breaks if the slave grows beyond
  80x24 (e.g. 80x25 already uses 0xF800..0xFFCF = 2000 B).

## Concrete sub-tasks

1. **Verify Am9517A capabilities** -- can the DMA source address
   be changed mid-frame or at vsync without glitching?  Per the
   RC702 schematic + datasheets.
2. **Verify 8275 char-row alignment** -- the 8275 has its own row
   tracking; if the DMA wraps mid-row, does the 8275 reprogram cleanly?
   This is what session 73e hit ("mid-frame DMA reprogram needing
   8275 STOP/PRESET/START to resync to row 0" -- per memory
   `feedback_rc702_bank2h_mirror` was filed but the resync issue is
   adjacent).
3. **Design the buffer layout** -- two 1920 B regions in RAM, one
   active + one scratch, with a swap mechanism.  RAM cost: +1920 B.
   On a 64 KB Z80 with ~48 KB TPA today, this is meaningful but
   feasible (TPA shrinks by ~2 KB).
4. **Prototype the scroll-via-swap path** -- write to scratch buffer
   the contents that scroll_lines would produce, then swap DMA source.
5. **Compatibility shim** -- if direct-poke compat is needed, mirror
   writes to 0xF800 into the active DMA region.

## Cost class

Large.  Touches DMA programming, 8275 sequencing, RAM map.  Real
risk of subtle glitches on the physical CRT.  User explicitly
called it an experiment.

## When

Defer until: (a) PROM1 budget is stable and feature-complete; and
(b) hot-path optimizations (impl_conout, etc.) have been pushed
about as far as they can go without architectural changes.  At
that point, the LDIR scroll is the next-biggest visible perf cost
worth attacking.

## Cross-references

- scroll_lines: `cpnos-in-c/src/resident.c` (113 B per llvm-nm)
- Display memory at 0xF800: `cpnos-in-c/docs/memory_map.md`
- DMA channels 2/3: `cpnos-in-c/src/hal.h` `DMA_CH_DISPLAY = 2`
- 8275 sequencing pitfall: rc700-gensmedet/tasks/timeline.md
  Session 73e ("mid-frame DMA reprogram needing 8275
  STOP/PRESET/START")
