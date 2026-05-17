# cpnos-in-c SDCC PROM1-only line program — WIP

**Status:** scaffolding committed, build pipeline not yet plumbed.

User direction (session 73j-late): bring the SDCC build to feature
parity with clang's `clang-prom1lineprog/`.  ZX0-compress the SDCC
resident + init, package into a PROM1-shaped image addressable by
autoload-in-c.  OK at 4 KB for now (not 2 KB).  Use C where possible.

Empirical inputs from session 73j-late:

  * SDCC resident raw = 2192 B (concatenation of resident_a + resident_b
    from the two-PROM build).
  * ZX0 compresses to 1554 B (-29%).
  * Estimated PROM1-only total: ~2080 B = 1554 + ~68 (decoder) +
    ~50 (bootstrap with sentinel/outcon pre-fill via init.c) + ~400
    (ZX0-compressed init) + 8 (header).  Probably fits 2 KB after
    init shrinkage.

## Files in this directory

  * `sections.asm` -- z88dk z80asm anchors for the SDCC link.
    LINEPROG_HEADER at 0x2000 (bootstrap entry + " RC702" signature),
    INIT_CODE at 0xC000 (relinked to RAM, was 0x02A0 in two-PROM),
    RESIDENT chain at 0xED00 (unchanged from sdcc/sections.asm).
    The two-PROM `RESET` / `PAYLOAD_HEADER` / `PAYLOAD_HEADER_P1`
    sections are dropped here -- they're for the two-PROM cold
    path which is parked.
  * `bootstrap.asm` -- DI + set SP + ZX0-decompress resident +
    ZX0-decompress init + JP 0xC000.  Mirror of
    `clang-prom1lineprog/bootstrap.s` in z88dk z80asm syntax.
  * `dzx0_standard.asm` -- copy of `z88dk/libsrc/compress/zx0/z80/
    dzx0_standard.asm`.  Needs SECTION + PUBLIC wrapper to expose
    `_dzx0_standard` to bootstrap.asm.

## Stage 1 (DONE): ZX0 measurement on SDCC resident

  * Makefile target: `COMPILER=sdcc make sdcc-resident-zx0-probe`
  * Measured: 2192 B raw -> 1554 B ZX0 (-29%, roundtrip OK)

## Stage 2 + 3 (DONE): two-pass build pipeline emits prom1-lineprog.bin

`make sdcc-prom1lineprog COMPILER=sdcc` now produces a complete image:

  * pass 1: zcc -create-app links with empty init.zx0 / payload.zx0
    placeholders; emits per-section .bin files including
    `cpnos_lp_INIT_CODE.bin` (653 B at VMA 0xC000) and
    `cpnos_lp_RESIDENT_JUMPTABLE.bin` (2190 B at VMA 0xED00).
  * ZX0 compress + z88dk-dzx0 roundtrip-verify both blobs:
      init    653 -> 562 B (-14%)
      payload 2190 -> 1552 B (-29%)
  * pass 2: zcc relinks with real ZX0 blobs INCBIN'd via
    init_zx0.asm + payload_zx0.asm.
  * Final image: cpnos_lp_LINEPROG_HEADER.bin = 2216 B raw,
    padded to 4 KB at sdcc-prom1lineprog/prom1-lineprog.bin.

Image contents (LMA 0x2000):
    0x2000+0: bootstrap_entry word (= 0x2008)
    0x2002:   " RC702" signature (autoload-in-c detection contract)
    0x2008+:  bootstrap.asm code (~30 B)
    + dzx0_standard (~69 B)
    + init.zx0 (562 B INCBIN)
    + payload.zx0 (1552 B INCBIN)

## Stage 4 (PARTIAL): MAME boot verification

Boot reaches cpnos banner + netboot dots; stalls before stamp print.

Companion MAME changes (ravn/mame@d0a7dcd81f2):
  * ROM_LOAD_OPTIONAL prom1.ic65 size 0x0800 -> 0x1000.
  * PORT_CONFNAME PROM1 default 0x00 -> 0x02 (4 KB / 2732 mode).
This gives MAME a 4 KB PROM1 region with bank2h exposing the upper
half at 0x2800..0x2FFF.  Earlier the loader was truncating my 4 KB
file to its first 2 KB.

SDCC PROM1-only verified output (SIO-B raw, this session):
    RC702 CP/NOS 55K PIO sdcc 2026-05-17 21:07 00791ce+
    ............................   (28 netboot dots = full cpnos.img)

Stall: stamp line ("2026-05-17 ... da_US") + E> never appear.
See tasks/todo-sdcc-prom1lineprog-netboot-stall-2026-05-17.md for
hypotheses + diagnostic plan.

## Stage 5 (NEXT): close the netboot stall

  * Makefile target: `COMPILER=sdcc make sdcc-prom1lineprog-try`
  * Current state: gets past the relocator.c (excluded via
    SDCC_LP_C_OBJS = $(filter-out relocator.o,$(SDCC_C_OBJS)))
    and most resident sources, but link still fails on missing
    symbols that the standard sdcc/sections.asm provides:
      - `__ivt_start` / `__ivt_end` (bss_ivt declarations)
      - `_pio_rx_buf` / `_pio_rx_buf_page` (bss_pio_rx + page-derive)
      - `__payload_zx0_start` / `__init_zx0_start` (not yet
        provided -- init_zx0.asm + payload_zx0.asm wrappers
        outstanding)

  Next steps:
   1. Copy bss_ivt + bss_pio_rx + scratch_bss alias declarations
      from sdcc/sections.asm into sdcc-prom1lineprog/sections.asm,
      relocating bss_pio_rx to its new 0xEC00 page and providing
      _pio_rx_buf_page = HIGH(_pio_rx_buf).  __ivt_start can stay
      at 0xEA00 (unchanged).
   2. Once the link succeeds, extract per-section .bin from
      cpnos_lp_<section>.bin outputs.
   3. ZX0 + roundtrip each .bin (init at 0xC000, resident at 0xED00).
   4. Generate init_zx0.asm + payload_zx0.asm with PUBLIC labels
      `__init_zx0_start` / `__payload_zx0_start` and `binary` /
      INCBIN of the ZX0 blobs.
   5. Final z80asm link of bootstrap + dzx0 + init_zx0 + payload_zx0
      anchored at 0x2000 -> sdcc-prom1lineprog/prom1-lineprog.bin.
   6. MAME verification via mame_capture.sh.

## What's NOT done yet

  1. **dzx0_standard SECTION wrapper.**  The vanilla z88dk source
     has no SECTION directive; left as-is it lands in default
     section.  Wrap with `SECTION LINEPROG_ENTRY` (or a dedicated
     ZX0_DECODER section) + `PUBLIC _dzx0_standard`.

  2. **Makefile rule `prom1-lineprog-sdcc`.**  Mirror clang's
     `prom1-lineprog` rule but using SDCC's zcc/z80asm/appmake
     pipeline instead of ld.lld/objcopy.  Approximate flow:
     a. Build SDCC objects with this dir's sections.asm
        (overriding sdcc/sections.asm).  zcc emits per-section
        .bin files (`-create-app -Cz"--org 0"`).
     b. Take `cpnos_RESIDENT_JUMPTABLE.bin` (concatenation of all
        resident chunks since they're contiguous at 0xED00); the
        existing SDCC build already does this via dd-splits, just
        without dd-split here.
     c. Take `cpnos_INIT_CODE.bin` (init code at VMA 0xC000).
     d. ZX0-compress both via `z88dk-zx0 -f` + roundtrip-verify
        via `z88dk-dzx0`.
     e. Wrap each ZX0 blob in an asm INCBIN stub (mirror
        `clang-prom1lineprog/payload_zx0.s`).
     f. Final link: bootstrap.asm + dzx0_standard.asm + init_zx0
        wrapper + payload_zx0 wrapper -> cpnos_LINEPROG_HEADER.bin.
     g. Pad to 2 KB or 4 KB depending on target; user said 4 KB
        OK for now.

  3. **Locale-prefix install** (cpnos.img prepended 384 B).
     Already works via shared install_locale_tables() in resident.c
     -- both compilers export the symbol.  Should "just work" once
     the bootstrap is alive.

  4. **Image verification.**  `make prom1-lineprog COMPILER=sdcc`
     produces sdcc-prom1lineprog/prom1-lineprog.bin.  Boot under
     MAME with `mame_capture.sh prom1only_sdcc_first -- ...`.
     Expected: PROM1 signature detected by autoload, ZX0 unpack,
     cpnos cold-init runs through to E> prompt.

## Pitfalls

  * **SDCC's `__asm__ volatile` vs z88dk's `__asm/__endasm`.**
    The locale pre-init in init.c::cpnos_cold_entry is portable C
    (for loop + sentinel write); not affected.

  * **dzx0_standard label naming.**  z88dk has no underscore
    prefix in the asm file (`dzx0_standard:` not `_dzx0_standard:`).
    When called from C the C-side symbol is `_dzx0_standard`.
    From bootstrap.asm calling z80asm-style we can use either; be
    consistent.  Wrap with PUBLIC _dzx0_standard alias.

  * **z88dk -create-app section ordering.**  Per-section ORG
    pinning controls LMA but z88dk's appmake concatenates sections
    in declaration order within a chain.  Verify the actual byte
    layout via `--list` or hex dump of the emitted .bin.

  * **Existing SDCC two-PROM PARKED but still builds.**  Do not
    delete sdcc/sections.asm -- the two-PROM build still references
    it.  This new sdcc-prom1lineprog/sections.asm is for the
    PROM1-only variant ONLY; the two builds coexist.

## When picking this up

Start by reading:
  * `clang-prom1lineprog/payload.ld` + `prom1.ld` (the layout shape
    we're mirroring).
  * `Makefile` lines 1354..1448 (clang prom1-lineprog rules).
  * `sdcc/sections.asm` (current SDCC section structure to diff
    against).
  * `tasks/todo-sdcc-zx0-2026-05-17.md` (the originally-filed plan,
    less detailed than this README).

Then write the Makefile rule.  Estimate: 2-3 hours iteration.
