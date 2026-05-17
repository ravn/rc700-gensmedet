# cpnos-in-c two-PROM build: PARKED 2026-05-17

## TL;DR

**The two-PROM build (`make cpnos-install`, `cpnos-shared/ld/payload.ld`,
`cpnos-shared/relocator.c`) is no longer the production target.  The
production target is autoload-in-c (ROA375) in PROM 0 + cpnos-in-c
PROM1-only line program (`make prom1-lineprog`) in PROM 1.**

Two-PROM still builds, still passes `cpnos-polypascal-test`, and still
mirrors the production layout (locale tables, da_US banner tag, all
of session 73j-locale).  It is kept around for the SDCC test path
ONLY -- see "why two-PROM survives" below.  Do not invest in it as
the primary slave topology.

## Why two-PROM survives

The clang cpnos build comfortably fits in 2 KB (`prom1-lineprog`
artifact = ~2020 / 2048 B as of session 73j-locale).  Combined with
the 4 KB autoload-in-c PROM 0 (ZX0-compressed, ~1509 / 2048 B), the
user's hardware -- which has NO A11 bridge and is hard-locked to two
2 KB PROMs (see memory rule `project_rc702_2kb_prom_hard_limit`) --
can run the production "autoload + cpnos" combination.

**SDCC's cpnos build is larger than 2 KB.**  It does not fit in PROM 1
alone.  Session 73j attempted ZX0-compression on the SDCC build to
recover the gap; that work is parked
(`tasks/todo-sdcc-zx0-2026-05-17.md`).  Until SDCC ZX0 lands, the
SDCC slave HAS to ship as the historical two-PROM split (relocator +
init + payload spread across PROM 0 + PROM 1).

So:

  * **clang slave -> autoload + PROM1-only**  (production)
  * **SDCC slave  -> two-PROM**                (regression / parity)

If SDCC's PROM1-only build ever fits a single PROM, the two-PROM
build can be deleted outright (relocator.c, payload header / chunk
machinery, cpnos-install, cpnos-disk-install, cpnos-shared/ld/
relocator.ld, the SDCC-specific sections.asm two-PROM glue).

## What landed before parking

Session 73j gave two-PROM full locale parity with PROM1-only:

  * `cpnos-shared/ld/payload.ld` now matches `clang-prom1lineprog/
    payload.ld`: SCRATCH 0xEB00, PIO_RX 0xEC00, CFGTBL_RAM 0xF53C,
    stack top 0xF680, locale tables 0xF680..0xF7FF.
  * `relocator.c` pre-fills outcon at 0xF680..0xF6FF + stamps
    `_prom1_only_sentinel = 0x5A` so `install_locale_tables`
    activates from cpnos.img's 384 B locale prefix.
  * `cpnos-disk-install` now always prepends the locale prefix
    + locale tag travels via stamp_cpnos.py --locale.
  * `cpnos-polypascal-test` PASS in 51 s; banner row 2 shows
    `... da_US`.

The autoload + PROM1-only path remains the canonical test target.

## When you come back to this

Read this file first.  If you find yourself "improving" the two-
PROM build, ask: is the SDCC ZX0 work done?  If yes, this build
is obsolete -- consider deleting it instead.  If no, the SDCC
test path still needs it; keep changes minimal and mirror what
PROM1-only does.
