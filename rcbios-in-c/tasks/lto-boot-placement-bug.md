# rcbios clang BIOS: `-flto` broke boot-code placement (root cause + fix)

**Status:** ROOT-CAUSED and FIXED (2026-06-28). Fix = disable `-flto` for the
rcbios clang build. Verified end-to-end: clang C BIOS boots to a usable CP/M
`A>` prompt in MAME (first confirmed `A>` for the clang BIOS).

## Symptom

The clang-built rcbios loaded from disk by the production autoload PROM never
reached an `A>` prompt in MAME. After autoload handed off, the CPU NOP-slid
across high RAM (0xDC00–0xFAFF, garbage SP) — the classic signature of a jump
into unpopulated memory. The stock-PROM + asm-BIOS path booted fine, so the
fault was specific to the clang C BIOS.

## Memory model (why placement matters)

The BIOS image is split into two address regions by `clang/rc700_bios.ld`:

- **`.boot` / `.boot_data` / `.boot_code`** at low VMA (0x0000 / 0x0080 / 0x0280),
  with **LMA == VMA** — these run *in place* exactly where autoload loads track 0.
- **BIOS runtime sections** (`.text`, `.data`, …) at **VMA 0xDA00** (`BIOSAD`),
  but with **LMA contiguous after the boot sections** (`AT(__boot_end)`).
  Nothing lives at 0xDA00 at power-on; `relocate_bios()` copies LMA → VMA.

Therefore **any function that runs before `relocate_bios` finishes must be
physically resident at its low load address** — i.e. it must land in
`.boot_code`. The pre-relocation functions are:

- `relocate_bios()`  (`boot_entry.c`)   — BSS clear + LMA→0xDA00 copy
- `verify_relocation()` (`boot_entry.c`)
- `bios_hw_init()`   (`bios_hw_init.c`)

`_coldboot` (hand-asm in `bios_shims.s`, in `.text.coldboot`, always low because
it's assembled directly) calls these three, then `jp _bios_boot_c` into the
now-populated high region.

## Root cause

`rc700_bios.ld` places the pre-relocation functions low using **per-input-file
section matchers**:

```ld
.boot_code 0x0280 : AT(...) {
    KEEP(*bios_shims.o(.text.coldboot))
    KEEP(*boot_entry.o(.text*))
    KEEP(*bios_hw_init.o(.text*))
}
```

This works **only when each `.c` compiles to its own ELF `.o`**. With `-flto`,
clang emits **LLVM bitcode** objects, and `ld.lld` **merges every C translation
unit into one combined LTO module** before applying the linker script. At that
point there is no longer a distinct `boot_entry.o` / `bios_hw_init.o` to match —
so `*boot_entry.o(.text*)` and `*bios_hw_init.o(.text*)` match **nothing**, and
those functions fall through to the catch-all BIOS text region:

```ld
.text BIOSAD : AT(...) { *(.text*) }     /* VMA 0xDA00 */
```

So under LTO, `relocate_bios` / `verify_relocation` / `bios_hw_init` are assigned
VMAs in the 0xDA00+ range. `_coldboot` (low) then does `call 0xDA9D` into RAM
that is still empty (relocation hasn't run yet) → NOP-slide → never boots.

`_coldboot` and `_trace_putc` survive because they are in `*bios_shims.o(.text.coldboot)`
— `bios_shims.s` is hand-assembled, never bitcode, so its file-scoped match still fires.

## Controlled experiment (what proved it)

Same source tree, identical except the `-flto` flag; symbol placement from
`llvm-nm bios.clang.elf`:

| symbol             | `-flto` (broken) | no-LTO (correct) |
|--------------------|------------------|------------------|
| `_coldboot`        | 0x0280           | 0x0280           |
| `_relocate_bios`   | **0xDA9D**       | **0x02AA**       |
| `_verify_relocation` | high           | 0x02E1           |
| `_bios_hw_init`    | high             | 0x02F2           |
| `_bios_boot_c`     | 0xDA8F (correct) | 0xDA8F (correct) |

Only the LTO flag changed; placement of the three pre-relocation functions
flipped from high (empty at boot) to low (resident). This is the bug.

**Note on an earlier false negative:** an initial "no-LTO" test merely removed
the link flag without forcing a recompile, so `make` reused the cached **bitcode**
`.o` files and `ld.lld` still LTO'd them — placement stayed high and LTO was
wrongly dismissed as the cause. The valid experiment requires `rm -f clang/*.o`
so the objects are regenerated as real ELF. Lesson: when toggling a compile-time
flag, force a clean recompile, not just a relink.

## End-to-end verification (no-LTO build)

Booted the no-LTO instrumented BIOS in MAME (`rc702`, pristine in-workspace
`SW1711-I8.imd`, track 0 patched with `bios.clang.cim`, instrumented autoload
PROM installed). SIO-B (38400 8N1) trace + a 50 Hz ISR heartbeat at 0xFFEE:

```
autoload: BIOS loaded from disk.  boot_ptr @0000 = 0280 ...
CRV                       <- coldboot -> relocate_bios -> verify_relocation all run
[H] hw_init+readi ok
RC700 56k CP/M 2.2 C-bios/clang 2026-06-28 ...   <- RELOCATED BIOS at 0xDA00 runs
[W] wboot_c
 00 01 02 ... 2A 2B       <- all 44 (NSECTS) CCP+BDOS sectors read from track 1
A>                        <- usable CP/M prompt (screenshot-verified)
```

Heartbeat ticked 0x16 → 0x39A (~1 per 50 Hz frame) → interrupts live. The
`plan.md` hypothesis (track-1 CCP+BDOS link mismatch / relink-and-shrink) was
**falsified**: the stock track-1 CCP+BDOS already matches the BIOS load address
(identical DRI MSIZE=56 formula). No relink was needed; LTO placement was the
only bug.

## LTO size win — where the ~15 B came from (measured)

For completeness, since LTO is being disabled: the LTO size benefit is almost
entirely **inlining one-shot helper functions**, which removes per-call
`CALL`/`RET`/argument-setup overhead. Functions LTO folds into their single
caller (each becomes a 0-size standalone symbol): the BIOS jump-vector bodies
`_bios_write_c` (170 B), `_bios_conin` (127 B), `_bios_reader_body` (106 B),
`_bios_linsel_body` (79 B), `_bios_home`/`_bios_listst`/`_bios_punch_body`/
`_bios_reads_body`/`_bios_const` (39–45 B each), and tiny SIO/disk helpers
`_sio_wr5`/`_sio_rd1`/`_xread`/`_kbbuf` (16–23 B); plus `_bg_clear_from`
specialized −27 B. Inlining **moves** those bytes into the caller, so the gross
figures overstate it — the **net** clean-build win is ~15 B. The BIOS runtime
region (0xDA00–0xF600 = 7168 B) has ~1 KB free, so 15 B is not load-bearing.

## Fix (applied)

Removed `-flto` from `clang/Makefile` `CFLAGS`. Each `.c` now compiles to a real
ELF `.o`, so the `.boot_code` per-file matchers fire and the pre-relocation
functions are resident low at boot. Robust and simple; ~15 B cost, comfortably
within headroom.

### Alternative not taken (LTO-safe section tags)

The size win could be kept by giving `relocate_bios`/`verify_relocation`/
`bios_hw_init` (and any helpers/data they reach) an explicit
`__attribute__((section(".boot_code_text"), used, retain))` and matching
`KEEP(*(.boot_code_text*))` in the linker script — mirroring the existing
LTO-safe `boot_header` pattern (`.boot` section comment in `rc700_bios.ld`).
Rejected for now: more fragile (must catch every transitively-called/inlined
helper and the objects' rodata/data too), and 15 B is not worth the risk on a
boot path. Revisit only if BIOS size becomes tight.
