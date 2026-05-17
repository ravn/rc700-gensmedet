# cpnos-in-c: reserve translation-table space + hook default tables

**Status:** TODO (planned, not started).  Filed 2026-05-17 during session 73j.

## What

Add input/output translation tables to the cpnos resident slave at the
same memory positions the full rcbios-in-c uses, and hook up sensible
default tables at boot.

## Why

rcbios-in-c provides `outcon` (output conversion) and `inconv` (input
conversion) tables at a fixed address (currently 0xF680, see
`rcbios-in-c/bios.c:779` and `bios.c:934` / `bios.c:1372`).  CONFI.COM
and other utilities expect the tables to live at that address so they
can patch them at runtime to switch locale (Danish / Swedish / German
/ French / UK ASCII / US ASCII / "library").  Source tables live in
`rcbios-in-c/locale/*_tables.h`.

cpnos-in-c (the diskless slave booted via PROM1 lineprog) currently
has no equivalent.  Programs that assume the BIOS layout -- including
locale-aware CP/M utilities -- break or silently render wrong glyphs
when run against the slave.  The slave doesn't load a disk-resident
CP/M BIOS, so this needs to live in the slave's PROM-backed image.

## Concrete sub-tasks

1. **Reserve the address range.**  Match rcbios-in-c's placement so
   downstream tools find the tables at the same canonical addresses
   (`outcon`, `inconv`, plus any auxiliary tables CONFI.COM patches).
   Audit `bios.c` for all referenced symbols and reserve byte-for-byte
   compatible slots.

2. **Bundle a default table set.**  Pick one (probably Danish, matching
   the rcbios default; confirm with user) and link those bytes into
   the slave image so a cold slave boot renders correctly.

3. **PROM1 budget check.**  PROM1 lineprog currently 1930 / 2048 B
   (118 B free, per session 73j sizes).  Each table pair is 256 B
   raw; locale-dependent.  Likely won't fit uncompressed -- options:
     - share the ZX0 dictionary already in the slave (cheap if the
       table fits the compressor's window)
     - store the table in the slave's RAM section (decompressed at
       cold-init like the rest of init.bin)
     - move some existing slave code out to make room (unlikely)
   Pick before implementing.

4. **CONFI.COM compatibility (stretch).**  Verify that CONFI.COM
   running against the slave can patch the tables in RAM the same way
   it does against full rcbios.  If addresses match, this should be
   automatic.

## Cross-references

- Full BIOS implementation: `rcbios-in-c/bios.c`,
  `rcbios-in-c/locale/*_tables.h`
- Slave memory map: `cpnos-in-c/docs/memory_map.md`
- Slave PROM1 build: `cpnos-in-c/Makefile` target `prom1-lineprog`
- Slave PROM size headroom: `tasks/timeline.md` session 73j

## Cost class

Medium.  Mostly compatibility plumbing -- the locale tables already
exist in rcbios-in-c/locale/; the work is in finding 256+ B in the
slave's PROM1 budget and wiring the same symbol names at the same
addresses.

## When

Deferred -- not blocking anything live.  Pick up next time the slave
is touched, or when a CP/M utility's locale handling is found to
break against the slave.
