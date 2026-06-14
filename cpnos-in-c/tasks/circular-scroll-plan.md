# cpnos circular hardware scroll via ch2/ch3 roll function

## Goal

Replace cpnos's CONOUT line-scroll memcpy (currently a 1920-byte `LDIR`
moving rows 1-24 → rows 0-23 when the cursor advances past row 24) with
a hardware-assisted circular scroll using the 8275's roll function.
"Scroll up" becomes a few DMA-register writes (sub-millisecond) instead
of a ~9 ms CPU stall (24 t-states × 1920 bytes / 4 MHz).

## Mechanism (same as `roa375.asm:890-967` `DISINT`)

Hold the display in a logical buffer larger than the visible 2000 bytes.
Maintain a software pointer `S` ("scroll offset", 0..buffer_size-80, in
bytes).  ch2 and ch3 are programmed once at scroll-time to split the
visible window between two regions:

- **ch2 base** = `DSPSTR + S`
- **ch2 wc** = `(buffer_end - (DSPSTR + S)) - 1` (bytes from S to end of
  buffer)
- **ch3 base** = `DSPSTR`
- **ch3 wc** = `(2000 - bytes_in_ch2) - 1` (bytes from start of buffer
  to where the visible window wraps to)

Each VRTC the 8275 issues 2000 DRQs.  ch2 services the first chunk (up
to its TC).  The 74LS74 on MIC 11 flips to Q=1 at ch2's TC, and ch3
takes over for the rest.  Next VRTC clears the FF, autoinit reloads
both base/wc registers, repeat.

Scroll up = `S += 80`; clear the new bottom row of the logical buffer
in-place; reprogram ch2/ch3 base+wc registers.  Zero memcpy of screen
memory.

Wrap: when `S` reaches `buffer_size - 2000`, the next scroll-up wraps
`S` back to 0 (or continues incrementing modulo `buffer_size`; the
register math handles it).

## Interaction with the parked PIO→INIR work (Steps 2+4)

**This is the load-bearing decision before starting work.**

Today's commit `9592c2d` stripped the per-VRTC DMA reload from cpnos's
`isr_crt` specifically to free ~150 T-states / frame so a `DI`-bracketed
INIR block-RX window (~1.5 ms) could survive without display garble.
That headroom is the reason the INIR Steps 0+1 stay in main while
Steps 2+4 are parked behind hardware.

Adding circular scroll re-introduces per-scroll DMA reprogramming, but
crucially it does **not** have to happen every VRTC — only at scroll
events.  Three approaches with different INIR compatibility:

| Approach | Scroll-time work | Per-VRTC work | INIR-headroom impact |
|---|---|---|---|
| **A. Program once, lean on autoinit** (preferred) | Mask ch2+ch3, CLBP, write ch2 base + wc, ch3 base + wc, unmask | None (autoinit reloads) | Zero — same model as today's stripped ISR; ch3 just doesn't sit at wc=0 anymore |
| **B. Per-VRTC reload** (the assembly-BIOS `DISINT` pattern, equivalent of pre-`9592c2d`) | None (state held in software) | Mask, reload all base/wc, unmask | High — costs the same ~150 T-states / frame we just freed; conflicts directly with INIR DI bracket |
| **C. Conditional reload** (per-VRTC only when scroll changed) | None | Either reload (if changed) or nothing (if not) | Variable — scroll bursts cost INIR headroom briefly; quiescent scroll has no cost |

**Recommended: approach (A) — program once, lean on autoinit.**

The 8237 autoinit reloads base + wc from the *base* registers on each
TC.  If we write the base registers at scroll-time and leave them
alone, the hardware applies the split on every subsequent frame
without ISR involvement.  This is the same shape as today's stripped
ISR model — the ISR doesn't touch DMA at all — just with ch3 holding a
real base and the visible split changing only when the software
scrolls.

The narrow risk window is the scroll-time programming itself: between
masking ch2 and unmasking ch3, the 8275 may issue a DRQ that goes
unserviced (display tearing for one row).  Mitigations:

1. Schedule the scroll programming inside the VRTC ISR window
   (between the VRTC IRQ and the 8275's next DRQ).  The ISR runs ~30 T
   today, leaving plenty of slack within VRTC's 22 scan lines × 64.9 µs
   = ~1.4 ms of retrace.  Even allowing ~150 T for the eight port
   writes is ~0.04 ms — well inside the budget.
2. If a scroll request arrives outside the VRTC window, queue it and
   apply at the next VRTC.  One-frame scroll latency (20 ms) is
   imperceptible.

Both mitigations preserve the INIR DI-bracket headroom: when INIR is
running, scroll requests just queue, and the DMA registers aren't
touched until VRTC fires (which is itself blocked during the DI
bracket; pending VRTCs queue at EI).

## Loss of `0xF800 + 2000 bytes` contiguous compatibility

User acknowledged 2026-06-14: this is the explicit trade-off.

Consequences:

1. **Snapshot tools that dump `0xF800..0xFFFF` to view the screen** will
   see the logical buffer in rotated/wrapped form, not in
   visible-row order.  A new dump tool that knows about `S` and the
   buffer size could de-rotate the bytes before display.  Add this to
   cpnos's debugging story.
2. **rcbios snapshots, autoload PROM display, and other RC700 firmware**
   reading the display via fixed `0xF800` address will see scrambled
   output after the first scroll.  Not a regression in practice because
   they don't reach in to read cpnos's display memory, but document it
   so future "why is the screen wrong" debugging has a one-line
   answer.
3. **MAME `polypascal_test.lua` and other lua scripts** that read
   display memory directly to verify content need to either learn the
   rotation, or be content with reading from the SIO-B mirror (which is
   already the production verification path).
4. **The display buffer size** is bigger than today's 2000 bytes —
   we need to decide where to place it and how much scrollback to
   allocate (32 rows × 80 = 2560 bytes? 50 × 80 = 4000? 64 × 80 = 5120
   = the 8275's logical max?).  Bigger buffer = more scrollback but
   less resident RAM for the program.  cpnos's current resident budget
   is tight.

## Implementation steps

1. **Pick the buffer size.**  Suggested first attempt: 32 rows = 2560
   bytes.  Big enough that ~half a screen of scrollback exists, small
   enough that the resident footprint impact is contained.
2. **Move `DSPSTR` to a location that gives 2560 bytes contiguous.**
   Either expand downward from `0xF800` (e.g. `0xF600..0xFFFF` minus
   CLOCK = ~2554 bytes — tight, requires moving CLOCK), or pick a
   different base.  Decide based on cpnos's resident memory map.
3. **Add scroll state**: `static word scroll_offset;` and a constant
   `BUFFER_SIZE`.
4. **Modify `impl_conout`** to detect "advance past row 24" and call a
   new `scroll_up()` helper instead of LDIR-ing 1920 bytes.
5. **Implement `scroll_up()`**:
   - `scroll_offset = (scroll_offset + 80) % BUFFER_SIZE;`
   - Clear the new bottom row at `DSPSTR + ((scroll_offset + 1920) %
     BUFFER_SIZE)` (one row of 80 bytes, may straddle the wrap point —
     needs two memsets in that case).
   - Reprogram ch2 base + wc and ch3 base + wc to reflect the new split
     (with appropriate mask/unmask around the writes).
6. **CRT init**: program ch2 + ch3 base+wc once at startup for
   `scroll_offset = 0`.  ch3 base stays at `DSPSTR` from then on (it's
   always the start of the buffer; only its wc changes with scroll).
7. **Cursor positioning** (`impl_setpos`): translate logical row,col to
   physical address through `(DSPSTR + (row * 80 + col + scroll_offset)
   % BUFFER_SIZE)`.  Wrap-aware writes for multi-byte operations.
8. **CONOUT.MAC parity check**: do any cpnos test programs use
   `goto_xy` to write at row 24 or near the wrap point?  If so, verify
   they still render correctly.
9. **MAME verification**: cpnos-polypascal-test with PolyPascal running
   PRIMES generates enough output to trigger many scrolls.  If it still
   PASSes with the new scroll path, the basic mechanism works.  Add a
   targeted test that fills the screen, scrolls once, fills again,
   confirms first-fill content has scrolled out but the wraparound is
   correctly stitched in the rendered frame (compare MAME-captured
   pixels at the boundary).
10. **Size impact**: scroll-up code is small (~30-50 bytes) but ch3
    programming adds ~20 bytes.  Net cost should be ≤ 0 once the
    1920-byte LDIR sequence is removed.

## Verification

1. cpnos-polypascal-test PASS with the new scroll path (PIO and SIO
   transports).
2. CCP `DIR` of a moderately full disk (scrolls multiple times) shows
   clean output.
3. MAME-captured frames at the wrap boundary show correctly stitched
   content from both ch2 and ch3 regions.
4. Resident size: PROM1 still fits in 2 KB (today: 2015 B / 33 B
   free) after the scroll path change.
5. INIR Steps 0+1 still verify-clean (the autoinit ISR pattern stays
   the same; we just changed the base+wc values).

## Cross-references

- `docs/dma_ch3_8275_roll_function.md` — gate-level schematic + how
  the FF switches ch2 to ch3 at TC.
- `roa375/roa375.asm:890-967` — working precedent (`DISINT`,
  per-VRTC reprogramming model; we'll do approach (A) one-shot
  instead).
- `rcbios-in-c/tasks/26-line-status.md` — the rcbios CRT26 plan uses
  ch3 for a static status buffer; cpnos's circular scroll uses ch3 for
  a dynamic top-of-screen region.  The two firmwares don't run
  together so there's no in-system conflict, but it's worth knowing
  ch3 is being repurposed differently in each.

## Status

**Planned, not started.**  Decision needed before starting:

1. Buffer size (32 rows / 50 rows / 64 rows)?
2. Memory layout — extend `DSPSTR` region, or move it?
3. Stay with one-shot programming (approach A) or per-VRTC (B/C)?
4. Block on INIR Steps 2+4 unparking, or proceed in parallel?

Cross-reference: `tasks/cpnos-in-c/PIO_INIR_PARKED.md` is the parked
work this interacts with.
