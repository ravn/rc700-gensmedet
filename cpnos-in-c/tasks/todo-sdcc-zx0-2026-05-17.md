# cpnos-in-c: extend ZX0 compression to SDCC builds

**Status:** TODO (planned, not started).  Filed 2026-05-17 during the
session 73j shrink investigation, as a do-later by the user.

## Goal

Wire the SDCC build path through the same ZX0 compression pipeline
that clang autoload + cpnos-in-c PROM1-only use, so that the SDCC
variants get the same ~30% PROM size reduction (from compressing
the `.text` payload + a 68 B `dzx0_standard` decoder).

User-stated motivation: "Perhaps it can fit in prom1 then" -- i.e. a
SDCC cpnos PROM1-only build that fits in the 2 KB socket on user's
physical hardware.  Today there is no SDCC PROM1-only target; the
existing `make prom1-lineprog` rule is clang-only.

Adjacent benefit: byte-level parity testing of the *compressed* image
(not just the source-level behaviour) becomes possible.

## Current state

| Build                                  | Compressed? | Size |
|----------------------------------------|-------------|------|
| autoload-in-c clang                    | yes (ZX0 .text, 68 B decoder) | 1661 / 2048 B |
| autoload-in-c sdcc                     | no | 2201 / 4096 B |
| cpnos-in-c PROM1-only clang × dual     | yes (ZX0 init+payload) | 1999 / 2048 B |
| cpnos-in-c PROM1-only sdcc             | not implemented | n/a |

z88dk ships ZX0 tooling (`z88dk-zx0`/`z88dk-dzx0` host binaries,
`dzx0_standard.asm` decoder in `libsrc/compress/zx0/z80/`).  The
compression step is compiler-agnostic; the missing piece is a SDCC
analogue of clang's two-pass link recipe.

## Concrete sub-tasks

1. **Two-pass SDCC link recipe for autoload-in-c.**  Clang's recipe
   in `autoload-in-c/Makefile` does:
     pass 1: `ld.lld --only-section=.text` -> `text_raw.bin`
     pass 2: link the original objects again with `text_compressed.s`
             (which `INCBIN`s the ZX0 output) replacing the original
             `.text`.
   SDCC + z88dk's `zcc` uses a different linker model -- needs
   research.  Likely path: emit a hex/binary intermediate, slice off
   the code segment by name, compress, regenerate.  May need
   `appmake` or `z88dk-objcopy` equivalents.

2. **`dzx0_standard.asm` for SDCC.**  The clang build uses
   `autoload-in-c/clang/dzx0_standard.s` (GAS-style).  z88dk's
   `libsrc/compress/zx0/z80/dzx0_standard.asm` is SDCC-compatible;
   either reference it from there or copy a sdcc-style version into
   `autoload-in-c/sdcc/`.

3. **Verify the host-side roundtrip.**  Match clang's pattern of
   running `z88dk-dzx0` on the compressed blob and `cmp`-ing against
   the pass-1 raw bytes -- catches any encoding-format drift.

4. **PROM1-only SDCC variant.**  Once SDCC autoload compresses, port
   the `make prom1-lineprog` target to also accept `COMPILER=sdcc`.
   Same bootstrap + dual-transport machinery; only the compiler
   front-end differs.  Estimate: similar payload size to clang
   (within ~5-10%), so likely lands at ~2050-2200 B -- may or may
   not fit in 2 KB depending on SDCC vs clang codegen efficiency.
   That's the actual test of "perhaps it can fit".

## Cost class

Medium-to-large.  Bulk of the work is in the SDCC linker plumbing;
the compression itself is a one-line host invocation.  Estimate
half-day to a day with iteration.

## When

Deferred -- not blocking anything live.  Two natural triggers:
1. The user wants SDCC parity-testable on the user's physical
   hardware (= cpnos PROM1-only sdcc must fit 2 KB).
2. Byte-for-byte clang/SDCC parity testing escalates from "source
   level same behaviour" to "image-level identical compressed bytes".

## Cross-references

- Clang autoload ZX0 recipe: `autoload-in-c/Makefile` (the
  "pass 1 / pass 2 / ZX0 compress" block, ~line 200-260)
- Clang cpnos-in-c PROM1-only recipe: `cpnos-in-c/Makefile`
  PROM1ONLY_* rules (~line 1245+)
- z88dk ZX0 source: `z88dk/libsrc/compress/zx0/z80/`
- Session 73j shrink investigation report:
  `cpnos-in-c/tasks/shrink-investigation-2026-05-17.md`
- Session 73i ZX0 landing plan:
  `cpnos-in-c/tasks/zx0-prom1-only-plan-2026-05-17.md`
