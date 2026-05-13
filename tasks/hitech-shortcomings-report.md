# HI-TECH C: shortcomings found while integrating into rc700-gensmedet

Investigation period: 2026-05-13.
Status: **PARKED** (second time, with substantially deeper findings).
Supersedes / extends the earlier note at [hitech-port-parked.md](hitech-port-parked.md).

## TL;DR

Two distinct HiTech C distributions were investigated as candidate third
compilers for the RC702 C sources (alongside clang Z80 and SDCC):

| Distribution | Run-on | Origin | Status |
|---|---|---|---|
| **V3.09 freeware** (CP/M-hosted) | DOSBox / linux re-port | `ogdenpm/hitech` / `agn453/HI-TECH-Z80-C`; vendored at [`ravn/hitech`](https://github.com/ravn/hitech) | working after 4 bugfixes; usable as CP/M userland target only |
| **V4.11 cross compiler** (DOS-hosted) | DOSBox | Microchip 2018 release; vendored at [`ravn/hitech-v411`](https://github.com/ravn/hitech-v411) | usable for intvec.c + boot_rom.c; rom.c blocked by two cgen bugs |

Net result: neither distribution can fully compile `rc700-gensmedet/autoload-in-c/rom.c`
without source-level rewrites that significantly reshape the codebase.
The infrastructure (Docker images, host wrapper, DOS-side stderr capture
and screen-dump tools) is reusable for any future investigation.

---

## V3.09 freeware investigation

Discovered four real bugs in the modern-C port that ships in `ravn/hitech`.
All fixed during this investigation; image republished. See timeline.md
session 70 for full chronology.

### Bug V3.09-1 — `optim` find_token char-sign bug
- **Site**: `optim/optim.c:1189`, `find_token()`.
- **Mechanism**: `char cmp;` then `cmp = strcmp(...)`. On ARM Linux (AAPCS64),
  `char` defaults to unsigned, so `strcmp`'s negative returns wrap to 0..255.
  `cmp < 0` is always false. Binary search of the 110-entry `operators[]`
  table never takes the "go-left" branch.
- **Effect**: `zc -O` non-functional on every published aarch64 image.
  Common mnemonics (`ld`, `add`, `jr`, `djnz`, `defw`) became unreachable;
  optim aborted with "Can't find op" or silently miscompiled.
- **Fix**: `char cmp;` → `int cmp;` (one character).
- **Filed**: `ravn/hitech` issue #1, fixed in commit `6b07966`.

### Bug V3.09-2 — `uint8_t` indices underflow in binary searches (latent)
- **Sites**: same `find_token` (optim.c:1190), `cgen/cgen.c:1028 sub_1B2`,
  `p1/lex.c:394–396 parseName`.
- **Mechanism**: `uint8_t high, low, mid;` then `high = mid - 1` underflows
  to 255 when `mid == 0`. Latent because with table sizes ≤ 110 entries
  and working comparisons, the loop converges before `mid` hits 0.
- **Fix**: widen to `int`.
- **Filed**: `ravn/hitech` issue #4, fixed in commit `546cab1`.

### Bug V3.09-3 — build-system char-sign fragility
- **Site**: `Linux/hi.mk` CFLAGS lacked `-fsigned-char`.
- **Mechanism**: the Nikitin-decompiled sources mirror 1989 K&R idioms that
  assumed `signed char` (HiTech CP/M's default). Without `-fsigned-char`,
  ARM-Linux builds silently break the assumption.
- **Fix**: `+ -fsigned-char` to global CFLAGS.
- **Filed**: `ravn/hitech` issue #3, fixed in commit `3515251`.

### Bug V3.09-4 — integration suite never exercised `zc -O`
- **Site**: `tests/Makefile` ran 5 cells, none with `-O`.
- **Mechanism**: V3.09-1 stayed green in CI for weeks because optim
  was never invoked end-to-end.
- **Fix**: added 5 parallel `-O` cells (`helloO`, `prfmtO`, …).
- **Filed**: `ravn/hitech` issue #2, fixed in commit `596cf3c`.

### V3.09 surface limitations (not bugs — historical artefacts)
Documented as `ravn/hitech` issue #5:
- No ROM-target startup object ships. V3.09 manual describes ROM mode;
  freeware only includes CP/M startups (`crtcpm.obj`, `nrtcpm.obj`, etc.).
- `-A ROMADR,RAMADR,RAMSIZE` syntax documented but unimplemented (the
  modern-C driver re-purposed `-A` for named alt-targets).
- `interrupt` / `port` type qualifiers documented but rejected at parse
  time by `p1`.
- `CPM` predefined unconditionally by `zc` driver.
- No `__HITECH__` / `HI_TECH_C` predef.

The freeware grant only covered the CP/M-native compiler. The commercial
cross-compiler product (which the manual describes ROM mode for) was
released separately by Microchip in 2018 — that's V4.11.

---

## V4.11 cross-compiler investigation

V4.11 is the DOS-hosted cross compiler the V3.09 manual originally
described. Released by Microchip in 2018 under a re-distribution license;
vendored at `agn453/HI-TECH-Z80-C-Cross-Compiler`; this fork
[`ravn/hitech-v411`](https://github.com/ravn/hitech-v411) adds a Docker
wrapper (DOSBox) + diagnostic tools.

V4.11 fixes all five V3.09 "manual vs reality" gaps:
- ROM is the default mode (no `-CPM` flag = ROM); `ZCRT.OBJ` / `ZCRTI.OBJ`
  ship as startups.
- `-A ROMADR,RAMADR,RAMSIZE` implemented (verified in `z80/ZC.C` source,
  the one source file that ships).
- `interrupt` type qualifier emits proper `ei` / `reti`.
- `port` type qualifier emits `IN A,(n)` / `OUT (n),A`.
- `CPM` only predefined when `-CPM` is passed.

**Empirical codegen comparison** (same `hello + sum 0..10` C source):
- V3.09: 8528 B without `-O`, 8517 B with `-O`.
- V4.11: 5148 B without `-O`, 5134 B with `-O`.

V4.11 saves ~40% on this microbenchmark, mostly via inlined function
prologue/epilogue (no `call ncsv / jp cret` round-trip).

### V4.11 toolchain limitations (workable, surface-level)

These were discovered and worked around in
`rc700-gensmedet/autoload-in-c/`; see commit `c131b85` for the
implementation.

| # | Limitation | Workaround |
|---|---|---|
| 1 | DOS 8.3 filenames only | Source filenames in autoload-in-c happen to fit; cross-subproject ports would need stub-shims |
| 2 | V4.11 `cpp.exe` doesn't implement `#elif` (silent no-op; always falls to `#else`) | Bypass via host `gcc -E -P` |
| 3 | V4.11 `p1` honours `\x1a` (CP/M EOF) mid-stream, truncating parse silently. Every V4.11 header ends with one | Python filter strips `\x1a` before feeding to p1 |
| 4 | No `<stdint.h>` / `<stdbool.h>` (pre-C99) | Shim header in `autoload-in-c/hitech/stdint.h` |
| 5 | `inline` keyword misparsed (treated as variable name) | `compat.h` `#define inline /* empty */` for HiTech |
| 6 | `for (int i=…; …)` rejected (no C99 for-loop decls) | None used in autoload-in-c; broader sweep would need source rework |
| 7 | `#include <string.h>` BEFORE `#include "rom.h"` makes cgen emit empty .OBJ | Swap include order (no-op for clang/SDCC) |
| 8 | `__attribute__` / `__naked` / `__interrupt` not recognised | `compat.h` macros: `SECTION()`, `NORETURN`, `USED`, `__naked` → empty, `__interrupt(n)` → V4.11 native `interrupt` |
| 9 | `port` keyword requires `-QP,port` flag to p1 (zc.exe passes automatically when targeting Z80) | Pass explicitly in our pipeline |
| 10 | DOSBox `>` redirect can't separate stdout from stderr; classic and Staging both collapse to last-redirect | Custom DOS .COM (`runcap.com`) uses INT 21h/46h DUP2 to alias handle 2 to a file before EXEC'ing the target |
| 11 | DOSBox 0.74 in headless mode discards all DOS console output (screen-only writes) | `SCRDUMP.COM` reads the text-mode VGA buffer at B800:0000 and writes to a host-visible file before exit |

All of (1)–(11) are working around the V4.11 toolchain's design choices,
not its bugs. The autoload-in-c HITECH compile path (commit `c131b85`)
gets `intvec.c` and `boot_rom.c` compiling to valid `.OBJ` files end-to-end
under V4.11; `rom.c` compiles partially.

### V4.11 cgen bugs (structural, blocking)

`rom.c` does NOT fully compile under V4.11. cgen.exe truncates the output
silently with no error message (cgen writes to handle 2; DOSBox 0.74's
`>` redirect doesn't capture it). The behaviour was reproducible and
identifiable only via interactive screen capture using the `SCRDUMP.COM`
tool — headless runs simply saw a 6104-byte output and an exit code we
couldn't read.

Once visible, the actual messages reveal **two distinct internal
assertion failures in cgen.exe** at three sites in rom.c.

#### Bug V4.11-A — `trees.c:1230` "tp->t_type" assertion

cgen's expression-tree code dereferences a type pointer field that's null.
The assertion `assert(tp->t_type)` says "every AST node must have a type
assigned by now"; the failing path constructs a node without setting its
type. Three constructs in `rom.c` trigger this:

```c
/* in calc_size_of_current_track() */
tb <<= 1;                               /* compound shift on word */

/* in fdc_write_full_cmd() */
for (i = 0; i < sizeof(fdc_cmd); i++) { /* sizeof on struct as loop bound */
    fdc_write_when_ready(((byte *) &fdc_cmd)[i]);    /* pointer-cast + index */
}
```

Each is a specific operator combo where V4.11's type-propagation has a hole:
- `<<=` compound assignment on a `word` (uint16_t) — the intermediate
  shift-tree's t_type doesn't propagate before the enclosing assignment
  asks for it.
- `(byte *)&struct_addr[i]` — three layered operators (address-of, cast,
  index). The cast result's t_type isn't set before the index uses it.
- `sizeof(struct_type)` as a loop bound — the sizeof's t_type
  (should be `size_t`) isn't set before the `<` comparison uses it.

**Per-site workarounds verified to compile**:
```c
/* (A.1) */ dma_transfer_size = ((word) sectors) << (7 + fdc_cmd.size_shift);
/* (A.2) */ fdc_write_when_ready(fdc_cmd.cylinder);  /* unroll the 7 fields */
/*       */ fdc_write_when_ready(fdc_cmd.head);  /* ... */
```

The workarounds are minor source rewrites; clang/SDCC compile both forms
identically. With them in place, cgen makes it further into `rom.c`, but
then hits Bug B.

#### Bug V4.11-B — `sym.c:433` "pp->s_nelem == 0" assertion

cgen's symbol-table code expects a symbol to NOT be an array (array-element-
count = 0), but finds a non-zero count.

From V3.09 cgen.c source (Nikitin reverse engineering — our closest proxy
for V4.11 internals):

```c
/* cgen.c:1482 — b_nelem is V4.11's s_nelem renamed */
if (sb->b_nelem == 0) sb->b_nelem = l1 / l2;  /* derive from declarator bounds */
```
```c
/* cgen.c:1545 — BSS emit only for arrays */
if ((sb->b_sloc & 1) == 0 && sb->b_nelem != 0 && (sb->b_refl & 2) == 0) {
    prPsect(P_BSS); ...
    printf("\tdefs\t%u\n", sb->b_size);
}
```

So `s_nelem` is 0 for scalars and N for arrays. The assertion guards a
scalar-only code path.

**Hypothesis**: V4.11 cgen *also* sets `s_nelem` to **struct member count**
for struct-typed symbols, conflating struct-member-count with array-element-
count. Then any scalar-only path that processes a struct symbol fires the
assertion.

V3.09 source has a "Strucdecl - bad nelem" error path (cgen.c:2176) which
hints `nelem` was already touched during struct decls in V3.09; V4.11
appears to have extended this without auditing the scalar-only paths.

Triggers in rom.c (and rom_boot.c, by extension):
- `fdc_command_block fdc_cmd = {0};` — global decl with brace-aggregate
  initialiser.
- `fdc_result_block fdc_result = {0};` — same.
- `byte *p = (byte *)&fdc_cmd;` — address-of-struct + cast.
- `((byte *)&fdc_cmd)[i]` — same path through cast operator.

Field accesses (`fdc_cmd.head = x`, `fdc_cmd.eot`) do **not** trip — they
look up the member symbol, whose own `s_nelem` is 0.

**Why this is structural, not surface-level**: `fdc_cmd` and `fdc_result`
are used as structs throughout the autoload-in-c codebase. Each address-
taking or aggregate-init site is a separate Bug-B trigger. The fix isn't
a per-site rewrite — it's a redesign of the data structures, or living
without struct globals entirely.

Options to address Bug B without modifying V4.11's source (which we don't
have):

1. **Replace `fdc_command_block` and `fdc_result_block` with byte arrays
   + named-index macros**:
   ```c
   extern byte fdc_cmd[8];
   #define FDC_CMD_CYLINDER   0
   #define FDC_CMD_HEAD       1
   /* ... */
   ```
   Mechanical refactor across 30–50 sites. Eliminates Bug B sources;
   clang/SDCC still compile fine but lose type safety.

2. **Split `rom.c` into smaller TUs** so the struct symbol re-enters
   each TU's cgen with a fresh symbol table. Doesn't fix Bug B per se,
   but reduces the surface area each cgen run sees. **Attempted**;
   broke clang due to `static`-helper visibility. Reverted. Real
   amount of refactoring needed.

3. **Live with `intvec.c` + `boot_rom.c` compiling under V4.11 and
   `rom.c` not** — use V4.11 for codegen-reference purposes (compare
   instruction-selection patterns against clang) on the working files
   only. Don't pursue a bootable V4.11 PROM.

### V4.11 calling convention

Empirical observation from `.as` output: same as V3.09 (stack-args,
HL-return), with the prologue/epilogue inlined (no external `ncsv`/`cret`
helpers). Args at `(ix+4)` / `(ix+6)` rather than V3.09's `(ix+6)` / `(ix+8)`
(no IY save).

There is no flag, pragma, or attribute in V4.11 to enable a
register-passing calling convention. Confirmed via inspection of `z80/ZC.C`:
zc passes `-QP,port` (port qualifier) to p1 but no flag that would enable
register-passing. The cgen call-emission code is fixed.

Consequence: V4.11 cannot serve as a quantitative codegen reference for
clang Z80 because clang with `sdcccall(1)` + `z80_preserves_regs` will
beat V4.11 on byte count for any register-pressure-sensitive code (see
session 58 — 36 B saved on `xport_send_byte` callers via exactly this
mechanism). V4.11 is useful only as a **qualitative** reference for
instruction-selection patterns.

---

## Tooling built during the investigation

All reusable for future V4.11 forensics. Committed to
`ravn/hitech-v411` master:

| Path | Purpose |
|---|---|
| `Dockerfile` | wraps V4.11 binaries in DOSBox; runs on any Linux/macOS host without a DOS install |
| `hitech-wrap` | per-tool entrypoint (zc, p1, cgen, optim, zas, link, …) inside the image |
| `tests/run-all-tests.sh` | 8-cell verification of V4.11 capabilities |
| `tools/runcap.asm` | DOS .COM that captures stderr via INT 21h/46h DUP2 (bypasses DOSBox's redirect limitations) |
| `tools/dup2test.asm` | sanity-check for the DUP2 mechanism |

Plus locally (not in git, recreatable): `/tmp/hitech-lab/` with
`SCRDUMP.COM` (NASM source at `/tmp/al-hitech-test/scrdump.asm`) — a
60-byte DOS .COM that dumps the 80×25 text-mode VGA buffer (B800:0000)
to a host-visible file. Essential for capturing cgen's BIOS-console
output, which DOSBox in headless mode silently discards. Also the
`find_all_asserts.py` driver that iteratively stubs trigger functions
until cgen runs clean.

---

## Why both distributions are parked

### V3.09 freeware (`ravn/hitech`)
- Compiler is working post-fixes; image is republished.
- Lacks the V3.09-manual features the cross-compiler had (ROM mode,
  -A flag, interrupt/port qualifiers, ROM library).
- Calling convention is stack-args, identical to V4.11.
- Suitable as a target only for CP/M userland binaries.

### V4.11 cross-compiler (`ravn/hitech-v411`)
- Has all the ROM-target features the V3.09 manual described.
- Has working `interrupt` / `port` qualifiers.
- Two compiler bugs (V4.11-A, V4.11-B) block compiling rom.c without
  source restructuring.
- We don't have V4.11 source (only the driver `ZC.C` ships); cannot
  fix cgen.
- Microchip released V4.11 in 2018 under freeware grant but does not
  maintain it. No active upstream.

### Bottom line
The original framing ("use HiTech as a Z80 codegen reference that clang
should aspire to") is unreachable through either distribution. HiTech
is fundamentally a 1989/1992-era stack-args compiler; modern clang with
`sdcccall(1)` + `z80_preserves_regs` wins on byte count for register-
pressure-sensitive code (already demonstrated in session 58).

HiTech remains useful for:
- **Qualitative instruction-selection comparison** on the files that
  already compile (intvec.c, boot_rom.c, parts of rom.c). Read `.as`
  listings to spot patterns clang doesn't find.
- **Historical fidelity** — building under the era's tooling for
  research / reference purposes.
- **CP/M userland** binaries (V3.09) where stack-args is the norm.

Neither use case justifies the structural rom.c rewrite Bug B would
require.

---

## What it would take to un-park

If the value calculus shifts, the resume work in priority order:

1. **Refactor `fdc_command_block` and `fdc_result_block` to byte arrays
   with named-index macros**. Eliminates Bug B at the structural level.
   ~30–50 sites in rom.c + rom_boot.c. Mechanical but invasive. Touches
   clang/SDCC builds (no functional change; loses type safety).

2. **Apply Bug A workarounds at each `rom.c` site**. ~3 statements need
   rewrite. Doesn't disturb clang/SDCC.

3. **Continue rom.c source split** (rom.c → rom.c + rom_boot.c) for
   cgen state hygiene. Re-do the work-in-progress split that broke clang;
   resolve static-helper visibility by promoting them to non-static in
   rom.h. ~10 sites.

4. **Write a V4.11 ROM startup `.obj`** and a linker invocation that
   produces a bootable `.bin` at 0x0000 + relocation logic. ~50 lines
   of `zas` source plus Makefile rework.

5. **Wire the V4.11 link → objtohex → MAME boot test**, mirroring the
   existing clang and SDCC paths in autoload-in-c/Makefile.

Total estimate: 2–3 days of focused work. Gated on a project decision
about whether HiTech-built bootable ROMs add enough value to justify
the structural changes.

---

## Cross-references

- `ravn/hitech` (V3.09 freeware fork) — issues #1–#5, commits
  `6b07966`, `546cab1`, `3515251`, `596cf3c`.
- `ravn/hitech-v411` (V4.11 cross-compiler fork) — commit `b9c02d7`
  with Docker wrapper, integration tests, runcap/dup2test tools.
- `rc700-gensmedet` commit `c131b85` — autoload-in-c HITECH compile
  path (compat.h shims, hitech/ subdir, build script).
- [`hitech-port-parked.md`](hitech-port-parked.md) — earlier (now
  superseded) parking note from the V3.09-only investigation.
- [`timeline.md`](timeline.md) sessions 70 (V3.09 fork sweep) and 71
  (V4.11 deep-dive with this report's findings).

## File index for the investigation

| Location | Content |
|---|---|
| `/tmp/al-hitech-test/` | scratch dir: probe.c (rom.c copy stubbed during automated runs), build-htc.sh, runcap.asm, scrdump.asm, dup2test.asm, find_all_asserts.py |
| `/tmp/hitech-lab/` | interactive lab: HITECH/ (V4.11 binaries), work/ (sources + .I + .COM tools), dosbox.conf, auto.conf, launch.sh, README.md |
| `/tmp/hitech-v411/` | local clone of `ravn/hitech-v411` |
| `/tmp/v411-zc.c` | V4.11's ZC.C driver source (only V4.11 source we have) |
| `/tmp/v309-cgen.c` | V3.09 cgen.c (Nikitin RE; our proxy for V4.11 cgen internals) |

The two `/tmp/` lab directories are not in git but trivially
recreatable from the in-repo `autoload-in-c/hitech/` infrastructure
plus the V4.11 fork checkout.
