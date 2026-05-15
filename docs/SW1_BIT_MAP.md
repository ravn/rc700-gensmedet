# RC702 SW1 DIP switch — bit allocation

The 8-position SW1 DIP switch is read at I/O port `0x14`.  Only bit 7
was documented in the original hardware reference (mini vs maxi
floppy).  The remaining bits are repurposed by the reconstructed
firmware in this workspace as listed below.

Convention: switch position **On** = bit reads **0**; **Off** = bit
reads **1**.  Default-zero (all switches On) gives stock-RC702
behavior wherever a switch hasn't been wired up.

| Bit  | Switch | Purpose                                       | 0 (On)                           | 1 (Off)                          | Consumer        |
|------|--------|-----------------------------------------------|----------------------------------|----------------------------------|-----------------|
| 0    | S01    | SIO-B console mode                            | local (CRT+kbd only)             | joined (+SIO-B RX/TX)            | rcbios-in-c     |
| 1    | S02    | PROM1 socket content                          | chargen ROM (ROA327)             | lineprog PROM (cpnos-in-asm)     | autoload-in-c   |
| 2    | S03    | unused                                        | -                                | -                                | -               |
| 3    | S04    | unused                                        | -                                | -                                | -               |
| 4    | S05    | unused                                        | -                                | -                                | -               |
| 5    | S06    | unused                                        | -                                | -                                | -               |
| 6    | S07    | unused                                        | -                                | -                                | -               |
| 7    | S08    | Floppy size (original-hardware bit)           | 8" maxi                          | 5.25" mini                       | autoload-in-c   |

## How autoload picks the PROM1 path

`autoload-in-c/rom.c` calls `load_chargen()` only when SW1 bit 1 is 0:

    if ((read_sw1() & 0x02) == 0) {
        load_chargen();
    }

For a stock RC702 with a ROA327 chargen ROM in the PROM1 socket, leave
S02 in the **On** position.  When swapping in the cpnos-in-asm
lineprog PROM (or any other PROM whose content is code/data rather
than font bitmaps), flip S02 to **Off** so autoload skips the font
load and the SEM702 RAM keeps whatever default state it boots into.

In MAME's `rc702` driver, S02 is labelled
`"S02 PROM1=lineprog (skip chargen)"` to remind the operator which
bit controls this.  MAME does not currently model the SEM702 (it
uses a built-in font), so the switch is a no-op in the emulator;
the gate matters only on real hardware once the SEM702 board is
present.

## Adding new bits

When wiring up another SW1 bit, update this table and the
`PORT_DIPNAME` labels in `mame/src/mame/regnecentralen/rc702.cpp` so
the MAME UI keeps documenting the contract.
