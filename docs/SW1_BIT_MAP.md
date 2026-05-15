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

**Important hardware-baseline note.**  Our current RC702 has NO
SEM702 RAM-based character generator board.  The font is in IC82
(a ROA327 ROM in the character-generator chip socket), which the
CRT reads directly.  `load_chargen()` only does anything meaningful
when a SEM702 is installed in IC82 -- on the no-SEM702 baseline its
writes to ports 0xD1/0xD2/0xD3 land nowhere observable.  So in
practice on the baseline machine SW1 bit 1 is informational only.

For the day a SEM702 is fitted: leave S02 **On** when PROM1 holds a
ROA327 font ROM image so autoload loads it into SEM702 RAM at boot.
Flip S02 to **Off** when PROM1 holds the cpnos-in-asm lineprog (or
any other code/data PROM) so autoload skips the now-misdirected
font load.

In MAME's `rc702` driver, S02 is labelled
`"S02 PROM1=lineprog (skip chargen)"` to remind the operator which
bit controls this.  MAME does not currently model the SEM702 (it
uses a built-in font), so the switch is also a no-op in the
emulator.  The gate matters only when both (a) a real SEM702 board
is fitted and (b) we choose to use it -- neither is true today.

## Adding new bits

When wiring up another SW1 bit, update this table and the
`PORT_DIPNAME` labels in `mame/src/mame/regnecentralen/rc702.cpp` so
the MAME UI keeps documenting the contract.
