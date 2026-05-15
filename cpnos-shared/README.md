# cpnos-shared — protocol contract + build infrastructure

Shared assets used by both [cpnos-in-c/](../cpnos-in-c/) and
[cpnos-in-asm/](../cpnos-in-asm/).  Nothing in this directory is
compiled directly; it's a library of binary contracts, linker scripts,
test fixtures, and helpers that the two variant directories consume.

## Layout

| Path | Purpose |
|---|---|
| `include/payload_header.h` | Binary contract: PROM payload header format |
| `include/cfgtbl.h` | Binary contract: CP/NOS config-table format |
| `ld/payload.ld` | LLVM `ld.lld` linker script (used by C variant) |
| `ld/relocator.ld` | Linker script for the cold-init relocator |
| `ld/cpnos_rom.ld` | Full ROM-image layout |
| `docs/CPNET_WIRE_PROTOCOL.md` | Authoritative protocol spec (DRI-cross-checked) |
| `docs/MEMORY_MAP.md` | Slave memory map |
| `docs/PORT_OUTPUTS.md` | Hardware port I/O reference |
| `mame/polypascal_test.lua` | 4-cell value-oracle test harness |
| `mame/bios_jt_trace.lua` | BIOS jump-table trace harness |
| `mame/minimal_trace.lua` | Minimal port-tap trace |
| `mame/porttap.lua` | Port-traffic recorder |
| `scripts/` | Python helpers: image-stitch, header-gen, checksums |
| `testutil/` | DRI CP/M tools, smoke-test utilities |
| `e_drive_seed/` | Test data (PolyPascal sources for the smoke matrix) |

## The two variants

- **[cpnos-in-c/](../cpnos-in-c/)** — clang + SDCC dual-compile C
  implementation.  2003 B resident (clang), 2068 B (SDCC).  Used as a
  compiler-improvement testbed; size moves track llvm-z80 backend
  changes.

- **[cpnos-in-asm/](../cpnos-in-asm/)** — pure Z80 assembly.  Target:
  fit in PROM1 (2 KB) so the autoload PROM in PROM0 can directly jump
  to it.  Bring-up scheduled for session 73e+.

## Value oracle

Both variants are validated against the same 4-cell test matrix:

```
make polypascal-test  # (run from each variant's dir)
```

The harness lives at `mame/polypascal_test.lua`.  Cells:
{compiler: clang | sdcc} × {transport: pio-irq | sio}.  All four must
PASS for any commit touching shared protocol or variant slave code.

## History

Split from the original `cpnos-rom/` directory on 2026-05-15 (session
73d).  See `../tasks/timeline.md` for the rationale.
