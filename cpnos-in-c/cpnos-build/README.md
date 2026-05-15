# CP/NOS build (cpnet-z80 -> cpnos.com)

Builds a 4-KB monolithic CP/NOS image from DRI sources in
`cpnet-z80/dist/src/` using VirtualCpm's RMAC + LINK-80.

## Why

cpnos-rom's netboot currently streams cpnet-z80's `ndos.spr`/`ccp.spr`,
which are CP/NET 1.2 binaries that assume a RESBDOS for local BDOS
delegation — we hit an infinite loop on BDOS fn 12 (GET VERSION)
because our system has no RESBDOS.  The proper CP/NOS architecture
combines five modules (cpnos stub + cpndos + cpnios + cpbdos + cpbios)
into one linked image.  This directory reproduces that build.

## Usage

    make             # build d/cpnos.com
    make clean

Produces `d/cpnos.com` linked at code 0xF000, data 0xEC00.  Symbol map
printed at link time — BIOS 0xFF21, NDOS 0xF003, BDOS 0xFCAA, etc.

## Tools

- `/Users/ravn/z80/cpnet-z80/tools/VirtualCpm.jar` (Java DRI-CPM emulator)
- `/Users/ravn/z80/cpnet-z80/dist/vcpm/{rmac,link}.com` (DRI tools,
  staged into `a/` before first run)

Drives: `a/` holds the CP/M tools, `d/` holds CRLF-converted sources
and build artifacts.

## Gotchas

- RMAC needs CRLF line endings; the Makefile converts `.asm` via perl.
- `VirtualCpm.jar --help` creates `/Users/ravn/HostFileBdos/` in the
  user's home when no `CPMDrive_*` env is set; the Makefile always
  exports `CPMDrive_D`/`CPMDrive_A`/`CPMDefault` so tools use this
  sandbox instead.
