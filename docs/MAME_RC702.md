# MAME RC702 Emulation Notes

## Source file
`~/git/mame/src/mame/regnecentralen/rc702.cpp` (~555 lines, original author: Robbbert, 2016)

## Build command
```sh
make SUBTARGET=regnecentralen DEBUG=1 SOURCES=src/mame/regnecentralen/rc702.cpp TOOLS=1 SYMLEVEL=3 SYMBOLS=1 OSD=sdl -j10
```
**IMPORTANT**: `OSD=sdl` is required — MAME makefile defaults to `OSD := sdl3` but SDL3 is not installed. SDL2 is installed (NOT via brew — never use brew on this machine). Without `OSD=sdl`, build fails with `'SDL3/SDL.h' file not found`.

## Machine variants
| Name | Floppy | FDC Clock | DIP S08 | Parent | Status |
|------|--------|-----------|---------|--------|--------|
| `rc702` | 8" DSDD (maxi) | 8 MHz | Off (0x00) | — | Working |
| `rc702mini` | 5.25" DD (mini) | 4 MHz | On (0x80) | rc702 | Working |
| `rc703` | 5.25" QD (80-track) | 4 MHz | On (0x80) | rc702 | Working |
| `rc703maxi` | 8" DSDD (maxi) | 8 MHz | Off (0x00) | rc702 | MACHINE_NOT_WORKING |

ROMs directory: `~/git/mame/roms/rc702/`

## Run commands
```sh
./regnecentralend rc702 -bios 0 -window -nomaximize -skip_gameinfo -resolution0 1100x805 -flop1 ~/Downloads/SW1711-I8.imd        # 8" maxi
./regnecentralend rc702mini -bios 0 -window -nomaximize -skip_gameinfo -resolution0 1100x805 -flop1 ~/Downloads/CPM_med_COMAL80.imd  # 5.25" mini
./regnecentralend rc703 -bios 1 -window -nomaximize -skip_gameinfo -resolution0 1100x805 -flop1 ~/Downloads/RC703_CPM_v2.2_r1.2.imd  # RC703
```
`-resolution0 1100x805` matches the view AR (776/568 = 1.366; 1100/1.366 = 805) so
no black bars.  The CRTC_BORDER=8 pixel amber margin is baked into the bitmap.

## Display layout
`src/mame/layout/rc702.lay` — custom layout at TRUE RC752 physical aspect.
- The RC752 (NEC JB-1201M(A)) active display area is **230 x 165 mm** (RCSL
  44-RT1981) for the 8275's 560x275 visible raster -> physical aspect
  **230:165 = 46:33 = 1.3939**, pixel aspect ratio **0.685** (pixels ~1.46x
  taller than wide).  See `RC702_HARDWARE_TECHNICAL_REFERENCE.md` "Video Monitor".
- View: **776x568**, screen fills full view (no separate bg artwork element).
- **Amber margin (CRTC_BORDER=8 px)** is baked into the screen bitmap in
  `rc702.cpp` (`screen_update_with_border` fills with palette[0] = dark amber,
  then i8275 renders at +CRTC_BORDER offset).  Renderer-independent: SDL and
  BGFX both show the correct colour.  Note: BGFX crt-geom shaders interact
  badly with the offset bitmap (pixel artefacts); use SDL/auto renderer.
- Background colour: rgb(0x4F, 0x25, 0x09) matching palette pen 0 (jbox/RC752
  dark warm-brown; foreground pen 1 is rgb(0xC4,0x9B,0x47) soft amber)
- Wired via `#include "rc702.lh"` and `config.set_default_layout(layout_rc702)` in rc702.cpp
- NOTE: `screen:snapshot()` (used by `make qr-test` / `sw1-test`) captures the
  RAW screen bitmap (square pixels, ~2:1), NOT this laid-out view; and headless
  `-aviwrite` records a reduced-resolution raw capture.  For a correct-aspect
  still, post-process the snapshot to DAR 230:165 (stretch vertical x1.46).

## What is implemented (and working)
- Z80 @ 4 MHz, 64 KB RAM
- ROM banking: PROM0 at 0x0000-0x07FF, PROM1 at 0x2000-0x27FF, disabled via port 0x18
- UPD765A FDC @ ports 0x04-0x05, DRQ->DMA ch1, INTRQ->CTC1 TRG3
- AM9517A DMA @ 0xF0-0xFF, all 4 channels wired (ch1=FDC, ch2/3=CRTC)
- I8275 CRTC, Z80CTC, Z80DART SIO, Z80PIO (keyboard only), beeper
- TTL 7474 flip-flop for video DMA gating
- Three floppy types: 8" DSDD, 5.25" DD, 5.25" QD (per variant)
- 3 ROM BIOS options: roa375.ic66 (BAD_DUMP), rob357.rom, rob358.rom
- All three variants boot CP/M successfully (MACHINE_NOT_WORKING removed)

## Automated boot test
```sh
./regnecentralend rc702mini -bios 0 -window -skip_gameinfo -nothrottle \
    -flop1 ~/Downloads/CPM_med_COMAL80.imd \
    -autoboot_delay 20 -autoboot_script path/to/mame_autoboot_dir.lua
cat /tmp/screen.txt  # should show signon + DIR listing + A> prompt
```
Script: `rcbios/mame_autoboot_dir.lua` — types DIR with 300ms key spacing,
dumps screen buffer (0xF800, 80x25) to `/tmp/screen.txt`, exits.

## What is NOT implemented
- Printer (PIO port B commented out)
- Hard disk (ports 0x60-0x67, CTC2 at 0x44-0x47)
- Real keyboard MCU (8048+2758 undumped) — uses generic keyboard
- PROM1 content (ROB388, empty)

## Known bug / root cause of floppy error
The comment "reads 0x780 bytes from the wrong sector" is caused by using
**rccpm22.imd** which has **0-based sector IDs (0-15)** — a ripping error in
the original rc700 emulator project images. The rc700 emulator never detected
this because it ignores physical sector IDs entirely (`track->sectors[R-1]`,
array index). The error was discovered later by Datamuseet (datamuseum.dk)
who produced correctly numbered images.

MAME's UPD765 uses physical sector IDs from the IMD file. The BIOS sends
READ DATA R=1 through R=16 — MAME finds sectors 1-15 (15 x 128B = 0x780
bytes) but not sector 16, then returns a disk error.

**Fix: use Datamuseum.dk IMD images (1-based sector IDs 1-16).**
Examples already on disk: CPM_med_COMAL80.imd, COMAL_v1.07_SYSTEM_RC702.imd

## IMD format in MAME
- IMD IS in default_mfm_floppy_formats (src/lib/formats/all.cpp)
- IMD loader handles per-track FM/MFM via mode byte — no custom format needed
- FM Track 0 Side 0 and MFM Track 0 Side 1 are natively supported by IMD

## UPD765 ST0 HD bit regression (CONFIRMED, FIX APPLIED)

**Root cause**: MAME commit `272ec75ca61` (cracyc, 2024-10-19) changed `seek_start()` and
`recalibrate_start()` to initialize `fi.st0 = command[1] & 7` (includes HD bit) instead of
the previous `fi.st0 = 0`. This causes Sense Interrupt Status after Seek to head 1 to return
ST0=0x24 (with HD=1), but the PROM's FLSEEK expects ST0=0x20 (SE + drive, no HD).

**Fix**: Change `command[1] & 7` -> `command[1] & 3` in both `seek_start()` and
`recalibrate_start()` in `src/devices/machine/upd765.cpp` (lines 1696 and 1712).

**Evidence**: Real NEC uPD765 does NOT set HD in ST0 for Seek (the PROM works on real RC702
hardware). The floooh/chips reference emulator also masks with `& 3`. Old MAME used `fi.st0 = 0`.

**Result**: rc702m boots CP/M with this fix. DSKAUTO succeeds on both heads, DISKBITS bit 1
(dual-sided) gets set, Side 1 MFM is read correctly, I=0xEC, EI succeeds.

**rc702 (8" maxi)**: Also fixed — needed `set_rate(500000)` for 8" drives (default is 250k).

**rc703**: Still boots (unaffected by both fixes, uses uniform MFM at 250 kbps).

**All three variants now boot CP/M successfully.**

Full investigation: `rcbios/MAME_BOOT_INVESTIGATION.md`

## FDC data rate fix (rc702.cpp)
MAME's UPD765 defaults to 250 kbps on reset. 8" drives need 500 kbps. Added to
`machine_reset()`:
```cpp
m_fdc->set_rate(BIT(ioport("DSW")->read(), 7) ? 250000 : 500000);
```
DIP S08 bit 7: clear=maxi/500k, set=mini/250k. Same pattern as imds2ioc.

## rc702.cpp remaining issues
1. Hard disk ports 0x60-0x67 and CTC2 0x44-0x47 not implemented (stub TODO)
2. DMA TC logic: `!m_eop && !m_dack1` — verify for multi-sector reads

## imd_rebase_sectors.py — sector ID rebase tool
`rcbios/imd_rebase_sectors.py` — rebases sector IDs in an IMD image (+1 by default).
Fixes 0-based images (rccpm22.imd) for MAME compatibility.
- Patches only sector number maps; copies all sector data verbatim (compressed stays compressed)
- Usage: `python3 imd_rebase_sectors.py rccpm22.imd -o rccpm22_mame.imd`
- `--info` flag: print sector map without writing
- `--delta N`: arbitrary offset (use -1 to go 1-based -> 0-based)

## rc700-vt100 build fix (macOS)
`rcterm-vt100.c` was missing a `main()` on macOS because `rc700.c` defines
`main` as `SDL_main` under `#ifdef __APPLE__` for SDL2 compatibility.
Fix added at end of `rcterm-vt100.c`:
```c
#ifdef __APPLE__
extern int SDL_main(int argc, char *argv[]);
int main(int argc, char *argv[]) { return SDL_main(argc, argv); }
#endif
```

## rc700 test automation (rc700.c)
`test_phases[]` in rc700.c drives automated test sessions via PIO Port A injection
(same as the physical intelligent keyboard's parallel interface). Each phase:
`{delay_frames, cmd, dump_label}`. Default is COMAL80 hello world test.
To revert to DIR test:
```c
static struct test_phase test_phases[] = {
  {{0, "DIR\r", NULL}, {500, NULL, "FINAL (0xF800)"}};
```
Emulator exits automatically at end of test (state 99 -> `exit(0)`).

## ROM files location
`~/git/mame/roms/rc702/` — roa375.ic66, rob357.rom, rob358.rom, roa296.rom, roa327.rom
