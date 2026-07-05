# Corpus perf findings: word_fill & pi (2026-07-06)

Two of the three questions from the 2026-07-06 sweep review, investigated and
confirmed empirically (red/green: fast baseline vs slow case, all else equal).
Question 3 (why zsdcc XFAILs fannkuch+pi) remains deferred — see
`tasks/zsdcc-bench-divergence-2026-06-08.md`.

## 1. word_fill: zsdcc ~2x faster  →  ravn/llvm-z80#99 (reopened)

Sweep: llvm-z80 210147 ts vs zsdcc 128796 ts (~63% slower; bench comment
predicted 15-25%). Confirmed by inspecting generated asm on both sides.

Root cause: the walking i16 pointer is exiled to **IY** (cannot be an `(hl)`
store base) → `push iy; pop hl` + `push bc; pop iy` shuffling every iteration,
and the i16 counter is spilled to BSS (`__sfrend_bench_run-2`), reloaded+stored
every iteration. Three live i16 values (pointer, counter, store-value) contend
for HL/BC. Minimal repro `fill_seq` in the issue.

zsdcc keeps pointer=HL, counter=BC → tight `ld(hl),c; inc hl; ld(hl),b; inc hl;
dec bc; ld a,b; or c; jr nz` (~52 ts body vs llvm-z80 ~143 ts, ~2.7x).

This is the unresolved i16-counter tail of the #97/#99 BC-ping-pong family;
`push iy/pop hl` is strictly worse than the `ld c,l; ld b,h` ping-pong #99 bailed
on. Fix: keep pointer=HL, counter=BC/DE.

## 2. pi: llvm-z88dk ~6x slower than llvm-z80  →  ravn/rc700-gensmedet#120

llvm-z88dk 231M ts vs llvm-z80 freestanding 38M ts (~6x), with **identical clang
codegen** for the pi TU. Only the linked 32-bit mul/div differs: the z88dk bridge
links naive C `rt_helpers.c` helpers; freestanding links `z80_rt.a` asm.

Confirmed with a 2000-iteration microbench (same clang/flags/call-sites, only the
linked helper swapped):

| Helper | freestanding z80_rt.a (asm) | naive rt_helpers.c (C) | factor |
| --- | --- | --- | --- |
| total (mul+div) | 23.2M ts | 138.8M ts | 6.0x |
| `__udivmodsi4` (div+rem) | 16.99M ts | 118.10M ts | 6.95x |
| `__mulsi3` | 6.42M ts | 20.86M ts | 3.25x |

6.0x microbench factor matches the pi gap (231M/38M) exactly. `z80_rt.a` div uses
shadow registers (`exx`) for a 32-step register-only non-restoring loop; naive C
does restoring division with spilled 32-bit-wide temporaries. Division dominates.

Fix: provide asm 32-bit runtime for the `llvmz80` bridge path
(`z88dk/lib/llvmz80/`), replacing the corpus stopgap `rt_helpers.c`.

## Reproduce

```
cd tasks/compiler-comparison-corpus
BENCH=word_fill ./sweep.sh
BENCH=pi ./sweep.sh
```
