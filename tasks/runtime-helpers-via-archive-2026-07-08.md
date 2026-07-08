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

| Build   | Before | After archive | Delta |
|---------|--------|---------------|-------|
| cpnos   | 2013 B | 2013 B        | 0 B   |
| rcbios  | 5906 B | 5951 B        | +45 B |

## Why +45 B on rcbios — the follow-up

The z80_rt.a helpers are NOT size-tuned.  They read stack args via an IX frame
(`push ix; ld ix,#0; add ix,sp; ld c,4(ix)`) and do explicit callee cleanup
(`inc sp; inc sp; push bc; ret`).  The hand-rolled runtime.s versions used the
tighter `pop iy` / `jp (iy)` idiom.  Both implement the same sdcccall(1) ABI;
the difference is pure tuning.

Per-symbol (rcbios):
- `_memcpy`  archive 31 B vs hand ~12 B
- `_memset`  archive 40 B vs hand ~15 B
- `___umodqi3` archive 15 B (restoring division) vs hand 9 B (subtraction loop)
- `__call_iy` 2 B (same)

**Follow-up (not yet done):** rewrite the 5-6 z80_rt.a helpers in
`llvm-z80/compiler-rt/lib/builtins/z80/` to the `pop iy` idiom and rebuild the
archive.  Then the archive is strictly better than any hand-rolled copy —
correctness + minimal size + zero duplication — and `lddr_copy` could even be
added to compiler-rt to delete rcbios's runtime.s entirely.  Requires the
llvm-z80 fork's runtime test suite to stay green (z80-utils/test-runner).

## Decision (user, 2026-07-08)

- **rcbios**: keep the archive link (+45 B accepted; rcbios has headroom).
  `memcpy/memset/__call_iy/___umodqi3` come from z80_rt.a; `lddr_copy` stays
  in runtime.s.  Verified: polypascal-pio-test PASS 14.05 s.
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
