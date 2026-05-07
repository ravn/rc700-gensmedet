# Memory-layout investigation: how to prevent segment overlap

Author: 2026-05-06.  Scope: cpnos-rom, both clang and SDCC builds.
Trigger: SDCC IVT-overlap JP-0 source (task #18) exposed the structural
gap between clang's MEMORY-region + ASSERT pipeline and SDCC's
sequential-SECTION + ad-hoc-`defc` pipeline.

Question from user: *"would it be a help to have all memory areas laid
out by the linker?  Some datastructures need to be at specific places
in memory, like the IVT at a page boundary and the screen memory at
0xF800 (can be temporarily relieved)."*

Short answer: **yes — fully linker-driven layout is the right design,
and SDCC's z88dk-z80asm supports the primitives needed.**  This doc
catalogs the current state, the constraints, and a migration path.

## 1. Current state — two pipelines, side by side

### 1A. clang (payload.ld + ld.lld)

Two-stage link.  `payload.ld` declares 4 MEMORY regions with explicit
ORIGIN + LENGTH and 16 link-time ASSERTs.  `relocator.ld` is a tiny
script for the PROM-side bootstrap.  Cross-stage handshake via
`--defsym=NAME=$(llvm-nm payload.elf | awk ...)` for symbols the
relocator needs from the payload (`_cpnos_cold_entry`, `__stack_top`,
`_bios_boot`, `__scratch_bss_start/end`, `__pio_rx_bss_start/end`).

| MEMORY region | ORIGIN  | LENGTH  | What lives there                |
| ------------- | ------- | ------- | ------------------------------- |
| `INIT`        | 0x0100  | 0x0300  | `.init.text` / `.init.rodata`   |
| `PAYLOAD`     | 0xEE00  | 0x1000  | resident code / rodata / data   |
| `SCRATCH`     | 0xF524  | 0x1DC   | scratch BSS (cfgtbl, kbd, etc.) |
| `PIO_RX`      | 0xF700  | 0x100   | 256-B PIO-B receive ring        |

Hardcoded literals in `payload.ld` (outside any MEMORY region):

```ld
__ivt_start = 0xF500;
__ivt_end   = __ivt_start + 18 * 2;
_pio_rx_buf_page = 0xF7;
__stack_top = 0xF700;
__stack_low = 0xF621;
```

Implicit IVT reservation: PAYLOAD is asserted `<= 0xF500` and SCRATCH
starts at `0xF524`, leaving 0xF500..0xF523 as a 36-B hole that nobody
writes during the link.  At runtime `setup_ivt()` is the sole writer.

The 16 ASSERTs cover:
- region size limits (.init ≤ 768 B; payload ≤ 4 KB)
- BIOS jt pin (`_bios_boot == 0xEE00`)
- SNIOS jt pin (`_snios_jt == 0xEE33`)
- BIOS jt offset invariants (CONOUT at +12, SECTRAN at +48)
- display memory (`__payload_end <= 0xF800`)
- IVT-vs-payload and IVT-vs-scratch overlap
- scratch_bss-vs-PIO_RX, scratch_bss-vs-stack
- stack-vs-cpnos.com (`__stack_top > __cpnos_load_end`)
- zp_init_data placement (must be resident, not init-only)

### 1B. SDCC (z88dk-z80asm + appmake +rom)

Single-stage link.  `sdcc/sections.asm` declares SECTIONs in a
sequential chain; addresses are picked by walk order.  No MEMORY
regions, no ASSERTs at link time.  A separate **post-link audit**
(`tasks/scripts/check_sdcc_layout.py`) parses `cpnos.map` and fails
the build on detected violations.

Hardcoded literals in `sections.asm`:
```asm
defc __ivt_start = 0xF500    ; (broken — see §3)
defc __ivt_end   = 0xF500 + 18 * 2
defc _pio_rx_buf_page = 0xF7 ; (broken — see §3)
```

SECTION chain:
```
SECTION RESIDENT_JUMPTABLE  (org 0xEE00)
SECTION RESIDENT_SNIOS_JT
SECTION RESIDENT_SNIOS
SECTION RESIDENT_ISR
SECTION RESIDENT_PRE_CODE
SECTION RESIDENT_PRE_RODATA
SECTION RESIDENT_CODE
SECTION code_clib / code_crt_init / code_home / code_l_sccz80 /
        code_string / code_compiler
SECTION RESIDENT_RODATA
SECTION rodata_clib / rodata_compiler / rodata_string
SECTION data_clib / data_compiler
SECTION RESIDENT_DATA
SECTION SCRATCH_BSS         (org 0xEC00)
SECTION bss_compiler
SECTION bss_clib / bss_string
```

`check_sdcc_layout.py` checks:
- every `addr, public` symbol falls inside its section's legal range
- every `__SECTION_head/tail` extent stays in the legal range
- no two non-zero sections overlap (start/end span comparison)

What it does **not** check:
- IVT region (0xF500..0xF523) for foreign symbols
- PIO_RX region (0xF700..0xF7FF) for symbol-vs-`_pio_rx_buf_page` mismatch
- Display memory (0xF800..0xFFFF) for any symbol crossing the line
- Stack growth area (0xF621..0xF6FF) for collisions
- The `__ivt_start = 0xF500` constant against the actual placement of
  symbols inside that range

## 2. Catalog of address-pinned vs movable items

### 2A. Externally pinned (cannot move; pinned by hardware or ABI)

| Item                       | Address           | Source of constraint            |
| -------------------------- | ----------------- | ------------------------------- |
| Z80 reset vector           | 0x0000            | CPU                             |
| Z80 NMI vector             | 0x0066            | CPU                             |
| CP/M zero-page (8 B)       | 0x0000..0x0007    | CP/M ABI (BIOS jump entries)    |
| CP/M IOBYTE                | 0x0003            | CP/M ABI                        |
| CP/M default DMA buffer    | 0x0080..0x00FF    | CP/M ABI                        |
| TPA                        | 0x0100..0xCFFF    | CP/M ABI                        |
| cpnos.com TEXT             | 0xDF80..(0xEC00)  | cpnos-build CODE_BASE           |
| BIOS jump table            | 0xEE00            | cpnos-build NIOS = 0xEE33 ←     |
| SNIOS jump table           | 0xEE33            | cpnos-build cpnios-shim.asm EQU |
| Display memory             | 0xF800..0xFFFF    | 8275 CRT controller hardware    |
| Frame counter (mirror)     | 0xFFFC..0xFFFF    | rcbios convention; in display   |

The `_bios_boot @ 0xEE00` constraint is *derived* from `_snios_jt @
0xEE33` (which IS hardware-pinned by cpnos-build's `cpnios-shim.asm`),
because the BIOS jt is 51 B and must immediately precede SNIOS jt for
NDOS's BIOS-routing offsets to resolve.  Move SNIOS jt and you can
move BIOS jt; both stay locked together.

### 2B. Convention-pinned (could move, but external code expects them)

| Item                  | Current addr     | Movable cost                    |
| --------------------- | ---------------- | ------------------------------- |
| zp_init_data target   | 0x0000..0x0007   | None — locked by CP/M ABI       |
| BDOS_DMAADDR          | 0x0080           | None — CP/M ABI                 |
| Reset SP              | 0xF700           | reset.s + payload.ld co-edit    |

### 2C. Internally placed (linker can decide; no external observer)

| Item              | Constraint                          |
| ----------------- | ----------------------------------- |
| **IVT** (36 B)    | Page-aligned only.  I register holds the high byte; device-supplied vector low byte must fall inside 36 B → top vector = 0x22 (PIO-B), so 36 B is exact. |
| Resident code     | Inside 0xEE00..0xF7FF, after BIOS+SNIOS jts. |
| Resident rodata   | Same.                               |
| Resident data     | Same.                               |
| Scratch BSS       | Anywhere with enough space.  Currently constrained: cpnos.com TEXT must end ≤ BSS_start, BSS_end ≤ stack_low, BSS not in IVT range. |
| PIO_RX ring (256 B) | Page-aligned (ISR `ld h, page; ld l, head` trick).  Must be inside RAM that prom_loader copies, OR cleared by relocator like scratch BSS. |
| Stack             | Inside RAM, above resident BSS, below display.  Stack pointer reset value reset.s. |

## 3. Where overlap risk currently bites

### 3A. SDCC IVT overlap (task #18, found this session)

`sections.asm` has `defc __ivt_start = 0xF500` but **no SECTION
reservation**.  z88dk's linker freely places `_cursor_down @ 0xF4FF`
and `_cursor_up @ 0xF516` inside that range.  At every boot
`setup_ivt()` writes 36 bytes of IVT pointers to 0xF500..0xF523,
**destroying the middle of cursor_down and the head of cursor_up**.

Mechanism by which this stays half-hidden:
- The corrupted bytes (16-bit pointers to ISRs at 0xF2A2 etc.) parse
  as `LD A,(nn); SBC A,A; JP P,nnnn; ...` on Z80, so execution
  often "falls through" to the next valid function instead of
  crashing.
- Banner (`\r\n` → cursor_down) survives by accident.
- Later code paths (CCP load, second-line netboot status) hit the
  corrupted bytes under different register state and crash.

### 3B. SDCC `_pio_rx_buf_page` ↔ actual buffer disagreement

`sections.asm` declares `_pio_rx_buf_page = 0xF7`, but `pio_rx_buf`
is in the default `bss_compiler` section and lands at **0xECEE**
(low byte 0xEE — not even page-aligned).  The ISR uses `ld h,
_pio_rx_buf_page; ld l, head` which builds an address of `0xF7xx`
— pointing into resident code/data, not into the buffer.

Dormant under TRANSPORT=sio because nothing strobes PIO-B in the
test harness.  Active under TRANSPORT=pio-irq → would corrupt
RESIDENT_CODE on every received byte.

### 3C. Cross-build drift opportunities

Every magic address in the layout is currently spelled in **multiple
places** (one per build pipeline + Makefile + headers):

| Address             | Locations                                            |
| ------------------- | ---------------------------------------------------- |
| 0xEE00 (BIOS_JT)    | payload.ld, sections.asm, cpnos-build/cpnios-shim.asm, BIOS_BASE comments |
| 0xEE33 (SNIOS_JT)   | payload.ld ASSERT, sections.asm comment, cpnios-shim.asm EQU |
| 0xF500 (IVT)        | payload.ld (`__ivt_start`), sections.asm (`defc`), init.c comments |
| 0xF700 (PIO_RX)     | payload.ld (PIO_RX origin + `_pio_rx_buf_page`), sections.asm (`defc`), isr.c comments |
| 0xF700 (stack)      | payload.ld (`__stack_top`), reset.s, reset.asm     |
| 0xEC00 (SCRATCH)    | sections.asm (`org`), payload.ld comments          |
| 0xF800 (display)    | hal.h, init.c, resident.c, payload.ld ASSERTs       |

Any single address change requires synchronized edits across 3-5
files in two compilers' pipelines.  Several historic regressions
came from one side moving and the other side not following
(Phase 33 `BIOS_BASE 0xF200 → 0xED00`, Path 4 `CODE_BASE 0xE180 →
0xDF80`, etc.).

## 4. Why "let the linker decide" is the right answer

Current SDCC build relies on **a hardcoded constant + an ad-hoc
section ordering + a post-link audit**.  This is fundamentally
fragile because:

1. The hardcoded constant and the section placement are independent
   sources of truth that can disagree silently (as IVT and pio_rx_buf
   demonstrate).
2. The audit only catches violations *after* the link succeeds; the
   damage is already in `cpnos.bin`, only the build gate refuses it.
3. Any future address shuffle requires touching multiple files.

Fully linker-driven layout flips this: every region is declared
**once**, the linker computes derived constants (page-high-byte,
end-of-region, alignment slack), and ASSERTs over all relationships
that the architecture requires.  Effects:

| Property                          | Hardcoded | Linker-driven |
| --------------------------------- | --------- | ------------- |
| Constant `__ivt_start = 0xF500` | manual; can disagree with placement | derived from `LABEL = .;` inside the section |
| `_pio_rx_buf_page`                | hand-edited | `HIGH(__pio_rx_bss_start)` |
| Page-alignment                    | comment-asserted | `align 256` directive enforces |
| Overlap with code/data            | hope + Python audit | link-time ASSERT |
| Move IVT 0xF500 → 0xF600          | edit 4+ files | edit 1 line in sections.asm |
| Discoverability of layout         | scattered | one file |

## 5. Proposed unified design

### 5A. Single source of truth: a memory-map file

Create `cpnos-rom/memory_map.h` (or `.inc`) with **only** the
externally-pinned addresses:

```c
/* Externally pinned — cannot be linker-decided. */
#define DISPLAY_BASE       0xF800   /* 8275 hardware */
#define BIOS_JT_ADDR       0xEE00   /* derived from NIOS+0xEE33 */
#define SNIOS_JT_ADDR      0xEE33   /* cpnos-build/cpnios-shim.asm */
#define CPNOS_TEXT_BASE    0xDF80   /* cpnos-build CODE_BASE */
/* ... TPA, ZP, etc. */
```

Both `payload.ld` and `sdcc/sections.asm` `#include` this file via
preprocessor (z88dk-z80asm passes through `#define`/`#include`-style
directives if pre-processed; clang's payload.ld already uses C
preprocessor — see Makefile `clang -E -P -x c ... payload.ld`).

### 5B. Sections, not literals, for everything else

Replace each `defc NAME = 0xADDR` with a section declaration that
**produces** the symbol via `.` assignment:

```asm
;-- IVT: 36 bytes, page-aligned, anywhere inside resident chain.
SECTION RESIDENT_IVT
align 256
__ivt_start:
defs 36
__ivt_end:

;-- PIO_RX: 256 bytes, page-aligned, anywhere.  Symbol-derived high byte.
SECTION RESIDENT_PIO_RX_BSS    ; NOLOAD-equivalent
align 256
__pio_rx_bss_start:
defs 256
__pio_rx_bss_end:

PUBLIC _pio_rx_buf_page
defc _pio_rx_buf_page = HIGH(__pio_rx_bss_start)
```

z88dk-z80asm supports:
- `align N` — pad to N-byte boundary
- `HIGH(symbol)` / `LOW(symbol)` — extract byte from address
- `__SECTION_*_head/size/tail` — per-section synthesised symbols
- `defs N` — reserve N bytes of zero (ROM image; in NOLOAD-style
  sections via Makefile `--ignore-section` to z88dk-appmake)

So the SDCC primitives exist.  The piece we don't currently use is
**`align`** + **HIGH() of a placed symbol**.

### 5C. Link-time ASSERTs in z88dk

z88dk-z80asm does not have ld.lld's `ASSERT(expr, msg)` directly,
but the same effect is achievable via:

- `ASSERT_NEAR(label1, label2, max_distance)` — check pairs of
  symbols are within range
- `IFDEF` + `defc` to compute constraints, manually error on
  violation via `defc` to a divide-by-zero or `__builtin_assert`
  trick (z80asm has limited expression error)
- **Cleanest**: extend `check_sdcc_layout.py` with the ASSERT
  conditions we want — they're already mechanically derivable from
  the map file.

The key delta versus today: today's audit is a *whitelist* of
ranges per section type.  Tomorrow's audit should be a *pairwise
overlap matrix* + *constraint list* (BIOS_JT == 0xEE00, SNIOS_JT ==
0xEE33, payload ≤ display, IVT outside payload, etc.).

### 5D. Display memory and "temporarily relieved"

The user noted display memory at 0xF800 *can be temporarily
relieved*.  Two interpretations:

1. **Pre-init.** The 8275 isn't initialised at reset; the 0xF800
   range behaves like normal RAM until `init_hardware()` programs
   the controller and DMA channels.  In that pre-init window the
   range is reusable.  Practical use: `BAD CHECKSUM` message in
   relocator (currently writes to 0xF800 *post* init in current
   code, but could move earlier).

2. **DMA-paused.** Once the 8275 is running, DMA continuously reads
   the 2 KB region; writes from CPU work but get redrawn within
   the next refresh.  Not "relieved" — the controller still owns
   the bytes.

For the layout question this means: pre-init code (relocator,
init_image) can use 0xF800..0xFFFF as scratch.  Post-init code
cannot.  If we wanted to grow resident *into* 0xF800 we'd need to
either reprogram the DMA source addr each frame, or shrink the
display window — both invasive.  Recommendation: **don't budget
on display memory; treat 0xF800 as a hard ceiling for resident.**

The frame counter at 0xFFFC..0xFFFF is a *deliberate* overlap with
display memory: the ISR writes there knowing the CRT will read it
back as the bottom-right cell of row 24 (or wraps to off-screen
attribute, depending on geometry).  That's a one-character cost
hidden in the corner.  Documented in `isr.c:113-117`.

### 5E. Migration order

This is mostly mechanical.  Suggested order:

1. **Define `memory_map.h`** with the 5-6 truly external constants.
   No layout change, just centralisation.  Replace duplicates in
   payload.ld + sections.asm + cpnos-build refs.

2. **SDCC: introduce `RESIDENT_IVT` section** with `align 256` +
   `defs 36`, export `__ivt_start` from inside.  Drop the `defc
   __ivt_start = 0xF500` literal.  Verify in `cpnos.map` that the
   linker chose a sensible page-aligned address.  This closes
   task #18.

3. **SDCC: introduce `RESIDENT_PIO_RX_BSS` section** with `align
   256` + `defs 256`, export `_pio_rx_buf_page = HIGH(...)` and
   `_pio_rx_buf` from inside.  Drop the `defc _pio_rx_buf_page =
   0xF7` literal.  Move `pio_rx_buf` declaration in
   `transport_pio.c` to use this section under SDCC.

4. **clang: mirror** — replace `__ivt_start = 0xF500` literal with
   a NOLOAD section between PAYLOAD and SCRATCH, page-aligned.
   Same for `_pio_rx_buf_page`.  Both builds end up with
   *symbol-derived* values and the literals are dropped from
   both pipelines.

5. **SDCC: add link-time ASSERT-equivalents** by extending
   `check_sdcc_layout.py` with: BIOS_JT_ADDR check, SNIOS_JT_ADDR
   check, IVT-outside-code check, PIO_RX-outside-code check,
   stack-growth-area-untouched check.  Roughly mirror the 16
   ASSERTs from `payload.ld`.

6. **Both: assert paired equality.** A meta-check that the same
   `memory_map.h` constants are reflected in both builds — a
   small Python script that diffs `clang/payload.elf` and
   `sdcc/cpnos.map` for each pinned symbol, fails CI on
   mismatch.  Catches "I edited memory_map.h but only one build
   picked it up."

The migration is **per-step shippable** — each step is a small,
verifiable improvement that doesn't require all of them to land.

## 6. What NOT to over-engineer

A few temptations to resist:

- **Generated linker scripts.** Tooling that generates `payload.ld`
  + `sections.asm` from a YAML/TOML config sounds clean but adds
  a build dependency for marginal gain over a shared `memory_map.h`.
- **Full memory-region declarations in z88dk.** z88dk-z80asm's
  section model is sequential-chain, not LMA/VMA-region; trying
  to fake clang's MEMORY{} blocks fights the tool.  Use what's
  natural: SECTION + align + defs.
- **Runtime layout changes.** All addresses are link-time fixed.
  Don't introduce a runtime memory manager; CP/M's TPA already
  provides that.

## 7. Concrete deliverables (if we proceed)

Files to add:
- `cpnos-rom/memory_map.h` — single source of truth for pinned addrs
- `cpnos-rom/tasks/sdcc-overlap-check.md` — list of overlap pairs
  the audit checks (or `check_sdcc_layout.py` comment header)

Files to edit:
- `cpnos-rom/sdcc/sections.asm` — add RESIDENT_IVT, RESIDENT_PIO_RX_BSS
  sections; drop two `defc` literals
- `cpnos-rom/payload.ld` — replace literals with symbols from new
  NOLOAD sections; add ASSERTs to mirror SDCC audit
- `cpnos-rom/transport_pio.c` — `pio_rx_buf` placement section
- `cpnos-rom/tasks/scripts/check_sdcc_layout.py` — extend overlap
  checks; mirror clang's ASSERTs
- `cpnos-rom/Makefile` — feed `memory_map.h` into both link paths
  (already does for clang via `-E -P`; add for SDCC via z88dk's
  preprocessor)

Tasks affected:
- Closes task **#18** (IVT location)
- Subsumes the latent `_pio_rx_buf_page` mismatch
- Reduces blast radius for any future cpnos.com address move
