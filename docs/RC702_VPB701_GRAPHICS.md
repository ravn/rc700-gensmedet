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
- **Host I/O ports (confirmed by disassembly, see below): `0xC8` and `0xC9`.**
  `0xC8` = the GDC **parameter/data** register **and** the **status** register
  (`IN A,(0C8h)`); bit 1 (`0x02`) is the µPD7220 "FIFO full" flag — the driver
  polls it and waits for it to clear before every write.  `0xC9` = the GDC
  **command** register.  So a GDC operation is: poll `0xC8` until bit 1 = 0,
  `OUT (0C8h),A` per parameter byte, then `OUT (0C9h),A` for the command.
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
   VPB701's host I/O ports **`0xC8` (param/data + status) and `0xC9` (command)**
   (confirmed from the HOEJDXY driver disassembly, below).
2. Give it its VRAM; implement the GDC draw callback.
3. **B/W mode:** OR the GDC bitmap into the existing 8275 `display_pixels`
   output at 560×275 (a second screen-update layer).
4. **Colour mode:** a second `screen` (external colour monitor) rendering the
   256×256 colour-plane image.
5. Then boot a VPB701 sample program (see candidates below) to exercise it.

### Two screens in MAME

MAME supports multiple `screen_device`s in one machine, which maps naturally
onto the VPB701's two output paths.  The two modes want **different** treatment:

- **B/W mode = one screen, two layers.**  The GDC bitmap is *merged (OR'd)* with
  the 8275 character video on the **same** internal RC752 monitor.  So this is
  **not** a second screen — it is a second *layer* composited into the existing
  `"screen"`.  Implementation: in the rc702 screen-update, draw the 8275 output
  as today, then OR the 560×275 GDC bitmap on top (both are 1-bpp; a pixel is lit
  if either source is lit).  No new `screen_device` needed for this mode.

- **Colour mode = a genuine second screen.**  The 256×256 colour image goes to a
  *physically separate* external colour monitor, so model it as a second
  `screen_device`:
  ```cpp
  SCREEN(config, "screen",  SCREEN_TYPE_RASTER);   // internal RC752 (8275 + B/W GDC merge)
  SCREEN(config, "screen2", SCREEN_TYPE_RASTER);   // external VPB701 colour monitor
  screen2.set_size(256, 256);
  screen2.set_screen_update(FUNC(rc702_state::screen_update_vpb701_colour));
  ```
  The `upd7220` device drives whichever is active for the current mode; give the
  colour path its own palette (OR'd colour planes → index into an RGB palette).

- **Layout / how the user sees both.**  MAME shows multiple screens either side
  by side in one window or in separate windows (`-video bgfx` / multi-window;
  Tab-menu / hotkeys switch focus).  The `rc702.lay` we already maintain would
  gain a two-screen view: `<screen index="0">` (internal) alongside
  `<screen index="1">` (external colour), each with its own `<bounds>`.  A
  single-screen view for index 0 can stay the default so nothing changes for
  users without the card.

This is standard MAME (many drivers ship dual-screen: dual-monitor arcade PCBs,
handhelds with a sub-LCD, etc.), so the two-screen part is low-risk; the real
work is the GDC draw callback and the B/W OR-merge.

## Candidate sample programs (in the datamuseum RC700 collection)

- **Bits:30003285** — "Mikro-Logo 18/2-1983 til Piccolo **med grafikkort**"
  (Logo with graphics card — turtle graphics; the clearest VPB701 user).
- **Bits:30003947** — SW1740/D5 Mikro-Logo 1.0.  Disk holds two variants:
  `HOEJBEG/HOEJDXY.COM` (**høj**opløsning = **VPB701**) and `SEMIBEG/SEMIDXY.COM`
  (semigraphics = plain 8275).  **`HOEJDXY.COM` VPB701 use is now confirmed** — see
  the driver disassembly below.
- **Bits:30003312** — "Elevopgave i styring af skildpadde" (turtle graphics),
  explicitly *"skrevet i PolyPascal"*.  Single `.COM`, card use not yet confirmed.
- **Bits:30003268** — "COMAL 80 rev1.07 opgaver + Tegngenerator".  **Confirmed NOT
  a VPB701 user** — it is the SEM702 RAM char-generator, not the graphics card
  (analysis below).

## Confirmed VPB701 user: SW1740 Mikro-Logo `HOEJDXY.COM` (2026-07-02)

`HOEJDXY.COM` (Bits:30003947, extracted via cpmtools; CP/M dir at raw-offset
`0x3C00`, `boottrk 2` on the data area) is **native Z80** (`C3` jump at entry
`0x100`→`0x1DC5`), i.e. compiled by a **native-code Pascal** — consistent with
**PolyPascal/COMPAS** (the sibling turtle disk 30003312 is explicitly PolyPascal;
the only runtime string is `" ERROR "`, the PolyPascal runtime error format).  It
is **not** UCSD p-code (which would need the p-System loader, as the *separate*
30003285 "Mikro-Logo med grafikkort" UCSD distribution does).

A recursive-descent reachability trace (only ~15 KB of the 32 KB `.COM` is code;
the rest is graphics data) found the graphics driver — a textbook µPD7220 GDC
sequence:

```
sub_237Ah (write GDC COMMAND)        sub_2386h (write GDC PARAM/DATA)
  in a,(0C8h)   ; read status          in a,(0C8h)   ; read status  (port 0xC8)
  and 02h       ; FIFO-full bit         and 02h
  jp nz,-       ; wait until clear      jp nz,-
  out (0C9h),a  ; command  (port 0xC9)  out (0C8h),a  ; data     (port 0xC8)
  ret                                   ret
```

The caller at `0x2354` pushes drawing parameters via `sub_2386h`, then issues
`LD A,06Ch` (**FIGD** = draw-figure) via `sub_237Ah` — exactly the manual's GDC
command.  This pins the VPB701 host ports (`0xC8` param/data+status, `0xC9`
command) used in the MAME-modelling section above.

### What the "graphics data" in the binary actually is

`HOEJDXY.COM` is 32 KB, of which the reachability trace marks ~15 KB as code.  The
other ~17 KB is **not** pixel/bitmap graphics — it is **unreached native code**
(PolyPascal reaches many routines through indirect dispatch the linear tracer
can't follow — the two largest "high-entropy" blocks at `0x0C23` and `0x0F3D`
contain 43 and 36 `CALL` opcodes) plus the interpreter's **Danish text-message
tables**.  The turtle drawings are rendered as **GDC vector figures** (FIGD /
lines), not stored bitmaps, so there is very little actual graphics data in the
file.  (User drawings are saved separately as `.LOG` files — none are on this
distribution disk, which carries only the interpreter.)

Decoding the strings (RC700 national charset `[\]{|}` → `ÆØÅæøå`) shows a complete
**Danish Logo interpreter**:

- **Identity:** `Mikro-Logo ver. 01/03/84HP.` (version dated 1984-03-01, author
  initials "HP"); machine banner `RC-702 Piccolo, RC-855`.
- **Runtime = PolyPascal/COMPAS:** the error epilogue `USER INTERRUPT` /
  `EXECUTION` / ` ERROR ` / ` AT PC=` / `Program terminated` is the exact COMPAS
  runtime signature — corroborating the native-code / not-UCSD finding.
- **Logo language (Danish):** procedure def `TIL … SLUTTIL`, control
  `hertil`/`ellers`/`sluthvis`, `løkke` (loop), primitives `sætxy`, `udport`;
  error tables ("Navn eller tal mangler", "Højre-parentes mangler", "Division
  med 0", "Parameterstak fuld", "SÆTNING/TIL ikke tilladt", …).
- **Output devices:** the VPB701 is referred to as *"Grafik-enheden"* — the menu
  toggles `Grafik-enheden er tændt/slukket` ("graphics unit on/off").  Also a
  **Roland DXY-800** plotter (terminal port) and an **OKI 82A/80A** printer.
- **`HOEJDXY.000`** (6912 B) is a **second native-code overlay** (`JP 0x33D1` at
  entry, 596 `CALL`s) — the editor / menu / disk-file segment: `.LOG` file
  handling, a Logo-VM cell inspector (`Værdi Nr Kommando Pstakp`), and the
  interpreter's internal pointers (`konnummer`, `parapeger`, `frinummer`,
  `procx`, `procy`, `stakp`, `tekstpt`, `lager`).

## Source code for Mikro-Logo — searched, not found online (2026-07-02)

There is **no source text** for `HOEJBEG`/`HOEJDXY` on the disk (only the compiled
`.COM` + `.000` overlay files), and none was found elsewhere online.  The DDHF wiki
[Mikro-Logo](https://datamuseum.dk/wiki/Mikro-Logo) page preserves only the
**user guide** (PDF, April 1985) and **compiled software v1.1** (rc700.dk) — no
`kildekode`.  Mikro-Logo was released June 1984 for Piccolo/Piccoline (a
parenthesis-free turtle-graphics Logo, akin to Myresnak).  So the recoverable
form is the native PolyPascal `.COM`; the graphics driver is understood by
disassembly (above), not from source.

## COMAL 80 disk (Bits:30003268) — SEM702 char-gen, NOT VPB701 (2026-07-02)

Analysed to settle whether its "Tegngenerator" drives the graphics card.  It does
**not** — it is the **SEM702 RAM character generator** (user-definable glyphs),
a different mechanism from the VPB701's µPD7220 bitmap.  Evidence:

- **Port scan of the whole disk image: zero VPB701 GDC accesses** — no
  `IN A,(0C8h)` / `OUT (0C8h),A` / `OUT (0C9h),A` anywhere (vs the HOEJDXY driver
  which is full of them).
- **`DIVERSE.CHR` and `HESTE.CHR` are each exactly 2.0 KB = 256 glyphs × 8
  bytes** — a complete SEM702 character-generator RAM image.  `TEGNGEN.PRG`
  (14.5 KB) is the char-set **editor**; `CHRHENT.EXT` is the COMAL external that
  loads a `.CHR` into the char-gen; `TEGNLOGO` a demo.
- Disk contents (51 files, CP/M dir at raw offset `0x5D80`): the RcComal80
  `SYSTEM` (13 KB), the char-gen toolset above, and a set of COMAL exercise/example
  sources (`opgaveNN`, `eksN.N`, `turtle.eks`, `quicksort`, `horner`, `cardano`,
  `funktion`) — plain COMAL text/tokenised programs, no graphics-card code.

So 30003268 is a **RcComal80 education disk using SEM702 custom characters** for
its "graphics", and is off the VPB701 modelling path.  (SEM702 is separately
modelled in MAME as the `rc702sem702` machine — see the workspace `CLAUDE.md`.)

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
