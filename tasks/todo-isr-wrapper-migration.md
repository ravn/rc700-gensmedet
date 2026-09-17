# TODO: migrate cpnos-in-c + rcbios-in-c to ISR wrapper pattern

**Filed:** 2026-09-17. **Status:** not started.

## What

Migrate all `__interrupt(N)` handlers in `cpnos-in-c/` and `rcbios-in-c/` to
the split wrapper/body pattern already applied to `autoload-in-c/rom.c` in
this session:

```c
ISR_BODY_INLINE void my_isr_body(void) {
    /* ... actual work ... */
}
void my_isr(void) __interrupt(N) {
    my_isr_body();
    ei();
}
```

`ISR_BODY_INLINE` is defined per-compiler in `rom.h`:
- clang: `static __attribute__((always_inline)) inline`
- SDCC/host: `static inline`

Each firmware needs its own definition (add to that firmware's local header
that already carries the `__interrupt` / `__critical` compat macros).

## Why

**Upstream design intent.** `llvm-z80/llvm-z80` PR #40 discussion:
`__attribute__((interrupt))` emits only RETI + register save/restore. EI is
programmer's responsibility. Keeping the wrapper minimal — one call plus
`ei()` — makes that policy visible at the source level and prevents future
scope-creep (someone adds "just one more thing" to the ISR body).

The split is **byte-neutral** on clang when the body is `always_inline`
(verified 2026-09-17 for autoload: 2113 B before and after refactor).
On SDCC the body is `static inline`; sccz80 will still inline trivial
bodies. In either case the emitted code is the same as a direct-body ISR.

Related memory: `tasks/memory/reference_z80_interrupt_attr_bare_reti.md`.
Related closed issue: `ravn/llvm-z80#317`.

## Where

- `cpnos-in-c/`: search for `__interrupt(` and refactor each handler.
- `rcbios-in-c/`: same.

Approach per file:
1. Move the ISR body to a `ISR_BODY_INLINE`-marked function named
   `<original>_body` (or `<name>_body` if the original is verbose).
2. Reduce the `__interrupt(N)` wrapper to just `body(); ei();`.
3. Verify byte-neutrality: compare `.text` size before/after with clang
   (should be within ±2 B).
4. Verify SDCC still compiles.

## Verification

After each firmware's migration:
- `make prom` / equivalent — both compilers cleanly build.
- MAME boot-gate for that component (autoload was verified via the CRT ISR
  firing at 50 Hz + display rendering; cpnos + rcbios have their own gates
  documented in each component's `tasks/`).
- No new lit-suite regressions (`build-macos/bin/llvm-lit
  llvm/test/CodeGen/Z80/`).

## Do NOT

- Add `__critical` — it is a fork-local carryover and rejected upstream. See
  the closed llvm-z80/llvm-z80 PR #40 discussion.
- Try to make the wrapper emit `EI; RETI` adjacent via compiler-side magic —
  that path was analysed in ravn/llvm-z80#317 (closed 2026-09-17) and is not
  wanted. The `ei()` between body and register-restore pops is stack-coherent
  and semantically correct; the only concern (peripheral daisy-chain
  in-service ordering) is not exercised by our production firmware.
- Force non-inlined bodies (real call) — that adds ~5 pushes/pops of the
  full ISR CSR set (AF/BC/DE/HL/IY) via the CALL RegMask, roughly +10 B and
  overhead per ISR. Only warranted if a body is legitimately shared between
  handlers.
