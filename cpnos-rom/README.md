# cpnos-rom — Combined CP/NOS client ROM for RC702

Single 4KB ROM image (two 2KB EPROMs: PROM0 @ 0x0000, PROM1 @ 0x2000) that
boots the RC702 as a CP/NOS client against an MP/M master over SIO-A
async 38400 baud, with optional 8" DSDD local diskette support.

## Status

2026-04-23: Initial+minimal version of CP/NOS client ROM, fully functional in MAME against z80pack

Phase 0 (scaffolding). See
[`../rcbios-in-c/tasks/cpnos-rom-plan.md`](../rcbios-in-c/tasks/cpnos-rom-plan.md)
for the full plan.

## How CP/NOS is split (the one-page version)

A CP/NOS slave like our RC702 has three software layers stacked between
the application program and "everything else". Two of those layers are
RC702-specific and live in this PROM; the third is generic DRI code
that arrives over the network as `cpnos.com`.

```
    +-------------------------------------+
    |   user program (CCP, MBASIC, ...)   |
    +-------------------------------------+
    |   BDOS    |   NDOS                  |   <-- cpnos.com (DRI, generic)
    +-----------+--------------+----------+
    |   BIOS                   |  SNIOS   |   <-- this PROM (RC702-specific)
    +--------------------------+----------+
    |   8275 CRT, PIO kbd,     |  SIO-A   |
    |   SIO-B console, FDC,    |  async   |
    |   CTC, IM2 IVT           |  9600..  |
    +--------------------------+----------+
       local hardware             wire
```

- **BIOS — talks to local hardware.** CRT (8275), keyboard (PIO), SIO/serial
  console, FDC, CTC, IM2 IVT. Exposes the standard 17-entry CP/M jump
  table (BOOT/WBOOT/CONST/CONIN/CONOUT/LIST/PUNCH/READER/HOME/SELDSK/
  SETTRK/SETSEC/SETDMA/READ/WRITE/LISTST/SECTRAN). Lives at 0xED00 in
  the resident image.

- **SNIOS — talks to the CP/NET server, "somehow".** 8 entries at 0xEA00
  (NTWKIN/NTWKST/CNFTBL/SNDMSG/RCVMSG/NTWKER/NTWKBT/NTWKDN). Today
  "somehow" = SIO-A async to z80pack on TCP 4002. Tomorrow it could be
  J3 parallel to a Pico bridge — only the SNIOS body changes; NDOS
  above it never notices.

- **NDOS — the router.** Sits in front of BDOS in `cpnos.com`. Decides per
  BDOS call whether to handle it locally (via BDOS+BIOS) or send it
  out over the wire (via SNIOS). Generic DRI code, vendor-neutral.

So the rule of thumb:

- **BIOS = local I/O, one box.**
- **SNIOS = remote I/O, one wire to one server.**
- **NDOS = decides which of the two each BDOS call goes to.**

Everything RC702-specific is in this PROM (BIOS + SNIOS). `cpnos.com`'s
only piece of RC702 knowledge is the address `NIOS = 0xEA00` — i.e.
"the SNIOS jump table lives here" — resolved at link time. Swap the
RC702 for a different CP/NOS slave and you'd rewrite this PROM; you'd
not touch `cpnos.com`.

## Architecture invariant: CP/NOS is diskless

A CP/NOS slave does NOT support local drives.  All disk I/O goes
through NDOS to the master via SNIOS over the wire — that's what
makes it CP/NET-OS rather than CP/M-with-network-drives.  CFGTBL
drive entries on the slave are either `NET_DRV(...)` (network drive)
or `0x0000` (no drive); local-floppy mounting is not part of the
CP/NOS architecture.

Historical note: an `ENABLE_FDC=1` build option exists in the
Makefile from a never-completed hybrid-mode design.  No C source
currently consumes the macro, so it's a no-op build flag — kept for
backwards compatibility with build scripts that pass it through.
Don't propose adding back local-floppy support; that would be a
different OS.

## Build configurations

- `make cpnos` — single config, NOS-only over CP/NET, targets ~55-56 KB TPA

Both produce a 4096-byte image split into `prom0.bin` (0x0000–0x07FF) and
`prom1.bin` (0x2000–0x27FF) for burning.

## Design constraints

- Display RAM at 0xF800–0xFFFF unchanged (Comal80 compatibility).
- BIOS resident code relocated to high RAM before PROM disable.
- Single OUT (0x18) disables both PROMs; everything needed at runtime must
  be in RAM by that point.
- Transport abstracted behind a vtable — parallel port (J3/J4) is parked
  but drops in without restructuring.

## Reference docs

- [`CPNET_WIRE_PROTOCOL.md`](CPNET_WIRE_PROTOCOL.md) — authoritative
  byte-level spec for the CP/NET 1.2 binary serial protocol that the
  cpnos-rom slave speaks to z80pack mpm-net2.  Cross-checked against
  master (`z80pack/cpmsim/srcmpm/netwrkif-0.asm`), DRI reference
  (`cpnet-z80/src/ser-dri/snios.asm`), and current cpnos-rom slave.
  Documents one slave-side deviation (busy-wait mid-frame receive)
  and flags that FNC=0xFF (init/get-node-ID) is protocol-defined but
  rejected by our master — slave ID is hardcoded via
  `RC702_SLAVEID=0x01` in the Makefile.
- [`MEMORY_MAP.md`](MEMORY_MAP.md) — RAM/PROM layout, IVT placement,
  resident-region bounds, BSS/cold-init split.
- [`PORT_OUTPUTS.md`](PORT_OUTPUTS.md) — RC702 I/O port map.

## Files (as Phase 0 adds them)

- `Makefile` — build targets, size check, PROM image split
- `cpnos_rom.ld` — linker script, 4KB ROM region + high-RAM runtime region
- `reset.s` — reset vector, minimum init before C
- `cpnos_main.c` — cold-boot driver: copy runtime to RAM, disable PROM, netboot
- `snios.asm` — ported from `../cpnet/snios.asm`, relocated entry points
- `netboot.asm` — ported from `../../cpnet-z80/src/netboot.asm`
- `bios_jt.c` — BIOS jump table (stubs for NOS, real bodies for FDC build)
- `console.c` — CONIN/CONOUT/CONST on SIO-B
- `fdc.c`, `deblock.c`, `dpb_maxi.c` — only compiled when `ENABLE_FDC=1`
