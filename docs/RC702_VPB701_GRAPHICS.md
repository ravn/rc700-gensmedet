# RC702/703 VPB701 graphics card (Video Processor Board)

The RC700 colour/graphics extension is the **VPB701 "Video Processor Board"**.
Documented in **RCSL 42-i-2164 — "Video Processor board VPB701 — Graphic Manual
RC702/703"** (edition 1983.11.29, Knud Erik Hansen), datamuseum
**[Bits:30005363](https://datamuseum.dk/bits/30005363)** (54-page PDF with a text
layer).  Analysed 2026-07-02.  The user has no VPB701 hardware; goal is to model
it in MAME and run the sample programs (catalogue TODO #8).

## Architecture

- A **piggy-back board** installed internally on the RC702/703, connected to the
  Z80 **databus**.
- Graphics controller: **NEC µPD7220 GDC** (Graphic Display Controller) — a
  fixed-function display processor driven by the host Z80 via a command/parameter
  FIFO + data port.  Commands seen in the manual: `RESET`(00H), `PITCH`(47H),
  `ZOOM`(46H), `FIGD`(6CH), `GCHRD`(68H), `WDAT`(base 20H), `VSYNC`, `SYNC`, etc.
  — the standard µPD7220 command set.
- **Two display modes:**
  1. **B/W mixed graphic/character** at **560×275** on the *internal* RC702/703
     monitor — the GDC's bitmap is **merged (OR'd) with the 8275 character
     video**, so graphics overlay the normal text screen on the one monitor.
  2. **Colour 256×256 pixels** on an **external colour monitor** — multiple
     **colour planes** OR'd together, each plane individually selectable; the
     board generates the RGB/sync for the external screen.

## Modelling in MAME

MAME already has a `upd7220` device (`src/devices/video/upd7220.cpp`), so the
VPB701 is very modellable:
1. Add a `UPD7220` to the `rc702` machine config, wired to the databus at the
   VPB701's host I/O port(s) (exact port TBD — in the manual's register section;
   the GDC needs a status/param port + a data port).
2. Give it its VRAM; implement the GDC draw callback.
3. **B/W mode:** OR the GDC bitmap into the existing 8275 `display_pixels`
   output at 560×275 (a second screen-update layer).
4. **Colour mode:** a second `screen` (external colour monitor) rendering the
   256×256 colour-plane image.
5. Then boot a VPB701 sample program (see candidates below) to exercise it.

## Candidate sample programs (in the datamuseum RC700 collection)

- **Bits:30003285** — "Mikro-Logo 18/2-1983 til Piccolo **med grafikkort**"
  (Logo with graphics card — turtle graphics; the clearest VPB701 user).
- **Bits:30003947** — SW1740/D5 Mikro-Logo 1.0.
- **Bits:30003312** — "Elevopgave i styring af skildpadde" (turtle graphics).
- **Bits:30003268** — "COMAL 80 rev1.07 opgaver + Tegngenerator".

Verify which actually drive the µPD7220 (vs plain 8275 semigraphics) once the
device is stubbed in MAME.

## Firmware / ROM notes

- `roa375/rob358.mac` (the RC703 autoload source) has a conditional **COLOR CRT
  autoload variant** (`COLOR EQU 0 ;SELECT COLOR CRT AUTOLOAD VERSION`,
  `COL EQU 193 ;COLOR ATTRIBUTE`) — firmware awareness of a colour CRT.
- **Correction to the ROE114/ROE115 hypothesis** (`roa375/RC703_DIV_ROA_DISK.md`):
  the graphics coprocessor is a **µPD7220**, a fixed-function GDC with **no
  program ROM**, so ROE114/ROE115 are **not** the coprocessor's firmware.  The
  µPD7220 *can* do character display via an external character generator, so the
  two 16 KB non-Z80 ROMs *might* be the VPB701's graphics/colour char-gen — but
  that is now speculative and unconfirmed.
