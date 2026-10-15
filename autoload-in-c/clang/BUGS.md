# LLVM-Z80 Backend Bugs Found

## Bug 1: address_space(2) crashes Legalizer

**Symptom**: `fatal error: unable to legalize instruction: G_LOAD ... addrspace 2`

**Trigger**: Using `__attribute__((address_space(2)))` pointer dereference for port I/O:
```c
#define __io __attribute__((address_space(2)))
return *(volatile __io byte *)(byte)(addr);  // crashes
```

**Workaround**: Use inline assembly for port I/O:
```c
#define port_in(port) \
    ({ byte _v; __asm__ volatile("in a, (" _XSTR(port) ")" : "=a"(_v)); _v; })
```

**Pass**: Legalizer (GlobalISel)

---

## Bug 2: "hl" inline asm constraint crashes IRTranslator

**Symptom**: `fatal error: unable to translate instruction: call (in function: z80_set_sp)`

**Trigger**: Using `"hl"` as an inline assembly input constraint:
```c
static inline void z80_set_sp(word addr) {
    __asm__ volatile("ld sp, hl" : : "hl"(addr));  // crashes
}
```

**Workaround**: Use a macro with stringified immediate:
```c
#define z80_set_sp(addr) __asm__ volatile("ld sp, " #addr)
```

**Pass**: IRTranslator (GlobalISel)

---

## Bug 3: areInlineCompatible() rejects always_inline on functions with > 10 instructions

**Symptom**: `remark: 'f' not inlined into 'g' because it should never be inlined (cost=never): conflicting target features [-Rpass-missed=inline]`

**Trigger**: Upstream LLVM commit `7bdca287` (July 6, 2026) moved `areInlineCompatible()` checks ahead of `always_inline` handling. In `llvm/lib/Target/Z80/Z80TargetTransformInfo.h`, `areInlineCompatible()` checks `InlineHint` and `instruction_count <= 10`, but lacks a check for `Attribute::AlwaysInline`:
```cpp
bool areInlineCompatible(const Function *Caller,
                         const Function *Callee) const override {
  if (Callee->hasFnAttribute(Attribute::InlineHint))
    return true;
  if (Callee->getInstructionCount() <= 10)
    return true;
  return false;
}
```
Any C function with > 10 instructions annotated with `__attribute__((always_inline))` gets `alwaysinline` attribute (not `inlinehint`), returning false from `areInlineCompatible()`. The inliner rejects it claiming "conflicting target features".

**Tracking**: ravn/llvm-z80#414
**Workaround**: Use macros (`#define func() do { ... } while (0)`) to force lexical inlining without relying on the function inliner.
**Fix**: In `Z80TargetTransformInfo.h`, add:
```cpp
if (Callee->hasFnAttribute(Attribute::AlwaysInline))
  return true;
```

---

## Bug 4: G_MEMSET lacks inline lowering in Legalizer

**Symptom**: `memset()` calls under Clang pull in `___z80_memset_builtin` from `compiler-rt`, adding library stubs to bare-metal / ROM builds.

**Trigger**: In `llvm/lib/Target/Z80/Z80LegalizerInfo.cpp:1801`, `G_MEMSET` only promotes the value operand to i16 and calls `Helper.createMemLibcall(MRI, MI, LocObserver)`, unlike `G_MEMCPY` which lowers directly to `Z80::LDIR`. Additionally, under `-ffreestanding`, Clang emits external library calls (`call _memset`, `call _memcpy`) rather than `@llvm.memset` / `@llvm.memcpy`.

**Workaround**: In C source, call `__builtin_memcpy` (which forces `@llvm.memcpy` and lowers to `LDIR`), and synthesize `memset` via 1-byte store + self-overlapping `__builtin_memcpy(_dst + 1, _dst, n - 1)`:
```c
#if defined(__clang__)
#undef memcpy
#define memcpy(d, s, n) __builtin_memcpy((d), (s), (n))
#undef memset
#define memset(d, c, n) do { \
    size_t _n = (size_t)(n); \
    if (_n != 0) { \
        byte *_dst = (byte *)(d); \
        *_dst = (byte)(c); \
        if (_n > 1) \
            __builtin_memcpy(_dst + 1, _dst, _n - 1); \
    } \
} while (0)
#endif
```

---

## Bug 5: Static frame lacks cost model on Z80 (unlike SM83), inflating call spills

**Symptom**: Functions compiled with `+static-frame` experience code size inflation when registers are spilled across `call` instructions (e.g. `_fdc_read_result` grew from 39 B to 51 B, +12 B).

**Trigger**: In `Z80FrameLowering.cpp:148`, commit `b28c4ab0518a` enabled a size cost model for SM83 (`KeepWideOnStack`) which leaves 16-bit slots on the stack if access overhead exceeds prologue savings. However, `KeepWideOnStack` was hardcoded to `false` for Z80 under the assumption that Z80 has 16-bit direct absolute addressing (`ld bc, (nn)`).
This overlooked that `ld bc, (nn)` is 4 bytes. Spilling `BC` and `D` across a call costs 16 bytes of static BSS stores and reloads per iteration vs 2 bytes for `push de; pop de` on the stack.

**Tracking**: ravn/llvm-z80#415
**Workaround**: In C, avoid function calls inside tight loops (e.g. inline callees via macros or `ALWAYS_INLINE`).

---

## Non-bug: Known Backend Weakness

**Bit test generates clunky code**: `status & 0x80` produces:
```asm
xor  128
ld   c,a
ld   a,255
xor  128
cp   c
jr   c,...
```
Instead of optimal: `bit 7,a; jr z,...` (2 bytes vs 8 bytes)
