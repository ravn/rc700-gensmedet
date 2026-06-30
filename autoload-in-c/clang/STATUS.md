# Clang Z80 PROM Build Status

## Current: CP/M boots, 1909 / 2048 B (139 B free) — re-baselined 2026-07-01

PROM0: **1909 / 2048 B (hard 2 KB cap, 139 B free)**, ZX0-compressed payload
(raw 2282 B → ZX0 1730 B).  CP/M boots in MAME (`make floppy-boot-test` PASS,
reaches `A>` on the unpatched `SW1711-I8.imd`).  clang is the production
compiler; SDCC is parity-only / 4 KB MAME-only.

Headroom dropped 388 → 139 B free since 2026-06-23 — root-caused to the SIO-B
debug facility (ravn/rc700-gensmedet#118); see
[`../tasks/finishing-checklist.md`](../tasks/finishing-checklist.md) for the
finishing state and [`../tasks/todo-later.md`](../tasks/todo-later.md) for the
headroom-recovery task.

> The byte/gap figures below predate ZX0 compression (2026-05-17) and the
> 2 KB-cap migration — kept only as historical context.

## Historical (pre-ZX0): 2453 bytes

PROM: 2453/4096 bytes (60%). CP/M boots in MAME.
SDCC: 1872 bytes. Gap: 581 bytes (31% larger).

Boot section (boot_rom.c) is now C with 4 irreducible asm
instructions (di, ld sp, jp, retn).  The compiler inlines
boot_copy/boot_zero and generates LDIR for both.

## Build
```bash
make clang         # build PROM
make clang_prom    # build + install to MAME/RC700
make clang_asm     # show assembly
make clang_clean   # clean
```

## Enabled compiler features

| Flag | Effect |
|------|--------|
| `-Os` | Optimize for size |
| `+static-stack` | Allocate locals in BSS (non-reentrant) |
| `+shadow-regs` | Use EXX for ISR save/restore |
| `--gc-sections` | Dead code elimination |
| `-ffunction-sections` | Per-function sections for GC |
| `-disable-lsr` | Disable loop strength reduction (saves ~90 bytes) |
| `-fno-freestanding` | Enable memcpy→LDIR inlining |

## Code size gap analysis (clang vs SDCC)

Top 5 functions by size gap (241 of 581 bytes):

| Clang | SDCC | +Diff | Function |
|------:|-----:|------:|----------|
| 91 | 32 | +59 | `check_sysfile` |
| 100 | 45 | +55 | `lookup_sectors_and_gap3_for_current_track` |
| 139 | 93 | +46 | `fdc_get_result_bytes` |
| 58 | 17 | +41 | `compare_6bytes` |
| 105 | 65 | +40 | `fdc_write_full_cmd` |

Three backend root causes explain the gap:

### 1. No DJNZ for counted byte loops (~30 bytes)

`compare_6bytes` and `check_sysfile` use `do { ... } while (--i)`
loops.  SDCC generates `DJNZ` (2 bytes), clang generates
`dec a; or a; jr nz` (4 bytes) plus IX-based counter management.

```
; SDCC (17 bytes total for compare_6bytes):
    ld b, 6
.loop:  ld a, (de)
    cp (hl)
    jr nz, .fail
    inc de
    inc hl
    djnz .loop
    xor a / ret / ld a,1 / ret

; Clang (58 bytes): IX frame, BSS spills, add hl,bc per iteration
```

### 2. BSS pointer spills for struct field access (~100 bytes)

With `+static-stack`, the compiler stores computed struct field
pointers in BSS, then reloads them to access the field.  Each
spill/reload pair costs 6 bytes (`ld (nn),hl` + `ld hl,(nn)`).

`lookup_sectors_and_gap3` computes `&fdc_cmd.eot`, `&fdc_cmd.gap3`,
`&fdc_cmd.dtl` as pointers, stores each in BSS, then loads them
back to write the field.  SDCC accesses fields directly via
`ld hl, base+offset`.

`fdc_get_result_bytes` loads `dma_transfer_address` from BSS twice
(for low and high byte port writes) instead of keeping it in a
register pair.

### 3. 8-bit values promoted to 16-bit (~50 bytes)

Byte comparisons go through 16-bit arithmetic.  In `check_sysfile`,
comparing `*dir++ != *pattern++` generates sign-extension
(`rlca; sbc a,a`) and 16-bit XOR/OR instead of a simple `cp (hl)`.

### 4. IX frame overhead (~60 bytes across all functions)

Every function with locals gets `push ix` / `pop ix` (4 bytes) +
`ld ix, $addr` (4 bytes) for BSS frame setup.  SDCC's IX-indexed
stack access is 3 bytes per access; clang's static stack with IX
pointer is also 3 bytes per access but pays the 8-byte setup even
for functions with only 1-2 locals.

## Other known issues

### IX used to hold constant across LDIR (boot_main)

The compiler loads BSS size into IX before the first LDIR, then
transfers to BC via `dec ix; push ix; pop bc` (6 bytes).
Optimal: `ld bc, imm` (3 bytes) after the first LDIR.

### See also

- [BUGS.md](BUGS.md) — backend bugs found during development
- [llvm-z80 issues](https://github.com/ravn/llvm-z80/issues)
