# Drop per-VRTC DMA reprogram from isr_crt — rely on 8237 autoinit

Status: planned, not started.

## Idea

`isr_crt` in `src/transport_pio.c:277` reprograms 8237 DMA channel 2
(display source addr + word count) AND channel 3 (attribute WC = 0)
on every VRTC interrupt (~50 Hz).  This is redundant: `init.c:218-229`
sets the 8237 mode register to `0x58 | 2 = 0x5A`, which has the
autoinit bit set (bit 4 = 1) -- the 8237 reloads its own base addr
and word count at terminal count.  No software reprogram is required
to keep the display refreshed.

Reference implementation: `cpnos-in-asm/src/prom1.asm:438-446` does
the same DMA setup once at slave_entry (`PORT_DMA_MODE, 0x5A`,
single mem->IO autoinit, ch=2), disables CTC ch2 IRQ entirely
(no isr_crt analogue), and runs to PolyPascal PASS + CONOTEST PASS
+ full netboot.  Empirical proof the autoinit works on RC702 / MAME.

## What stays in isr_crt

The ISR still has work that must run per-VRTC:

  - **Frame counter** (4 bytes at 0xFFFC..0xFFFF, RTC).  Used by the
    file-I/O bench + MAME taps as the "did the CRT ISR fire" probe.
  - **CRT status ACK** (`IN A, (0x01)`).  Required to clear the
    8275's pending-interrupt flag; without it the ISR re-fires on
    the same condition.
  - **CTC ch2 re-arm** (`OUT (0x0E), 0xD7` + `OUT (0x0E), 1`).
    CTC ch2 generates the VRTC IRQ; needs re-arming each frame.
  - **Deferred cursor sync** (the `_cur_dirty` block at lines
    348-360 of transport_pio.c).  Mainline conout sets the flag;
    the ISR (or impl_conin via this session's
    `sync_cursor_if_dirty` helper) writes the 8275 cursor regs.

## What can be removed

Lines 308-340 of `transport_pio.c` -- everything between the CRT
status ACK and the CTC re-arm:

  - Mask DMA channels 2 + 3 (2 OUTs)
  - XOR A + clear flip-flop OUT (2 instructions, 1 OUT)
  - DMA ch2 ADDR low + high (3 instructions, 2 OUTs)
  - DMA ch2 WC low + high (4 instructions, 2 OUTs)
  - DMA ch3 WC zero, zero (3 instructions, 2 OUTs)
  - Unmask channels 2 + 3 (4 instructions, 2 OUTs)

About 22 instructions / ~60 B of inline asm in transport_pio.c's
`isr_crt` body.  Source-level removal; binary saving slightly less
after the rest of the ISR re-shuffles around it.

## Expected savings

  - Resident PROM1 footprint: ~50-60 B raw, ~30-40 B after ZX0
    (compressed savings smaller because the OUT sequence compresses
    well).  At today's 1931 / 2048 B = 117 B free in PROM1, the
    extra room is welcome but not critical -- the autoinit drop is
    primarily a correctness/elegance fix.
  - T-states per VRTC: ~200 T saved (22 instructions × ~9 T avg).
    At 50 Hz that's 10 kT/s out of ~4 MHz -- negligible runtime
    impact, but the simplification matters for code clarity.
  - Removes a divergence between cpnos-in-c and cpnos-in-asm: both
    will use the same hardware contract.

## Steps

1.  Delete lines 308-340 of `src/transport_pio.c` (between CRT ACK
    and CTC re-arm).
2.  Confirm `init.c` mode-register setup at `PORT_DMA_MODE = 0x5A`
    (already correct).  Also confirm CLBP / ADDR / WC are programmed
    ONCE at init -- they currently are (lines 220-225).
3.  Rebuild cpnos-in-c via `make COMPILER=clang` and via the
    `prom1-lineprog` target.
4.  Verify visually in MAME: display refreshes correctly, no flicker
    or stale rows.  Test for at least 60 seconds to catch slow drift.
5.  4-cell value oracle (clang × {PIO, SIO}, SDCC × {PIO, SIO}) per
    memory rule `feedback_value_oracle_all_transport_cells`.
6.  Cross-check: same change against cpnos-rom-historical / any other
    branch carrying a similar ISR.

## Risk

Low.  cpnos-in-asm has been running with autoinit-only DMA since
session 73e (2026-05-15) with no display issues across:

  - phase 2a SIO-B banner stream
  - phases 3a/3b/3c/3d CP/NET 1.2 wire-up
  - phase 3e/3g/4a LOGIN + full netboot
  - PolyPascal PASS (PPAS + PRIMES.PAS + 29989)
  - CONOTEST.COM stress test
  - This session's hand-driven interactive boot to E>

If something does go wrong, symptom would be display freezing on one
frame's contents (no refresh) or display going blank (DMA never
fires).  Easy to diagnose visually.

## When this should land

Low priority.  cpnos-in-c PROM1-only fits comfortably today; this
is cleanup / correctness, not a fit problem.  Defer until next time
someone is in transport_pio.c for another reason, OR bundle with
the SDCC × SIO value-oracle work for the prom1-lineprog target
(both touch the same files and want the same 4-cell verification).
