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

`autoload-in-c/rom.c` calls `define_sextants()` unconditionally on
every boot.  The function programs a 64-glyph 2x3-block subset into
the SEM702 RAM at the same codepoints they occupy in ROA327
(0x20..0x3F + 0x60..0x7F); non-sextant codepoints are blanked.  No
SW1 gate -- a real ROA327 ROM in IC82 simply ignores the writes to
ports 0xD1/0xD2/0xD3, so the call is a safe no-op on baseline
hardware.  The PROM1->SEM702 font-loading path (formerly
`load_chargen()`) has been removed.

S02 is therefore no longer overloaded with a chargen meaning.  It
remains the PROM1-content selector for autoload's signature check:
when PROM1 holds a lineprog (e.g. cpnos-in-asm slave), set S02 to
the corresponding side; when PROM1 is empty / a chargen ROA327
image, leave it on the no-lineprog side.  The label in MAME's
`rc702_maxi` / `rc702_mini` input ports still reads
`"S02 PROM1=lineprog (skip chargen)"` for historical clarity.

MAME models the SEM702 in machine `rc702sem702` (see
`mame/src/mame/regnecentralen/rc702.cpp`).  Boot that variant when
you want to exercise the same display path as the user's physical
SEM702-equipped RC702.  Baseline `rc702` still uses the ROA327 ROM
at IC82 and is unaffected by this change.

## Adding new bits

When wiring up another SW1 bit, update this table and the
`PORT_DIPNAME` labels in `mame/src/mame/regnecentralen/rc702.cpp` so
the MAME UI keeps documenting the contract.
