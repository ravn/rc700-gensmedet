# cpnos-rom Memory Map and Linker Sections

Authoritative reference for cpnos-rom's address-space layout and the
linker sections that produce it.  Last refreshed 2026-05-10
(post-Phase 58 / #75 close-out).

**Authoritative sources** (this doc summarises; if it disagrees with
any of the below, the source files win):

| Concern | clang | SDCC |
|---|---|---|
| PROM-side layout (relocator + chunks) | `cpnos-rom/relocator.ld` | (same Makefile-driven `dd` split) |
| Resident image layout | `cpnos-rom/payload.ld` | `cpnos-rom/sdcc/sections.asm` |
| cpnos.com base | `cpnos-rom/cpnos-build/Makefile` (CODE_BASE / DATA_BASE) | (same) |
| Per-file section assignment | `__attribute__((section(".X")))` in `compiler/compat.h` | `--codeseg X` / `--constseg X` per-file `CFLAGS` in `Makefile` |

The linker scripts contain hard ASSERTs at all critical boundaries.
A boundary violation fails the build with a clear message; this doc
explains the WHY.

---

## 64 KB address space (post-PROM-disable)

```
0x0000 ┌────────────────────────────────────────┐
       │ Z80 zero page                          │
       │ 0x0000..0x00FF                         │
       │ ┌─ 0x0000  jp WBOOT (set by zp_init_data on cold boot)
       │ ├─ 0x0005  jp BDOS  (set by cpnos.com when NDOS hands off)
       │ └─ 0x0007..0x00FF unused (CP/M reserves; NMI vector etc.)
0x0100 ├────────────────────────────────────────┤
       │ TPA — Transient Program Area           │
       │ 0x0100..0xD97F                         │
       │ Apps load + run here.                  │  ~54.5 KB
       │ User CCP, MBASIC, M80, BDOS apps...    │
0xD980 ├────────────────────────────────────────┤
       │ cpnos.com DATA segment                 │  1024 B
       │ 0xD980..0xDD7F                         │  (per cpnos-build CODE/DATA_BASE)
0xDD80 ├────────────────────────────────────────┤
       │ cpnos.com CODE segment                 │  ~3.2 KB
       │ 0xDD80..0xE9FF                         │  CCP + NDOS + cpbios stubs.
       │                                        │  Loaded by netboot from master's CPNOS.IMG.
       │ Contains the NDOS SNIOS-JT stub that   │
       │ forwards to our 0xED33 SNIOS JT.       │
0xEA00 ├────────────────────────────────────────┤
       │ IM 2 IVT page                          │  256 B reserved
       │ 0xEA00..0xEAFF                         │  (only 36 B = 18 vectors used)
       │ I register = 0xEA selects this page.   │  set by init.c::setup_ivt
0xEB00 ├────────────────────────────────────────┤
       │ SCRATCH BSS (NOLOAD; zeroed by         │
       │ relocator's BSS-pair loop)             │  512 B region
       │ 0xEB00..0xECFF                         │  (~275 B used in current build)
       │                                        │
       │ Holds: cfgtbl (210 B), kbd_ring,       │
       │   clang static-stack frames            │
       │   (__sframe_<funcname>)                │
       │                                        │
       │ Was 0xF500 pre-#75 Phase 5+6;          │
       │ relocated to 0xEB00 (the unused gap    │
       │ above IVT in cpnos.com layout) to      │
       │ free 0xF500..0xF6FF for the larger     │
       │ plain-C SNIOS payload.                 │
0xED00 ├────────────────────────────────────────┤
       │ Resident image (RAM-resident BIOS +    │  ~2.1-2.2 KB used today
       │ SNIOS + ISRs + transport)              │  (~2.5 KB region max)
       │                                        │
       │ Loaded into RAM by the PROM-side       │
       │ relocator at cold boot.  Persists      │
       │ across PROM disable (`OUT (0x18),A`).  │
       │                                        │
       │ Layout (in load order, see § Resident  │
       │ image internal layout below):          │
       │  0xED00 BIOS jt (51 B + 2 B)           │
       │  0xED33 SNIOS jt (24 B, NDOS ABI)      │
       │  0xED4B SNIOS bridges (10 B asm)       │
       │  ...    transport + ISRs + C bodies    │
       │  ...end .resident_checksum (2 B)       │
       │                                        │
0xF500 ├────────────────────────────────────────┤
       │ Free space (was SCRATCH pre-#75)       │
       │ 0xF500..(end-of-resident)              │  Used as resident growth space
       │                                        │  on the post-#75 layout.
       │ Whatever's left between resident-end   │
       │ and the stack region (below) is        │
       │ unused.                                │
       ├────────────────────────────────────────┤
       │ Stack growth area                      │  ~223 B
       │ ~0xF621..0xF6FF                        │  __stack_top = 0xF700;
       │                                        │  growing downward.
0xF700 ├────────────────────────────────────────┤
       │ PIO_RX BSS (NOLOAD)                    │  256 B page-aligned
       │ 0xF700..0xF7FF                         │  PIO-B receive ring buffer.
       │                                        │  Page-aligned for ISR's
       │                                        │  `ld h, page; ld l, head` trick.
0xF800 ├────────────────────────────────────────┤
       │ Display memory (8275 CRT)              │  2048 B
       │ 0xF800..0xFFCF                         │  80 × 25 character cells
       │                                        │  (hardware-mapped, write-only
       │                                        │   from CPU's perspective).
0xFFD0 ├────────────────────────────────────────┤
       │ Free scratch RAM                       │  44 B
       │ 0xFFD0..0xFFFB                         │
0xFFFC ├────────────────────────────────────────┤
       │ Frame counter                          │  4 B (u32)
       │ 0xFFFC..0xFFFF                         │  Incremented each vsync by isr_crt.
       │                                        │  Read at FRAME_COUNTER_ADDR.
0xFFFF └────────────────────────────────────────┘
```

---

## 4 KB PROM (boot-time, before `OUT (0x18),A`)

Two 2 KB PROMs are mapped at 0x0000 and 0x2000 at reset.  After
`OUT (0x18),A` ("RAMEN"), both are unmapped and the underlying RAM
shows through.  By that point the resident image is in RAM 0xED00+,
so execution continues seamlessly.

```
PROM0 (2 KB at 0x0000):
0x0000 ┌────────────────────────────────────────┐
       │ Reset vector (.reset section)          │  16 B
       │ 0x0000..0x000F                         │  Sets SP, jumps to relocator.
0x0010 ├────────────────────────────────────────┤
       │ Relocator + payload header             │  ~656 B max
       │ 0x0010..0x029F                         │  (.text in relocator.ld)
       │                                        │
       │ Reads `__payload_header` struct, copies│
       │ chunk-A from 0x0520 to RAM 0xED00,     │
       │ copies chunk-B from PROM1 0x2032 to    │
       │ RAM 0xEDxx, zeroes BSS-pair regions,   │
       │ verifies word-additive checksum,       │
       │ tail-calls _cpnos_cold_entry.          │
0x02A0 ├────────────────────────────────────────┤
       │ Cold-init code (INIT_CODE)             │  640 B max
       │ 0x02A0..0x051F                         │  (ASSERT __init_end <= 0x520)
       │                                        │
       │ Runs in place from PROM:               │
       │  - print_banner (cpnos_cold.c)         │
       │  - init_hardware (init.c) — port init, │
       │    IVT setup, IM 2 mode, EI            │
       │  - cfgtbl_init (cfgtbl.c)              │
       │  - netboot_mpm (netboot_mpm.c)         │
       │                                        │
       │ Tail-jumps to RAM-resident             │
       │ resident_handoff at 0xEDxx, which      │
       │ does OUT (0x18),A.  After that point   │
       │ this region is no longer mapped.       │
0x0520 ├────────────────────────────────────────┤
       │ Resident chunk-A                       │  736 B (PROM0 tail)
       │ 0x0520..0x07FF                         │  Loaded to RAM 0xED00 by relocator.
0x0800 └────────────────────────────────────────┘

PROM1 (2 KB at 0x2000):
0x2000 ┌────────────────────────────────────────┐
       │ Payload header P1 (.payload_header_p1) │  50 B
       │ 0x2000..0x2031                         │  Mirror of the magic + sentinel
       │                                        │  for dual-header consistency check
       │                                        │  (catches PROM0/PROM1 mismatch).
0x2032 ├────────────────────────────────────────┤
       │ Resident chunk-B                       │  variable size
       │ 0x2032..0x27FF                         │  Loaded to RAM 0xEDxx (after
       │                                        │  chunk-A) by relocator.
       │                                        │  Currently 1402 B clang /
       │                                        │  ~1428 B SDCC.
0x2800 └────────────────────────────────────────┘
```

---

## Resident image internal layout (LOAD-time order in payload.bin)

The resident image is one contiguous blob produced by linking
`payload.elf` at VMA = LMA = 0xED00.  It's then split by `dd` into
chunk-A (PROM0 tail) and chunk-B (PROM1) for ROM placement; the
relocator stitches it back together in RAM at boot.

The order below matches the order of bytes in `payload.bin`, which
is the order they end up in RAM 0xED00+ after relocator copy.

| Section name(s) | Role | Approx size |
|---|---|---:|
| `.resident.jumptable` | BIOS jump table (17 entries × 3 B = 51 B + 2 B `_zp_init_data` header) | 53 B |
| `.resident.snios_jt` | SNIOS jump table — public to NDOS at 0xED33 | 24 B |
| `.resident.snios` | SNIOS-area asm: 2 BC→HL bridges (`_snios_sndmsg_jt`, `_snios_rcvmsg_jt`) | 10 B |
| `.resident.isr` | All ISRs: `_isr_crt`, `_isr_pio_kbd`, `_isr_pio_par`, `_isr_noop`, helpers | ~150-200 B |
| `.resident_pre`, `.text.init` | (legacy section names; consolidated into resident below) | — |
| `.resident`, `.text*`, `.rodata*`, `.data*` | Bulk of resident: BIOS function bodies, SNIOS C bodies, transport, display ops | ~1500-1800 B |
| `.payload_checksum` | 2-byte placeholder; post-link patched so word-additive sum = 0xCAFE | 2 B |

All input sections from C `__attribute__((section("X")))` and asm
`.section X` directives end up here, glued by `payload.ld`'s
SECTIONS block.

---

## Linker sections (segment-level reference)

cpnos-rom uses the following named sections.  The section name
appears in:
- clang: as `__attribute__((section(".X")))` on individual functions
  / variables (and as `.section X` in `.s` files);
- SDCC: as `--codeseg X` / `--constseg X` per-file CFLAGS (the entire
  TU's code/rodata goes to that seg) and `SECTION X` directives in
  `.asm` files.

### PROM-side sections (in PROM image; unmapped after RAMEN)

| Section | Address range | Per-compiler designation |
|---|---|---|
| **`.reset` / `RESET`** | PROM0 0x0000..0x000F | `reset.s` body — di, set SP, jp _relocate |
| **`.text` (relocator)** | PROM0 0x0010..0x029F | `relocator.c`'s code; clang's relocator.ld assigns it explicitly |
| **`.payload_header`** | inside relocator region | The `__payload_header` struct emitted by the C source — read by `_relocate` to find chunks + BSS pairs + entry point |
| **`INIT_CODE`** | PROM0 0x02A0..0x051F (≤ 640 B) | Cold-init function bodies; SDCC: `--codeseg INIT_CODE` per-file (`init.c`, `cfgtbl.c`, `netboot_mpm.c`, `cpnos_cold.c`); clang: `__attribute__((section(".init.text")))` |
| **`INIT_RODATA`** | inside INIT_CODE region | Cold-init read-only data (banner string literals, etc.); SDCC: `--constseg INIT_RODATA`; clang: `__attribute__((section(".init.rodata")))` |
| **`.prom0_tail`** (chunk-A) | PROM0 0x0520..0x07FF (736 B) | First 736 B of payload.bin extracted by `dd` and embedded by the relocator's `#embed` |
| **`PAYLOAD_HEADER_P1`** | PROM1 0x2000..0x2031 (50 B) | Mirror of payload header at top of PROM1 — for cross-PROM consistency check |
| **`.prom1`** (chunk-B) | PROM1 0x2032..0x27FF (variable) | Rest of payload.bin extracted by `dd` |

### RAM-side sections (resident image; persists across RAMEN)

| Section | VMA | Per-compiler designation |
|---|---|---|
| **`.resident.jumptable` / `RESIDENT_JUMPTABLE`** | 0xED00..0xED32 | BIOS jt (`_bios_jt` and 17 entries: BOOT/WBOOT/CONST/CONIN/CONOUT/LIST/PUNCH/READER/HOME/SELDSK/SETTRK/SETSEC/SETDMA/READ/WRITE/LISTST/SECTRAN); plus `_zp_init_data` and `_bios_stub_ret` |
| **`.resident.snios_jt` / `RESIDENT_SNIOS_JT`** | 0xED33..0xED4A (24 B) | SNIOS jt (8 entries: NTWKIN/NTWKST/CNFTBL/SNDMSG/RCVMSG/NTWKER/NTWKBT/NTWKDN) — `_snios_jt` symbol; ABI-fixed at 0xED33 (asserted in payload.ld) |
| **`.resident.snios` / `RESIDENT_SNIOS`** | 0xED4B..0xED54 (10 B) | The two BC→HL bridges `_snios_sndmsg_jt` and `_snios_rcvmsg_jt`; everything else previously in this section moved to `snios_c.c` (now in `RESIDENT_CODE`) |
| **`.resident.isr` / `RESIDENT_ISR`** | follows snios | All ISR bodies; SDCC: per-file `--codeseg RESIDENT_ISR` (currently only `isr.c`); clang: `SECTION_RESIDENT_ISR` macro |
| **`.resident_pre` / `RESIDENT_PRE_CODE`** | follows ISRs | Transport layer (`transport_pio.c`, `transport_sio.c`); SDCC: `--codeseg RESIDENT_PRE_CODE`; clang: `SECTION_RESIDENT_PRE` |
| **`.resident_pre.rodata` / `RESIDENT_PRE_RODATA`** | follows pre-code | Transport-layer const data |
| **`.resident` / `RESIDENT_CODE`** | follows pre-code | Default for non-init resident C code: `cpnos_main.c`, `resident.c`, `rc700_console.c`, `snios_c.c`; SDCC: default `--codeseg RESIDENT_CODE`; clang: `SECTION_RESIDENT` |
| **`.rodata*` / `RESIDENT_RODATA`** | folded into resident | Const data: lookup tables, string literals; SDCC: `--constseg RESIDENT_RODATA`; clang: default rodata sections all glob into `.payload` |
| **`.data*` / `RESIDENT_DATA`** | folded into resident | Initialised writable data (rare in cpnos-rom) |
| **`.payload_checksum` / `RESIDENT_CHECKSUM`** | last 2 B of resident | 2-byte placeholder; post-link `cpnos-build/patch_payload_checksum.py` overwrites it so word-additive sum over the full resident equals 0xCAFE |

### RAM-side BSS (NOLOAD; zeroed by relocator at boot)

| Section | VMA | Contents |
|---|---|---|
| **`.ivt` / `bss_ivt`** | 0xEA00..0xEAFF | IM 2 IVT page (256 B reserved, 36 B used) |
| **`.scratch_bss` / `bss_compiler` + `bss_cfgtbl`** | 0xEB00..(varies) | `cfgtbl` (210 B), `kbd_ring`, clang static-stack frames |
| **`.bss.cfgtbl` / `bss_cfgtbl`** (sub-section) | inside scratch | Specifically the `cfgtbl` struct |
| **`.pio_rx_bss` / `bss_pio_rx`** | 0xF700..0xF7FF | PIO-B receive ring buffer (256 B, page-aligned) |

### z88dk runtime sections (SDCC build only)

z88dk's runtime library uses its own section naming.  Each is
explicitly placed in `sdcc/sections.asm` so the link audit
(`tasks/scripts/check_sdcc_layout.py`) catches any symbol that
resolves outside the resident image.

| Section | Role |
|---|---|
| `code_clib` | z88dk libc helpers (rare; we minimise these) |
| `code_l_sccz80` | sccz80 inline runtime (alias targets) |
| `code_string` | `_memcpy`, `_memset`, `_memmove` library implementations |
| `code_home` | Per-source homing code |
| `code_crt_init` | CRT init-time code (we don't actually run this) |
| `code_compiler` | Compiler-emitted helpers (`___sdcc_call_hl`, `___sdcc_enter_ix`, etc.) |
| `bss_clib`, `bss_string`, `bss_compiler` | BSS counterparts of the above |

These are forced-anchored at the end of the SDCC `RESIDENT_CODE`
chain so they don't accidentally land in cold-init or scratch
regions.

---

## Section assignment mechanics — clang vs SDCC

**Clang** uses per-function `__attribute__((section(...)))`.  This
is byte-precise: any C function or variable gets assigned to its
declared section regardless of which `.c` file it lives in.

The macros in `compiler/compat.h`:
```c
#define SECTION_RESIDENT      __attribute__((section(".resident"), used))
#define SECTION_RESIDENT_ISR  __attribute__((section(".resident.isr"), used))
#define SECTION_INIT_TEXT     __attribute__((section(".init.text")))
... (etc)
```

**SDCC** uses per-file `--codeseg X` / `--constseg X` flags.  This
is whole-file: the entire compilation unit's code goes to one named
segment.  So if you want some functions in `INIT_CODE` and others
in `RESIDENT_CODE`, you must split them across `.c` files.

Per-file assignment in `cpnos-rom/Makefile`:
```make
$(BUILDDIR)/init.o:           CFLAGS := $(SDCC_INIT_CFLAGS)  # INIT_CODE
$(BUILDDIR)/netboot_mpm.o:    CFLAGS := $(SDCC_INIT_CFLAGS)  # INIT_CODE
$(BUILDDIR)/cfgtbl.o:         CFLAGS := $(SDCC_INIT_CFLAGS)  # INIT_CODE
$(BUILDDIR)/cpnos_cold.o:     CFLAGS := $(SDCC_INIT_CFLAGS)  # INIT_CODE
$(BUILDDIR)/transport_sio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)   # RESIDENT_PRE_CODE
$(BUILDDIR)/transport_pio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)   # RESIDENT_PRE_CODE
$(BUILDDIR)/isr.o:            CFLAGS := $(SDCC_PRE_CFLAGS)   # RESIDENT_PRE_CODE
$(BUILDDIR)/relocator.o:      CFLAGS := $(SDCC_INIT_CFLAGS)  # INIT_CODE
# all others default to RESIDENT_CODE
```

**Practical consequence**: a function that needs to live in
`INIT_CODE` on SDCC must be in a TU dedicated to INIT_CODE.  This
is why `cpnos_main.c` was split into `cpnos_main.c` + `cpnos_cold.c`
in Phase 51A.2 (#68): the cold-entry function had to move out of
the resident TU into an INIT_CODE TU.  Saved 108 B SDCC resident.

The resulting cross-TU optimization barrier is documented as
ravn/rc700-gensmedet#88 (~50-150 B cost from no-LTO + per-file
codeseg).

---

## Section-level invariants (load-bearing ASSERTs)

These are checked at link time; a violation fails the build with a
clear message.  Listed in approximate order of severity.

1. **`_bios_boot == 0xED00`** — BIOS jump table must start at the
   resident base.  NDOS calls into the BIOS at `_bios_boot + N*3`.
2. **`_bios_conout - _bios_boot == 12`**, **`_bios_sectran - _bios_boot == 48`** — BIOS jt slot offsets are ABI-fixed (CP/M 2.2 BIOS contract).
3. **`_snios_jt == 0xED33`** — SNIOS jump table must follow the
   BIOS jt at the offset NDOS expects.  cpnos.com's
   `cpnios-shim.asm` hardcodes this address.
4. **`__cpnos_load_end <= 0xEA00`** — cpnos.com's CODE end must not
   overflow into the IVT region.
5. **`__cpnos_load_end <= 0xED00`** — cpnos.com's CODE end must not
   overflow into the resident region.
6. **`__ivt_end <= 0xED00`** — IVT must not overflow into resident.
7. **`__stack_top > __cpnos_load_end`** — stack top must be above
   cpnos.com's load end (else stack pushes corrupt loaded image).
8. **`__scratch_bss_end <= __payload_start`** — SCRATCH (at 0xEB00)
   must end before the resident image starts at 0xED00.
9. **`__payload_end <= 0xF800`** — resident must not overflow into
   display memory.
10. **`__payload_end <= 0xF700`** — resident must not overlap PIO_RX
    ring at 0xF700.
11. **`(__pio_rx_bss_start & 0xFF) == 0`** — PIO_RX must be
    page-aligned (so ISR can use `ld h, page; ld l, head`).
12. **`_zp_init_data >= 0xED00 && < 0xF800`** — zp_init_data must be
    in resident RAM (it's read AFTER PROM disable; reading it from
    .init.rodata would silently fail).

If you move any of these boundaries, search for the matching
ASSERT in `payload.ld` (clang) or `sdcc/sections.asm` /
`sdcc/check_sdcc_layout.py` (SDCC) and update in lockstep.

---

## Moving a section boundary

Before moving any address in this map:

1. Identify all C `__attribute__((section(...)))` placements that
   reference the affected region (`grep -r 'section(' .`).
2. Identify all SDCC `--codeseg` / `--constseg` per-file CFLAGS in
   the Makefile that reference it.
3. Update `payload.ld`'s `MEMORY` block + ASSERTs.
4. Update `sdcc/sections.asm`'s SECTION ordering + addresses (this
   is the SDCC linker's view; must mirror clang's payload.ld).
5. Update `relocator.ld` if PROM-side regions are affected.
6. Update `cpnos-build/Makefile` if cpnos.com base shifts (this
   cascades to NDOS via cpnos_addrs.h regeneration).
7. Update this doc.
8. Run `make cpnos-polypascal-test COMPILER=clang` AND `COMPILER=sdcc`
   (4-cell matrix).

Tools that catch drift:
- `payload.ld` ASSERTs (clang link-time).
- `tasks/scripts/check_sdcc_layout.py` (SDCC link-time; symbol
  out-of-range guard).
- `tasks/scripts/check_no_frame_ptr.py` (regression gate for
  unintended IX-frame growth).
- `tasks/scripts/check_unreferenced_publics.py` (dead-symbol gate).

---

## See also

- `cpnos-rom/CPNET_WIRE_PROTOCOL.md` — CP/NET 1.2 byte protocol spec
  (separate concern: what bytes go on the wire vs where they live in
  memory).
- `cpnos-rom/PORT_OUTPUTS.md` — RC702 I/O port map.
- `cpnos-rom/README.md` — entry-level overview.
- `cpnos-rom/payload.ld` — clang authoritative source for resident layout.
- `cpnos-rom/sdcc/sections.asm` — SDCC authoritative source.
- `cpnos-rom/relocator.ld` — clang authoritative source for PROM-side layout.
- `cpnos-rom/Makefile` — `dd` split + per-file SDCC `--codeseg` + ASSERTs.
- `tasks/timeline.md` — phase-by-phase narrative including layout shifts:
  Phase 50 (cold-init → PROM-only), Path 6 (cpnos.com base 0xDF80→0xDD80),
  Phase 56 (wire spec authored), Phase 57 (#75 plain-C SNIOS landed),
  Phase 58 (size-optimization investigation).
- `ravn/rc700-gensmedet#82` — ZX0 compression (alternative source of headroom).
- `ravn/rc700-gensmedet#88` — Cross-TU optimization barrier (the cost of
  the per-file SDCC `--codeseg` split + no LTO).
