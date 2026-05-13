# HiTech C as third compiler — PARKED 2026-05-13

## Status

Investigation complete; port effort **parked**.

**Update 2026-05-13 (later same day):** the V4.11 cross-compiler distribution
was investigated as a separate alternative after this initial V3.09-only
parking. Deeper bug findings + tooling are captured in the companion
report [`hitech-shortcomings-report.md`](hitech-shortcomings-report.md).
That report supersedes this one for any resume decision.

`ghcr.io/ravn/hitech:latest` (Mark Ogden + Andrey Nikitin modern-C
reverse-engineering of HI-TECH C 3.09, vendored under `ravn/hitech`)
is now correct and usable as a compiler — four real bugs were found
during this investigation and fixed upstream. But adapting our
RC702 C sources to be HiTech-compilable is a substantially larger
piece of work than initially estimated, and the value proposition
shifted during the investigation. See "Why parked" below.

## What was done

### Upstream `ravn/hitech` work

Four issues filed, all fixed, image republished and verified:

- **#1** — `optim/optim.c:1189` `char cmp` → `int cmp`. Binary-search
  in `find_token` was unreachable on aarch64 Linux (char-unsigned
  ABI) — `zc -O` was non-functional on every published image. Fixed
  in commit `6b07966`.
- **#2** — Integration suite never invoked `zc -O`, so the optim
  regression slipped past CI for weeks. Added 5 `-O` test cells
  (`helloO`, `prfmtO`, `stropsO`, `arithO`, `pairO`) reusing the
  same `.expected` files. Commit `596cf3c`.
- **#3** — Added `-fsigned-char` to global CFLAGS (`Linux/hi.mk`)
  as defence-in-depth against the same class of bug in any of the
  17 other decompiled tools. Commit `3515251`.
- **#4** — Latent `uint8_t hi/lo/mid` underflow in the same
  binary-search idiom across `optim`, `cgen`, and `p1`. Widened
  all three sites to `int`. Commit `546cab1`.
- **#5** — Docs note: V3.09 manual claims that aren't in the
  freeware Z80 build (still open, documentation-only).

All four functional fixes are merged to `ravn/hitech` `main`; the
Container workflow republished `ghcr.io/ravn/hitech:latest` with
the new SHAs. The 5+5+1 integration suite is green on the published
image.

### Investigation of feature surface

Surveyed the V3.09 freeware Z80 build (as vendored from `agn453/`).
Items the manual claims exist but the freeware doesn't ship — all
unrelated to the bugs above; these are commercial-product features
that never entered the public archive:

1. **No ROM startoff `.obj`** despite manual §4 p.8. Only the four
   CP/M variants ship (`crtcpm.obj`, `drtcpm.obj`, `nrtcpm.obj`,
   `rrtcpm.obj`).
2. **`-A ROMADR,RAMADR,RAMSIZE`** documented (§4 p.9), not
   implemented (the flag is now an alt-target selector).
3. **`interrupt` / `fast interrupt` type qualifiers** listed
   (§5.11 p.20), rejected by `p1` at parse time.
4. **`port` type qualifier** same status.
5. Only `z80` and `CPM` are predefined macros (Table 2 p.22) —
   no `__HITECH__` exists; source can't self-detect.
6. **`CPM` always defined** by `zc` driver — must pass `-UCPM`
   to keep bare-metal headers from picking the CP/M path.
7. **`inline` keyword** (not a manual claim — V3.09 predates C99)
   parses as syntax error: `static inline T f(...)` → "; expected /
   storage class redeclared". Any port requires
   `#define inline /* empty */` for the HiTech branch.

What is in the freeware:
- `csv.obj` (40 B in `libc.lib`) provides the runtime helpers
  `ncsv`/`cret`/`indir`/`csv` as bare-metal-safe IX-frame
  manipulation. No CP/M dependency.
- `brelop.obj` likewise for relational-operator helper.
- `zas` + `link` + `objtohex` form a complete toolchain.
  `-Ptext=ADDR,bss=ADDR -Cbase` placement works for arbitrary
  ROM bases.

So a bare-metal HiTech build is possible: write ~15 lines of asm
for the reset/SP/BSS/initdata startup, drive `link → objtohex`
directly, link against `libc.lib` for the runtime helpers. No
upstream code needed.

## Why parked

Three reasons in order of weight:

### 1. Calling convention is stack-only, by design

HiTech V3.09's calling convention is hardwired in `cgen` and the
`csv`/`ncsv` runtime helpers: every function reads args from
`(ix+N)` stack slots after a `call ncsv` prologue. There is no
flag, no pragma, no attribute, no command-line switch to enable
register-passing. The only way to get register-passing would be to
modify `ravn/hitech`'s `cgen` itself — thousands of lines of
Nikitin-decompiled K&R C — which would then produce a non-standard
HiTech that isn't comparable to the historical 1989 binary.

This was the primary value gap. The user's stated framing was
"use HiTech as a reference for Z80 machine code generation that I
would like clang to aspire to." Clang Z80 with `sdcccall(1)` +
`z80_preserves_regs` will reliably beat HiTech on byte count for
any code that benefits from register-passing (session 58 saved
36 B on `xport_send_byte` callers under exactly this mechanism).
HiTech can therefore serve as a **qualitative** reference for
instruction selection patterns, but not as a quantitative byte-count
target. That's a less compelling value proposition than originally
imagined.

### 2. Source-language adaptation cost

Across cpnos-rom + rcbios-in-c + autoload-in-c (35 .c+.h files),
the C23 / C99 isms that don't compile under HiTech's K&R-ANSI parser:

| Item | Count | Backport |
|---|---|---|
| `inline` keyword | 93 | `#define inline /* empty */` |
| `__naked` / `__interrupt` / `__critical` / `__sdcccall` / `__preserves_regs` / `__attribute__` | 219 | no-op shims (mostly already in `compat.h` framework) |
| `0b…` binary literals | 42 | script sweep |
| `static_assert` / `_Static_assert` | 14 | typedef trick |
| `address_space(2)` port I/O | 12 | inline asm `IN`/`OUT` |
| for-loop decls | 10 | hoist |
| `//` line comments | 11 | likely OK (agn453 cpp is modern) |
| `true` / `false` / `_Bool` | 16 | macro + typedef |
| Mid-block declarations | unknown | hoist per error |

Estimated work: ~1.5 days for cpnos-rom + ~1 day rcbios-in-c +
~0.5 day autoload-in-c. Plus per-subproject Makefile rework for
`link → objtohex` and a hand-asm reset stub for each ROM.

### 3. autoload-in-c dry-run hit the wall immediately

`zc -C -DHITECH=1 -UCPM -Ihitech -I. boot_rom.c` against
`autoload-in-c/` produced:
- `dma_status: argument mismatch` — macro-vs-function name collision
  in `rom.h`.
- `static inline uint8_t port_in_…(void)` parse error: `, expected`
  / `storage class redeclared`.
- Multiple `#pragma clang diagnostic` lines ignored (expected).

The port is doable but requires intrusive rework of `rom.h`'s
port-I/O abstraction (currently three branches: clang/SDCC/host
stub; needs a fourth that emits inline `IN`/`OUT` asm without
`inline` or `address_space`). This is mechanical but tedious, and
the value-gap argument from (1) means even a successful port would
not give us what was originally hoped for.

## What would unblock a resume

If the value calculus shifts (e.g., user explicitly wants the
qualitative-only comparison for instruction-selection patterns, or
wants HiTech codegen for a CP/M userland utility where the
register-passing penalty doesn't matter), pick up from here:

1. **Pick scope first.** Codegen-reference-only (Scope 1) needs
   only language shimming + `zc -S` per file. Bootable ROM (Scope 2)
   adds startup asm + linker invocation + IM2 vector trampolines.

2. **Start with `compat.h`'s `__HITECH__||HI_TECH_C` branch.**
   It's already stubbed in cpnos-rom with `#error`. Replace with
   real shims (most items are no-ops or trivial macros — see the
   table above).

3. **Pass `-DHITECH -UCPM` on every `zc` invocation.** HiTech has
   no `__HITECH__` predef, and `CPM` is always defined by the
   driver.

4. **For Scope 2:** write a tiny `start_rom.s` per ROM that defines
   `_start` (DI / LD SP, top-of-RAM / clear BSS / copy initdata /
   call _main / halt). Link with
   `link -Z -Ptext=ADDR,bss=ADDR -Cbase -ofoo.lkd
   start_rom.obj user.obj libc.lib`, then `objtohex foo.lkd foo.bin`.

5. **Calling-convention compatibility for BIOS/SNIOS entry points:**
   HiTech defaults match SDCC's `sdcccall(0)` (stack args, HL return),
   so the existing register-translation wrappers in `bios_jt.s` and
   `snios.s` need a HiTech variant. Shape is identical to the
   SDCC-default variant. No `__sdcccall(1)` analogue exists.

## Cross-refs

- `ravn/hitech` issues #1–#5 — investigation outcomes.
- `ravn/hitech` PRs (commits `6b07966`, `546cab1`, `3515251`,
  `596cf3c`) — landed fixes.
- `cpnos-rom/compiler/compat.h` — has stub `__HITECH__` branch
  with `#error`, ready to receive the real shims.
- `cpnos-rom/hal.h:62-70` — has matching stub with TODO.
- `cpnos-rom/Makefile:171-172` — `COMPILER=hitech` errors out by
  design.
- `cpnos-rom/tasks/sdcc-port.md` — references hitech scaffold.
