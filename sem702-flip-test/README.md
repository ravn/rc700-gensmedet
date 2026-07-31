# SEM702 flip test

End-to-end proof that MAME's `rc702sem702` SEM702 RAM character generator
works: the `0xD1`/`0xD2`/`0xD3` write path reaches `m_sem702_ram`, and
`display_pixels` reads it live every frame.

## How it works

`flip_test.c` (CP/M `.COM`, built with z88dk `+cpm`):

1. Loads the **ROA296 letter font** (`font296.h`, extracted from `roa296.rom`)
   into the SEM702 RAM via ports `0xD1`/`0xD2`/`0xD3`.
2. Switches the console to **semigraphics mode** with BIOS control code `0x84`
   (the RC700 BIOS keeps a sticky graphics-mode flag; `0x80` switches back), so
   the following characters are rendered from the SEM702 (`GPA0=1`) instead of
   the ROA296 ROM.  Prints the alphabet + digits.
3. Reprograms the SEM702 with the **same font flipped top-to-bottom**.

Because the display re-renders from `m_sem702_ram` every frame, the
already-printed characters flip in place without touching display RAM.

The program writes a phase marker to `0xBF00` (1 = printed, 2 = flipped) so
`flip_test.lua` snapshots at the right moments.

## Result

- `snap/sem702_A_normal.png` -- alphabet upright.
- `snap/sem702_B_flipped.png` -- same characters upside-down, while the CP/M
  banner (rendered via the ROA296 ROM, `GPA0=0`) stays upright.

The banner staying upright while the semigraphics text flips confirms the
`GPA0` selection and the SEM702 path are both correct.

## Run

    make run

Requires the rc702 ROMs in `../../mame/roms/rc702/`, a built `../../mame/mame`,
z88dk in `../../z88dk`, and `cpmtools` (`cpmcp`) with the `rc702-8dd` diskdef
from `../rcbios/diskdefs`.
