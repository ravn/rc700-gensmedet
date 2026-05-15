# cpnos-rom split plan: cpnos-shared/ + cpnos-in-c/ + cpnos-in-asm/

Date: 2026-05-15.  Session 73d planning.

## Goal

Split current `cpnos-rom/` into three sibling directories:

- `cpnos-shared/` — protocol contract, build infrastructure, MAME
  test harness, docs.  Used by both variants.
- `cpnos-in-c/` — current C-language slave (clang + SDCC dual-compile,
  2003 B clang resident).  Becomes the compiler-improvement testbed.
- `cpnos-in-asm/` — new pure-Z80-asm slave.  Goal: fit in PROM1 (2 KB)
  with autoload in PROM0 jumping to it.  Bring-up in next session.

Single big rename commit; cpnos-in-asm scaffold (README + Makefile
skeleton) only — no asm code in this commit.

## File-move table

### To cpnos-shared/

Binary contract (used by both variants):

```
payload_header.h           ->  cpnos-shared/include/payload_header.h
cfgtbl.h                   ->  cpnos-shared/include/cfgtbl.h
```

Linker scripts (layout shared, may diverge later):

```
payload.ld                 ->  cpnos-shared/ld/payload.ld
relocator.ld               ->  cpnos-shared/ld/relocator.ld
cpnos_rom.ld               ->  cpnos-shared/ld/cpnos_rom.ld
```

Documentation (project-wide, not C-specific):

```
CPNET_WIRE_PROTOCOL.md     ->  cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md
MEMORY_MAP.md              ->  cpnos-shared/docs/MEMORY_MAP.md
PORT_OUTPUTS.md            ->  cpnos-shared/docs/PORT_OUTPUTS.md
docs/memory_map.md         ->  cpnos-shared/docs/memory_map.md
README.md                  ->  cpnos-shared/README.md (rewrite to point at variants)
```

MAME test harness (binary-only, variant-agnostic):

```
mame_polypascal_test.lua   ->  cpnos-shared/mame/polypascal_test.lua
mame_bios_jt_trace.lua     ->  cpnos-shared/mame/bios_jt_trace.lua
mame_minimal_trace.lua     ->  cpnos-shared/mame/minimal_trace.lua
mame_porttap.lua           ->  cpnos-shared/mame/porttap.lua
```

Test data:

```
e_drive_seed/              ->  cpnos-shared/e_drive_seed/
testutil/                  ->  cpnos-shared/testutil/
```

Python build/check scripts (variant-agnostic):

```
tasks/scripts/             ->  cpnos-shared/scripts/
(bin2inc.py, build_prom_image.py, build_prom1.py, check_no_frame_ptr.py,
 check_no_helper_calls.py, check_sdcc_layout.py,
 check_unreferenced_publics.py, gen_payload_header.py, pad_rom.py,
 regen_buildinfo.sh)
```

New shared file:

```
                           ->  cpnos-shared/common.mk
```

Will hold shared Make variables and pattern rules: paths, MAME
install logic, smoke-test invocations, size-check macros.  Each
variant's Makefile `include`s it.

### To cpnos-in-c/

C-language slave sources:

```
cpnos_main.c               ->  cpnos-in-c/src/cpnos_main.c
init.c                     ->  cpnos-in-c/src/init.c
relocator.c                ->  cpnos-in-c/src/relocator.c
resident.c                 ->  cpnos-in-c/src/resident.c
snios_c.c                  ->  cpnos-in-c/src/snios_c.c
transport_pio.c            ->  cpnos-in-c/src/transport_pio.c
transport_sio.c            ->  cpnos-in-c/src/transport_sio.c
transport.h                ->  cpnos-in-c/src/transport.h
hal.h                      ->  cpnos-in-c/src/hal.h
runtime.s                  ->  cpnos-in-c/src/runtime.s
snios.s                    ->  cpnos-in-c/src/snios.s
bios_jt.s                  ->  cpnos-in-c/src/bios_jt.s
reset.s                    ->  cpnos-in-c/src/reset.s
```

Makefile (refactored to include common.mk, ~1200 lines after extracting
the test-harness 700 lines into common.mk):

```
Makefile                   ->  cpnos-in-c/Makefile
```

C-specific tasks:

```
tasks/{compare-clang-vs-sdcc-*,
       dri-cpnos-source-audit-*,
       dual-header-plan-*,
       issue-29-ivt-relocation-plan,
       memory-layout-investigation-*,
       probe-results-*,
       sdcc-port.md,
       check_no_frame_ptr_baseline.txt,
       check_unreferenced_publics_allowlist.txt}
                           ->  cpnos-in-c/tasks/
```

Build outputs (gitignored):

```
clang/                     ->  cpnos-in-c/clang/ (gitignored)
sdcc/                      ->  cpnos-in-c/sdcc/ (gitignored)
compiler/                  ->  cpnos-in-c/compiler/ (gitignored)
cpnos-build/               ->  cpnos-in-c/cpnos-build/ (gitignored)
snap/                      ->  cpnos-in-c/snap/ (gitignored)
trace.dbg                  ->  cpnos-in-c/trace.dbg (gitignored)
cfg/                       ->  cpnos-in-c/cfg/
```

### Create cpnos-in-asm/ (scaffold only, this commit)

```
cpnos-in-asm/README.md         - bring-up plan, target PROM1 fit
cpnos-in-asm/Makefile          - skeleton: `all: error "not yet implemented"`
cpnos-in-asm/src/.gitkeep      - placeholder
cpnos-in-asm/tasks/.gitkeep    - placeholder
```

## Path-reference updates required

Every reference to `cpnos-rom/` must update.  Found via
`git grep -l "cpnos-rom"`:

- Workspace `CLAUDE.md` (paths in "Workspace Layout" section)
- `llvm-z80/CLAUDE.md` (cpnos sizes section)
- `rc700-gensmedet/CLAUDE.md` (project layout)
- `rc700-gensmedet/tasks/timeline.md` (all session entries)
- `rc700-gensmedet/cpnos-rom/Makefile` (becomes cpnos-in-c/Makefile)
- `rc700-gensmedet/cpnos-rom/README.md` (becomes cpnos-shared/README.md)
- Plus any session-summary docs in `llvm-z80/tasks/`

`git mv` preserves history; rename detection should work but the
single commit will be diff-heavy.

## Makefile refactor outline

Current `cpnos-rom/Makefile` (1630 lines) breaks into:

| Section | Lines | Goes to |
|---|---:|---|
| Variables, paths, defaults | 1–50 | both (parameterised) |
| TRANSPORT defines | 50–238 | both (cpnos-shared/common.mk) |
| Payload build (clang chain) | 239–561 | cpnos-in-c/Makefile |
| PROM0/PROM1 production | 561–620 | both (shared rules) |
| .COM loader | 603–614 | cpnos-shared/common.mk |
| Burner split | 615–620 | cpnos-shared/common.mk |
| MAME install | 621–668 | cpnos-shared/common.mk |
| MAME boot/test harness | 676–1277 | cpnos-shared/common.mk |
| Smoke tests (cpnet/pio-irq/sio) | 792–1276 | cpnos-shared/common.mk |
| Inspection | 669–675 | cpnos-shared/common.mk |
| Clean | 1286–1297 | both (per-variant) |
| SDCC build pipeline | 1298–1630 | cpnos-in-c/Makefile |

Variant Makefile interface (each variant must define):
- `RESIDENT_SOURCES` — list of source files
- `RESIDENT_LD` — linker script(s)
- `RESIDENT_BUILDDIR` — where intermediate .o land
- `RESIDENT_FINAL` — final payload .bin name
- Then `include $(CPNOS_SHARED)/common.mk` adds MAME install,
  smoke tests, size checks, etc.

## Validation

Post-rename, the value oracle is:

1. `cd cpnos-in-c && make` builds without error
2. `cd cpnos-in-c && COMPILER=clang make cpnos-size` reports
   2003 B non-padding (unchanged from pre-rename)
3. `cd cpnos-in-c && COMPILER=sdcc make cpnos-size` reports the
   SDCC size (unchanged)
4. The 4-cell MAME test matrix (clang × sdcc × pio-irq × sio) all PASS
5. `cd cpnos-in-asm && make` errors-out cleanly with "not yet
   implemented" (no half-build artifacts left behind)

(4) is a slow integration test, but mandatory because Makefile
refactoring is exactly the class of change that breaks test harnesses
silently.

## Scope cutoff

**This session**: layout + scaffold cpnos-in-asm/ README only.
**Next session**: cpnos-in-asm bring-up (minimal asm slave that boots
in MAME, then iteratively implements the wire protocol).

PROM1 fit target = 2048 bytes.  Current C resident = 2003 B.  ASM
should comfortably hit 1200–1500 B based on typical clang→asm density
ratios on this kind of code (~50–70% reduction).
