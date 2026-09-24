# Status line on row 26 — design notes & findings (abandoned 2026-04-08)

Goal: add a 26th display row used as a system status line, while keeping
the original `0xF800 + 2000` byte display layout untouched (so the
status row's 80 bytes have to come from somewhere else in memory).

**Outcome: shelved.** The hardware mechanism works (verified by buffer
dumps and screen rasterisation), but every approach we tried produces
visible flicker during cold boot. We pushed three feature branches with
the working implementation in case we want to come back to this:

- `ravn/rc700-gensmedet @ status-line-26`
- `ravn/mame-rc702-rc759-rc750 @ status-line-26-dual-dma`
- `ravn/z80-compiler-suite-workspace @ status-line-26`

## Hardware mechanism (RC700 dual-DMA CRTC)

The 8275 has one DRQ output that the rc702/rc700 hardware routes through
a `74LS74` D flip-flop to either DMA channel 2 or channel 3:

- `Q = 0 / Qbar = 1` → DRQ goes to DMA ch.2
- `Q = 1 / Qbar = 0` → DRQ goes to DMA ch.3
- `~CRTC_IRQ` clears the flop at the start of every frame (→ ch.2)
- `D` is wired to `Qbar` (toggle), `CLK` is wired to DMA EOP

So inside one frame ch.2 transfers its full byte count, EOP fires, the
flop toggles, the next batch of DRQs is serviced by ch.3, then EOP
toggles back. At the next frame the CRTC IRQ clears the flop and the
sequence restarts.

In rc702-bios this dual-DMA path was never used; rc702-bios fed the
8275 from a single channel and put a 0xFF "End of Screen-Stop DMA"
sentinel after the visible content. We wanted the dual-DMA path so we
could keep the existing display memory at `0xF800 + 2000` bytes
unchanged and source the extra 80 bytes from a separate buffer.

## What we tried

1. **MAME emulation gap.** Plain MAME didn't model the 7474 toggle —
   only `CLR` from `~CRTC_IRQ` was wired; `D` and `CLK` were unconnected,
   so the flop sat at `Q=0/Qbar=1` forever and only ch.2 ever serviced
   the CRTC. Patched `src/mame/regnecentralen/rc702.cpp`:

   - `D ← Qbar` (so each clock toggles)
   - `CLK ← DMA EOP` (the chip's shared TC pin)

   Tried gating `CLK` so only ch.2/ch.3 EOPs (not FDC ch.1 EOPs) toggle
   the flop, by tracking DACK2/DACK3 state. The gate broke the toggle
   in MAME — DACK timing relative to EOP is different from real
   hardware — so the gate was reverted. Ungated `CLK` works.

2. **BIOS side**: in `bios_hw_init.c`, override `CFG.par[1]` with
   `par[1] - 0x3F` to enable 26-row mode (the `crt26` trick from
   rc702-bios `INIT.MAC`). Pre-arm DMA ch.2 (0xF800, wc=1999) and ch.3
   (`status_line[]`, wc=79) before the 8275 reset.

3. `isr_crt` (CTC ch.2 ISR, fires at vertical retrace) re-arms both
   channels every frame and refreshes `status_line[]` content.

4. `status_line[80]` lives in BIOS BSS. The content is
   `FDD:x  RX:hh [<64-char bar>]` where `x = '*'` during floppy activity
   and `hh + bar` reflect the SIO RX ring buffer fill.

5. **Cold-boot flicker mitigations** — none of these eliminated it:
   a. Move DMA reprogram to be the *first* thing in `isr_crt` — no help.
   b. Pre-arm in `bios_hw_init` *before* the 8275 reset — no help.
   c. Re-order so DMA is programmed before the 8275 reset+reprogram — no help.
   d. Plant 8275 `0xF3 End-of-Screen-Stop-DMA` sentinel after the
      signon, hoping the screen stays blank until CCP overwrites the
      sentinel with the first `A>` prompt — works for that purpose, but
      the brief ~80 ms window when the sentinel is being placed and the
      8275 is mid-reprogram is still visibly disturbed.
   e. Throttle `status_line_update()` to every 10th frame and gate it
      behind a `boot_done` flag set just before `jump_ccp` so the buffer
      doesn't change at all during boot — no help.
   f. Enable Am9517 **rotating priority** (cmd register bit 4) so FDC
      ch.1 doesn't starve the CRT channels during the disk read for
      CCP+BDOS — no help.
   g. Memset `status_line[]` to spaces so the row 26 buffer has stable
      blank content from the very first frame — no help.

## Why the flicker is hard to remove

- Reprogramming the 8275 (mode change to 26 rows) takes 1-2 frames to
  resync, during which the rendering blanks. Unavoidable without
  programming the PROM to start in 26-row mode.
- The Am9517 priority arbitration in MAME's emulation may not match real
  hardware exactly — the rotating-priority fix that *should* let the
  CRT channels share bandwidth with the FDC didn't help in MAME, which
  may be an emulation gap rather than a real-hardware limitation.

## Remaining work if we revisit this

1. **Modify the autoload-in-c PROM** to start in 26-row mode and
   pre-arm DMA ch.2/ch.3 before the BIOS even runs. The BIOS would then
   inherit a working 26-row display and never reprogram the 8275 —
   eliminating the unavoidable mode-change blank window.
2. **Verify on real hardware**: it's possible the rotating-priority fix
   *does* eliminate the FDC-vs-CRT contention on real RC700 hardware
   and the residual flicker is purely a MAME timing gap. Worth a real
   hardware test before scrapping the dual-DMA design.
3. Alternatively, take the rc702-bios approach: single DMA channel,
   higher byte count, `0xFF` end-of-screen sentinel after the visible
   content. Requires the status row to be physically contiguous with
   the main display memory (would have to reuse the work area at
   `0xFFD0` or relocate display).

## Latent bugs found in passing

- `__asm__("...")` in `isr_enter_full` / `isr_exit_full` was missing
  `volatile`. Without `volatile`, clang's DCE could remove the asm
  after inlining, silently stripping the ISR register save/restore.
  An unrelated change to `isr_crt`'s body shifted clang's inlining
  decisions and exposed the bug. Fixed by:
  - making the asm `volatile` defensively for the SDCC build
  - making the helpers no-op stubs on the clang build path, where the
    save/restore is done by the wrappers in `clang/bios_shims.s`

- Whether or not 8275 char code `0x00` is rendered as the ü glyph or
  as blank depends on the active CRT character ROM. In MAME's emulation
  it shows as ü; some boot sequences may need the buffer pre-filled with
  spaces (`0x20`) to look "empty" instead of "ü-filled".

- Clang Z80 backend produces correct code for 64-iter byte loops with
  ternary inside the loop body (verified — the original "this is a
  codegen bug" suspicion was wrong; the real bug was the missing
  `volatile` on the ISR helpers above).
