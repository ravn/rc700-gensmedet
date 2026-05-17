# SDCC build: implement install_locale_tables + get_img_base

**Status:** TODO -- pair with the SDCC ZX0 work
(`todo-sdcc-zx0-2026-05-17.md`).

## Why

Session 73j-locale moved the cpnos slave to a locale-aware design:

  * Bootstrap (PROM1-only's `bootstrap.s`) or relocator (two-PROM's
    `relocator.c`) pre-fills outcon at 0xF680..0xF6FF with identity
    bytes and stamps `_prom1_only_sentinel = 0x5A`.
  * `init.c::netboot_mpm` calls `get_img_base()` to choose a shifted
    LDIR destination so the master's cpnos.img locale prefix lands
    at 0xDC00 (= NDOS-384 B).
  * `cpnos_main.c::resident_handoff` calls `install_locale_tables()`
    which LDIRs the prefix to 0xF680..0xF7FF.

These three pieces are clang-only.  The corresponding SDCC paths
were gated `#ifdef __clang__` at session 73j end so the SDCC
two-PROM build at least compiles (commit 00791ce).  Effect: SDCC
slave boots, reaches CCP, but locale tables NEVER load -- banner
row 2 doesn't get a `da_US` tag; impl_conout/impl_conin run the
byte-identity bypass.

## Sub-tasks

1. **SDCC `install_locale_tables()` implementation.**  Live in
   sdcc/resident_extras.asm (or a small resident_locale.c if SDCC
   z88dk-c keeps clang-source compatibility).  Mirrors the clang
   version: 384-byte LDIR from 0xDC00 to 0xF680, gated on the
   sentinel byte.

2. **SDCC `get_img_base()` implementation.**  Same gating logic;
   returns shifted address when sentinel = 0x5A.  Could be a 5-byte
   `LD HL, 0xDC00; RET` (sentinel-conditional via cp + jp).

3. **SDCC two-PROM relocator pre-init.**  Equivalent of the clang
   relocator.c inline-asm block: outcon pre-fill + sentinel write.
   Lives in `sdcc/reset.asm` or a small new asm file pulled into the
   relocator link.  SDCC's `__asm/__endasm` syntax in C source also
   works.

4. **Test parity.**  `make cpnos-polypascal-test COMPILER=sdcc`
   should PASS with `da_US` on row 2 of the SIO-B raw.

## Cost class

Small once written; the patterns are identical to clang.  Probably
land alongside the SDCC ZX0 work since both touch the SDCC build
infrastructure.

## When

After SDCC ZX0 compression lands (`todo-sdcc-zx0-2026-05-17.md`),
because that work introduces the SDCC PROM1-only path -- the locale
implementation should support both two-PROM and PROM1-only SDCC
targets in one go.
