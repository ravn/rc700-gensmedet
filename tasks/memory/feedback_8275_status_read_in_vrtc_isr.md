---
name: feedback_8275_status_read_in_vrtc_isr
description: 8275 VRTC ISR must read port 0x01 (8275 status) to de-assert interrupt — not port 0x0C (CTC ch0)
metadata:
  type: feedback
---

The 50Hz CRT vertical retrace ISR (CTC ch2) MUST read the 8275 status register
(port 0x01) as its first action after saving registers.

**Rule:** `in a, (0x01)` — NOT `in a, (0x0c)`.

**Why:** The 8275 holds its VRTC interrupt signal asserted until the CPU reads
the 8275 status register. If the ISR does not perform this read, the VRTC signal
stays high after the ISR returns. When the ISR re-arms CTC ch2 (`out (0x0e), 0xD7`
= software reset + TC follows, then `out (0x0e), 0x01`), the CTC resets and waits
for the NEXT falling edge. But if VRTC is still asserted (high), it never de-asserts
→ no falling edge → CTC ch2 never fires again → ISR never runs again → DMA ch2 is
never re-armed → display goes blank after the first pre-programmed DMA frame.

Symptom on real hardware: display shows correctly for ~20ms (one DMA frame), then
goes permanently blank, with 8275 cursor still blinking at top-left (8275 runs but
gets no character data). Identical to no-DMA behaviour.

The bug does NOT show up in MAME because MAME's 8275 emulation does not model the
VRTC signal hold behaviour accurately.

**How to apply:** Any ISR triggered by 8275 vertical retrace (CTC ch2) must start with:
```asm
ex af, af'
in a, (0x01)    ; read 8275 status register — de-asserts VRTC, enables CTC ch2 re-arm
```

Source: original ROA375 asm (`roa375/roa375.asm` DISINT function):
```asm
IN A,(CRTCOM)   ; CRTCOM = 0x01 — Read 8275 status to acknowledge interrupt
```

Fixed in commit `c090cfb` (2026-11-18). See `autoload-in-c/rom.c`
`refresh_crt_dma_50hz_interrupt`.
