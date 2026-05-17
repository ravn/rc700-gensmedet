# cpnos-in-c: ZX0-compress cpnos.img

**Status:** TODO (filed 2026-05-17 from session 73j-locale follow-up).

## What

Replace the raw 3584 B `cpnos.img` (384 B locale prefix + 3200 B
stamped cpnos.com) with a ZX0-compressed variant unpacked on the
slave between netboot completion and `resident_handoff`.  Expected
compressed size ~2200..2500 B (DRI-assembled Z80 code typically
compresses to 65..75% via ZX0; the locale prefix's near-identity
outcon block compresses very hard).

## Why

  * **Netboot speed.**  CP/NET ships 128-byte READ-SEQ records.
    Saving ~1.0..1.4 KB shaves 6..8 records off the cold-boot path
    -- worth ~0.5..1 s on physical SIO, less on cpnet_bridge socket.
  * **Disk footprint.**  Master's `mpm-net2-1.dsk` and
    `cpnetsmk-1.dsk` carry ~1 KB less per cpnos.img.

## Mechanics

PROM1-only build already has `dzx0_standard` in `bootstrap.s`
(68 B in PROM1).  Reusable from C side via an extern, or call
directly from bootstrap before jumping into init.

Slave-side flow change:

  1. Netboot reads compressed cpnos.img into a staging area
     (e.g. 0xC000..0xCA00 -- below CPNOS_NDOSRL_ADDR=0xD980 so
     TPA isn't affected).
  2. New step: `dzx0_standard` from staging to 0xDC00.
  3. install_locale_tables + resident_handoff as today.

Master-side flow change:

  1. `cpnos-disk-install-with-locale` post-processes
     `cpnos_with_locale.img` through z88dk-zx0 before `cpmcp`.
  2. A 4..6 B header (magic + decompressed length) lets the slave
     sanity-check before decoding.

## Cost

  * Slave: ~15..20 B init.c for the staging-area read + dzx0 call
    + magic check.
  * Master: 2 lines in Makefile.
  * Build: z88dk-zx0 is already in the workspace
    (`z88dk/src/zx0/`).

## Caveats

  * **Two-PROM build has no decoder.**  Either ship uncompressed
    cpnos.img for that target (different filename) or add ~68 B
    of `dzx0_standard` to its PROM 0.  PROM 0 budget allows.
  * **Opaque failures.**  A corrupt compressed image fails into
    garbage at 0xDC00; NDOS executes random bytes.  Keep an
    uncompressed `cpnos_raw.img` next to the compressed one so
    `cpnos-disk-install` (the legacy non-locale variant) can fall
    back without touching the new path.
  * **Decompression CPU time.**  ZX0 decodes at ~2 KB/s on a 4 MHz
    Z80; 2.5 KB takes ~1.3 s.  Net netboot saving is the wire-time
    delta minus this 1.3 s -- positive on physical SIO, neutral
    over a fast socket.

## When

After session 73j-locale lands; before any further PROM1 budget
push.  Cleanly orthogonal to the 56K-TPA work and the relocatable-
cpnos.img work.
