# Z80 C compiler landscape — survey 2026-05-13

Inventory of maintained and historical Z80 C compilers, evaluated for their
usefulness as additional codegen oracles alongside our existing SDCC +
clang/llvm-z80 toolchain. The ZX Spectrum / RC2014 / MSX retro scenes were
explicitly canvassed.

Driver question: *Which independent Z80 C compilers can we run on the same C
sources to detect codegen weaknesses in llvm-z80?* A third compiler that
generates better code than both clang AND SDCC on a specific construct is a
strong oracle signal for filing a llvm-z80 issue.

## Tier 1 — actively maintained, worth adding

### sccz80 (z88dk's native non-optimising C compiler)

Distinct from zsdcc (already used). Independent codegen path inside z88dk;
emphasis on small code via runtime helper calls rather than inlining. Very
different shape from SDCC's IX-frame-heavy output. Already installed in our
workspace via the z88dk Docker image — no new toolchain needed.

- C90-ish (not full C99/C23)
- ROM output via `zcc +z80 -clib=sdcc_ix -create-app` with custom target cfg
- ORG configurable; standalone binaries straightforward
- Same toolchain we already invoke for zsdcc

Oracle value: **high**. Different design philosophy from both SDCC and clang;
likely to surface fresh outliers in the cpnos-rom matrix.

### ~~vbcc Z80 backend~~ — CORRECTION 2026-05-14: vbcc has NO Z80 backend

This entry was wrong. Re-verified 2026-05-14 against authoritative sources:

- Wikipedia "vbcc" article CPU list: *"68k, ColdFire, PowerPC, 6502, 65C02,
  65C816 (in native mode), VideoCore, 80x86 (386 and above), Alpha,
  C16x/ST10, 6809/6309/68HC12, and Z-machine."* No Z80.
- vbcc upstream target archives at `sun.hasenbraten.de/vbcc/?view=targets`:
  all targets are m68k/PPC/ColdFire variants for Amiga/Atari. No Z80
  download exists.
- The earlier survey conflated **Z-machine** (Infocom interactive-fiction
  virtual machine) with **Z80** (Zilog 8-bit CPU). David Given's `vbccz`
  is the Z-machine backend, not a Z80 backend.

There may be a private / third-party vbcc-Z80 fork somewhere, but nothing
public was found in 2026-05-14 searches. Treating vbcc as **not viable**
for Z80 oracle work.

ACK is promoted to the highest-value remaining candidate (see below).

**Resolution 2026-05-14: ACK measured and kept in Tier 1.** ACK's `cpm`
platform targets i80 (Intel 8080), not Z80 — but **8080 is a strict subset
of Z80, so ACK's `.com` output runs natively on Z80** and ACK is a Z80-capable
Tier-1 compiler (the weakest of the four, but a fourth Tier-1 entry, not a
separate category). Output is 4.2× clang on this corpus. See ACK section
below for details. No further Tier-1 entries remain to add.

## Tier 1 (continued) — ACK

### ACK (Amsterdam Compiler Kit) — MEASURED 2026-05-14

Tanenbaum/Jacobs's classic retargetable toolchain, maintained by David Given.
V6.2+ as of April 2025; active GitHub repo at `davidgiven/ack`.
C/Pascal/Modula-2/BASIC frontends.

**ACK has no separate Z80 backend.** Its `cpm` platform target uses the `i80`
(Intel 8080) machine description. Output `.COM` files run on Z80 because
8080 is a strict subset of Z80, but ACK does not emit any Z80-only
instructions (`DJNZ`, `JR`, `EX AF,AF'`, `EXX`, `IX`/`IY`, `BIT`/`SET`/`RES`,
`LDIR`/`LDDR`, block I/O, etc.). Confirmed: zero CB/DD/ED/FD prefix bytes in
linked output.

Measured in `sccz80-oracle-corpus/findings-2026-05-13.md`:
- Total corpus: **481 B**, vs clang's 115 B → **4.2× clang**
- Worst-of-four on every function tested
- `-DUSE_VOLATILE` produces byte-identical output (ACK ignores volatile for
  codegen — no merging to suppress, no caching to skip)

Oracle value: low. Disagreement direction is always "ACK lacks the instruction
clang used", which is structurally pre-determined by the i8080 ISA, not by
codegen choices. Some indirect value as a "1976 i8080 floor" data point: if
clang ever regresses to within 2× of ACK, that signals a structural backend
breakage.

Folklore "ACK is the world's smallest CP/M C compiler" refuted on this
corpus — likely referred to the *compiler binary* being small, not its
generated code.

### MESCC (Mike's Enhanced Small C Compiler)

MiguelVis on GitHub. Modern revival of Small-C 1.7 (Oct 1985), GPL-licensed,
runs natively under CP/M on Z80 (not a cross-compiler). Trivia only — Small-C
is a strict subset of C (no `struct` returns, limited type system) and won't
compile the cpnos sources without rewriting them. Not useful as an oracle.

### Rust → Z80 via LLVM (`ajokela/rust-z80`, `z80-backend` branch)

Mirror of LLVM's generic SDAG/GISel paths *without* our llvm-z80 patches.
Useful as a regression-mirror to spot where ravn/llvm-z80's improvements
diverged from upstream LLVM behavior. Not a separate codegen oracle.

### Zig eZ80 backend (issue #23579)

Ongoing community effort; not production. jacobly0 (upstream llvm-z80 owner)
contributes here, which means future Zig signal will overlap heavily with
upstream LLVM behavior. Watch but don't invest.

### Cranelift-Z80

Experimental Rust compiler backend targeting Z80 without LLVM. Very early.
Worth knowing about.

### Z80Babel (`MartinezTorres/z80_babel`)

Pipeline: C/C++/Rust/Zig/D → LLVM-IR → C → SDCC. Output is ultimately SDCC's,
so *not* an independent oracle — its codegen is downstream of one we already
use.

## Tier 3 — historical / unavailable / not viable

### Commercial, unavailable

- **IAR Z80 v4.06A** — last IAR Z80 compiler. Not on IAR's site; reportedly
  still sold privately. No public availability, no benchmarks, no integration
  path.
- **Zilog ZDS-II for Z80** — last Zilog plain-Z80 compiler. Not for sale;
  binaries to existing license-holders only. (ZDS-II for eZ80 is a different
  product, reportedly buggy — farlow.dev 2025-08-08 — and eZ80 isn't our
  target.)
- **Cosmic / Whitesmiths Z80** — historical Cosmic Z80 cross-compiler
  (v3.32). Cosmic's current product line dropped Z80; no maintained release.

### Open / freely distributable but frozen

- **HiTech C 3.09** — parked in this project; see
  `rc700-gensmedet/tasks/hitech-port-parked.md`. Available via
  `ghcr.io/ravn/hitech` Docker.
- **BDS C** — 8080/Z80 CP/M compiler, public-domain since 2002. *The* CP/M C
  compiler of the early 80s. Code-quality benchmark of historical interest;
  not maintained.
- **ASCII MSX-C** — proprietary MSX-native C compiler. Abandoned;
  Japanese-only docs.
- **GST C, Aztec C, Software Toolworks C/80, Mark Williams Let's C, Lattice
  C for CP/M, HiSoft C** — historical CP/M / ZX Spectrum C compilers. All
  frozen.

### ZX Spectrum Next specifically

- **ZNC** (taylorza, itch.io) — "C-like", not C. Cannot ingest cpnos
  sources.

### Confirmed non-existent for our purposes

- **GCC** — no Z80 backend; historical attempts never merged or maintained.
- **TCC, chibicc, cproc, 8cc, PCC, Open Watcom, CompCert** — no Z80 backend.

## Comparison summary

| Compiler | Maintained | Independent codegen | ROM-capable | Cost to add | Oracle value |
|----------|------------|---------------------|-------------|-------------|--------------|
| SDCC / zsdcc | Yes | Yes | Yes | (already used) | baseline |
| clang / llvm-z80 | Yes | Yes (with our patches) | Yes | (already used) | baseline |
| **sccz80** | Yes | Yes | Yes | Low (Docker present) | Low (~2.2× clang, uniformly worse — corpus 2026-05-14) |
| ~~vbcc~~ | n/a | n/a | **NO Z80 target** | n/a | n/a |
| **ACK** | Yes | Yes (i8080, not Z80) | Yes (via cpm) | Done | **Low (~4.2× clang, i8080 floor — corpus 2026-05-14)** |
| MESCC | Yes | Yes | CP/M only | High (port C subset) | None (C subset) |
| Rust-LLVM-z80 | Partial | No (shares LLVM) | Experimental | High | Mirror only |
| Zig eZ80 | Early | No (shares LLVM) | Experimental | High | Mirror only |
| Z80Babel | Yes | No (downstream SDCC) | Yes | Med | None |
| HiTech C | Parked | Yes | Yes | (parked) | n/a |
| IAR / Zilog ZDS / Cosmic | n/a | Yes | Yes | Unobtainable | n/a |

## Recommendation (revised 2026-05-14)

1. ~~Add sccz80~~ — DONE 2026-05-14 in `sccz80-oracle-corpus/`. Result:
   sccz80 lands at ~2.2× clang's size on every codegen pattern tested.
   Uniformly worse → low oracle value (disagreement always means "sccz80
   is wrong", not actionable about clang). Do not add as cpnos-rom build
   cell.
2. ~~Add vbcc~~ — IMPOSSIBLE. No Z80 backend in vbcc. Survey error
   corrected above.
3. ~~Try ACK next~~ — DONE 2026-05-14 in `sccz80-oracle-corpus/`. Result:
   no Z80 backend exists in ACK; `cpm` platform uses i8080. Output is
   4.2× clang on this corpus, byte-identical between volatile/non-volatile.
   Useful only as a "1976 i8080 floor" data point; no codegen oracle value
   because every disagreement is "ACK lacks the instruction" rather than
   "ACK chose differently".
4. **Stop here.** No C compiler exists for Z80 oracle expansion beyond the
   four now measured (clang / zsdcc / sccz80 / ack). Direct llvm-z80 work
   (the original goal) is the higher-value direction. Future oracle
   expansion should target hand-written assembly references rather than
   another C compiler — see `findings-2026-05-13.md` final section.

Tasks tracked in `rc700-gensmedet/tasks/todo.md` under "Additional Z80 C
compilers as codegen oracles".
