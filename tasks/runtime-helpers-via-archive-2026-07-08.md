# Runtime helpers: link z80_rt.a instead of hand-rolling (2026-07-08)

## The right way to provide freestanding runtime helpers

llvm-z80 builds its compiler-rt builtins into an archive:
`build-macos/lib/z80/z80_rt.a` (and `sm83_rt.a`).  It contains
`memcpy/memset/memchr/memmove/__call_iy/___umodqi3/__udivsi3/…` — each a
separate `.o` member.

The clang driver (`clang/lib/Driver/ToolChains/Z80.cpp:206`) auto-appends
`z80_rt.a` when linking through the driver, **unless** `-nostdlib` /
`-nodefaultlibs` is set.  The RC702 PROM builds bypass this two ways:
(1) they compile with `-nostdlib`, and (2) they invoke `ld.lld` directly with
a custom linker script + computed `--defsym`, so the driver's append never
runs.  That is why each project hand-rolled a `runtime.s`.

**Correct pattern:** add the archive as the LAST input on the `ld.lld` line:

```make
$(LD) --gc-sections -T script.ld <objects...> $(CLANG_BUILD)/../lib/z80/z80_rt.a -o out.elf
```

Archive semantics pull in only the members that resolve an otherwise-undefined
symbol; `--gc-sections` drops unreferenced sections; `*(.text*)` in the linker
script already captures the pulled-in `.text`.  Unused helpers cost 0 B.  No
linker-script change needed.

Applied 2026-07-08:
- **cpnos-in-c**: runtime.s deleted (was 100% dead code); archive added to link
  line (0 B — references no helpers).
- **rcbios-in-c**: runtime.s reduced to `lddr_copy` only; archive linked.
  memcpy/memset/__call_iy/___umodqi3 now come from z80_rt.a.

## Measurement

Clean side-by-side (same toolchain, MSIZE=56), after the archive-helper
tightening below:

| Build   | Hand-rolled | Archive (tightened) | Delta |
|---------|-------------|---------------------|-------|
| cpnos   | 2014 B      | 2011 B              | −3 B  |
| rcbios  | 5908 B      | 5918 B              | +10 B |

The initial archive link (with the *un-tightened* helpers) cost rcbios +45 B;
the tightening below recovered 35 of those.

## Follow-up DONE (2026-07-08): tighten the archive helpers to pop-iy

The z80_rt.a `memcpy`/`memset`/`memchr` used to read the stack size arg via an
IX frame (`push ix; ld ix,#0; add ix,sp; ld c,4(ix)`) plus explicit callee
cleanup — needlessly conservative, since **IY is caller-saved** (Z80CallingConv:
`Z80_CSR = CalleeSavedRegs<(add IX)>`).  Rewritten to the tight `pop iy` /
`jp (iy)` idiom (+ dropped `.globl` on internal labels so `jr` stays 2 bytes):

| helper | archive before | archive after | hand-rolled |
|--------|----------------|---------------|-------------|
| memcpy | 31 B | 14 B | 13 B (buggy return dest+n) |
| memset | 39 B | 23 B | 24 B |
| memchr | ~41 B | ~26 B | (not used by rcbios) |

The archive `memcpy` returns the **correct** original dest (the hand-rolled one
returned `dest+n` — a latent bug, unused).  Committed to llvm-z80 main
(`[Z80] runtime: tighten memcpy/memset/memchr to the pop-iy idiom`) with a
runtime fixture (`test_runtime_mem_helpers.c`, 6/6 O0-Oz) + full clang suite
906 pass / 0 fail + lit 182+5.

**Residual rcbios +10 B is justified, not tuning debt:**
- `___umodqi3` +4 B — archive's O(1) shift-divide vs hand-rolled O(n) subtract
  loop; the faster one is deliberately kept (at `-Oz` the *caller* is compact:
  `ld e,l; jp ___umodqi3`).
- `_memcpy` +1 B — correct return value.
- ~+5 B archive/section/relocation packaging overhead.

So all hand-rolled memcpy/memset/memchr/__call_iy are deleted; rcbios keeps only
`lddr_copy` (no compiler-rt equivalent — a project-specific end-pointer backward
copy).

## Decision (user, 2026-07-08)

- **rcbios**: keep the archive link.  User goal: move all helpers into the
  compiler long-term.  After the pop-iy tightening the cost is **+10 B** (was
  +45), well within rcbios headroom (hard cap is `__bss_end ≤ 0xF600`, KB free).
  `memcpy/memset/__call_iy/___umodqi3` come from z80_rt.a; `lddr_copy` stays
  in runtime.s.  Verified: MAME mame-test boot → A>, 77-track sweep ERR=0.
- **lddr_copy → memmove was tried and REVERTED**: the archive's general
  `memmove` (~62 B) cost +97 B vs the 7 B specialized backward-LDDR
  `lddr_copy` (rcbios 5951 → 6048 B).  Kept `lddr_copy` — a legitimate
  Z80-specific specialization until the archive's memmove is retuned.
- **cpnos**: archive added to the link line (0 B — references no helpers);
  future-proofs against a later helper need resolving from the archive.

## Filed

Field note posted to ravn/llvm-z80 #35 (the runtime-library issue): the
archive-link recipe + the per-symbol size gap + the two suggestions
(document the recipe; retune the helpers to the pop-iy idiom).

## Compiler fix: memmove runtime-base fold (2026-07-08) — and why rc700 still keeps lddr_copy

Root-caused why `__builtin_memmove(base + K, base, n)` did NOT fold to inline
LDDR when `base` is a runtime value (`screen + cury`): the Z80 memmove
direction analysis (`Z80LegalizerInfo.cpp`) had a too-strict guard
(`SrcBase == Register()`) that spuriously failed when `src` was itself a
G_PTR_ADD.  Fixed in llvm-z80 (merged to main): drop the guard on case 1/2 so
`dst = SrcPtr + const` folds regardless of SrcPtr's internal structure.  Lit
182+5, runtime O1-Oz both directions.  It does NOT need to prove absolute
"A > B" (overflow-unsafe) — only the relative same-base + positive-constant
delta, which is explicit in the IR.

**But rc700 insert_line still keeps lddr_copy.**  Measured with the fix (and
now with the tightened archive, rcbios 5918 B baseline):
- archive + lddr_copy: 5918 B
- archive + __builtin_memmove (folds to inline LDDR): ~+49 B

Inline LDDR with a *runtime* count needs per-site end-pointer computation
(`add hl,bc; dec hl` for both src and dst).  lddr_copy centralizes this in a
shared 7 B helper whose callers pass pre-computed end pointers — strictly
smaller for rc700's 2-site screen-scroll.  The compiler fold wins for
single-site / compile-time-count cases and is the right general capability;
it just doesn't beat a hand-tuned shared primitive for this specific
multi-site runtime-count pattern.  **Decision: keep lddr_copy** (size-optimal
here); the compiler fix ships regardless.
