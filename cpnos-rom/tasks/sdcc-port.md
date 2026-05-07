# cpnos-rom SDCC dual-compiler port

Started 2026-05-05 by user directive.  Goal: make cpnos-rom buildable
under SDCC (z88dk-zsdcc) in addition to the existing clang Z80 build,
so deploy time chooses one of two valid PROM images.  Third compiler
(HiTech zc, ravn/hitech) scaffolded but not implemented.

## Status — 2026-05-06

| Phase | Status         | Notes                                            |
| ----- | -------------- | ------------------------------------------------ |
| 1A    | DONE 2026-05-05 | hal.h three-backend dispatch                     |
| 1B    | DONE 2026-05-05 | compiler/compat.h shim                           |
| 1C    | DONE 2026-05-05 | all 10 .c files compile clean under SDCC -S      |
| 1D    | DEFERRED       | LDDR/LDIR sites — gated `#ifdef __clang__`, TODO |
| 2A    | DONE 2026-05-06 | Makefile COMPILER=clang/sdcc/hitech dispatch     |
| 2B    | DONE 2026-05-06 | Hybrid Option C+ link green: 2 KB PROM0 + 2 KB PROM1 = 4 KB image. |
| 2C    | DONE 2026-05-06 | reset.asm, bios_jt.asm, snios.asm, prom_loader.asm, hal.asm — all linked clean. |
| 2D    | PARTIAL 2026-05-06 | zp_init_data LDIR site fixed (cpnos_main.c).  resident.c::insert_line LDDR still gated `#ifdef __clang__` (task #17). |
| 2E    | PARTIAL 2026-05-06 | SDCC boots → netboots all 25 sectors → handoff (`I PNILOREC+P J`) → NDOS COLDST → nwboot → CCP load → STACK CORRUPTION.  Two JP-0 sources fixed this session: (a) NIOS placement (BIOS jt at 0xEE00 so SNIOS jt lands at 0xEE33 per cpnios-shim.asm); (b) _bios_stub_ret moved out of z88dk's code_l_sccz80 section into RESIDENT_CODE.  More JP-0 paths suspected (task #13).  Polypascal-test cannot run yet (tasks #15, #16). |
| 2F    | DONE 2026-05-06 | Link audit: pinned every z88dk runtime section (`code_*`, `rodata_*`, `data_*`, `bss_*`) inside its proper chain in `sdcc/sections.asm`; built `tasks/scripts/check_sdcc_layout.py` and wired it as a hard build-failure gate in the SDCC `cpnos.cim` recipe.  Caught and fixed `_memset @ 0xEDF1` (was outside resident, overlapping RESIDENT_JUMPTABLE); now `_memset @ 0xF7A3` inside resident.  Audit re-runs on every SDCC build and refuses to produce a `cpnos.bin` if any symbol is mis-placed or any sections overlap. |

## Bugs fixed this session (2026-05-06)

1. **TRANSPORT_NAME quoting under SDCC** — zcc strips inner double
   quotes from `-DTRANSPORT_NAME='"PIO-IRQ"'`, so SDCC parser saw
   bare `PIO-IRQ` token.  Fix: SDCC-conditional `-DTRANSPORT_NAME='\"...\"'`
   in Makefile (escaped quotes inside single-quoted shell arg).
2. **`<string.h>` shim for `__builtin_mem*`** — z88dk-zsdcc 4.5.0
   lowers `__builtin_memcpy/memset` to library calls without
   auto-declaring; assembler errored on `_memset`.  Fix: include
   `<string.h>` and `#define __builtin_memcpy memcpy` etc. in
   `compat.h`'s non-clang branch.
3. **File-scope vs block-scope externs** — SDCC only emits asm
   `EXTERN` directives for file-scope `extern` declarations.  Block-
   scope `extern void f(void);` inside a function body doesn't
   propagate.  Fixed by hoisting `clear_screen`, `kbd_*`, `pio_rx_*`,
   `cur_*`, `curx`, `cury`, `pio_rx_buf_page` to file scope in init.c
   and isr.c.
4. **PATH for z88dk-z80asm / z88dk-appmake** — zcc internally calls
   these via `$PATH`.  Fix: `export PATH := $(Z88DK_HOME)/bin:$(PATH)`
   in Makefile SDCC branch.
5. **xport_aliases.asm** — z88dk has no `--defsym` equivalent; use
   3-byte JP trampolines instead.  Generated at build time from
   `TRANSPORT=` value.
6. **cpnos.com BSS overlap (Path 4)** — SDCC BSS at 0xEC00 was being
   clobbered by cpnos.com sectors 22+ during netboot, killing
   `_cfgtbl.netst.ACTIVE`.  Fix: `cpnos-build/Makefile` `CODE_BASE`
   shifted from `LE180` to `LDF80` so cpnos.com ends at 0xEC00 and
   leaves 0xEC00..0xEDFF for slave BSS.  TPA reduces 56→55 KB (acceptable).
7. **Sentinel cause of stalls: NIOS placement** — cpnos.com hardcodes
   `NIOS = 0xEE33` in `cpnos-build/src/cpnios-shim.asm`.  SDCC initial
   layout had BIOS jt at 0xF200 → SNIOS jt at 0xF233, so NDOS's
   `call nios+0` jumped into uninitialised code.  Fix: sections.asm
   places RESIDENT_JUMPTABLE at org 0xEE00 (BIOS jt is 51 B → SNIOS
   jt at 0xEE33 ✓).
8. **`_bios_stub_ret` outside resident range** — SDCC's link of
   `void f(void){}` placed it in z88dk's `code_l_sccz80` section at
   0xEDF4, outside our PROM-loaded RAM.  NDOS's calls to unimplemented
   BIOS entries (LIST/PUNCH/SELDSK/...) JP'd into uninit RAM →
   eventually JP 0 → warm-boot loop.  Fix: defined `_bios_stub_ret`
   directly in `sdcc/bios_jt.asm SECTION RESIDENT_CODE` (NOT
   RESIDENT_JUMPTABLE — would shift SNIOS jt off 0xEE33).
9. **`zp_init_data` Phase 2D** — `cpnos_main.c::resident_handoff`'s
   LDIR was `#ifdef __clang__`-gated; SDCC saw a no-op `else`, so
   ZP[0..7] was never written.  NDOS's WBOOT calls then jumped via
   uninit ZP.  Fix: replace the SDCC `else` with `ASM_VOLATILE("ld
   hl,_zp_init_data; ld de,0; ld bc,8; ldir")`.
10. **`_memset` outside resident range — generalised root cause of #8**
    (2026-05-06).  z88dk's link auto-places `code_string` (containing
    `_memset` from libsdcc_iy/string), `code_clib`, `code_l_sccz80`,
    `code_home`, `code_crt_init` *anywhere* it can find a slot in the
    section chain.  In our previous layout that slot was at the tail
    of the SCRATCH_BSS chain (0xEDF1+), OUTSIDE the PROM-loaded
    resident range and *physically overlapping* RESIDENT_JUMPTABLE
    (0xEE00..0xEE0D).  Every `__builtin_memset` in resident.c
    (`clear_screen`, `scroll_up`, `erase_to_eol/eos`, `insert/delete_line`,
    `redraw`) called into uninitialised RAM.  Fix has two parts:
    (a) declare every runtime CODE/RODATA/DATA section explicitly
        in `sdcc/sections.asm` at the END of the resident chain (and
        every BSS alias inside the BSS chain) so z88dk has nowhere
        else to put them.  See `code_clib`, `code_string`, `data_clib`,
        `bss_clib`, etc. additions there.
    (b) hard build gate `tasks/scripts/check_sdcc_layout.py` runs
        after every SDCC link.  It parses `cpnos.map`, walks every
        `addr` symbol + every `__SECTION_head/size/tail`, fails the
        build if a `code_*`/`rodata_*`/`data_*` symbol resolves
        outside 0xEE00..0xF7FF, or a `bss_*` symbol resolves outside
        0xEC00..0xEDFF, or any two non-zero-size sections overlap.
        Re-runs of the broken layout produce: 4 violations including
        `_memset @ EDF1`, `code_string overlap with RESIDENT_JUMPTABLE`.
    This pair is the durable fix for the same class of bug #8 caught
    by hand: pin the sections + audit on every build.

## Architecture summary

cpnos-rom builds for both `clang` (LLVM Z80) and `sdcc` (z88dk-zsdcc)
from one set of `.c` sources via:

- `hal.h` — backend dispatch (`_port_in/_port_out` same call-shape
  per backend)
- `compiler/compat.h` — keyword/macro shim (`__naked`, `ASM_VOLATILE`,
  `SECTION_*`, `intrinsic_*`, `__builtin_mem*` for non-clang)
- `Makefile` `COMPILER=clang|sdcc|hitech` selects per-compiler tool/flag
  block; `BUILDDIR=$(COMPILER)` parameterises 96 paths

SDCC build adds 7 hand-written asm files in `cpnos-rom/sdcc/`:

| File                  | Section(s)                | Purpose                  |
| --------------------- | ------------------------- | ------------------------ |
| `sections.asm`        | (top, all sections decl)  | section ordering + origins |
| `reset.asm`           | RESET (org 0x0000)        | reset vector             |
| `prom_loader.asm`     | INIT_CODE                 | two LDIRs to copy resident to RAM |
| `bios_jt.asm`         | RESIDENT_JUMPTABLE + RESIDENT_CODE | CP/M BIOS jt + _bios_stub_ret |
| `snios.asm`           | RESIDENT_SNIOS_JT/SNIOS/DATA | SNIOS protocol code   |
| `hal.asm`             | RESIDENT_CODE             | _port_in/_port_out (sdcccall(1)) |
| `xport_aliases.asm`   | RESIDENT_CODE (generated) | _xport_send/recv → _transport_*_byte trampolines |

Plus two helper Python scripts in `tasks/scripts/`:
- `bin2inc.py` — generates `.inc` byte-array files for the clang
  `#include "*.inc"` workaround
- `build_prom_image.py` — assembles a 2 KB PROM image with chunks at
  specific offsets, padded with 0xFF
- `pad_rom.py` — older single-chunk pad-to-N helper
- `build_prom1.py` — older two-chunk PROM1 helper

`cpnos-build/Makefile` shifts cpnos.com `CODE_BASE` from `LE180` to
`LDF80` (Path 4) — cpnos.com ends at 0xEC00 instead of 0xEE00, freeing
0xEC00..0xEDFF in slave RAM for SDCC's larger BSS.  TPA reduces 56→55 KB.
Both clang and SDCC slaves load the same cpnos.com image at the new
address.  Permanent fix tracked as task #11 (relocatable cpnos.SPR).

## Phase 2E follow-up findings (2026-05-06 evening)

### IVT-overlap JP-0 source (found 2026-05-06 PM, fix deferred)

`cpnos-rom/sdcc/sections.asm` currently declares `__ivt_start = 0xF500`
as a `defc` constant.  This number is *not* a reservation — z88dk's
linker is free to place RESIDENT_CODE bytes at that address, and it
does:

```
_cursor_down = $F4FF   (RESIDENT_CODE; 23 B → 0xF4FF..0xF515)
_cursor_up   = $F516   (RESIDENT_CODE; 15 B → 0xF516..0xF524)
_home        = $F525
```

`setup_ivt()` in `init.c` writes 18 × 2 = 36 bytes to
`0xF500..0xF523` at boot, **destroying the tail of cursor_down (22 B)
and the head of cursor_up (14 B)**.  Any subsequent BIOS-CONOUT path
that reaches `cursor_down`/`cursor_up` (^J newline, ^Z up-arrow,
banner reflow at column 80, etc.) jumps into garbage IVT bytes →
JP-0 cascade.

Clang's `payload.ld` reserves a NOLOAD region at 0xF500..0xF523, so
RESIDENT_CODE physically cannot spill into it; SDCC's `sections.asm`
only stores the literal.  This is a structural difference between
the two builds, NOT a TableGen / regalloc issue.

**ISR audit (this session, 2026-05-06):** all four ISRs in `isr.c`
(`isr_noop`, `isr_crt`, `isr_pio_kbd`, `isr_pio_par`) compile cleanly
under SDCC with `__naked` honored (no compiler-inserted prologue/
epilogue), end with `ei; reti`, and save exactly the registers they
clobber (AF/HL for crt, AF/BC/HL for kbd, AF/HL for par).  No ISR
touches IX/IY or shadow registers.  Confirmed by inspecting SDCC
output of `isr.c -S`.  ISRs are NOT the JP-0 source.

**Fix deferred to task #18** — proper solution is to let the linker
decide the IVT address: `SECTION RESIDENT_IVT` with `align 256` +
`defs 36` inside the resident chain, export `__ivt_start` as a PUBLIC
label, mirror the change in clang's `payload.ld`, and extend
`tasks/scripts/check_sdcc_layout.py` to flag any symbol that lands
in `__ivt_start..__ivt_end`.

## Size oracle (final hybrid Option C+, 2026-05-06)

| Chunk                                  | Bytes | Budget | Headroom |
| -------------------------------------- | ----: | -----: | -------- |
| reset+prom_loader (PROM0 head)         |    29 |   1024 |    995 B |
| RESIDENT_PRE_CODE (PROM0 tail)         |   990 |   1024 |   **34 B** |
| RESIDENT_JUMPTABLE+body (PROM1 head)   |  1534 |   1536 |    **2 B** |
| Resident in RAM 0xEE00..0xF7FF         |  2524 |   2560 |     36 B |

Total ROM image: PROM0 (2 KB) + PROM1 (2 KB) = 4 KB, identical
in size to the clang build.

Display memory at 0xF800 is the hard ceiling — copying past 0xF800
would clobber the CRT controller's video RAM.  PROM1 chunk capped at
1536 B (= 0xF800 - 0xF200) for that reason; the trailing 512 B of
PROM1 is 0xFF padding (unused).

**Tightness warning** — RESIDENT body has only 2 B of headroom.  Any
further code growth in non-init .c files (resident.c, cpnos_main.c,
snios.asm) will overflow.  Mitigation if it does:

- move more files into RESIDENT_PRE (cap 1024 B, currently 34 B free)
- replace `__builtin_memcpy/memset` with inline LDIR/LDDR asm
  (saves ~50-150 B by skipping libsdcc memcpy/memset bodies)
- shrink netboot_mpm.c (mostly cold-init code)

## Phase 2E follow-up findings (2026-05-06 evening)

After the cpnos.com `CODE_BASE` shift to 0xDF80 and the resident-layout
fix (BIOS jt at 0xEE00 so SNIOS jt lands at NIOS=0xEE33 per
`cpnios-shim.asm` EQU), full handoff completes — every cold-init phase
emits its boot mark (`I PNILOREC+P J`).

**Discovered post-handoff bug**: SDCC's compilation of empty C function
`void bios_stub_ret(void) { }` placed the symbol in z88dk's
`code_l_sccz80` runtime-library section at ~0xEDF4 — outside our
PROM-loaded resident range (0xEE00..0xF7FF).  NDOS's calls to
unimplemented BIOS entries (LIST/PUNCH/SELDSK/READ/WRITE/...) JP'd
into uninitialised RAM, eventually wrapping to a `JP 0` warm-boot
loop.  Fixed by defining `_bios_stub_ret: ret` directly in
`sdcc/bios_jt.asm`'s `SECTION RESIDENT_CODE` (NOT in
`RESIDENT_JUMPTABLE` — would shift SNIOS jt off 0xEE33).  Original C
definition wrapped `#ifdef __clang__` since the SDCC link path now
provides the symbol.

**Still hung post-handoff** at gdbstub probe — slave reaches NDOS
COLDST + nwboot but stack contains multiple `0x0000` return values
(symptom of additional JP-0 cascades).  Recent sample (PC=0xE0CC,
SP=0xDCD7) showed return addresses including 0xF3DC (our
`_bios_stub_ret` — fix working) AND 0x0000 entries — meaning other
code paths still resolve to address 0 somewhere.  Probable causes
(unconfirmed): another SDCC-placed-outside-resident symbol, or
unbalanced push/pop in inline asm, or interrupt context smashing
the stack.

## Phase 2E first-boot results (2026-05-06)

`make cpnos-install COMPILER=sdcc TRANSPORT=sio` + 60 s MAME run with
SIO-A wired to mpm-net2 on :4002.  Captured SIO-B output:

```
RC702 CP/NOS 56K SIO 2026-05-06 08:14 6fd1b93+
......................
```

What this proves works under SDCC:
- reset vector (DI / SP=0xF700 / JP _relocate)
- prom_loader's two LDIRs (PROM0 tail -> 0xEE00, PROM1 -> 0xF200)
- JP _cpnos_cold_entry (now in RAM)
- init_hardware: port writes via hal.asm's `_port_out` (sdcccall(1))
- IVT setup, IM2 enable, ISR install
- SIO-A and SIO-B init, ASCII output via impl_conout
- Banner stringification (CPNOS_TPA_KB / TRANSPORT_NAME / BUILD_INFO_STR)
- First 22 ENQ/ACK rounds of SNIOS netboot

What stalls: SNIOS netboot freezes after ~352 of ~4096 bytes (22 dots
= 22 packets at 16 B/packet header).  Some SDCC-produced behavior
diverges from clang past the SNIOS handshake.  Suspects to investigate
(in priority order):

1. **`_xport_send_byte` / `_xport_recv_byte` aliases**: my
   `xport_aliases.asm` adds a JP trampoline (3 B + 10 T-states per
   call).  ENQ-ACK has tight timing requirements; the extra latency
   may push us past a CTC-derived window.  Test: drop the trampoline
   by direct `defc _xport_send_byte = _transport_send_byte` in
   sections.asm if z88dk supports it — falls under "alias an EXTERN
   from one TU to a defined symbol in another".
2. **ISR shadow-register handling**: cpnos's isr.c was hand-tuned so
   no ISR touches BC'/DE'/HL'/AF' (PolyPascal lives there).  SDCC's
   compilation of the C wrappers around inline asm might emit a stray
   `EX AF,AF'` / `EXX`.  Compare disasm of clang-`isr.o` vs sdcc-`isr.o`
   for the three ISRs.
3. **`__builtin_memcpy/memset` macros in compat.h** route to libsdcc
   functions for SDCC.  netboot_mpm.c uses memcpy in the credentials
   handoff.  Library memcpy may clobber more registers than clang's
   inline LDIR.  Test: replace those calls with explicit inline asm
   on the SDCC path.
4. **SDCC-emitted code timing** for the SNIOS retry loop: more
   T-states per iteration may exceed the master's ACK window and
   trigger NAK retries.  Lower-likelihood; the first 22 packets
   succeed which suggests timing isn't the gate.

Verdict: SDCC build boots cleanly, runs cold-init code correctly,
prints the banner, and starts netboot.  The netboot stall is a
focused regression vs the clang build — actionable but not yet
investigated.

## File assignment to PRE vs RESIDENT (Makefile target-CFLAGS)

| File              | Section            | Reason                          |
| ----------------- | ------------------ | ------------------------------- |
| init.c            | RESIDENT_PRE_CODE  | cold-init (one-shot use)        |
| netboot_mpm.c     | RESIDENT_PRE_CODE  | cold-init (one-shot use)        |
| transport_sio.c   | RESIDENT_PRE_CODE  | size-fit; transport reachable from anywhere |
| transport_pio.c   | RESIDENT_PRE_CODE  | size-fit                        |
| isr.c             | RESIDENT_PRE_CODE  | ISRs reachable via IVT          |
| cfgtbl.c          | RESIDENT_PRE_CODE  | size-fit; small table init      |
| cpnos_main.c      | RESIDENT_CODE      | cold_entry must JP-able from prom_loader |
| resident.c        | RESIDENT_CODE      | display + console hot path      |
| (bios_jt.asm)     | RESIDENT_JUMPTABLE | hard-pinned at 0xF200 (CP/M ABI) |
| (snios.asm)       | RESIDENT_SNIOS_*   | sequential after BIOS jt        |

## Phase 1 — source-level dual-compile

### 1A. hal.h — DONE 2026-05-05
- Three-backend dispatch in `hal.h`: clang z80 / SDCC|sccz80 / HiTech /
  host fallback.
- Same `_port_in(p)` / `_port_out(p, v)` signature in every backend.
- Clang side unchanged semantically; +1 B drift in PROM0 padding (1777->1778
  non-padding, payload byte-identical at 1738 B) due to source-map
  line-number reaction in init.c.

### 1B. compiler/compat.h — DONE 2026-05-05
- Renamed from `compiler/intrinsic.h` to avoid clash with z88dk's
  system `<intrinsic.h>`.
- ASM_VOLATILE, __naked, NORETURN, USED, NOINLINE, STATIC_ASSERT, SECTION_*,
  CPNOS_STR(x), intrinsic_di/_ei/_halt/_nop/_im_2/_ld_i_a per-backend.

### 1C. .c file conversion — DONE 2026-05-05
All 10 cpnos-rom .c files compile clean under SDCC `-S`.  Clang side
byte-stable: 1738 B payload / 1778 PROM0 non-padding.

### 1D. LDDR/LDIR sites — DEFERRED to Phase 2D
Two sites use clang Z80's `"+{de}"` / `"+{hl}"` / `"+{bc}"` register-
class constraints.  SDCC parser doesn't accept; `__builtin_memmove`
inflates clang Z80 payload past budget.  Both sites gated
`#if defined(__clang__) && defined(__z80__)` with TODO marker.
Replacement: shared `mem_copy_forward` / `mem_copy_backwards` helper
in runtime.{s,asm}.  Tracked: ravn/llvm-z80#126.

## Phase 2 — build infrastructure

### 2A. Makefile dispatch — DONE 2026-05-06
- `COMPILER ?= clang` selects the build path.  `BUILDDIR = $(COMPILER)`.
- Per-compiler tool/flag block: clang (existing path, byte-stable),
  SDCC (z88dk-zsdcc via `+z80 -clib=sdcc_iy`), HiTech (`$(error ...)`).
- `make cpnos COMPILER=clang`: byte-identical to baseline.
- `make cpnos COMPILER=sdcc`: invokes zcc, stops at first .s file.

### 2B/2C. Section layout + asm port — PARTIAL 2026-05-06

Files written (cpnos-rom/sdcc/):

- `sections.asm` — z88dk section ordering and origin addresses for
  cpnos-rom's four-region layout: RESET (0x0000), INIT_*, RELOCATOR_*,
  RESIDENT_PRE_* (org 0xEE00), RESIDENT_JUMPTABLE (org 0xF200),
  RESIDENT_SNIOS_*, RESIDENT_*, SCRATCH_BSS (org 0xEC00).
- `reset.asm` — port of reset.s.  z88dk syntax: SECTION RESET, EXTERN/PUBLIC.
- `bios_jt.asm` — port of bios_jt.s.  17-entry CP/M BIOS jump table.
- `snios.asm` — port of snios.s.  Mechanical translation of the 518-LOC
  SNIOS protocol code: `.equ` -> `defc`, `.section X,"ax",@progbits` ->
  `SECTION X`, `.global` -> `PUBLIC`, `.extern` -> `EXTERN`, `.2byte` ->
  `defw`, `.byte` -> `defb`.  Body Z80 instructions identical.

runtime.s NOT ported — z88dk's `+z80 -clib=sdcc_iy` provides memcpy /
memset / memchr / memmove / etc. as part of the standard runtime.

### 2B blocker — design fork: PROM-image build pipeline

The clang build pipeline is fundamentally different from a typical
z88dk single-link pipeline:

1. Compile all .c -> .o
2. Link **payload** with `payload.ld` (everything that runs at runtime
   addresses 0xEC00..0xF7FF — no PROM awareness)
3. Extract `payload.bin` via `llvm-objcopy --only-section=.payload`
4. Split into `payload_a.bin` (first 1024 B) + `payload_b.bin` (rest)
5. Generate `.inc` files via `bin2inc.py`
6. Compile `relocator.c` which `#include "init.inc" "payload_a.inc"
   "payload_b.inc"` as byte arrays with `__attribute__((section))`
7. Link **relocator** with `relocator.ld` — places the byte arrays at
   physical PROM offsets (PROM0 0x0400..0x07FF, PROM1 0x2000..0x27FF)
8. `llvm-objcopy --gap-fill=0xFF --pad-to=0x2800` -> `cpnos.raw`
9. dd extract bytes 0..0x07FF -> `prom0.bin`, 0x2000..0x27FF -> `prom1.bin`

The two-stage link + #include is essential: `payload.ld` lets the
runtime image use addresses 0xEC00..0xF7FF, while `relocator.ld`
places those bytes at physical PROM offsets via clang's
`__attribute__((section))` on the C arrays.

z88dk doesn't have an analogous primitive.  Three migration options:

**Option A — single-stage link, dd-extract from sparse binary.**
Keep all sections in one z88dk link; the resulting binary will be
sparse (filled to 0xF800).  Extract prom0 = bytes[0..0x07FF],
prom1 = bytes[0x2000..0x27FF].  Resident chunks at VMA 0xEE00 /
0xF200 sit at those binary offsets, but they need to be COPIED to
PROM offsets 0x0400 / 0x2000 by a runtime relocator.  Need to either
write that relocator in z80asm OR keep the existing C relocator and
embed payload bytes as defb-arrays generated from the dd-extracted
chunks.  Cleanest: dd from the z88dk binary, then a `bin2inc.py`-
equivalent emits an asm `defb` block that gets included in a
parallel `relocator_sdcc.asm` file.  ~3-5 hours.

**Option B — two-stage build mirroring clang's pipeline.**  Link
SDCC payload (sections at 0xEC00..0xF7FF) -> payload.bin -> split ->
generate .inc -> relocator.c (compiled by SDCC) #includes the .inc
files -> link relocator with custom z88dk sections.asm that pins
the byte arrays at PROM0 tail / PROM1.  Closer to clang's pipeline
but requires SDCC `--codeseg` / `--constseg` to land arbitrary `const
unsigned char arr[]` at specific PROM offsets.  z88dk `org` works
per section but mixing data sections at multiple origins inside one
link is awkward.  ~5-8 hours.

**Option C — skip the relocator, two separate ROM links.**  Build
PROM0 and PROM1 as two independent z88dk links with their own
sections.asm files.  PROM0 is reset + init code; PROM1 holds
.resident.  Reset code copies PROM1 contents to RAM at 0xF200
directly (no .inc, no #embed).  Loses the unified-payload model;
makes maintaining the resident section feel different in clang vs
sdcc.  ~2-3 hours but worse architectural coherence.

**Recommendation** (deferred to user): Option A is the most natural
fit to z88dk's section model and reuses existing infrastructure
(bin2inc.py extended to emit asm).  Tracked separately because it
needs user input.

## Phase 3 — validation (TODO)

`cpnos-polypascal-test` against the SDCC build.  Confirm transport,
NDOS, BDOS, console, keyboard, file load, code execution, output
framing all work equivalent to clang build.  Compare sizes.

## Notes / decisions

- Coexistence required (user 2026-05-05): two output dirs, deploy
  picks one.  No replacement.
- Same _port_in/_port_out call shape across backends (clarity rule).
- HiTech C scaffold: hal.h #error with TODO comment, intrinsic.h
  with `#error`, Makefile path errors with "not yet implemented".
- snios.s mechanical translation took only ~30 directive substitutions
  across 518 LOC — Z80 instruction syntax is identical.  Same
  pattern would apply if/when reset.s / bios_jt.s grow.
