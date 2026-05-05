# RC702 CP/M BIOS in C (REL30)

Rewrite of the REL30 BIOS in C using z88dk with sdcc backend, following the
same approach as `autoload-in-c/` (ROA375 PROM rewrite).

See `rcbios/BIOS_IN_C_PLAN.md` for the full implementation plan.

There is a good explanation of the CP/M data structures and their naming at https://www.idealine.info/sharpmz/dpb.htm. 

TODO:  Rewrite bios routines to use https://www.z88dk.org/wiki/doku.php?id=libnew:intrinsic#intrinsics_-_function_return_value to indicate the return value is in C and not A, and possibly use some of the demo programs to test code generation.

2026-03-10:  BIOS is now feature-complete (except for harddisk support) and boots CP/M to A> on the MAXI 8" disk image. Remaining work is refactoring and size reduction to fit the MINI 5.25" image.  Also making hot paths as fast as possible and move as many pointer operations to standard C idioms working on table structures etc, and then add peep hole optimization to make the generated code sharper.

2026-03-11:  Major refactoring session.  Converted all inline asm to `__asm__()` form.
Converted 6 SIO ISRs from `__naked` to `__critical __interrupt(N)` (pure C).
Discovered and documented RETN vs EI+RETI bug (`__interrupt(N)` number is mandatory).
Refactored display memory as typed 2D array (`Display[25][80]`) with all dimensions
derived from `sizeof`.  Added 7 dead-code elimination peephole rules saving 69 bytes
(discovered gap in sdcc/z88dk: neither eliminates unreachable asm after unconditional
jumps).  Fixed copt comment parsing issue (`;` lines corrupt rule boundaries).
Size: 6762 → 6702 bytes.

2026-03-11:  Binary size analysis and optimization.  Removed danish.bin character
conversion tables (384 bytes) — PROM loads tables from disk already, BIOS only needs
placeholder space.  Cold boot generates identity mapping tables instead.  Rewrote
`specc()` control character dispatch from switch to if/return chain for frequency-based
ordering (CR/LF first) — sdcc sorts switch cases by value, if/return preserves source
order.  Added 4 conditional jump inversion peephole rules (`jr NZ/jp` → `jp Z`) saving
34 bytes across 17 call sites.  Extracted `start_xy()` for tail-call optimization.
Size: 6702 → 6692 bytes.

2026-03-11:  Code pattern optimization session.  Key changes:
- Merged `secrd()`/`secwr()` into `sec_rw(cmd, dma_dir)` — eliminated 91 bytes of
  duplicated retry/recalibrate logic (the largest single saving).
- Replaced explicit shift loops (`while (n--) mask >>= 1`) with direct expressions
  (`0x80 >> n`, `0xFF >> n`, `0xFF << n`) — sdcc generates tight inline shift loops
  instead of round-tripping through static variables each iteration. Saved 79 bytes
  across `bg_set_bit`, `bg_clear_from`, and `rwoper`.
- Eliminated load-modify-store through temp variables (`val = *ptr; val &= ~mask;
  *ptr = val` → `bgstar[byteoff] &= ~mask`) — compound assignment generates direct
  read-modify-write. Saved 31 bytes in `bg_clear_from`.
- Removed dead `gfpa()` function (24 bytes), inlined `trkcmp()` (10 bytes).
- Computed SELDSK format index once instead of twice (5 bytes).
- Changed `clear_foreground` loop counter from `word` to `byte` (9 bytes).
- Added peephole rules for redundant `xor a,a` after `ld (var),a` (3 bytes).
- Also: extracted `jump_ccp()` as `__naked` function, reordered `goto00`/`start_xy`,
  made Makefile z88dk/zmac paths portable, added `lis.sh` listing navigation tool.
Size: 6692 → 6439 bytes (253 bytes saved, 36% of gap to mini closed).

2026-03-11:  Tail-call fall-through optimization and cleanup.  Converted INCONV/OUTCON
from raw pointer arithmetic to C array indexing (size-neutral, cleaner code).  Documented
8275 CRT semigraphics encoding in `displ()` (ch ≥ 192 folds to 0-63 via 7-bit char ROM).
Reordered 6 function pairs so tail calls fall through: `displ`→`cursor_right`,
`carriage_return`→`cursorxy`, `erase_to_eos`→`bg_clear_from`, `start_xy`→`goto00`,
`rdhst`→`sec_rw`, `cursor_down`→`rowdn`.  Added 4 comment-aware peephole rules that
match `jp target; ;comments; target:` patterns (sdcc inserts 3 separator comments between
functions).  Generalized existing fall-through rule from `_%1` to `%1` (conditional jumps
naturally excluded — labels can't contain commas).  Created PEEPHOLE.md documenting all
22 peephole rules.  Added `make asm-test` target for automated FILEX integration test.
Size: 6439 → 6402 bytes (37 bytes saved from 6 fall-through + conditional inversions).

2026-03-13:  Branch `experiment/c-stdlib-ivt` wrap-up.  The original goal (standard
library C program) was not reached, but the branch delivered major architectural
improvements:

- **Boot sector simplification**: _cboot (cold boot relocator) moved into the
  128-byte boot sector itself, where there is room.  Only the relocator remains
  in assembly — everything else is C.
- **IVT in C**: Interrupt vector table moved from assembly to a C function pointer
  array, letting the linker resolve ISR addresses.
- **Dual-section layout**: z88dk_section_layout.asm defines two sections (BOOT at 0x0000, BIOS at
  BIOSAD) with CONFI block and Danish tables included as binary files.  The Makefile
  concatenates the two sections into bios.cim.
- **MSIZE-derived addresses**: All CP/M addresses (CCP, BDOS, BIOS) derived from
  `MSIZE EQU 56`, matching the original BIOS.MAC pattern.  Changing MSIZE adjusts
  the entire memory layout.
- **Drive B support**: Full CFG.infd[] table copied at boot, enabling all configured
  drives.
- **MAME two-drive support**: rc702/rc702mini/rc703 drivers expose both fdc:0 and
  fdc:1 with default drive types.  MFI images preserved between sessions for
  writable persistent disks.
- **Test infrastructure**: All Lua test scripts use os.exit() for clean MAME
  termination.  Poll-based timeout exits within 1 second of test completion.
- **Boot pointer investigation**: Documented the 0x47/0x48 boundary limit in
  BOOT_POINTER_INVESTIGATION.md.

Previous entries (2026-03-12/13): Unified binary layout, extracted boot entry and
CONFI sectors into binary files, relocated _cboot, documented PURE_C_PLAN.md.

2026-03-11:  Performance benchmarking infrastructure.  Added cycle-tracking test
(`make cycle-test`, `make cycle-baseline`) that measures CPU cycles per command in the
ASM FILEX integration test using MAME's emulated time.  PC sampled at 50 Hz for
function-level hotspot detection.  Uses `emu.keypost()` for BIOS-agnostic keyboard
input (works with both C and original BIOS).  Added instruction-level profiling mode
(`make profile`) using MAME debugger trace with `profile_trace.py` post-processor.
Baseline: C BIOS is 5.2% slower than original REL2.3 on TYPE FILEX.PRN (188M vs 179M
cycles).  Main hotspot: `_scroll` at 12.4% of samples.  See `CONOUT_BENCH.md`.

2026-03-19:  All code is now in --no-crt C except for the entry stub and ISR stack switch wrappers.

2026-04-01:  Session 7 — llvm-z80 ISel optimizations + BIOS inline asm.  (1) #45 direct LD (nn),A/HL for constant-address stores/loads, (2) #46 ptrtoint(GV+const) fold with linker 16-bit wrapping fix (#47), (3) BSS load forwarding in LateOptimization.  BIOS: insert_line backward copies via lddr_copy()/LDDR, SIO init via OTIR (contiguous sioa/siob arrays share HL).  PROM 1842B (-6B), BIOS 5712B (-245B from 5957B).  MAME boot verified.


## Status

**Feature-complete** — CP/M boots to A> on MAXI 8" with two floppy drives.
All floppy BIOS features working.  Current size: 5473 bytes (fits maxi 9984
with 4511 to spare; fits mini 6144 with 671 to spare).

### Missing features

- **Hard disk support** (WD1000 controller): HRDFMT stub and HD ISR stub present.
  Not a priority — target machine is maxi (8") without drives, using CP/NET.

### Inline assembly syntax

All inline assembly uses the `__asm__("string")` form (sdcc 3.2.0+) instead of the
older `__asm/__endasm` block form. This allows the host C compiler (clang/gcc) to
parse `__naked` functions when `#define __asm__(x)` stubs out the asm content.
Most `#ifndef HOST_TEST` guards around `__naked` functions have been removed.

Build with `cc -DHOST_TEST -Wall -Wextra -fsyntax-only bios.c` to check for
C-level errors. Remaining host warnings are expected (pointer/int cast size
differences on 64-bit, unused functions in `#ifndef HOST_TEST` blocks).

### Remaining inline assembly

24 `__asm__()` blocks remain in bios.c. Categorized by whether they can move to C:

**Must stay in asm** (ABI / hardware constraints):
- ISR stack switch helpers (`isr_enter`/`isr_exit`, 4 blocks) — SP manipulation, EI+RETI
- `bios_boot` / `bios_wboot` (2) — set SP then JP, no return
- `bios_settrk` / `bios_setsec` / `bios_setdma` (3) — CP/M passes value in BC, single `ld (var),bc` + ret
- `bios_sectran` (1) — return BC in HL, single instruction + ret
- `bios_wfitr` tail (1) — load fdc_result[0]→B, fdc_result[1]→C for CP/M ABI
- `bios_linsel` entry (1) — store A→ls_port, B→ls_line (ABI bridge)
- SIO init (1) — OTIR to ports 0x0A/0x0B (no C equivalent for OTIR)

**Could move to C** (best candidates first):
- **5 stack-switch wrappers** (`bios_conout`, `bios_home`, `bios_seldsk`, `bios_read`,
  `bios_write`) — all do the same DI/save-SP/switch-to-BIOS-stack/EI/call-C-body/
  restore-SP pattern (~15 lines each). A shared inline helper would eliminate
  duplication. The C body functions already exist.
- **`bios_exit`** (1 block) — stores HL→warmjp, DE→timer1. Two assignments, but
  needs `__naked` to receive HL/DE from CP/M ABI.
- **`bios_clock`** (1 block) — reads/sets rtc0+rtc2 with DI/EI. Return convention
  (DE+HL) makes pure C awkward.
- **`bios_linsel` returns** (3 blocks) — `xor a; ret` / `ld a,#0xFF; ret`. Could be
  `return 0`/`return 0xFF` if the function weren't `__naked`.
- **`wboot_c` tail** (1 block) — load cdisk, mask, JP to CCP. Non-returning jump.

### Pointer-to-C-idiom cleanup candidates

Analysis of remaining raw pointer patterns that could use cleaner C constructs:

**Priority 1 — CTC config** (`bios_hw_init`, lines 585-590):
`*((&mode0) + 2)` etc. — taking address of scalar then offsetting. The 8 CTC bytes
are contiguous in z88dk_section_layout.asm. Declaring as `extern byte ctc_config[8]` allows
`ctc_config[2]` indexing.

**Priority 2 — disk_parameter_header struct** (`bios_hw_init` lines 663-672, `bios_seldsk` lines 1434-1438):
`dph_table[d * 8]` with magic offsets 0-7 could be a proper CP/M disk_parameter_header struct:
```c
typedef struct { word xlt, scratch[3], dirbf, disk_parameter_block, chk, alv; } disk_parameter_header;
```
Eliminates magic numbers; compile-time layout checking.

**Priority 3 — INCONV lookup** (`conin_translate`, line 817):
`*((volatile byte *)(INCONV_ADDR + raw))` → define `INCONV` as array macro,
use `INCONV[raw]`.

**Priority 4 — Static variable groups** (multiple functions):
Functions like `bg_clear_from`, `insert_line`, `delete_line` have 5-9 scattered
`static` variables. Packing into structs enables HL-relative addressing (sdcc
generates shorter code for struct member access than individual absolute loads).

**Priority 5 — warmjp callback** (`isr_crt`, line 1917):
`((void (*)(void))warmjp)()` → macro `CALL_WARMJP()` for readability.

**Already idiomatic** (no changes needed): display buffer overlays (`screen`,
`DISPLAY_ROW`, `bgstar` macros), WorkArea struct at 0xFFD0, SIO init loops with
`sizeof`, ring buffer arithmetic, backward copy loops.

## Building

Requires z88dk installed at `../z88dk/`.

```bash
make bios    # build bios.cim
make size    # check fit against mini/maxi limits
make clean   # remove build artifacts
```

## Architecture

The design has a clean separation: z88dk_section_layout.asm handles the binary layout, boot
relocation, and JP table; everything else is C.

- **z88dk_section_layout.asm**: Two-section layout (BOOT at 0x0000, BIOS at BIOSAD).  Boot sector
  with relocator (_cboot), JP table, JTVARS, section ordering.  All CP/M addresses
  derived from `MSIZE EQU 56`.
- **confi.bin** / **danish.bin**: CONFI config block (128 bytes) and Danish conversion
  tables (384 bytes), included as BINARY directives at disk offset 0x080.
- **bios.c**: All BIOS entry points, ISRs, IVT (C function pointer array), and disk
  data tables
- **bios.h**: Constants, memory layout (MSIZE-derived), `WorkArea`/`JTVars`/`disk_parameter_block`/
  `FSPA`/`FDF`/`ConfiBlock` structs, `byte`/`word` typedefs
- **hal.h**: Hardware abstraction (`__sfr __at` port I/O, `hal_di`/`hal_ei`/`hal_halt` macros)
- **peephole.def**: SDCC peephole optimizer rules
- **bgstar_test.asm**: BGSTAR foreground/background test (draw, insert/delete line, clear FG)
- **mame_bgstar_test.lua**: Automated MAME test for bgstar_test.asm (verifies screen contents)
- **gdb_bgstar.py**: GDB RSP debug client for tracing bg_set_bit and specc breakpoints
- **conout_test.asm**: CONOUT control code exerciser (insert/delete line, scroll, erase)
- **SDCCCALL.md**: Calling conventions, register allocation, inlining guide
- **ASM_BLOCKS.md**: Analysis of all inline asm blocks and C convertibility
- **STACK_ANALYSIS.md**: Call graph, no-recursion proof, stack depth
- **STACK_BUG_ANALYSIS.md**: Warm boot stack corruption bug and fix
- **test_sdcccall.c**: Experimental verification of sdcccall(1) register usage

### Memory-mapped variables

Fixed-address hardware variables are defined as C structs with pointer casts:

- **`WorkArea`** at 0xFFD0: cursor state, timers, ISR variables (cleared at boot)
- **`JTVars`** at 0xDA33: CONFI configuration, drive format table (in binary)

Accessed via macros (`curx`, `cury`, `timer1`, `fd0[n]`, etc.) that expand to
`W.field` or `JT.field` where `W`/`JT` are volatile struct pointers. This
generates efficient direct-address code and saved 33 bytes vs individual `__at()`.

### Disk layout and boot process

The BIOS binary (`bios.cim`) is written to Track 0 of the floppy disk.
The ROM (ROA375) loads Track 0 to address 0x0000, reads the boot pointer
from offset 0, and jumps there.

**Disk layout (bios.cim, loaded by ROM to physical address 0x0000):**

```
Offset  Size   Section     Source              Contents
------  -----  ----------  -----------------   --------------------------------
0x0000    128  BOOT        boot_block.c        Boot pointer (→coldboot),
                                               " RC702" signature, builddate
0x0080    512  BOOT_DATA   boot_confi.c        CONFI defaults (128B) +
                                               conversion tables (384B)
0x0280    505  BOOT_CODE   boot_entry.c        coldboot() + relocate_bios()
                           bios_hw_init.c      bios_hw_init() + IVT + setup
0x0477    113  BIOS        bios_jump_vector_table.c  JP table + JTVARS
0x04E8   4284  code+data   bios.c              BIOS code + const data
------  -----
Total:  5542 bytes
  Boot loader (0x0000-0x0476): 1143 bytes — discarded after boot
  BIOS payload (0x0477-end):   4397 bytes — relocated to BIOS_BASE
```

The ROM loads the entire file to address 0x0000.  coldboot() copies
the BIOS payload (offset 0x0477 onward) to BIOS_BASE (0xDA00 for
56K), copies CONFI and conversion tables to their runtime addresses,
zeros BSS, calls bios_hw_init (from BOOT_CODE, not yet overwritten),
and jumps to bios_boot.

**Runtime memory map (after relocation by coldboot, 56K system):**

```
Address         Size   Contents
──────────────  ─────  ──────────────────────────────────────────────
0x0000-0x00FF     256  CP/M zero page (warm boot JP, IOBYTE, BDOS)
0x0100-0xC3FF   50432  TPA (transient program area)
0xC400-0xC405           CCP base
0xCA06-0xCA08           BDOS entry
0xD500-0xD548      72  CONFI config block (copied at boot, init-only)
0xDA00-0xDA70     113  BIOS JP table + JTVARS + extended JP
0xDA71-0xE9A4    3892  BIOS code (compiled C)
0xE9A5-0xEAFA     342  BIOS const data (rodata)
0xEAFB-0xEB0C      18  BIOS initialized data
0xEB2D-0xF11A    1518  BSS (static variables, zeroed at boot)
0xF11B-0xF4FF     997  Free (BIOS stack growth headroom)
0xF500-0xF5FF     256  BIOS stack (grows down)
0xF600-0xF67F     128  IVT + interrupt stack (Mode 2, page-aligned)
0xF680-0xF7FF     384  OUTCON/INCONV conversion tables
0xF800-0xFFCF    2000  Display refresh memory (80×25, 8275 CRT DMA)
0xFFD0-0xFFFF      48  Work area (timers, cursor, RTC)
```

All addresses from 0xDA00 onward are derived from `MSIZE` (default 56)
via `BIOS_BASE = 0x3400 + (MSIZE-20)*1024 + 0x1600`.  Addresses from
0xF500 upward are hardware-fixed (display, IVT alignment, work area).

Moving bios_hw_init to BOOT_CODE freed 438 bytes from the resident
BIOS (4835 → 4397), increasing stack headroom from 559 to 997 bytes.

**Boot sequence (coldboot in boot_entry.c):**

1. DI (disable interrupts, via `intrinsic_di()`)
2. `memcpy`: copy BIOS section from physical offset to BIOS_BASE (0xDA00)
3. `memcpy`: copy CONFI defaults (128B) to CCP area (init-only)
4. `memcpy`: copy conversion tables (384B) to CONV_ADDR (0xF680)
5. `memcpy`+zero: zero BSS
6. Call `bios_hw_init()` (IVT, PIO, CTC, SIO, DMA, CRT, FDC init)
7. Call `bios_boot()` (sets SP to BIOS_STACK, never returns)

Uses ROM's stack pointer (0xBFFF) throughout steps 1-7.  Interrupts
stay disabled until bios_boot's init path enables them.

### Source files

| File | Section | Description |
|------|---------|-------------|
| z88dk_section_layout.asm | — | Section ordering and org addresses (linker scaffolding, no code) |
| boot_block.c | BOOT | Boot sector header: pointer, signature, timestamp |
| boot_confi.c | BOOT_DATA | CONFI config defaults + keyboard conversion tables |
| boot_entry.c | BOOT_CODE | Cold boot: coldboot(), LDIR-based copy/zero helpers |
| bios_jump_vector_table.c | BIOS | Const JP table + JTVARS (linker-resolved function pointers) |
| bios.c | code_compiler | All BIOS logic: ISRs, console, disk, serial, display |
| bios.h | — | Structs, macros, port definitions, memory map |
| hal.h | — | Hardware abstraction: __sfr port declarations |

Each C file is compiled into its own section via `--codeseg`/`--constseg`
flags. The section ordering in z88dk_section_layout.asm determines the binary layout.
The Makefile concatenates `bios_BOOT.bin` and `bios_BIOS.bin` (trimmed
to exclude BSS) to produce `bios.cim`.

### z88dk notes

- `-pragma-define:CRT_ORG_CODE=0x0000` sets the binary output origin.
- **appmake `+rom`**: z88dk's binary output tool.  `-create-app` on the
  final link invokes `z88dk-appmake +rom` which splits the linker output
  into per-section `.bin` files (`bios_BOOT.bin`, `bios_BIOS.bin`, etc.).
  The Makefile concatenates these to produce `bios.cim`.
  - With `--no-crt`, appmake cannot determine the code origin from the
    CRT file and warns: "could not get the code ORG".  Suppressed with
    `-Cz--org -Cz0` which passes `--org 0` to appmake (BOOT starts at
    0x0000).
  - `--code-fence N` restricts CODE below address N.  Could be used
    to catch BIOS code overflowing into BSS/IVT (e.g. `--code-fence 0xF600`).
  - **`-Cz`** passes options to appmake.  Not `-Cm` (that's m4) or
    `-Ca` (assembler) or `-Cl` (linker).
  - In Makefiles, `-Cz"--org 0"` works (make handles quoting).
    On the command line, split as `-Cz--org -Cz0` to avoid shell issues.
- **z88dk intrinsics** (`#include <intrinsic.h>`): compile to single
  Z80 instructions with no call overhead.  Available intrinsics:
  - `intrinsic_di()`, `intrinsic_ei()` — DI/EI
  - `intrinsic_halt()` — HALT
  - `intrinsic_nop()` — NOP
  - `intrinsic_im_0()`, `intrinsic_im_1()`, `intrinsic_im_2()` — IM 0/1/2
  - `intrinsic_reti()`, `intrinsic_retn()` — RETI/RETN
  - `intrinsic_ex_de_hl()` — EX DE,HL
  - `intrinsic_exx()` — EXX
  - `intrinsic_swap_endian_16(n)` — byte-swap 16-bit value
  - `intrinsic_return_bc()`, `intrinsic_return_de()` — return BC/DE as pointer
  - `intrinsic_stub()` — no-op (placeholder)
  All preserve registers (marked `__preserves_regs`).  Tested: `intrinsic_di()`
  emits a single `di` instruction even inside `__naked` functions.
- sdcc resolves function pointers in const struct initializers via
  `DEFB`+`DEFW` with linker-resolved addresses.  This is how the JP
  table in bios_jump_vector_table.c works — no runtime initialization needed.
- Each Boot sub-section (BOOT, BOOT_DATA, BOOT_CODE) requires a
  separate .c file because `--codeseg`/`--constseg` flags are per-file.
  Tested: `#pragma constseg` mid-file is **file-global, not positional**
  — the last pragma wins for all const data in the file.  So two const
  arrays in different sections cannot share a .c file.
- sdcc rejects byte decomposition of function pointers in const
  initializers (`(byte)(word)func` → "not a constant expression") but
  accepts whole function pointers (`(fptr)func` → `DEFW _func`).
  The JP table exploits this with `{ byte opcode, fptr target }` structs.

### ISR design

sdcc provides three ways to write interrupt service routines:

**`__interrupt`** — puts `EI` at the *start* of the function (before the
push/pop prologue), enabling nested interrupts immediately.  The epilogue
ends with `RETI`.  **Never use this on the RC702** — the hardware requires
interrupts to be disabled throughout all interrupt handlers.

**`__critical __interrupt`** — keeps interrupts disabled throughout.  The
prologue pushes AF, BC, DE, HL, IY; the epilogue pops them, then does
`EI; RETI`.  This is the correct pattern for non-nesting ISRs.  The
function body is pure C — no inline assembly needed.

**`__naked`** — no compiler-generated prologue or epilogue at all.  The
programmer writes everything in inline asm.  Required when the ISR must
switch to a private stack (`sp_sav`/ISTACK) or when the compiler's
register save set (5 pairs) is too heavy.

**The `(N)` in `__interrupt(N)` is mandatory.**  Without it, `__critical
__interrupt` generates `RETN` instead of `EI; RETI`.  `RETN` leaves
interrupts permanently disabled — a fatal error on the RC702 where all
I/O (keyboard, floppy, serial) is interrupt-driven.  The number N is an
sdcc-internal slot that prevents duplicate declarations; it does NOT
generate or affect the interrupt vector table (sdcc has no IVT generation
for Z80).  Our vector table is defined manually in z88dk_section_layout.asm (`itrtab`
at 0xDB00).  Every `__interrupt` in this project must use `(N)`.

#### Which ISRs use which form

| ISR | Form | Why |
|-----|------|-----|
| `isr_crt` | `__naked` | Stack switch + DMA programming, must protect `sp_sav` |
| `isr_pio_kbd` | `__naked` | Stack switch, ring buffer with local variables |
| `isr_floppy` | `__naked` | Stack switch, calls `fdc_result()`/`fdc_sense_int()` |
| `isr_sio_a_rx` | `__naked` | Stack switch, ring buffer + RTS flow control |
| `isr_sio_b_tx` | `__critical __interrupt` | Trivial body (port write + flag) |
| `isr_sio_b_ext` | `__critical __interrupt` | Trivial body (port read + store) |
| `isr_sio_b_spec` | `__critical __interrupt` | Trivial body (error read + reset) |
| `isr_sio_a_tx` | `__critical __interrupt` | Trivial body (port write + flag) |
| `isr_sio_a_ext` | `__critical __interrupt` | Trivial body (port read + store) |
| `isr_sio_a_spec` | `__critical __interrupt` | Trivial body (error reset + flush) |
| `isr_hd` | `__interrupt` | Empty stub (hard disk not implemented) |
| `isr_pio_par` | `__interrupt` | Empty stub today; will host the PIO-B / J3 CP/NET RX path under Option P (`docs/cpnet_fast_link.md`) when bring-up phase opens |

The 6 `__critical __interrupt` ISRs were originally `__naked` with a
stack switch to ISTACK (0xF620).  The stack switch was removed because
their bodies are trivial — the compiler pushes 5 register pairs (10 bytes)
which fits safely on any interrupted code's stack.  If a body becomes
non-trivial, it must revert to `__naked` with `isr_enter`/`isr_exit`.

### Code/BSS separation

The binary on disk contains only code and initialized data. Uninitialized variables
(buffers, driver state) are in BSS, placed by the linker after all code/data sections,
not written to the floppy image. The cold boot code zeroes BSS using
`__bss_compiler_head`/`__bss_compiler_size` linker symbols. Section ordering is
declared explicitly in z88dk_section_layout.asm to ensure all code/data sections precede BSS.
The `code_string` section (containing `memset`) must be declared before BSS to
avoid linker placement errors.

### Disk data tables

Translation tables (`xlt_maxi_128`–`xlt_identity`), Disk Parameter Blocks (`dpb_maxi_128`–`dpb_maxi_256`),
Floppy Disk Format descriptors (`fdf[4]`), and Floppy System Parameters (`fspa[4]`)
are defined as typed C arrays/structs in bios.c.  Per-drive track offsets are stored
in each DPB's `.off` field (the original ASM `TRKOFF[]` table is unused in the C port).
The `current_format` pointer (`const FDF *`) provides struct-based access to FDF fields
(`current_format->dma_count`, `&current_format->mf`), replacing raw byte offset arithmetic.

## Testing

`run_mame.sh -t` runs the automated test: assembles FILEX.ASM with CP/M's
ASM.COM, then verifies the output via STAT and TYPE. This exercises the full
BIOS file I/O path (sequential read, sequential write, directory operations).

```
ASM FILEX        → 910-line source, 009H USE FACTOR, 0 errors
STAT FILEX.PRN   → 266 records, 34K
TYPE FILEX.PRN   → listing ends at 0x0932 with END START
```

Reference addresses are saved to `filex_ref.txt`.

`make bgstar-test` runs the BGSTAR foreground/background test: assembles bgstar_test.asm,
injects BGTEST.COM into a disk image, boots in MAME with mame_bgstar_test.lua,
and verifies that background drawing, insert/delete line, and clear foreground
all produce correct screen output.

### Writing test programs

Test programs can be written in C using z88dk (same toolchain as the BIOS) or
in Z80 assembly using zmac. Compiled programs are injected into disk images
using `cpmcp -f rc702-8dd` and run under CP/M in MAME.

### GDB RSP debugging

MAME's gdbstub provides source-level debugging via the GDB Remote Serial
Protocol. Launch MAME with `-debugger gdbstub -debugger_port 23946`, then
connect with `gdb_bgstar.py` (or any GDB RSP client). This supports breakpoints,
single-step, register/memory read/write — useful for tracing BIOS internals
without modifying the binary.

### MAME disk format

MAME cannot write back to IMD disk images (`supports_save()` returns false).
All MAME launch modes convert IMD→MFI (MAME Floppy Image) for writable disks.
Disk changes persist between interactive MAME sessions. Use `-f` to force a
fresh image from the IMD source.

### CP/M source reference

- **PL/M and ASM sources**: `~/Downloads/cpm2-plm/`
- **Build instructions**: https://www.jbox.dk/rc702/cpm.shtm

## Compiler optimization

All compiler tuning options are documented in `SDCCCALL.md` and `OPTIMIZATION_PLAN.md`.
Summary:

- **No recursion** → all locals are `static` → no IX/IY frame pointer usage
- **Makefile build guard** fails if `ix[+-]` or `iy[+-]` appear in listing
- **Makefile build guard** fails if sdcccall(0) library functions are linked
- **Makefile build guard** verifies position-sensitive symbols at expected addresses
- **FDC wait loops non-inline** (callable) — compactness over speed for wait loops
- **`--max-allocs-per-node 1000000`** for aggressive register allocation
- **`--std-sdcc99`** enables `inline` keyword
- sdcc has no automatic inlining — `inline` keyword is the only mechanism
- **Block instructions**: `memcpy`→LDIR (inlined), `memset`→LDIR, OTIR via inline asm
- **Z80 block ops used**: SIO init via OTIR, 128-byte deblocking via LDIR (memcpy)
- See `OPTIMIZATION_PLAN.md` for sdcc internals analysis and future optimization paths

## Stack requirements

The C BIOS uses significantly more stack than the original assembly BIOS
(~80 bytes vs ~16 bytes at peak). No recursion exists in the codebase, so
all local variables are declared `static`. See `STACK_ANALYSIS.md`.

The warm boot stack must be outside the CCP+BDOS area (0xC400-0xD9FF) being
loaded. Both `bios_boot` and `bios_wboot` use SP=0xF500 (the BIOS private
stack, 5KB above BSS). See `STACK_BUG_ANALYSIS.md` for the original bug.

## Remaining inline assembly

All block memory operations (scroll, clear, insert/delete line) are now pure C
using `memcpy`/`memset`/loops. The remaining asm blocks are:

- **ISR prologues/epilogues** (10): SP switch to ISTACK, PUSH AF/BC/DE/HL, POP, EI+RETI
- **BIOS stack-switch entries** (7): SP switch to 0xF500 before calling C body
- **CP/M ABI glue** (4): `settrk`/`setsec`/`setdma` store BC, `sectran` BC→HL
- **SIO init** (1): OTIR to ports 0x0A/0x0B (no C equivalent for OTIR)
- **DI/EI/HALT**: `hal_di()`, `hal_ei()`, `hal_halt()` macros in hal.h
- **CCP jump**: load CDISK, jump to CCP at warm boot

See `ASM_BLOCKS.md` for full analysis.

## Binary layout (6324 bytes)

The .cim binary is a single compiled unit starting at ORG 0xD480.
The Makefile trims BSS from the .rom output — no separate files.

```
Address range  Size   Section
-------------  -----  ------------------------------------------
D480h–D500h      128  Boot sector (DW 0x0080, " RC702", zeros)
D500h–D522h       34  _cboot (relocate, BSS clear, hw init, jp DA00)
D522h–DA00h     1246  Free INIT space (zeros, available for init code)
DA00h–DA33h       51  BIOS JP table (17 entries, fixed address)
DA33h–DA4Ah       23  JTVARS (CONFI configuration variables)
DA4Ah–DA70h       38  Extended JP table entries (INTJP0-10)
DA70h+          ....  C code, ISRs, const data (incl. confi_on_disk)
```

The INIT section (D480–DA00) is overwritten by CCP after cold boot;
only the resident portion (DA00+) must fit the system track.  The
free INIT region (D522–DA00, 1246 bytes) can hold init-only code.

The CONFI configuration block (72 bytes) is embedded as `confi_on_disk`
in the resident C code section.  The original disk layout placed this
at offset 0x080; restoring that for CONFI.COM is a long-term goal.

BSS (uninitialized variables) is NOT included in the binary — it is
zeroed by `_cboot`.

### Top 10 largest C functions

| # | Function | Bytes | Purpose |
|---|----------|------:|---------|
| 1 | `bios_hw_init` | 412 | Hardware init (INIT section, overwritten by CCP) |
| 2 | `bg_clear_from` | 274 | BGSTAR bitmap clear (semi-graphics) |
| 3 | `bios_seldsk_c` | 229 | Disk select + format table lookup |
| 4 | `rwoper` | 223 | Blocking/deblocking state machine |
| 5 | `insert_line` | 216 | Screen insert line + BGSTAR shift |
| 6 | `xwrite` | 168 | Disk write + pre-read logic |
| 7 | `isr_crt` | 150 | CRT refresh ISR (DMA, timers, keyboard scan) |
| 8 | `delete_line` | 137 | Screen delete line + BGSTAR shift |
| 9 | `chktrk` | 130 | Multi-density track 0 format switching |
| 10 | `specc` | 125 | Control character dispatch (if/return chain) |

### Space by category

| Category | Bytes | % |
|----------|------:|--:|
| Boot sector (compiled) | 128 | 2.0 |
| _cboot + free INIT space | 1280 | 20.3 |
| z88dk_section_layout.asm (JP table + JTVARS) | 112 | 1.8 |
| C code (functions + ISRs) | ~4250 | 67.2 |
| Const data (CONFI + tables + library) | ~554 | 8.8 |
| **Total** | **6324** | |

### MINI fit analysis (need to cut 180 bytes)

| Optimization | Saving | Notes |
|--------------|-------:|-------|
| Remove BGSTAR code | 419+ | Plus tails in insert/delete line, displ |
| Shared stack-switch trampoline | ~50 | 5 wrappers → 1 trampoline |
| Additional peephole rules | ~20 | Further pattern matching opportunities |
| Micro-optimizations | ~60+ | Tail calls, shared code paths |
| **Total estimated** | **~549+** | Only 180 needed; comfortable margin |

### specc control character dispatch

sdcc **sorts switch cases by value**, ignoring source order.  Using
`if (x == N) { handler(); return; }` chains instead preserves the
source ordering and generates `cp a,N / jr NZ / jp handler` with A
reused across comparisons (no reload).  This costs only 4 bytes more
than a switch (the `0x05`/`0x08` cursor_left case can't fall through)
but puts CR and LF first — the most frequent control codes get a
2-comparison fast path.

### Character conversion tables

The danish.bin conversion tables are **not included** in the BIOS binary.
The cold boot code generates identity tables (all characters map to
themselves) as a safe default.  The original disk layout placed the tables
at offset 0x100; that region is now part of the free INIT space.

## Next steps

- MINI (5.25") support (currently 110 bytes over mini limit, needs size reduction)
- Move remaining inline asm from bios.c to z88dk_section_layout.asm (see `PURE_C_PLAN.md`)
- Remove BGSTAR code (~419 bytes, largest single saving)
- Shared stack-switch trampoline (~50 bytes saving, see `OPTIMIZATION_PLAN.md`)
- Further peephole rules and micro-optimizations
