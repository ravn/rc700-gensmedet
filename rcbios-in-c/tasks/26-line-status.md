# 26-Line Display with Status Line

## Background

The ravn/rc702-bios assembly BIOS implements a 26th screen line by
reprogramming the Intel 8275 CRT controller. This document captures
the findings from analyzing that implementation and plans the port
to the C BIOS.

## Findings from ravn/rc702-bios

### How the 26th line is enabled

In `CDEF.MAC`, a build flag controls the feature:

    crt26  equ  yes

In `INIT.MAC`, the CRT 8275 reset sequence modifies the second
parameter byte:

```asm
LD  A,CRTreset      ; 8275 Reset command (0x00)
OUT (CRTctrl),A
LD  A,(CRT0)         ; PAR1: 0x4F → 80 chars/row
OUT (CRTdata),A
LD  A,(CRT1)         ; PAR2: 0x98 (25 rows, VRTC timing)
ifdef crt26
 sub  03fh           ; VerticalRetraceCount-1, LinesOnScreen+1
endif
OUT (CRTdata),A      ; PAR2 becomes 0x59 → 26 rows
LD  A,(CRT2)         ; PAR3: 0x7A → underline on line 7, 11 lines/cell
;ifdef crt26
; add a, 030h        ; UnderLinePlacement=+3 (commented out)
;endif
OUT (CRTdata),A
```

The commented-out `add a, 030h` would have shifted underline from
line 7 (intrudes into the descender area of g/p/q/y glyphs) to
line 10 (the bottom-most scan line of the cell, below all chargen
pixels).  User confirms (2026-06-14): this was an aesthetic
preference experiment — underline below glyphs vs. intruding on
them.  The breadcrumb survives in the source but the experiment
was reverted to the shipped configuration (line 7); both modes
work, the choice is taste.

The `SUB 0x3F` on the 8275 Parameter 2 byte achieves two effects
in one instruction:
- **High bits (7:6)**: VRTC count decremented by 1 retrace row
  (freeing scan-line budget for the extra character row)
- **Low bits (5:0)**: Row count incremented by 1 (25→26)

The value 0x98 encodes: bits 7:6 = 0b10 (V=3 retrace rows), bits 5:0 = 0x18
(24 → 24+1=25 visible rows). After SUB 0x3F: bits 7:6 = 0b01 (V=2 retrace
rows), bits 5:0 = 0x19 (25 → 25+1=26 visible rows).

The trick works because the +1 encoding of both fields aligns with the
arithmetic: `−0x40` on the V field decrements its value by 1, `+0x01` on
the R field increments it by 1, and `0x40 − 0x01 = 0x3F` is the net SUB.
Frame total scan lines is preserved (28 rows × 11 = 308 scan lines),
so vertical sync stays at 50 Hz.

### Vertical retrace budget vs the RC752 monitor's spec

The system ships with the **RC752** monochrome monitor, a vendor-
rebranded **NEC JB-1201M(A)** (RC752 Technical Manual = RCSL 44-RT1981,
included as part of `docs/RC702tech.pdf` pages ~9211-10250; also noted
in `RC702_HARDWARE_TECHNICAL_REFERENCE.md` § Video Monitor).  The
monitor's published vertical timing:

- Vertical scan: 50 Hz (20 ms/field)
- Active vertical: 17.9 ms
- → **Active vertical blanking: 2.1 ms**

8275 retrace time at 64.9 µs/line:

| Mode | V retrace rows × 11 scan lines × 64.9 µs | Total | vs RC752's 2.1 ms |
|---|---|---|---|
| 25-row (PAR2=`0x98`) | 33 × 64.9 µs | **2.142 ms** | +0.04 ms — *essentially at spec* |
| 26-row (PAR2=`0x59`) | 22 × 64.9 µs | **1.428 ms** | **−0.67 ms** — *under spec* |
| 27-row (PAR2=`0x1A`, hypothetical) | 11 × 64.9 µs | 0.714 ms | −1.4 ms — far under spec |

The original 25-row config sits **exactly at the RC752's published
blanking budget — no documented retrace margin**.  CRT26 runs the
monitor below the published 2.1 ms blanking spec.  That CRT26 works in
practice (the author shipped it) is consistent with the RC752 being a
**flexible-rate progressive video monitor in the NTSC data-terminal
tradition, locked to a 50 Hz field rate** (user, 2026-06-14) — not a
strict PAL broadcast receiver.  The spec sheet's 17.9 ms active video
period characterises the original 25-row timing; the monitor's PLL
tracks whatever the source produces, and real CRT flyback completes in
~1.0-1.4 ms regardless of spec wording.  Flexible-rate progressive
monitors of this era are *designed* to track non-broadcast line
counts, which is exactly why CRT26 works.

Hypothetical CRT27 has been considered (`SUB 0x3F` again would give
`0x1A` — V=0, R=26 → 27 visible rows + 1 retrace row) but the 0.7 ms
retrace budget is well below any realistic CRT flyback floor.  The
author of the original BIOS didn't try it; no `crt27` flag exists.

### Screen memory layout with CRT26

```
0xF800  ┌─ 25 rows × 80 cols = 2000 bytes (normal display area)
        │  Rows 0-24, addressed by CONOUT cursor logic
0xFF9F  └─
0xFFA0  ┌─ Row 25: status line (80 bytes)
0xFFEF  └─
0xFFF0     0xFF terminator byte (stops DMA feed to CRT)
```

In `CONOUT.MAC`, the DMA word count adapts:

```asm
ifdef crt26
  screensize  defl  800h-5    ; 0x7FB = 2043 bytes
else
  screensize  defl  screenlength  ; 0x7CF = 1999 bytes
endif
```

The extra bytes cover the 26th row (80 bytes) plus a 0xFF stop byte.
The 8275 interprets 0xFF as "end of row" (all-ones special code),
which terminates the DMA transfer cleanly.

### INIT.MAC screen clear covers the 26th line

```asm
LD  BC,SCREENsize     ; 910307 — Erases also the 26th line
LD  (HL),' '
LDIR
ld  (hl), 0ffh        ; Last visible screenbyte. Stops DMA feed to CRT.
call  n$statl          ; Display default status line.
```

### Status line module (STATL.MAC)

The status line is a callback-based system:

- `N$STATL` — reset to default (clock display)
- `S$STATL(hl)` — set callback to HL; update immediately
- `U$STATL(hl)` — update only if HL is the active callback

The callback function returns HL pointing to a NUL-terminated string.
STATL copies up to 39 characters to `scstat` (0xF800 + 25×80), padding
with spaces.

```asm
scstat  equ  0F800h + (25*80)   ; byte 2000 of display memory
sclen   equ  39                 ; max status line length
```

### Clock module (CLOCK.MAC)

The default status line shows date and time: `DD/MM HH:MM`.
Updated from the 50Hz CRT interrupt via BCD arithmetic (DAA).
The tick counter and clock bytes are:

```asm
cl$yy:  db  93h        ; Year (BCD)
cl$mm:  db  04h        ; Month
cl$dd:  db  19h        ; Day
cl$tim: db  0          ; Hours
cl$min: db  0          ; Minutes
cl$sec: db  0          ; Seconds
cl$tck: db  ticks      ; Tick counter (50)
```

The `tick` routine is called from `IntDisplay` (the CRT ISR) 50×/sec.

### Keyboard-activated status line (KEYINT.MAC)

The SystemRequest key (CLEAR, 0x8C) activates a mode menu on the
status line: `D)isk, L)aTeX, I)SO, N)ormal`. This allows runtime
switching between keyboard mapping modes (Danish, LaTeX, ISO-8859-1).

### DMA ISR (C.MAC IntDisplay)

The CRT ISR programs DMA ch2 every frame with `SCREENBASE` and
`SCREENSIZE`. No DMA split (ch3 word count = 0). The 26th line
is simply part of the contiguous DMA transfer.

## DMA split for separate status line buffer

### How the 8275 + Am9517A DMA split works

**Confirmed from the Intel 8275 datasheet (1984, pages 11 and 17):**

The 8275 has a **single DRQ output**. It requests characters via DMA
bursts through this one line — it does NOT have separate DMA channels
for character data and attributes. The attribute handling is internal
(FIFO-based, for transparent/non-transparent field attribute modes).

The ch2/ch3 split works because of Am9517A priority arbitration:
- Ch2 (higher priority) services DRQ first
- When ch2 reaches terminal count, the Am9517A stops servicing ch2
- Ch3 (lower priority) takes over servicing the **same DRQ line**
- The 8275 is completely unaware of the channel switch — it just
  sees characters arriving in response to its DRQ requests

The ROA375 PROM's circular-buffer scroll (roa375.asm:893-967) proves
this mechanism works in practice with the RC702 hardware.

In the circular scroll case:
- Ch2: `DSPSTR + S` to end of buffer (2000 - S bytes)
- Ch3: `DSPSTR` for wrap-around (S bytes)
- Total: 2000 bytes from two disjoint regions

### Applying the split to a 26-line status line

For 26 rows (2080 characters total), the split would be:
- **Ch2**: 2000 bytes from `DSPSTR` (0xF800) — rows 0-24
- **Ch3**: 80 bytes from `STATBUF` (a separate buffer) — row 25

The 8275 requests 26×80 = 2080 characters per frame. Ch2 serves the
first 2000 (rows 0-24). When ch2 reaches terminal count, ch3 kicks in
and serves the remaining 80 characters (the status line) from a
completely separate memory address.

### Advantages over contiguous layout

1. **Display buffer stays clean**: 0xF800-0xFF9F is exactly 2000 bytes,
   no gap, no 0xFF terminator, no risk of overwriting BSS variables
2. **Status buffer location is flexible**: can be in BSS, in the gap
   between BSS end and 0xF600, or at any fixed address
3. **No memory conflict**: in the original assembly BIOS, the contiguous
   approach is hard-constrained by `CLOCKADDR`/`CLOCKLOW`/`CLOCKHIGH` at
   `0xFFFA..0xFFFF` (user, 2026-06-14).  A full 26 × 80 = 2080-byte
   display from `0xF800` would land directly on top of the clock
   variables.  The `0xFF` stop code at the buffer tail isn't a stylistic
   choice — it's the *only* way to fit any 26th-row content without
   overwriting the clock.  `screensize = 2043` gives 25 full rows + ~43
   chars of partial 26th row + the stop code, which is what `CONOUT.MAC:10`
   literally calls "25 1/2 line" — half a status row visible.  The DMA-split
   design separates the status buffer entirely, freeing it from the
   high-memory layout constraint.
4. **Compatible with circular scroll**: if we later implement zero-copy
   scrolling, ch2 handles the circular split and ch3 still provides
   the status line (would need 3-way split — see below)

### Three-way split for scroll + status line (future)

If both circular scroll and status line are wanted, we need three
segments but only have two DMA channels. Options:

a. **Copy the status line into display memory** at the scroll boundary.
   Ch2 serves [S..1999], ch3 serves [0..S-1] + status line (contiguous
   if status line is placed right after the wrap-around region).
   Complication: status line must move with S.

b. **Use 0xFF terminator** after row 24 to stop ch2 early, then ch3
   serves the status line from a separate buffer.
   Problem: 0xFF also terminates DMA mid-row, not at the end of 2000.
   Need to verify 8275 behavior with 0xFF in this context.

c. **Abandon circular scroll** for the status line variant.
   Use memcpy_z80 scroll (current) + DMA-split status line.
   Simplest and already fast enough (memcpy_z80 with 16×LDI).

Decision: start with option (c). Circular scroll is a separate
optimization and can be added later if needed.

### Memory map with DMA-split status line

```
0xDA00  BIOS JP table + JTVARS
0xDA71  BIOS code (.text)
  ...   BIOS rodata, data
  ...   BIOS BSS
        [gap]
0xF600  IVT (interrupt vector table, page-aligned)
        Interrupt stack (grows DOWN from 0xF600)
0xF680  OUTCON/INCONV tables (384 bytes)
0xF800  Display memory: 25 rows × 80 cols (2000 bytes)
0xFF9F  End of display (unchanged, clean 2000-byte boundary)

Status line buffer: 80 bytes in BSS (e.g. statbuf[80])
```

The status line buffer lives in BSS alongside other BIOS variables.
It's written by the status line driver and read by DMA ch3 at 50Hz.
No fixed address needed — the ISR programs ch3 with the buffer address.

### Current C BIOS state

- `bios.h`: `Display[25]` = 25 rows, `SCRN_SIZE` = 2000
- `boot_confi.c`: `par2 = 0x98` (25 rows, standard)
- `bios_hw_init.c:202`: `port_out(crt_param, CFG.par2)` — writes par2 unmodified
- `bios.c isr_crt()`: DMA ch2 word count = `SCRN_SIZE - 1` = 1999,
  ch3 word count = 0 (attributes disabled)
- `hal.h`: `DMA_CH_DISPLAY = 2`, `DMA_CH_DISATTR = 3`
- `hal.h`: `hal_dma_atr_wc(w)` macro exists but only sets word count
  (no `hal_dma_atr_addr` macro — needs adding)
- No status line, no clock display, no 26th line

## Implementation Plan

### Phase 1: CRT26 + DMA split — enable the 26th line

**Goal**: Display 26 rows with the status line in a separate BSS buffer,
fed by DMA ch3 while ch2 serves the normal 25-row display.

1. **Add `CRT26` build flag** to Makefile (`-DCRT26`)
   - Both clang and SDCC variants

2. **Modify CRT init** in `bios_hw_init.c`:
   ```c
   #ifdef CRT26
       port_out(crt_param, CFG.par2 - 0x3F);  /* 26 rows */
   #else
       port_out(crt_param, CFG.par2);          /* 25 rows */
   #endif
   ```

3. **Add status line buffer** in `bios.c` (BSS):
   ```c
   #ifdef CRT26
   static byte statbuf[80];  /* status line content, DMA ch3 source */
   #define STAT_LEN  39      /* max status string length */
   #endif
   ```

4. **Add `hal_dma_atr_addr` macro** in `hal.h`:
   ```c
   #define hal_dma_atr_addr(a) do { \
       port_out(dma_atr_addr,(uint8_t)(a)); \
       port_out(dma_atr_addr,(uint8_t)((a)>>8)); \
   } while(0)
   ```

5. **Rename ch3 from "attributes" to "status"** in `hal.h`:
   ```c
   #ifdef CRT26
   #define DMA_CH_STATUS  3  /* status line (replaces attributes) */
   #else
   #define DMA_CH_DISATTR 3  /* 8275 display attributes (unused) */
   #endif
   ```
   Or keep DISATTR and repurpose it — both work.

6. **Update isr_crt** in `bios.c`:
   ```c
   /* Ch2: 25 rows of normal display */
   hal_dma_dsp_addr(DSPSTR);
   hal_dma_dsp_wc(SCRN_SIZE - 1);   /* 1999 */

   #ifdef CRT26
   /* Ch3: status line from separate buffer */
   hal_dma_atr_addr((word)statbuf);
   hal_dma_atr_wc(SCRN_COLS - 1);   /* 79 */
   #else
   hal_dma_atr_wc(0);               /* no attributes */
   #endif
   ```

7. **Init: clear status buffer** in `bios_hw_init.c`:
   ```c
   #ifdef CRT26
   memset(statbuf, ' ', sizeof(statbuf));
   #endif
   ```

8. **DMA mode for ch3**: currently set to `DMA_MODE_MEM2IO(3)` in
   `bios_hw_init.c`. This is correct — ch3 reads from memory and
   writes to I/O (the 8275). No change needed.

9. **CONOUT stays 25 rows**: cursor addressing, scroll, insert/delete
   all remain bounded to rows 0-24. The 26th line is ISR-managed only.

Files: `bios.h`, `hal.h`, `bios_hw_init.c`, `bios.c`,
`Makefile`, `clang/Makefile`, `sdcc/Makefile`

### Phase 2: Status line driver

**Goal**: Callback-based status line, matching the assembly BIOS design.

1. **Status line API** (in `bios.h`):
   ```c
   typedef const char *(*statline_fn)(void);
   void statline_set(statline_fn fn);    /* S$STATL */
   void statline_update(statline_fn fn); /* U$STATL */
   void statline_reset(void);            /* N$STATL */
   ```

2. **Status line rendering** (in `bios.c`):
   - Copy up to `STAT_LEN` bytes from callback string to `statbuf`
   - Pad remainder with spaces
   - Called from `isr_crt` every second (not every frame — no need
     to re-render 50×/sec when content changes at most 1×/sec)

3. **Default status line**: show a simple clock (HH:MM) derived from
   the existing `rtc0` counter (already incremented 50×/sec in isr_crt).
   - BCD encoding not needed — can use integer division
   - Format: `DD/MM HH:MM` or simpler `HH:MM`

Files: `bios.h`, `bios.c`

### Phase 3: Interactive status line (optional, later)

- SystemRequest key triggers status line menu
- Disk status display (current drive, track)
- Keyboard mode switching

This phase matches the full ravn/rc702-bios feature set but is not
essential for the initial implementation.

## Verification

1. Build with `-DCRT26` for both clang and SDCC
2. MAME boot: verify 26th line visible, status line shows clock
3. Verify status line content is correct (spaces initially, clock later)
4. CONOUT regression: cursor addressing, scroll, insert/delete line
   must all work correctly within the 25-row area
5. Screen clear (^L) must clear rows 0-24 and reset status line
6. No display corruption at row 25/26 boundary
7. Verify DMA ch3 is correctly programming from BSS buffer address
8. Binary size impact: should be small (< 80 bytes for phase 1)

## Open questions

1. **Ch3 address register**: the current `hal_dma_atr_wc` macro only
   sets word count. We need `hal_dma_atr_addr` to set the base address.
   Does the assembly BIOS set ch3 address? Yes — roa375.asm:960-964
   programs ch3 address for circular scroll. The C BIOS currently
   doesn't because ch3 is "disabled" (wc=0). Adding the macro is
   straightforward.

2. **DMA mode register**: ch3 is currently initialized as
   `DMA_MODE_MEM2IO(3)` = single mode, memory→I/O read, channel 3.
   This is correct for feeding the 8275. No change needed.

3. **0xFF terminator**: with the DMA split, ch2 serves exactly 2000
   bytes and ch3 serves exactly 80 bytes. The 8275 gets exactly 2080
   characters — no 0xFF terminator needed. The terminal count on both
   channels ensures clean cutoff.

4. **Attribute mode**: the 8275 handles field attributes internally
   via its FIFO buffers — they are NOT fed by a separate DMA channel.
   Ch3 in the RC702 is wired to the same DRQ as ch2 (the 8275's
   single DMA request line). The BIOS labels ch3 "display attributes"
   but it actually serves as a secondary character data channel that
   kicks in after ch2 reaches terminal count. Setting ch3 wc=0
   effectively disables it. Repurposing ch3 for the status line is
   the intended use of this Am9517A priority mechanism — confirmed
   by the ROA375 PROM's circular scroll and the 8275 datasheet.

5. **ISR cost**: programming ch3 address + word count adds ~8 port
   writes (4 for address, 4 for word count including clear-byte-pointer).
   At 11T per OUT, that's ~88T extra per frame = ~4400T/sec at 50Hz.
   Negligible (0.1% CPU at 4MHz).

## 8275 Reset Command Parameter Reference (from datasheet p.17)

Screen Composition bytes 1-4 follow the Reset command (0x00 to cmd port):

```
Byte 1: S HHHHHHH     S=spaced rows, H=chars/row - 1 (0..79)
Byte 2: VV RRRRRR     V=VRTC row count (0-3 → 1-4), R=rows/frame - 1 (0..63)
Byte 3: UUUU LLLL     U=underline line# (0-15), L=lines/char row - 1 (0..15)
Byte 4: MF CC ZZZZ    M=line counter mode, F=field attr mode,
                       C=cursor (00=blink rev, 01=blink uline,
                                 10=steady rev, 11=steady uline)
                       Z=H retrace count - 2 (encoded)
```

RC702 defaults: `0x4F 0x98 0x7A 0x6D`
- 0x4F: S=0, H=79 → 80 chars/row
- 0x98: V=0b10(=3 VRTC rows), R=0x18(=24) → 25 rows/frame
- 0x7A: U=0x7(=line 7 underline), L=0xA(=10) → 10+2=12? (check)
- 0x6D: M=0, F=1(non-transparent), C=0b10(steady rev block),
        Z=0xD → H retrace

CRT26 modification: `0x98 - 0x3F = 0x59`
- 0x59: V=0b01(=2 VRTC rows), R=0x19(=25) → 26 rows/frame
- Reduces VRTC by 1 row and adds 1 display row simultaneously

Special control codes (character data with MSB=1, bit6=1):
- 0b1100xxxx: End of Row (VSP to end of line)
- 0b1101xxxx: End of Row + Stop DMA
- 0b1110xxxx: End of Screen (VSP to end of frame)
- 0b1111xxxx: End of Screen + Stop DMA

## References

- ravn/rc702-bios: `CDEF.MAC` (crt26 flag), `INIT.MAC` (CRT init),
  `CONOUT.MAC` (screensize), `C.MAC` (IntDisplay ISR),
  `STATL.MAC` (status line driver), `CLOCK.MAC` (clock display),
  `KEYINT.MAC` (keyboard menu)
- roa375/roa375.asm:893-967 — circular-buffer DMA split (ch2+ch3
  feeding 8275 from two disjoint memory regions, proves the mechanism)
- Intel 8275 datasheet: Reset command parameter encoding
- Am9517A / Intel 8237 DMA: channel priority, terminal count behavior
- C BIOS: `bios.h` (ConfiBlock.par2), `hal.h` (DMA macros),
  `bios_hw_init.c` (CRT init, DMA mode), `bios.c` (isr_crt DMA),
  `boot_confi.c` (default par2=0x98)
