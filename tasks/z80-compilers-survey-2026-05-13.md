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

### vbcc Z80 backend (Volker Barthelmann)

Manual reissued February 2025. Genuinely independent IR + register allocator +
peepholer; well-regarded across the compiler-construction community. Z80 target
supports ROM via linker scripts; no CP/M dependency.

- C89 plus parts of C99 (covers cpnos sources)
- Multi-backend (m68k/PPC/6502/8086/Z80); Z80 backend mature
- Licensing requires unaltered vbcc download + separate Z80 patch
- Needs Docker image (no brew per project rule)

Oracle value: **high**. Backend choices on the same source highlight where
clang/llvm-z80 makes weak decisions that SDCC happens to share — the most
useful kind of third opinion.

## Tier 2 — useful but lower priority

### ACK (Amsterdam Compiler Kit)

Tanenbaum/Jacobs's classic retargetable toolchain, maintained by David Given
(same author as vbccz). V6.2+ as of April 2025; active GitHub repo at
`davidgiven/ack`. C/Pascal/Modula-2/BASIC frontends. Z80 backend with `cpm`
platform target emits `.COM` files; ROM target needs custom platform stanza
but is structurally feasible.

Caveat: ACK's Z80 backend is widely considered weak on code density — more of
a teaching / portability project than an optimizing compiler. Its oracle
value is inverted from vbcc's: a *worse* compiler agreeing with clang carries
less signal than a *better* compiler diverging. Still genuinely independent
code, so a disagreement is informative.

Recommendation: add after sccz80 + vbcc are landed and their signal is
characterised. If those two exhaust the cheap codegen wins, ACK is unlikely
to add much.

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
| **sccz80** | Yes | Yes | Yes | Low (Docker present) | **High** |
| **vbcc** | Yes | Yes | Yes | Med (new Docker) | **High** |
| ACK | Yes | Yes | Yes (via cpm) | Med (new Docker) | Medium-low |
| MESCC | Yes | Yes | CP/M only | High (port C subset) | None (C subset) |
| Rust-LLVM-z80 | Partial | No (shares LLVM) | Experimental | High | Mirror only |
| Zig eZ80 | Early | No (shares LLVM) | Experimental | High | Mirror only |
| Z80Babel | Yes | No (downstream SDCC) | Yes | Med | None |
| HiTech C | Parked | Yes | Yes | (parked) | n/a |
| IAR / Zilog ZDS / Cosmic | n/a | Yes | Yes | Unobtainable | n/a |

## Recommendation

1. Add **sccz80** as a third cpnos-rom build cell. Cheapest by far.
2. Add **vbcc** as a fourth codegen oracle (size-diff only, do not ship a
   PROM). Medium effort; high expected signal.
3. **ACK** is opportunistic; pick up only if (1) and (2) plateau and we still
   want a fourth independent opinion.
4. Skip everything else unless project priorities change.

Tasks tracked in `rc700-gensmedet/tasks/todo.md` under "Additional Z80 C
compilers as codegen oracles".
