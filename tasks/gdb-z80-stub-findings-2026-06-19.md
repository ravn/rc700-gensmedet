# GDB-on-Z80 experiment — findings 2026-06-17..19

User question (2026-06-17, parked-task unpark): can we drive GDB against a
**physical RC702** now that GDB has Z80 support?  Investigation started
the same day; this doc captures what's already in place vs what needs
building.

**Archival note (2026-07-05):** this investigation originally lived in the
top-level workspace at `tasks/gdb-z80/` (Docker build recipe, ~24 MB
upstream `gdb-17.2.tar.xz`, the unpacked `gdb-17.2/` source tree, and a
`build/` scratch dir with measured stub-size experiments). That directory
has been removed as workspace cleanup (all the *findings* below are
preserved here; the removed Docker/source tree is fully reproducible —
see "Reproducing the removed environment" at the end of this doc). See
`future-gdbstub-over-sio.md` (this same directory) for the earlier, more
abstract parking-ticket version of the same idea — this doc is the
concrete follow-up investigation with a Docker image actually built and
a real stub footprint measured.

## Three pre-existing GDB→Z80 paths in this workspace

| Path | Status in repo | Wire format | Notes |
|---|---|---|---|
| **`gdb_trace.py`** raw GDB-RSP client (`rcbios-in-c/gdb_trace.py`) | working today | Hand-rolled GDB Remote Serial Protocol over TCP socket | Talks to MAME on port 23946.  Sets breakpoints on all 17 BIOS JP-table entries, logs BIOS calls + registers + BDOS function names.  Has been the BIOS-tracing workhorse for months. |
| **`z88dk-gdb`** (Docker `z88dk:2.4` ships it at `/opt/z88dk/bin/z88dk-gdb`) | working | GDB-RSP client; supports MAME (1337), Fuse (1667), **Spectranet on physical hardware (1667)** | Wraps z88dk-ticks's `debugger_gdb.c` — register order matches MAME's. |
| **`z80-elf-gdb` 17.2** (upstream GDB; Dockerfile in `tasks/gdb-z80/`) | built today via `docker build -t z80-elf-gdb:17.2 .` | GDB-RSP client (full GDB UX) | Reads DWARF5 from clang ELF; understands source/line-number breakpoints. |

## MAME gdbstub ↔ upstream GDB register mismatch (one-line fix needed)

`mame/src/osd/modules/debugger/debuggdbstub.cpp:357-379` serves:
- `<architecture>z80</architecture>` ✓ (matches)
- `<feature name="mame.z80">` — but **GDB expects `org.gnu.gdb.z80.cpu`** (line 1098 of `gdb-17.2/gdb/z80-tdep.c`)
- 12 registers in MAME-co-designed order: `af bc de hl af' bc' de' hl' ix iy sp pc`
- vs upstream GDB's 13-register order: `af bc de hl sp pc ix iy af' bc' de' hl' ir`
- `pc` width: MAME = 16-bit, GDB = 32-bit (eZ80 ADL 24-bit support)

Effect: when upstream `z80-elf-gdb` connects to MAME, `z80_gdbarch_init()`
hits the `if (feature == NULL) return NULL;` bail at z80-tdep.c:1099-1100
because MAME's feature name is wrong.  Architecture init fails; symbol
mapping breaks even though the wire works.

**Fix is a one-line MAME patch** in our `ravn/mame` fork (which already
carries the col-80 `set_size(560,…)` fix at `035d29086bf`):
```c
"mame.z80",  →  "org.gnu.gdb.z80.cpu",
```
And add an `IR` slot to the register map.  Worth upstreaming to mamedev.

**Or** point GDB at its built-in description before connecting:
```
(gdb) set tdesc filename <gdb-prefix>/share/gdb/features/z80.xml
(gdb) target remote :23946
```

**Or** use `z88dk-gdb` instead — it was co-designed with MAME's layout
and Just Works.

## DWARF status on clang output

`cpnos-in-c/clang-prom1lineprog/payload.elf` (30 KB):
- `.debug_info` 6.7 KB, `.debug_line` 4.0 KB, `.debug_loclists`, `.debug_str_offsets`, `.debug_addr` — full DWARF5
- No `.eh_frame` / `.debug_frame` — frame unwind falls back to
  `z80_skip_prologue` + the prologue-pattern analyzer in z80-tdep.c.
  Acceptable for `+static-stack` (no frame pointer); source-level
  breakpoints + `info locals` work; deep backtraces may be imperfect.

Same expected for `rcbios-in-c/clang/bios.clang.elf` (5.4 KB code, full
DWARF5).

## Existing scaffolding in the project

`rcbios-in-c/run_mame.sh -g`:
```
ARGS+=(-debug -debugger gdbstub -debugger_port 23946 -nothrottle)
```
Requires a `regnecentralend` (debug-build) MAME at `$MAME_DIR`.
**`MAME_DIR=/Users/ravn/git/mame` is pre-workspace-reorg path** — needs
updating to `/Users/ravn/z80/mame/` and a `make REGENIE=1 -d` debug build.

## Physical RC702 — path resolved

User confirmed 2026-06-17: SIO ch A (currently wired as CP/M RDR:/PUN:
auxiliary device — rarely used) is available for reassignment to a debug
channel.  That collapses the design space.

**Use the upstream reference Z80 stub.**  GDB 17.2 ships
`gdb/stubs/z80-stub.c` (1355 lines, ©2021-2025 FSF), explicitly designed
to be dropped into a Z80 firmware build with thin per-platform glue:

- **Configurable via `#define`s** before include: `DBG_SWBREAK`,
  `DBG_SWBREAK_RST 0x08`, `DBG_HWBREAK`, `DBG_NMI_EX`, `DBG_INT_EX`,
  `DBG_MEMORY_MAP` (XML telling GDB which regions are ROM vs RAM),
  `DBG_PACKET_SIZE 150` default
- **Overlay support built in** — matches RC700's PROM-bank concept
  (`_ovly_region_table` hook is exactly the abstraction needed for
  port-0x18 RAMEN swapping)
- **What we have to write** (small): `getDebugChar()` / `putDebugChar()`
  blocking SIO ch A reads/writes, plus a serial init routine called at
  startup
- **Vectors we have to reserve:** `RST 0x08` for software breakpoints,
  `NMI @ 0x66` for break-in.  Current rcbios IVT (see
  `bios_hw_init.c:80-103`) doesn't use RST 0x08 — it's free.
  NMI handler is currently a `RETN` placeholder in autoload-in-c
  (`begin()` at `rom.c`), trivially repurposable to call into the stub.
- **Tested compilation:** SDCC-supported port list = `z80, z180, z80n,
  gbz80, ez80_z80`.  Our clang should also compile it (the file is
  vanilla C); worth a separate verification step.
- **Measured footprint** (2026-06-19, `tasks/gdb-z80/build/`, z88dk-zsdcc
  4.5.0 #15242, `+z80 -clib=sdcc_iy -SO3 --max-allocs-per-node 1000000
  --sdcccall 1 --fomit-frame-pointer --allow-unsafe-read`,
  full-features default config, linked with a minimal SIO ch A
  glue.c + main.c referencing the four entry points):

  | Build | Linked ROM | Notes |
  |---|---|---|
  | Full features | **2016 B** | rich `T` stop reply, `vCont`, `X` packet, `qXfer:memory-map`, swbreak via GDB-managed M-write |
  | `-DDBG_MIN_SIZE` | 1601 B | drops the four +-encoded packet features; not worth the complexity once we accept growing the BIOS |

  Plus 27 B `state[]` BSS, 151 B packet buffer (stack-allocated during
  stub execution), 11 B SDCC `___sdcc_enter_ix` helper, 28 B libc
  `memcmp`.  Add ~150 B rodata for a realistic RC702 `DBG_MEMORY_MAP`
  XML literal.  No `memcpy`/`strchr`/`strlen` libc pulls — they got
  optimised away by the SDCC peephole.

  **The earlier "fits in BIOS headroom" claim was wrong.** With BIOS
  at 5462 B and the 6 KB target = 6144 B, headroom is 682 B; the full
  stub overshoots by ~1.3 KB.  Resolution chosen 2026-06-19: grow the
  BIOS downward (see deployment plan below).  The 6 KB target was
  self-imposed and there is no hard ROM constraint on rcbios the way
  there is on autoload (2 KB hard); the constraint that matters is
  TPA top, and the user has accepted a ~2 KB TPA reduction in the
  debug-build variant.

### Concrete plan for RC702 physical-hardware bring-up

**Deployment shape** (user decision 2026-06-19): "grow the BIOS
downward" — debug-enabled BIOS is a separate build artifact that
starts ~2 KB lower than production rcbios.  TPA drops from ~53.5 KB
to ~51.5 KB in the debug variant; production keeps the larger TPA.
SW1 bit 3 dropped from the plan — no runtime mode-switch needed
when the stub is either in the build or not.

Memory map (debug variant):
```
0xF800-0xFFFF  display RAM (DMA only — readonly to GDB)
0xE9EB-0xF7FF  free
0xDA00-0xE9EB  BIOS code+data (unchanged 5462 B)
0xD200-0xD9FF  z80-stub.c + glue (~2 KB linked here)
0x0800-0xD1FF  TPA (51.5 KB)
0x0000-0x07FF  low RAM, RST 8 + NMI vectors point into stub area
```

1. **Add `z80-stub.c` to `rcbios-in-c/`** verbatim from
   `tasks/gdb-z80/gdb-17.2/gdb/stubs/`.  Treat as third-party drop-in
   (do not edit; configure via `#define`s in a calling TU).
2. **Write `rcbios-in-c/gdb_glue.c`** with:
   - `int getDebugChar(void)` — blocking SIO ch A RX
   - `void putDebugChar(int c)` — blocking SIO ch A TX
   - `void gdb_serial_init(void)` — SIO ch A init (19200 8N1)
   - `void gdb_break_at_start(void)` — `debug_exception(EX_SIGTRAP)`
     called from the head of `_bios_hw_init`, after PROM disable +
     IVT setup
3. **Add `STUB=1` build target**: `make COMPILER=clang STUB=1`
   - Switches to a debug-variant linker script that sets the BIOS
     load address ~2 KB lower (current 0xDA00 → 0xD200)
   - Links in `z80-stub.c` + `gdb_glue.c`
   - Output: `bios.clang.debug.elf` (separate from production
     `bios.clang.elf`)
   - Production build path unchanged
4. **Reserve `RST 0x08` slot** for the stub's `_debug_swbreak`
   (already free in current IVT)
5. **Repurpose NMI handler** at 0x66 to `JP _debug_nmi` for user
   break-in (physical NMI button or MAME debug menu)
6. **Add DBG_MEMORY_MAP XML** describing RC702 memory:
   - 0x0000-0x07FF stack + low RAM (after PROM disable)
   - 0x0800-0xD1FF TPA (RAM, writeable)
   - 0xD200-0xE9EB stub + BIOS (RAM, writeable so GDB can install
     `RST 0x08` swbreak via M-packet)
   - 0xE9EC-0xF7FF free RAM
   - 0xF800-0xFFFF display RAM (DMA-only — flag readonly to keep
     GDB from poking it)
7. **clang compatibility check** required before the SDCC-built stub
   gets dropped in: the file uses `__naked`, `__asm`/`__endasm`, and
   `__z88dk_fastcall`.  clang understands `__attribute__((naked))`
   and `__asm` but not the z88dk fastcall calling-convention
   attribute.  Either compile the stub TU under SDCC and link the
   resulting `.rel` alongside clang objects, or mechanically rewrite
   the FASTCALL annotations to `__attribute__((sdcccall(1)))` and
   verify the inline asm call sites still match.
8. **MAME tests first** — every step verifiable against
   `run_mame.sh -g` before touching real hardware

### Measurement reproduction

```
cd tasks/gdb-z80/build
PATH=$Z88DK/bin:$PATH ZCCCFG=$Z88DK/lib/config \
  zcc +z80 -compiler=sdcc -clib=sdcc_iy --no-crt \
  -Cs"--std-sdcc23" -Cs"--sdcccall 1" \
  -Cs"--max-allocs-per-node 1000000" \
  -Cs"--fomit-frame-pointer" -Cs"--allow-unsafe-read" \
  -Cs"--disable-warning 296" -SO3 \
  z80-stub.c glue.c main.c -o stub-tuned.bin -create-app
ls -l stub-tuned.bin    # → 2016 B as of 2026-06-19
```

`glue.c` and `main.c` in the build dir are minimal — `glue.c` is
12 lines of inline-asm SIO ch A I/O, `main.c` is 14 lines that just
references the four entry points so DCE doesn't eat them.

### Alternative #1 — adapt ZSID as the on-target engine

ChatGPT suggested (relayed 2026-06-17) using DRI's ZSID debugger as the
debug engine and replacing only its CLI command interpreter with
GDB-RSP.  W. Cirsovius's reverse-engineered ZSID sources are mirrored
in-repo at `rc700-gensmedet/docs/zsid-reverse-engineered/`.

**Architecture of ZSID (from its source structure):**
- `SIDREL` — kernel: breakpoint setup, command dispatch, register save/restore
- `ZSIDLA` — Z80-specific instruction decoder for single-step (covers `JP`,
  `CALL`, `RET`, `RST`, conditional jumps, computed jumps)
- `SIDCMD` — CLI command interpreter (D, H, I, L, M, O, R, S, T, U, W, …)
- `HIST`, `TRACE` — stand-alone profiling utilities (not part of online
  debug)

**The adaptation:** keep SIDREL+ZSIDLA, replace SIDCMD with a GDB-RSP
packet handler that calls the same internal primitives the CLI does.

### Comparison: upstream `z80-stub.c` vs ZSID-adapted

| Aspect | `z80-stub.c` | ZSID-adapted |
|---|---|---|
| Code size | ~1.5-2 KB | ~5-10 KB (SIDREL 3038 + ZSIDLA 2282 lines of asm) |
| Where it lives | Linked into rcbios at build | Loaded as a CP/M TPATOP utility (high RAM) |
| Single-step | New code, decodes-then-traps next PC | **40-year-tested** instruction decoder |
| Breakpoint | `RST 0x08` | `RST 0x38` (configurable) |
| Memory map | Has ROM/RAM/flash XML to GDB | RAM-only (TPA model) — would need extending |
| Overlay/PROM-bank aware | Yes (`_ovly_region_table` hook) | No (CP/M is post-PROM-disable world) |
| CP/M-aware | No | Yes (FCB, DMA, BDOS — but irrelevant when GDB drives) |
| Can debug what we didn't compile | No (must be linked in at build) | **Yes — any .COM file, the CCP, PolyPascal, anything** |
| Implementation effort | Drop-in + thin SIO glue | Adapt SIDCMD → RSP packet handler (~500 lines of new asm/C) |
| Lives across cold-boot | Yes (it IS the BIOS) | No (gone after reset) |

### Decision: ship BOTH, in this order

The two are **complementary**, not competing:

1. **First — `z80-stub.c` compiled into rcbios** (small, fast, debug
   the firmware itself).  Reaches cold-boot path, ISRs, hardware init,
   CP/NET transport, CRT/floppy ISR sequencing — everything before the
   CCP takes over.  This unblocks debug-loop iteration on the four
   finishing-firmware components.

2. **Later — ZSID-adapted as a separately-loaded debug utility.**
   Debug arbitrary CP/M applications without recompiling.  Killer use
   case: stepping through the original CCP, the SDCC-built
   autoload.bin running from RAM, or third-party CP/M binaries we
   don't have source for.  Cost: ~5-10 KB resident high.

The two share the host-side toolchain (`z80-elf-gdb` Docker image,
ELF+DWARF loading, the user's GDB session).  Only the on-target
runtime differs — and on a session-by-session basis: enable `z80-stub`
at boot for firmware debug, drop into CP/M and load `GDBZSID.COM`
(working name) for application debug.

### Alternative #2 — Pi/Pico bus-snooper bridge

Still on the bench.  Would unblock the parked INIR work too, but
requires hardware fabrication.  Both target-side paths above ship
entirely as firmware/software and use the same existing-but-spare
UART, so they're lower-risk first attempts.  Pico-bridge stays as
fallback if either software path runs into an unrecoverable problem
(e.g. RST-trap overhead too high, or stub footprint too large).

## Next concrete steps (if user wants to proceed)

1. Patch `MAME_DIR` in `rcbios-in-c/run_mame.sh` to the new location,
   rebuild MAME with debug symbols, smoke-test `run_mame.sh -g` +
   `python3 gdb_trace.py` to confirm the in-workspace path still works
2. Test `z88dk-gdb` against the same MAME instance — symbolic
   debugging end-to-end without any MAME patch
3. Test `z80-elf-gdb` against MAME — expect the register-mapping bail;
   either patch MAME's feature name or apply the `set tdesc filename`
   workaround; document which one we ship
4. Scope option-2 (Pico bus bridge) — pin allocation, /BUSRQ halt
   protocol, single-step hardware semantics

## Status

- **z80-elf-gdb 17.2 Docker image: built and verified.**  `docker run --rm
  z80-elf-gdb:17.2 --version` reports `GNU gdb (GDB) 17.2`.  Accepted
  architectures: `z80, z80-strict, z80-full, r800, gbz80, z180, z80n,
  ez80-z80, ez80-adl, auto`.
- **DWARF read against our clang ELF: works.**  `z80-elf-gdb` against
  `rcbios-in-c/clang/bios.clang.elf` resolves:
  - `_bios_hw_init` at `0xdae5`
  - `_specc` at `0xe213`
  - `_isr_crt` at `0xe71c`
  - All 12 source files (`bios.c`, `bios_hw_init.c`, intrinsic headers, …)
  - Sections: `.boot 0x0-0x80, .boot_code 0x280-0x290, .bios_jt 0xda00,
    .text 0xda00-0xe8eb, .rodata, .data, .bss`
- MAME-gdbstub runtime connect (end-to-end live demo): not run interactively
  in this session — but the `gdb_trace.py` python RSP client confirms the
  wire works against the real MAME gdbstub today.  Live `z80-elf-gdb`
  connect needs the MAME feature-name patch (or `set tdesc filename`
  workaround); live `z88dk-gdb` connect needs no patch.
- Physical-hardware stub: design proposed (option 2 — Pico bus bridge),
  not built.  Pairs with the parked INIR work (same hardware unblocks both).

## Reproducing the removed environment

The workspace-level `tasks/gdb-z80/` directory (Docker recipe + unpacked
GDB source + measured build outputs) was removed 2026-07-05 as cleanup —
it was fully reproducible scratch, not source of record. To rebuild it:

1. `Dockerfile` (was `tasks/gdb-z80/Dockerfile`): `ubuntu:24.04`, installs
   build deps, fetches GDB 17.2 source, configures
   `--target=z80-unknown-elf --enable-languages=c`, builds `gdb`. Tag as
   `z80-elf-gdb:17.2`. Trivial to recreate from scratch — this is a
   completely stock upstream GDB build, no local patches applied.
2. `gdb-17.2.tar.xz` — pristine upstream source, `https://ftp.gnu.org/gnu/gdb/gdb-17.2.tar.xz`.
   `gdb/z80-tdep.c` and `gdb/features/z80-cpu.xml` are the two files worth
   reading in detail if resuming this investigation (see the register-order
   mismatch section above).
3. Stub footprint measurement (build dir): copy `gdb/stubs/z80-stub.c` out
   of the tarball, write a minimal `glue.c` (12-line inline-asm SIO ch A
   I/O) and `main.c` (14 lines referencing the four stub entry points so
   DCE doesn't eat them — both are still tracked in this repo, see below),
   then run the exact `zcc` command under "Measurement reproduction" above.

**`glue.c` and `main.c` (the two small hand-written files, not upstream
GDB source) are preserved in this repo** at
`tasks/gdb-z80-stub-glue/glue.c` and `tasks/gdb-z80-stub-glue/main.c` —
moved here from the removed workspace directory since they're real
authored code, not scratch.

This unparks the todo entry "Investigate GDB-over-physical-RC702" as a
**proven path forward via the Pi/Pico bridge that the INIR work is also
waiting for**.  Same hardware unblocks both.
