# Production verification — autoload-in-c

How to verify autoload-in-c is shippable.  Two end-to-end paths +
three component-level oracles + one logging tool.  All target the
clang build (production); the SDCC parity path is Docker-gated and
out of scope here.

## Production boot paths

autoload-in-c hands off to one of two BIOSes depending on which PROM1
is plugged in.  Both paths must reach a CP/M-class prompt for the
release to ship.

### A. Floppy CP/M boot (DRI rel.2.3 BIOS)

```bash
make floppy-boot-test
```

What it does:
1. Builds + installs `prom0.ic66` (clang, 1658 / 2048 B).
2. Launches MAME `rc702` with `test-disks/SW1711-I8.imd` on `-flop1`
   (in-tree, committed copy of the unpatched SW1711 distribution disk).
3. `mame_boot_test.lua` polls the DMA-derived display address AND
   the canonical RC702 BIOS address `0xF800`.
4. PASS when `A>` appears on screen; FAIL on "NO SYSTEM" / "ERROR"
   text, on the autoload "NO LINEPROG" halt, or on a 60 s timeout.

Expected log line:
```
PASS
frame=200 (4.0s emulated)
display base (DMA ch2) = 0x7A00
```

The displayed PASS dump shows the autoload banner on the
autoload-private buffer at `0x7A00`, then the DRI BIOS banner +
`A>` prompt on the canonical buffer at `0xF800` — confirming both
the autoload boot path and the BIOS hand-off.

Canonical screenshot: `snap/autoload_sw1711_boot.png` (2026-06-03).

### B. cpnos slave boot (PROM1 line program)

```bash
cd ../cpnos-in-c && make cpnos-polypascal-test
```

Owned by cpnos-in-c's finishing-checklist + parked 2026-06-04 awaiting
the physical Z80-PIO parallel cable; see
`tasks/memory/project_cpnos_parked_awaiting_parallel_cable.md`.  For
autoload-in-c's purposes, the relevant assertion is that
`prom0.ic66` correctly probes PROM1 for the cpnos signature and jumps
to its entry point — that's covered indirectly by the polypascal-test
PASS (which would not boot otherwise).

## Component-level oracles

### `make mame` — autoload banner identity

Boots the PROM in MAME with an empty PROM1 (so autoload reaches its
NO-LINEPROG halt) and asserts the autoload banner string matches
`RC700 ROA375 CL` (clang) or `RC700 ROA375` (SDCC).  Catches banner
regressions from `clang/banner.h` regeneration drift.

### `make sw1-test` — SW1 status display

Renders the DIP-switch status line on row 0 of the autoload display
buffer and asserts the regex `SW1 12345678: [01]{8}` appears.  Catches
display formatting / port-read regressions in `display_sw1_status()`.

### `make prom` — size cap + ZX0 round-trip

Build-time size check.  Fails if the post-ZX0 binary exceeds 2 KB
(clang) — the hardware-fixed PROM cap on the user's RC702.

## Cross-version boot interop (pre-merge gate)

The autoload PROM and the rcbios C BIOS ship as independent artifacts
that meet only at runtime, so a change to either must not break boot
against the OTHER side's *unmodified* counterpart, in BOTH SW1-S01
switch positions.

```bash
bash ../tasks/scripts/cross-version-boot-test.sh
```

What it does — a 4-way matrix (each PROM paired with its cross-version
counterpart BIOS, in both switch positions):

| # | PROM | BIOS / disk | SW1-S01 |
|---|------|-------------|---------|
| A | original `roa375/roa375.rom` (genuine 2 KB dump) | clang rcbios patched disk | On + Off |
| B | clang autoload `prom0.ic66` | stock unpatched `SW1711-I8.imd` | On + Off |

PASS iff all 4 boots reach the CP/M `A>` prompt (scanned by
`mame_boot_test.lua`) AND the autoload PROM fits its 2 KB cap.  Switch
position is forced via the `:DSW` S01 ioport field (`SW1_S01` env into
`mame_boot_test.lua`), never an I/O read tap.

This encodes three standing acceptance facts:
1. rcbios + the original `roa375.rom` must boot in BOTH switch positions.
2. The clang autoload PROM must boot the stock unmodified BIOS in BOTH positions.
3. The autoload PROM must fit in 2 KB.

NOTE: the matrix asserts `A>` (boots), not banner identity — a
swapped-but-bootable disk would still pass; it is an interop gate, not
an identity oracle (see `make mame` for banner identity).

## Logging / diagnostic

### `make fdc-log` — µPD765 transaction trace

Boots autoload with `test-disks/SW1711-I8.imd` on the floppy and
captures every µPD765 command + result byte via MAME passive I/O taps.
Decodes Read-Track ST1-ND (FDC bug A) and Sense-Int ST0-HD (FDC bug B)
signatures.  Use to diagnose floppy-boot regressions or to verify the
local upd765 `& 3` fix in the ravn/mame fork still suppresses the
head-bit leak.

Not a PASS/FAIL oracle by itself; outputs `/tmp/autoload_fdc_decoded.txt`.

## Quick CI gate (post-clean)

```bash
make clean && make floppy-boot-test && make sw1-test
```

If both pass, autoload-in-c is shippable for the floppy production
path.  The cpnos production path additionally requires the cpnos
checklist to be green (currently parked, see above).

## Dependencies for verification

- Native clang at `../../llvm-z80/build-macos/bin/` (built via
  `make toolchain` in workspace root).
- ravn/mame fork submodule at `../../mame/` with the rc702 driver.
  The local upd765 `& 3` fix protects the floppy-boot path from
  the head-bit leak.
- `test-disks/SW1711-I8.imd` — checked into the tree; the production
  reference disk.
