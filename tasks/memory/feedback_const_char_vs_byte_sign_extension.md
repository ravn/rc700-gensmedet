---
name: feedback_const_char_vs_byte_sign_extension
description: const char* vs const byte* in comparison functions causes sign-extension in Z80 codegen — use const byte* for ALL byte-comparison parameters
metadata:
  type: feedback
---

When a function takes `const char *` (signed) and compares it byte-by-byte with
`const byte *` (unsigned), the C standard requires integer promotion. On Z80 with
clang, this causes sign-extension to 16-bit int before comparison — producing
BSS-spilling code instead of a simple byte loop.

**Example fixed in this project (`check_sysfile`, 2026-10-09):**
- Before: `const char *pattern` → 87 B (sign-extension overhead)
- After: `const byte *pattern` → ~43 B (direct byte comparison)
- Savings: 43 B PROM

**Rule:** For byte-comparison loops in Z80 firmware, ALL pointer parameters must be
`const byte *`. Even ASCII-only `const char *` causes the compiler to generate
sign-extension overhead.

**Callers with string literals need an explicit cast:**
```c
check_sysfile(dir, (const byte *)"SYSM")
```

**Why:** `char` is signed by default in clang. Comparing `unsigned char` with `signed
char` triggers C integer promotion to `int` (16-bit on Z80), which generates wider
comparison code instead of the optimal `ld a,(de); cp (hl)` pattern.
