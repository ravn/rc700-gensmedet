# cpnos-in-c two-PROM build: PARKED 2026-05-17 (status: BROKEN, no plans to revive)

## TL;DR

**The two-PROM build (`make cpnos-install`, `cpnos-shared/ld/payload.ld`,
`src/relocator.c`) is parked.  The only supported slave topology is
autoload-in-c (ROA375) in PROM 0 + cpnos-in-c PROM1-only line program
(`make prom1-lineprog`) in PROM 1.**

Two-PROM is BROKEN as of session 73j-locale's late-cycle refactor:
the locale pre-init machinery moved from bootstrap.s + relocator.c
into `cpnos_cold_entry()` (init.c) so both compilers + both cold
paths share one C site.  Two-PROM still ROUTES through that function
on clang, so clang two-PROM may compile -- but no one is testing it
anymore.  SDCC two-PROM gets an `_get_img_base` link error in
`init.c` (sdcc/init.o cannot resolve the symbol via the two-PROM
relocator link); fixing it has no value because two-PROM is parked.

User directive 2026-05-17:
  > please park the two-prom scenario.  it is only the autoload+
  > cpnos scenario that interests e

So: ALL effort on cpnos targets autoload+PROM1-only.  Once SDCC ZX0
lands (`tasks/todo-sdcc-zx0-2026-05-17.md`), `make prom1-lineprog`
gains a SDCC variant; two-PROM is then deleteable.

## Why two-PROM survives

The clang cpnos build comfortably fits in 2 KB (`prom1-lineprog`
artifact = ~2020 / 2048 B as of session 73j-locale).  Combined with
the 4 KB autoload-in-c PROM 0 (ZX0-compressed, ~1667 / 2048 B), the
user's hardware -- which has NO A11 bridge and is hard-locked to two
2 KB PROMs (see memory rule `project_rc702_2kb_prom_hard_limit`) --
can run the production "autoload + cpnos" combination.

**SDCC's cpnos build is larger than 2 KB.**  Raw resident = 2192 B.
Two-PROM SDCC builds today, but FUNCTIONALITY IS BROKEN:

  * `install_locale_tables` and `get_img_base` are clang-only
    resident-c symbols.  SDCC's two-PROM cold path is gated via
    `#ifdef __clang__` -- the SDCC slave boots and reaches CCP but
    locale tables are NEVER installed.  The banner row 2 will not
    include a locale tag.  impl_conout/impl_conin use byte-identity
    bypass (sentinel never set in SDCC).
  * SDCC PROM1-only does not exist yet.

**Experimental result (2026-05-17):**  z88dk-zx0 on the raw SDCC
resident (2192 B) compresses to **1554 B** (-29%).  Adding a 68 B
dzx0_standard decoder + ~50 B bootstrap + ZX0-compressed init image
(rough estimate 400 B) + 8 B lineprog header lands at ~2080 B for a
hypothetical SDCC PROM1-only target -- JUST over the 2 KB cap.
Probably fits after init-region shrinking or dropping dual-transport.

So the SDCC slave is in a transitional state: builds two-PROM-OK
for size, but the locale + sentinel machinery has been gated off
clang-only until SDCC ZX0 lands (see `tasks/todo-sdcc-zx0-2026-05-17.md`).

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
