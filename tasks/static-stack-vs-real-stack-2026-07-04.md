# `+static-stack` vs. real-stack frames — settled 2026-07-04

## Question

`+static-stack` (locals live in fixed BSS slots at `__sfrend_<fn> - N`,
addressed directly instead of via SP/IX) was originally adopted because the
firmware has no recursion and IX/IY-relative addressing was expensive. A lot
of backend work has landed since. Does disabling `+static-stack` now produce
better code, given register pressure is otherwise severe (only BC/DE/HL are
freely allocatable)?

## Answer: No — empirically confirmed on both hard-size-capped production
## targets. Disabling it breaks the build outright, it doesn't just regress.

### autoload-in-c (2048 B hard PROM cap)

| static-stack | raw `.text` | ZX0-compressed | fits 2048 B cap? |
|---|---:|---:|:---:|
| ON (current) | 3393 B | 1916 B | yes (132 B free) |
| OFF | 4162 B (**+769 B, +22.7%**) | 2272 B | **no — 224 B over cap** |

Build command used for the OFF measurement: `make -C clang clean && make
CLANG_EXTRA="-Xclang -target-feature -Xclang -static-stack" clang/prom.clang.bin`
(from `autoload-in-c/`). `ld.lld` fails with `PROM0 socket exceeds 2048 bytes
after ZX0!`.

### cpnos-in-c PROM1-only line program (2048 B hard cap)

| static-stack | result |
|---|---|
| ON (current) | 2012 / 2048 B (36 B free) |
| OFF | `.init` region overflow by 218 B — **link fails** |

Build command: `make prom1-lineprog COMPILER=clang
CLANG_EXTRA="-Xclang -target-feature -Xclang -static-stack"` (from
`cpnos-in-c/`). `ld.lld` errors: `.init exceeds 640 B INIT region budget`,
`payload grew into stack workspace at 0xF60E`.

Both experiments were reverted immediately after measurement (git-tracked
build artifacts restored via `git checkout --`, both baselines rebuilt clean
and re-verified). No production code or build files were changed by this
investigation.

## Why (architectural reasons, verified against current backend code)

1. **IX is always reserved**, with or without `+static-stack`
   (`Z80RegisterInfo.cpp` `getReservedRegs`, blocked by ravn/llvm-z80#112's
   pseudo-expansion gap — un-reserving it produces FATAL encoder errors).
   So there is no "free extra register from using IX as a real frame
   pointer" to be had by turning static-stack off; that door is closed
   either way.
2. **IY is only allocatable when `hasOptSize() && staticStack()`**
   (`llvm::z80IsIYAllocatable`, `Z80RegisterInfo.cpp:277-279`). Turning
   static-stack off doesn't just lose the addressing-mode benefit below —
   it also takes IY back out of the allocatable set at `-Oz` (the flag
   production actually builds with), making register pressure *worse*, not
   better.
3. **Without static-stack and without stack-passed args/allocas,
   `Z80FrameLowering::hasFPImpl` picks SP-relative addressing, not an IX
   frame.** Z80 has no `LD reg,(SP+d)` addressing mode — the address must
   be materialized into HL every time via `LD HL,n; ADD HL,SP` (or the
   1-instruction `LDHL SP,e` where legal), clobbering HL and costing several
   bytes per access, often per loop iteration. BSS-direct addressing
   (`LD (nn),r` / `LD r,(nn)`) needs no such materialization.
4. **16-bit locals have no single-instruction IX-relative store** (there is
   no `LD (IX+d),HL`); an IX-relative frame has to decompose every 16-bit
   local access into two 8-bit `LD (IX+d),L` / `LD (IX+d+1),H`-style ops,
   where BSS-direct gets a single 3-byte `LD (nn),HL`.

Net: static-stack's real payoff isn't "fewer registers used for a frame
pointer" (IX was never available for that anyway) — it's **cheaper
addressing** (no SP/IX materialization step, single-instruction 16-bit
stores) **plus** an extra allocatable register (IY) at `-Oz`, which the
non-static-stack path doesn't get either.

## Scope / what wasn't tested

- BIOS (rcbios-in-c) was **not** re-measured — it has more size headroom
  (not hard-capped at 2 KB like autoload/cpnos) so a regression there might
  not break a build the way it did here. Given both harder-capped targets
  regressed heavily and the architectural reasons above are target-agnostic,
  a similar regression on BIOS is expected but unverified. Revisit if BIOS
  size ever becomes a binding constraint.
- This investigation used the blanket `-target-feature -static-stack`
  override; `Z80AutoStaticStack.cpp`'s per-function auto-enable (leaf /
  non-recursive-SCC detection) was not separately exercised — the
  Makefiles force `+static-stack` unconditionally, so the auto-enable pass
  is currently moot for these targets regardless of this investigation's
  outcome.

## Verdict

**Keep `+static-stack` in autoload-in-c and cpnos-in-c.** The flag is not a
legacy artifact from before register-allocator work landed — it remains
load-bearing today, confirmed by two clean build failures under the
alternative. No follow-up action needed; this closes the "does static-stack
still make sense" question raised 2026-07-04.
