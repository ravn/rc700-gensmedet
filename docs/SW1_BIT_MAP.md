# RC702 SW1 DIP switch — bit allocation

The 8-position SW1 DIP switch is read at I/O port `0x14`.  Only bit 7
was documented in the original hardware reference (mini vs maxi
floppy).  The remaining bits are repurposed by the reconstructed
firmware in this workspace as listed below.

Convention: switch position **On** = bit reads **0**; **Off** = bit
reads **1**.  Default-zero (all switches On) gives stock-RC702
behavior wherever a switch hasn't been wired up.

| Bit  | Switch | Purpose                                       | 0 (On, default)                       | 1 (Off)                              | Consumer            |
|------|--------|-----------------------------------------------|---------------------------------------|--------------------------------------|---------------------|
| 0    | S01    | Console mode                                  | joined (SIO-B+kbd in, SIO-B+CRT out)  | local (CRT+kbd only)                 | rcbios-in-c, cpnos-in-c |
| 1    | S02    | PROM1 lineprog enable                         | check PROM1 sig; jump if present      | skip check; halt NO DISKETTE-NOR-LINEPROG | autoload-in-c       |
| 2    | S03    | CP/NOS transport (PROM1-only lineprog build)  | PIO (Z80-PIO Mode 1, IRQ + 256 B ring) | SIO (SIO-A async 38400 polled)        | cpnos-in-c          |
| 3    | S04    | unused                                        | -                                     | -                                    | -                   |
| 4    | S05    | unused                                        | -                                     | -                                    | -                   |
| 5    | S06    | unused                                        | -                                     | -                                    | -                   |
| 6    | S07    | unused                                        | -                                     | -                                    | -                   |
| 7    | S08    | Floppy size (original-hardware bit)           | 8" maxi (500 kbps FDC)                | 5.25" mini (250 kbps FDC)            | autoload-in-c, MAME |

## Bit 0 -- console mode (rcbios + cpnos)

Spec finalised 2026-05-17:

- **On** (bit=0, default): joined console.  Both keyboard and SIO-B
  provide input to the CCP / BDOS; both CRT and SIO-B receive every
  output byte.  SIO-B writes go into the void if nothing is connected
  on the other end -- harmless.  Use a serial cable + terminal program
  on the host side to log slave output and inject commands.

- **Off** (bit=1): local-only console.  SIO-B is ignored on both
  input and output; only CRT + keyboard are active.

Implementations:

- rcbios-in-c: `bios.c` cold-boot picks `IOBYTE_CON_JOINED` (UC1) or
  `IOBYTE_CON_LOCAL` based on the bit at boot.  IOBYTE can still be
  changed later with `STAT CON:=...`.
- cpnos-in-c: `cpnos_cold_entry()` (init.c) samples the bit and stores
  it in `console_joined` (resident.c BSS); `impl_conin` skips the
  SIO-B poll when 0, `impl_conout` skips the SIO-B mirror when 0.
  Compile-time `MIRROR_SIOB=0` removes the SIO-B output code path
  entirely (operates as if bit was always Off).

The previous mapping (before 2026-05-17) was inverted in rcbios:
bit=1 meant JOINED and bit=0 meant LOCAL.  That was opposite to the
"default = stock behaviour" convention used for the other bits.

## Bit 1 -- PROM1 lineprog enable (autoload only)

Spec finalised 2026-05-17 (option B of the bit-1 question):

- **On** (bit=0, default): `prom1_if_present()` checks the PROM1
  signature (` RC702` at offset 0x2002).  If present, autoload JMPs
  to the lineprog at 0x2000 (e.g. cpnos slave).
- **Off** (bit=1): `prom1_if_present()` skips the signature check
  entirely and halts with `** NO DISKETTE NOR LINEPROG **`.

Use Off to lock out the PROM1 fallback at boot without physically
pulling the EPROM -- handy when debugging or when you want autoload's
halt screen even though a lineprog PROM is socketed.

Bit 1 no longer gates chargen loading.  `autoload-in-c/rom.c` calls
`define_sextants()` unconditionally on every boot, programming a
64-glyph 2x3-block subset into the SEM702 RAM at the codepoints they
occupy in ROA327 (0x20..0x3F + 0x60..0x7F).  A real ROA327 ROM in
IC82 silently ignores the OUT writes -- safe no-op on baseline.

MAME models the SEM702 in machine `rc702sem702` (see
`mame/src/mame/regnecentralen/rc702.cpp`).  Boot that variant when
you want to exercise the SEM702 display path; baseline `rc702` still
uses the ROA327 ROM and is unaffected.

## Bit 2 -- CP/NOS transport (cpnos-in-c PROM1-only build)

Spec finalised 2026-05-17:

- **On** (bit=0, default): the cpnos slave drives the SNIOS byte
  layer through `transport_pio_send_byte` / `transport_pio_recv_byte`
  (Z80-PIO Mode 1, IRQ-driven 256 B SPSC ring buffer).
- **Off** (bit=1): the cpnos slave drives the SNIOS byte layer
  through `transport_send_byte` / `transport_recv_byte` (SIO-A async
  ~38400 baud, polled, no buffer).

Only effective on the **PROM1-only lineprog build**
(`make prom1-lineprog` in `cpnos-in-c/`).  The legacy two-PROM
build (`make cpnos-burn`) still picks the transport at compile time
via `TRANSPORT=pio-irq` or `TRANSPORT=sio`; bit 2 is ignored there
because only one transport's code is linked.

Implementation: both `transport_pio.o` and `transport_sio.o` are
linked into the PROM1-only image.  A 6-byte jump table in
`src/xport_jt.s` provides `_xport_send_byte` / `_xport_recv_byte`
as 3-byte `JP NN` trampolines defaulting to the PIO bodies.  At
cold-init, `install_transport()` (init.c, in `.resident` because
`.init` was at its 640 B cap) reads SW1 bit 2 and, if set, patches
the NN bytes to point at the SIO bodies.  Cost: ~69 B of PROM1
(transport_sio.o + jump table + cold-init patcher).

PROM1 sizes:
- PIO-only build (`make prom1-lineprog` pre-dual): 1949 / 2048 B
- Dual-transport build: 2018 / 2048 B (30 B free)

Buffer-sharing question (was the original ask): the SIO transport
uses no RX buffer (it polls SIO-A directly), so the PIO's 256 B
`pio_rx_buf` is the only buffer in either path -- nothing to share.

SIO transport selection means SIO-A is the CP/NET wire.  SIO-B
remains the console serial port (independent chip channel), so
the bit 0 joined-console mode does not conflict with bit 2 SIO
transport.

## Adding new bits

When wiring up another SW1 bit, update this table and the
`PORT_DIPNAME` labels in `mame/src/mame/regnecentralen/rc702.cpp` so
the MAME UI keeps documenting the contract.
