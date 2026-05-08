# Issue #29 — IVT relocation plan (status as of 2026-05-08)

## Background

The CP/NOS slave runs Z80 Interrupt Mode 2.  IM 2 forms the vector-fetch
address as `(I << 8) | (device_byte & 0xFE)`: the I register fixes a
256-byte **page**, and at interrupt time the CPU reads a 16-bit ISR pointer
from somewhere inside that page determined by the interrupting device's
vector low byte.

#29 was originally filed because the SDCC port had no `RESIDENT_IVT`
SECTION reservation; `defc __ivt_start = 0xF500` was a literal that
disagreed with the actual symbol layout, so the IVT region overlapped
real code (`_cursor_down` / `_cursor_up` lived inside 0xF500..0xF523),
and `setup_ivt` corrupted them at boot.  The session-47 hot fix was to
reserve a `RESIDENT_IVT` SECTION inside the resident region — which
required trimming SDCC code first, since the resident was at the byte
cap.

## Initial plan (2026-05-07 evening) — WRONG

A "clean fix" was floated based on the 48 B of scratch RAM at
0xFFD0..0xFFFF (the gap between display end at 0xFFCF and end of address
space).  Proposal: place the IVT at 0xFFD0, set `I = 0xFF`, reconfigure
each device's vector low byte to 0xD0..0xF2.

**This is unsafe.**  Under IM 2 the I register fixes the *whole* 256 B
page.  With `I = 0xFF` the page is 0xFF00..0xFFFF, of which
**0xFF00..0xFFCF is on-screen character RAM** (display memory occupies
0xF800..0xFFCF).  Any spurious, misprogrammed, or future-added device
whose vector low byte is < 0xD0 would have the CPU fetch its ISR pointer
from a pair of bytes currently displayed on the screen — i.e. a jump to
arbitrary memory determined by what the operator last typed.  All pages
I = 0xF8..0xFF are similarly forbidden.

See `~/.claude/projects/-Users-ravn-z80/memory/project_rc702_ivt_page_constraint.md`.

## Actual fix (Phase 47b Path 6, landed 2026-05-08)

A different mechanism, landed independently of #29's original framing,
solves the SDCC blocker.

- **CODE_BASE shifted** in cpnos-build: LDE80 → LDD80 (cpnos.com 0xDE80
  → 0xDD80).  Resident lower bound 0xEE00 → 0xED00; 256 B added to
  resident budget (2560 → 2816 B).
- **SDCC SCRATCH_BSS** moved 0xEB00 → 0xEA00.
- **`bss_ivt` SECTION** added at the head of SCRATCH_BSS, page-aligned
  by `org 0xEA00`.  `__ivt_start` and `__ivt_end` are PUBLIC labels
  inside that section; no literal address in the assembler source.
- **`I = 0xEA`**: `init.c::setup_ivt` derives `IVT_ADDR = (uintptr_t)
  &_ivt_start` and calls `set_i_reg(IVT_ADDR >> 8)`.  No literal in C
  either.
- **Device vector low bytes** stay at 0x00..0x22 (the natural offsets
  off the page base 0xEA00), no `port_init[]` rewrite needed.
- **Payload header** `bss_pairs` list carries `(__ivt_start, __ivt_end)`
  via `gen_payload_header.py --include-ivt`; the relocator zeroes the
  IVT region during the BSS-clear pass before checksum.
- **Asymmetric:** clang still uses `__ivt_start = 0xF500` in the
  resident region (page-aligned, I = 0xF5).  Costs 36 B of clang
  resident.  Functionally fine; just not symmetric with SDCC.

The bss_ivt page is 256 B; the IVT itself uses 36 B; the remaining
220 B inside the same page hosts `_bios_log_buf[219]` + `_bios_log_idx`
(BIOS-JT call trace buffer for issue #60), placed by the linker
immediately after `__ivt_end` so no page-alignment slack is wasted.

## Outstanding (clang-side mirror, optional)

Moving the clang IVT to a BSS-scratch page would:

- Free 36 B of clang resident (currently at `__ivt_start = 0xF500..0xF523`).
- Match the SDCC layout one-for-one.
- Remove the only remaining literal IVT address in the build (the
  `0xF500` in `payload.ld` line 75).

Sketch of the change (clang side):

1. **`payload.ld`**:
   - Delete `__ivt_start = 0xF500;` literal.
   - Add a new MEMORY region or output section in the BSS region,
     page-aligned, exporting `__ivt_start = .;` then `. += 36;`
     `__ivt_end = .;`.
   - Pick a free BSS page that does not overlap any other allocation
     (audit `cpnos.map` first; candidates: a new 256 B reserve in the
     existing SCRATCH region or carve from an existing BSS hole).
   - Update the two ASSERT lines that bound `__ivt_start..__ivt_end`
     against `__payload_*` and `__scratch_bss_*` to match the new
     placement.
2. **`init.c`**: nothing; `IVT_ADDR` is already derived from
   `_ivt_start`, and `set_i_reg(IVT_ADDR >> 8)` is already
   linker-derived.
3. **`gen_payload_header.py`**: nothing; `--include-ivt` already adds
   the `(__ivt_start, __ivt_end)` pair to the bss_pairs list.
4. **Boot test**: `make autoload-clang` + MAME boot to `E>` prompt;
   `make cpnos-polypascal-test COMPILER=clang` PASS.

**Not urgent.**  No functional bug; just symmetry + 36 B clang resident
recovery.  Schedule when there is unrelated reason to touch
`payload.ld` or when clang resident pressure becomes the binding
constraint.

## Hard rules (carry forward)

1. **IVT page placement constraint**: under IM 2 on RC702, no IVT page
   may include any byte in 0xF800..0xFFCF (display RAM).  Forbidden I
   values: 0xF8..0xFF inclusive.  Memory rule
   `project_rc702_ivt_page_constraint.md`.

2. **No literal IVT addresses**: every IVT address in C, asm, and
   linker scripts must be derived from `__ivt_start` / `__ivt_end`
   PUBLIC symbols defined inside a page-aligned SECTION.  Memory rule
   `feedback_no_literal_addresses.md`.

3. **IVT region in payload header bss_pairs**: the relocator zeroes
   the IVT before checksum verification by walking the bss_pairs list;
   `gen_payload_header.py --include-ivt` is mandatory for any build
   that uses an IVT inside the loaded image.
