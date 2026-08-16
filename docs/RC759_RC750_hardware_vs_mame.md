# RC759 Piccoline & RC750 Partner — hardware vs. MAME

Analysis of the two RC700-series 16-bit machines against MAME's driver,
sourced from the two Programmer's Guides in `docs/`:

- `PICCOLINE_Programmers_Guide_v2.pdf` (CCP/M-86 3.1, XIOS 2.3)
- `PARTNER_Programmers_Guide_v3_jun1986.pdf`

MAME driver examined: `mame/src/mame/regnecentralen/rc759.cpp`
(branch `rc759-fdc-dma-fix`, upstream Dirk Best + fork WD2797 fix).

All statements below are *verified* this session from the guide text and the
MAME source — not inferred — unless explicitly marked otherwise.

---

## 1. Hardware inventory per model

Both machines are Intel **80186**-based (2 DMA channels, 3 timers, 1 interrupt
controller all integrated on the CPU) plus an external Intel **8259A** PIC.
They share the **Intel 82730** text/CRT coprocessor and the same video model
(see §3). The peripheral sets diverge as follows.

| Peripheral | PICCOLINE (RC759) | PARTNER (RC750) |
|---|---|---|
| CPU | 80186 | 80186 |
| Extra PIC | Intel 8259A | Intel 8259A |
| CRT controller | Intel 82730 | Intel 82730 (guide OCR prints "80730") |
| Floppy controller | **WD2797** | **WD1797** |
| Serial (SIO) | via **iSBX** module (optional) | **Intel 8274** (standard) |
| SCSI | — | **SCSI bus interface** (standard) |
| Keyboard | yes | yes |
| Real-time clock | MM58167 | yes (guide: MM58167-class) |
| Sound | yes (SN76489-class) | yes |
| NVM (256×4 CMOS) | yes | yes |
| Local parallel printer | yes (Centronics) | (not in std list) |
| Cassette tape | **yes** | **—** |
| Disk/Printer-Adaptor (DPC) | yes | — |
| micronet connector | yes | — (I/O expansion connector) |
| iSBX connector | yes | I/O expansion connector |
| Arithmetic coprocessor | — | **Intel 8087** (optional, 8 MHz) |
| LAN (optional) | Intel 82586 | Intel 82586 |
| Operating system | Concurrent CP/M-86 | Concurrent DOS |

Key divergences: Partner replaces the Piccoline's cassette/DPC/micronet with a
standard **8274 serial + SCSI** and an optional **8087**; the FDC part number
differs (WD1797 vs WD2797, pin-compatible family).

---

## 2. MAME coverage

**MAME emulates only `rc759` (Piccoline). There is no RC750/Partner machine
in MAME.** So "is MAME correct?" only has an answer for the Piccoline; for the
Partner, MAME does not model it at all (would need a new driver: 8274 SIO,
SCSI, WD1797, 8087, Concurrent DOS ROMs).

### 2.1 Piccoline: device & interrupt map — MAME matches the guide

MAME instantiates: I80186 @6 MHz, PIC8259, I8255 PPI, MM58167 RTC, I82730,
64-entry PALETTE, SN76489A, CASSETTE, ISBX_SLOT, WD2797, RC759_KBD_HLE,
CENTRONICS, NVRAM. The 8259A IRQ wiring matches the guide's Appendix C
exactly:

| IRQ | Guide (App. C) | MAME |
|---|---|---|
| IR0 | Floppy controller (ext 0) | wd2797 intrq → ir0 ✓ |
| IR1 | Keyboard (ext 1) | kbd int → ir1 ✓ |
| IR3 | Real-time clock (ext 3) | mm58167 irq → ir3 ✓ |
| IR4 | CRT (ext 4) | i82730 sint → ir4 ✓ |
| IR2 | DPC interface (ext 2) | not emulated |
| IR5 | Net controller (ext 5) | not emulated |
| IR6 | Parallel interface (ext 6) | centronics (no direct ir6) |

The I/O port map (`rc759_io`) matches Appendix B: 8259A@0x00, keyboard@0x20,
sound@0x56, RTC@0x5a/0x5c, PPI@0x70-0x76, NVM@0x80-0xfe, palette@0x180-0x1be,
CRT reset@0x230, channel-attention@0x240, printer@0x250/0x260, WD2797@0x280,
floppy control/reserve@0x288-0x290, iSBX@0x300-0x330. **Verdict: the
device/port/IRQ model is accurate.**

---

## 3. Video — where MAME is incomplete (the "graphics" gap)

The guide (§4.1.2–4.5) documents the 82730 video precisely:

- **32 KB pixel memory at D000:0000H** (MAME: `map(0xd0000,0xd7fff).share("vram")` ✓).
- 16-bit character words: bits 0–9 = pixel-block address, bits 10–14 =
  palette select (alphanumeric) / 10–13 + bit 14 resolution (graphics),
  bit 15 = command flag.
- **Three modes**: alphanumeric **560×250**, high-res graphics **560×256**
  (1 bit/pixel), medium-res graphics **280×256** (2 bits/pixel).
- **32-cell palette**, each cell two 4-bit **IRGB** nibbles, written to
  0x180–0x1BE even addresses; palette-select field per character picks the
  cell. Monochrome monitor uses only the R bit.
- Mode switch: `OUT 76H,0CH` = graphics, `OUT 76H,0DH` = alphanumeric — an
  8255 BSR of **PPI port C bit 6**.

What MAME does (`txt_update_row`, `ppi_portc_w`, `palette_w`):

1. **Monochrome only.** `palette_w` correctly converts IRGB → RGB into the
   64-entry palette, but `txt_update_row` renders literal
   `rgb_t::white()/black()` and never reads `m_palette->pen()` nor the
   per-character palette-select bits. On-screen output is always B/W.
2. **Graphics mode unimplemented.** `m_gfx_mode = BIT(data,6)` captures PC6
   (matches the documented 0x76 BSR switch), but the flag is *never read* —
   only the alphanumeric character-generator path exists. High-res (560×256)
   and medium-res (280×256) bitmap modes do not render.
3. **CRT control port disabled.** `map(0x060,...crt_control_w)` is commented
   out.
4. **Crude glyph width.** Character width is guessed by scanning for a 0 bit
   ("pretty crude detection", per the source comment) instead of the
   documented 7–15-pixel variable-width mechanism.
5. **Screen geometry** (`set_raw(...,896,96,816,377,4,364)`, visible ≈720×360)
   does not match the documented 560×250/560×256. *(Unverified whether this
   is wrong in practice — the 82730 programs its own layout from the command
   block; flagged for on-screen check.)*

The upstream driver header already says so: `TODO: - Needs better I82730
emulation`.

---

## 4. Conclusions

- **Device/port/IRQ level: MAME's `rc759` is an accurate Piccoline.** Chips,
  I/O addresses, and interrupt wiring all match the Programmer's Guide.
- **Video is the gap.** To make "graphics work" the driver needs: (a) use the
  palette + per-char palette-select instead of hard-coded B/W; (b) implement
  the graphics-mode bitmap path (`m_gfx_mode`, hi/med-res); (c) likely revisit
  the glyph-width heuristic and the screen geometry. These are best verified
  visually on a real display (headless capture is unavailable here).
- **Partner (RC750) is not emulated by MAME.** A faithful RC750 would be a new
  machine: WD1797, Intel 8274 SIO, SCSI, optional 8087, Concurrent DOS ROMs —
  sharing the 80186 + 8259A + 82730 core with the Piccoline.
