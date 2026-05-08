# Session 47 — cpnos-rom: header-driven relocator + memory-layout audit

Branch: `session47-cpnos-header-driven-relocator` (z80, rc700-gensmedet, cpnos-rom).
Date: 2026-05-06 → 2026-05-07.

## Outcomes

1. **Clang cpnos verified end-to-end** at HEAD via the polypascal-test
   target.  Build hygiene fixes were needed to make it work after the
   inherited "BSS-clearing relocator" change from a previous session
   left clang's link path broken (missing `<stddef.h>` in relocator.c;
   missing `__pio_rx_bss_*` symbols in `payload.ld`; missing
   `--defsym` lines in the Makefile relocator-link).  After fixing,
   PPAS PRIMES runs to 29989, returns to `E>` cleanly.

2. **Two memory-layout JP-0-class bugs identified in the SDCC port**:
   - **IVT overlap** (active): `defc __ivt_start = 0xF500` was a
     hardcoded numeric constant with no SECTION reservation behind
     it.  z88dk's linker placed `_cursor_down @ 0xF4FF` and
     `_cursor_up @ 0xF516` inside that range; `setup_ivt()`
     destroyed their middle bytes at every boot.  Banner survived
     by accident (the corrupted bytes happened to form benign-ish
     opcodes), but later impl_conout paths through `\n` → cursor_down
     hit the same garbage under different register state.
   - **`_pio_rx_buf_page` ↔ `_pio_rx_buf` mismatch** (latent):
     the `defc _pio_rx_buf_page = 0xF7` literal disagreed with where
     SDCC actually placed `pio_rx_buf` (0xECEE — page-misaligned, in
     the wrong page).  Dormant under TRANSPORT=sio because nothing
     strobes PIO-B in the test harness.

3. **`_pio_rx_buf_page` fixed** in both pipelines: now derived from
   `HIGH(_pio_rx_buf)` at link time, not a hardcoded literal.
   - SDCC: `SECTION bss_pio_rx` with `align 256` + 256 B reservation;
     `defc _pio_rx_buf_page = _pio_rx_buf / 256`.  Buffer at 0xEC00
     (page-aligned).
   - clang: `payload.ld` `_pio_rx_buf_page = (__pio_rx_bss_start >> 8)
     & 0xFF` plus `ASSERT((__pio_rx_bss_start & 0xFF) == 0, ...)`.
     Buffer at 0xF700 (page-aligned).

4. **Memory-layout investigation** written
   (`cpnos-rom/tasks/memory-layout-investigation-2026-05-06.md`) —
   surveys the structural mismatch between clang's `payload.ld`
   (MEMORY{} regions + 16 link-time ASSERTs) and SDCC's
   `sections.asm` (sequential-SECTION + ad-hoc `defc` constants),
   catalogs all the address-pinned vs movable items, and proposes
   the linker-driven layout that became plan #19.

5. **Plan #19 — header-driven relocator**: approved this session,
   steps 1-5 implemented on the clang side.  Architecture: a small
   `__payload_header` is emitted into the PROM image by both
   pipelines (after the relocator code, before `.init`).  At boot
   the relocator reads its metadata (chunk srcs/sizes, cold entry,
   BSS-pair list, checksum magic) from the header instead of from
   `--defsym`-injected externs.  Adding a new BSS region or
   page-aligned reservation now requires touching exactly TWO files
   (linker script + header generator) — no Makefile awk, no defsym,
   no underscore-counting Z80-ABI traps.

6. **Compiler stamped in the boot banner**:
   `RC702 CP/NOS 55K PIO-IRQ clang 2026-05-07 08:55 6fd1b93+` —
   `CPNOS_COMPILER_NAME` macro in `compiler/compat.h` selects
   `clang`/`sdcc`/`hitech`/`host` from the predefined macros at
   preprocess time, no Makefile -D flag to forget.

## What this session changed

### Files added (cpnos-rom)
- `payload_header.h` — struct definition shared by header generator + relocator
- `tasks/scripts/gen_payload_header.py` — emits `payload_header_data.s` from payload symbols (clang or SDCC dialect)
- `tasks/memory-layout-investigation-2026-05-06.md` — full design doc

### Files modified (cpnos-rom)
- `relocator.c` — rewritten to read `_payload_header`; dropped `cpnos_cold_entry`/`bios_boot`/`__scratch_bss_*`/`__pio_rx_bss_*` externs; checksum invariant preserved (LDIR → BSS → checksum → JP)
- `relocator.ld` — `.payload_header` output section added; `__chunk_a_start`/`__chunk_b_start` linker-emitted; `__init_end` ASSERT bumped to 0x500; relocator code budget bumped to 0x200
- `payload.ld` — `INIT origin: 0x0100 → 0x0200`; `__pio_rx_bss_start/end` symbols added inside `.pio_rx_bss`; `_pio_rx_buf_page` derived from `HIGH()`; page-alignment ASSERT
- `Makefile` — header-gen invocation; `payload_header_data.{s,o}` target; `RELOC_OBJS` extended; `PROM0_TAIL_SIZE: 1024 → 768`; 6 `--defsym` lines deleted from relocator-link
- `compiler/compat.h` — `CPNOS_COMPILER_NAME` macro
- `cpnos_main.c` — banner uses `CPNOS_COMPILER_NAME`
- `transport_pio.c` — `pio_rx_buf` extern under SDCC; clang side unchanged
- `sdcc/sections.asm` — `bss_pio_rx` section with linker-derived `_pio_rx_buf_page`; IVT comment notes the open task
- `tasks/scripts/check_sdcc_layout.py` — skip `*_page` derived-byte constants

### Memory rules added (cross-session, in `~/.claude/.../memory/`)
- `feedback_memory_layout_on_port.md` — HARD: audit memory-layout invariants when porting to a new compiler/linker; hardcoded address constants describe hope, not invariants
- `feedback_extract_rules_from_time_sinks.md` — HARD (meta): after every long debug session, propose new memory-rule entries that would have caught the class of bug earlier
- `feedback_relink_dependencies_atomically.md` — HARD: cross-stage `--defsym` requires C decl + linker script + Makefile awk + Makefile defsym in the same commit
- `feedback_kill_stale_servers_on_test_target.md` — HARD: auto-cleanup leftover daemons (BYE → SIGTERM) instead of aborting

## Issues / followups raised by this session

### Open in tasks
- **#13** cpnos-rom: hunt remaining JP-0 sources in SDCC build —
  IVT overlap accounted for; further hunting needs MAME probes after
  the IVT fix lands.  Static analysis is exhausted.
- **#15** build MAME_IRQ branch for polypascal-test (older task —
  branch built, gate fix present, binary may need a rebuild)
- **#16** adapt polypascal-test harness for SDCC (the harness uses
  `llvm-nm payload.elf` for symbol extraction; doesn't exist for
  SDCC)
- **#17** Phase 2D LDDR/LDIR sites in resident.c::insert_line —
  one remaining `#ifdef __clang__`-gated LDDR site
- **#18** cpnos-rom SDCC: fix IVT location via linker-decided
  address — folded into plan #19 step 7
- **#19** cpnos-rom: header-driven relocator (data-driven payload) —
  steps 1-5 complete (clang side), 6-8 remaining (SDCC port)

### New issues to file (next session)
1. **`relocator.c` indirect-call inline asm has no clobber list**
   — the `jp (hl)` after loading HL with cold_entry doesn't declare
   "hl" as clobbered.  Works today because nothing reads HL after
   the call, but is fragile.  ~1 line fix.
2. **Stale `cpnos_main.c` comments** mention `0x0100` as the .init
   PROM offset; the actual base shifted to `0x0200` this session.
   Cosmetic; would mislead a reader.
3. **`PROM0_TAIL_SIZE = 768` is now soft** — was 1024 with a
   comment claiming "PROM0_TAIL_SIZE = 0x800 - 0x400".  Comment
   updated to match new layout but the fixed dd-split + magic
   constants are still hand-typed in the Makefile.  Could move
   to a single source-of-truth (linker script symbol or generated
   header constant).
4. **`cpnos_RESET.bin` filename misleading post-Plan-#19** —
   the file at `sdcc/cpnos_RESET.bin` is 29 B containing reset.s
   bytes only.  After step 6 lands, this file's role disappears
   entirely (the unified relocator absorbs reset).  Cleanup.
5. **Audit script (`check_sdcc_layout.py`) has no header check**
   — should verify `_payload_header` magic is `0x6350` and the
   sentinel pair is at the expected offset.  Add at step 8.
6. **Header version field is unchecked at runtime** — relocator
   only looks at `magic`.  Add a `version != PAYLOAD_HEADER_VERSION`
   halt so a stale relocator binary running against a new header
   format catches itself loudly.  ~5 B.
7. **`gen_payload_header.py` SDCC syntax path is untested** —
   wrote the function but only exercised the clang path.  SDCC
   integration happens at plan step 6.
8. **Cross-compiler verification of placed symbols** — proposed
   in the investigation doc as item 6: a script that compares
   `clang/payload.elf` and `sdcc/cpnos.map` for matching pinned
   symbols (BIOS_JT, SNIOS_JT, _bios_boot, _cpnos_cold_entry).
   Catches "edited memory_map.h but only one build picked it up".
9. **Banner under SDCC mentions transport "SIO"** but the SDCC
   build defaults to `TRANSPORT=sio`; the polypascal-test target
   uses `TRANSPORT=pio-irq`.  Either harden the cpnos-install rule
   to fail loudly on transport mismatch with the harness, or
   switch SDCC's default to match.
10. **Polypascal-test harness can't run SDCC** today — uses
    `$(NM) $(BUILDDIR)/payload.elf` (= llvm-nm).  SDCC build
    produces `cpnos.map`, no payload.elf.  Adapt at task #16
    or fold into the Stage-1 / Stage-2 split.

## Risks / known fragilities going forward

- **Relocator code-size budget** is 512 B (0x200), 393 B used.
  Adding the BSS-pair sentinel-magic check, version check, etc. all
  cost bytes.  When approaching the limit, the .init VMA can shift
  from 0x200 to 0x300 (and chunk A to 0x600, etc.) — but each shift
  costs 256 B of init-region budget plus a corresponding chunk-A
  reduction.

- **SDCC's stage-2 link** (plan #19 step 6) requires splitting
  z88dk's currently-single z80asm invocation into payload-link +
  relocator-link.  This is the biggest unknown — z88dk's appmake
  flow may resist the split.

- **Two-stage build for SDCC** is a Makefile restructure of ~100
  lines; will benefit from being on its own commit/branch.

## Verification this session

- `make cpnos COMPILER=clang TRANSPORT=pio-irq` — builds clean
- `make cpnos COMPILER=sdcc TRANSPORT=sio` — builds clean,
  layout audit OK, banner correct
- `make cpnos-polypascal-test` — PASS (PPAS PRIMES → 29989 → E>),
  re-verified after each step that touched the relocator pipeline

## Compaction note

This branch (`session47-cpnos-header-driven-relocator`) is a
checkpoint of all session work.  The implementation steps 1-5 are
on this branch; the analysis docs (this file +
`memory-layout-investigation-2026-05-06.md` +
`sdcc-port.md` updates) are also on this branch.

When resuming next session:
1. Check out this branch
2. Verify clang polypascal-test still PASS (regression guard)
3. Pick up plan #19 step 6 (compile relocator.c under SDCC)
4. Follow plan steps 7-8 to close task #18 and unify the architecture
