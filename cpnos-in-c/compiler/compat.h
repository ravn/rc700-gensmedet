/* compiler/compat.h — keyword-compatibility shim for cpnos-rom
 * across clang Z80, SDCC (z88dk-zsdcc), and HiTech zc.
 *
 * Goal: every cpnos-rom .c source uses one canonical vocabulary
 * (`__naked`, `__sdcccall`, `ASM_VOLATILE(...)`, `STATIC_ASSERT(...)`
 * and the `intrinsic_*` helpers) and this header maps that vocabulary
 * to whatever the active compiler accepts.
 *
 * Per the clarity-in-c-code rule the .c sources contain NO direct
 * `#ifdef __SDCC` branches — all compiler dispatch lives here.
 *
 * Header is found via -Icompiler on the compile line.  Renamed from
 * `intrinsic.h` to `compat.h` 2026-05-05 to avoid the `<intrinsic.h>`
 * name clash with z88dk's system header (which we explicitly want to
 * pull in for SDCC builds).
 */
#ifndef CPNOS_COMPAT_H
#define CPNOS_COMPAT_H

#include <stdint.h>

/* ================================================================
 * STR(x): preprocessor stringify.  STR(0xCAFE) -> "0xCAFE".
 *
 * Two-stage indirection lets STR see the *expanded* token, not the
 * literal name (`STR(MACRO)` -> "value", not "MACRO").  Used inside
 * ASM_VOLATILE strings to splice numeric constants — both compilers
 * accept a literal address in `jp 0xCAFE` style, but neither parses
 * the clang `%0` operand-substitution syntax.
 * ================================================================ */
#define _CPNOS_STR(x) #x
#define CPNOS_STR(x) _CPNOS_STR(x)

/* ================================================================
 * Inline-asm volatile portability shim.
 *
 * Clang requires `__asm__ volatile(...)` so outputless inline asm
 * survives DCE after inlining.  SDCC's gcc-compat parser does NOT
 * accept the `volatile` keyword (errors `syntax error: token ->
 * 'volatile'`); SDCC inline asm is implicitly volatile and never
 * DCE'd, so the keyword is unnecessary there.
 *
 * Inside ASM_VOLATILE("...") strings, the asm syntax must be
 * acceptable to BOTH GAS-Z80 (clang) and z80asm (SDCC).  Notable
 * differences to avoid:
 *   - Local labels: GAS uses `8:` + `jr nz, 8f`; SDCC uses `8$:`
 *     + `jr nz, 8$`.  Use unique global labels instead.
 *   - Hex: `0xFF` works in both; `$FF` and `0FFh` don't.
 * ================================================================ */
#ifdef __clang__
#define ASM_VOLATILE(...) __asm__ volatile(__VA_ARGS__)
#elif defined(__SDCC) || defined(__SCCZ80)
#define ASM_VOLATILE(...) __asm__(__VA_ARGS__)
#else
/* Host (CLion LSP / non-z80 clang): swallow the asm — IDE doesn't
 * understand Z80 mnemonics anyway, this prevents red-squiggle noise. */
#define ASM_VOLATILE(...) ((void)0)
#endif

/* ================================================================
 * SDCC keyword stubs for clang
 *
 * cpnos-rom .c sources can use SDCC keywords (`__naked`,
 * `__sdcccall(1)`, etc.); these become no-ops or near-equivalents
 * under clang.  For the keywords that have a real clang attribute
 * counterpart (`naked`, `interrupt`), expand to the attribute.
 * ================================================================ */
#if defined(__clang__) && defined(__z80__)
/* Clang Z80: native `__attribute__((naked))` exists and works.
 * Use a token-paste so `void f(void) __naked { ... }` compiles. */
#define __naked        __attribute__((naked))
#define __critical
#define __interrupt(n) __attribute__((interrupt))
#define __sdcccall(x)
#define __preserves_regs(...)
/* ravn/llvm-z80#131: a clang attribute exists that lets the caller's
 * regalloc keep values alive in the listed regs across the call.
 * Argument syntax differs from SDCC: clang takes STRING literals
 * (`"d","e"`), SDCC takes BARE identifiers (`d, e`).  Use the
 * PRESERVES_REGS_CLANG(...) helper alongside __preserves_regs(...)
 * at every declaration so both compilers see what they understand. */
#define PRESERVES_REGS_CLANG(...) __attribute__((z80_preserves_regs(__VA_ARGS__)))

#elif defined(__SDCC) || defined(__SCCZ80)
/* SDCC: __naked, __critical, __interrupt etc. are real keywords —
 * leave them as-is.  Define __sdcccall(0/1) only if the SDCC version
 * is too old to know it (unlikely on z88dk-zsdcc 4.x).  We rely on
 * the toolchain's --sdcccall=1 flag rather than per-function decls. */
/* PRESERVES_REGS_CLANG is a no-op for SDCC — it uses __preserves_regs. */
#define PRESERVES_REGS_CLANG(...)

#elif defined(__HITECH__) || defined(HI_TECH_C)
/* HiTech C: TODO — verify naked/interrupt syntax on real zc.
 * Probably wants `interrupt void f(void)` (no `__`).  Fail loud. */
#error "compiler/intrinsic.h: HiTech C keywords not yet mapped"

#else
/* Host clang on macOS (no __z80__): swallow the SDCC keywords so
 * the IDE parses the sources cleanly. */
#define __naked
#define __critical
#define __interrupt(n)
#define __sdcccall(x)
#define __preserves_regs(...)
#define PRESERVES_REGS_CLANG(...)
#endif

/* ================================================================
 * CPNOS_COMPILER_NAME — short compiler identifier used in the boot
 * banner so an operator (or a serial-log scrape) can tell at a glance
 * which compiler produced the running image.  Selected at preprocess
 * time from the compiler-specific predefined macros so a forgotten
 * Makefile -D flag can never cause a wrong tag.
 * ================================================================ */
#if defined(__clang__) && defined(__z80__)
#define CPNOS_COMPILER_NAME "clang"
#elif defined(__SDCC) || defined(__SCCZ80)
#define CPNOS_COMPILER_NAME "sdcc"
#elif defined(__HITECH__) || defined(HI_TECH_C)
#define CPNOS_COMPILER_NAME "hitech"
#else
#define CPNOS_COMPILER_NAME "host"
#endif

/* ================================================================
 * USED — keep the symbol even if no other TU references it.
 *
 * Clang/GCC: `__attribute__((used))` survives `--gc-sections`.
 * SDCC: no equivalent; the linker keeps anything in a custom
 * `--codeseg`/`--constseg` named section, which is how the SDCC
 * build path emits these symbols.  Macro expands to nothing for
 * SDCC and host.
 * ================================================================ */
#if defined(__clang__) || defined(__GNUC__)
#  define USED __attribute__((used))
#else
#  define USED
#endif

/* NOINLINE — clang/GCC have an inlining heuristic that can duplicate
 * a function body across multiple call sites under -Oz; this annotation
 * forces a single shared copy.  SDCC's inliner is much more conservative
 * and rarely duplicates, so the macro is a no-op there.  */
#if defined(__clang__) || defined(__GNUC__)
#  define NOINLINE __attribute__((noinline))
#else
#  define NOINLINE
#endif

/* ================================================================
 * NORETURN — function-attribute portable across clang / SDCC / host.
 *
 * C23 has `[[noreturn]]` on the declarator side (used in some cpnos
 * sources), but on extern declarations the older `__attribute__`
 * form is more portable across SDCC versions.  Use this macro to
 * keep the spelling identical across compilers.
 * ================================================================ */
#if defined(__clang__) || defined(__GNUC__)
#  define NORETURN __attribute__((noreturn))
#elif defined(__SDCC) || defined(__SCCZ80)
/* SDCC's `_Noreturn` is C11 and works on declarations; the GCC-style
 * `__attribute__((noreturn))` errors with "token -> '__attribute__'". */
#  define NORETURN _Noreturn
#else
#  define NORETURN
#endif

/* ================================================================
 * STATIC_ASSERT — works under both C11+ static_assert and SDCC's
 * _Static_assert.  cpnos-rom already uses C23 `static_assert`; SDCC
 * 4.x supports `_Static_assert`.  Macro lets us paper over older
 * variants if needed.
 * ================================================================ */
#ifndef STATIC_ASSERT
#  if defined(__cplusplus)
#    define STATIC_ASSERT(c, m) static_assert((c), m)
#  elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
#    define STATIC_ASSERT(c, m) static_assert((c), m)
#  elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#    define STATIC_ASSERT(c, m) _Static_assert((c), m)
#  else
#    define STATIC_ASSERT(c, m) /* pre-C11: silently drop */
#  endif
#endif

/* ================================================================
 * Section attribute portability
 *
 * Clang accepts `__attribute__((section(".init.text"))) void f(...)`.
 * SDCC instead wants `--codeseg INIT_TEXT` / `--constseg INIT_DATA`
 * passed per-file at compile time, and ignores `__attribute__((section))`
 * entirely.
 *
 * The cleanest pattern is: each .c file uses
 *     SECTION_INIT_TEXT void foo(...)
 * and the macro expands to `__attribute__((section(".init.text")))`
 * under clang and to nothing under SDCC (SDCC handles it via the
 * compile-line --codeseg flag, set by the cpnos-rom Makefile).
 *
 * The rcbios-in-c sdcc/Makefile already proves this pattern works:
 * each .c file is compiled with its own `-Cs"--codeseg X"` line.
 * ================================================================ */
#if defined(__clang__) && defined(__z80__)
#define SECTION_INIT_TEXT       __attribute__((section(".init.text")))
#define SECTION_INIT_RODATA     __attribute__((section(".init.rodata")))
#define SECTION_RESIDENT_DATA   __attribute__((section(".resident.data"), used))
#define SECTION_RESIDENT_ISR    __attribute__((section(".resident.isr"), used))
#define SECTION_RESIDENT_PRE    __attribute__((section(".resident_pre"), used))
#define SECTION_RESIDENT        __attribute__((section(".resident"), used))
#define SECTION_PROM0_INIT      __attribute__((section(".prom0_init"), used))
#define SECTION_PROM0_TAIL      __attribute__((section(".prom0_tail"), used))
#define SECTION_PROM1           __attribute__((section(".prom1"), used))
#define SECTION_PAYLOAD_CKSUM   __attribute__((section(".payload_checksum"), used))
#define SECTION_BSS_CFGTBL      __attribute__((section(".bss.cfgtbl"), used))
#define SECTION_PIO_RX_BSS      __attribute__((section(".pio_rx_bss")))
#else
/* SDCC / host: section assignment via compile-line --codeseg/--constseg. */
#define SECTION_INIT_TEXT
#define SECTION_INIT_RODATA
#define SECTION_RESIDENT_DATA
#define SECTION_RESIDENT_ISR
#define SECTION_RESIDENT_PRE
#define SECTION_RESIDENT
#define SECTION_PROM0_INIT
#define SECTION_PROM0_TAIL
#define SECTION_PROM1
#define SECTION_PAYLOAD_CKSUM
#define SECTION_BSS_CFGTBL
#define SECTION_PIO_RX_BSS
#endif

/* ================================================================
 * __builtin_unreachable / __builtin_offsetof / __builtin_memcpy etc.
 *
 * SDCC documents `__builtin_memcpy` / `__builtin_memset` in 4.x but
 * the z88dk-zsdcc 4.5.0 path lowers them to library calls `_memcpy`
 * / `_memset` without auto-declaring — assemble-time error.  Map the
 * builtins to <string.h> functions for SDCC; they link against
 * libsdcc_iy at the final link.  __builtin_unreachable is GCC/clang-
 * only — wrap it for SDCC as a `while (1) {}` busy-loop.
 * ================================================================ */
#if !defined(__clang__) && !defined(__GNUC__)
#  include <string.h>
#  define __builtin_memcpy(d, s, n)   memcpy((d), (s), (n))
#  define __builtin_memset(d, c, n)   memset((d), (c), (n))
#  define __builtin_memmove(d, s, n)  memmove((d), (s), (n))
#  ifndef __builtin_unreachable
#    define __builtin_unreachable() do { /* unreachable */ } while (1)
#  endif
#endif

/* ================================================================
 * mem_copy_backwards — direction-known overlap-safe block move.
 *
 * For callers that statically know dst > src (e.g. shifting display
 * rows down).  Skips the runtime direction check + add-bc/dec-hl
 * preamble inside the general memmove path.  Args are END-pointers
 * (last byte of region) per LDDR semantics:
 *
 *     mem_copy_backwards(dst + n - 1, src + n - 1, n)
 *
 * Equivalent to memmove(dst, src, n) when caller knows dst > src.
 *
 * Clang lowers to inline LDDR (~6 B at the call site, no call).
 * SDCC calls _mem_copy_backwards_callee in sdcc/runtime.asm (~12 B
 * helper + push push push call site).  Both bypass the 33 B
 * _memmove_callee dispatch.  Tracked as ravn/rc700-gensmedet#77.
 * ================================================================ */
#include <stddef.h>
#if defined(__clang__) && defined(__z80__)
static inline void mem_copy_backwards(void *dst_end, const void *src_end,
                                      size_t n) {
    __asm__ volatile("lddr"
        : "+{de}"(dst_end), "+{hl}"(src_end), "+{bc}"(n)
        :
        : "memory");
}
#elif defined(__SDCC) || defined(__SCCZ80)
extern void mem_copy_backwards_callee(void *dst_end, const void *src_end,
                                      size_t n) __z88dk_callee;
#define mem_copy_backwards(d, s, n)  mem_copy_backwards_callee((d), (s), (n))
#else
/* Host stub for IDE LSP — portable equivalent (slower but correct). */
static inline void mem_copy_backwards(void *dst_end, const void *src_end,
                                      size_t n) {
    unsigned char       *d = (unsigned char *)dst_end;
    const unsigned char *s = (const unsigned char *)src_end;
    while (n--) *d-- = *s--;
}
#endif

/* ================================================================
 * Z80 intrinsics — di / ei / halt / nop / im_2 / ld i,a
 *
 * Using one consistent vocabulary across the two compilers:
 *   intrinsic_di()    intrinsic_ei()    intrinsic_halt()
 *   intrinsic_nop()   intrinsic_im_2()  intrinsic_ld_i_a(page)
 *
 * SDCC: z88dk's <intrinsic.h> already defines `intrinsic_di()` etc.
 * as zero-cost macros / static inline wrappers — one Z80 instruction
 * each.  Importing the header gives us the optimized definitions for
 * free; we just wrap the few that don't have a z88dk equivalent
 * (`intrinsic_im_2`, `intrinsic_ld_i_a` need synthesis).
 *
 * clang Z80: roll our own static inline + inline asm.  ASM_VOLATILE
 * keeps the body alive past DCE.
 *
 * Host clang (no Z80): no-ops so the IDE LSP doesn't complain and the
 * file parses.  Code that depends on these intrinsics for correctness
 * obviously won't *run* on the host.
 *
 * The naked-function form (an entire function whose body is just
 * `__asm__ volatile("di"); ret`) was an early pattern in cpnos-rom but
 * is unnecessary — a normal C function with `intrinsic_di()` in its
 * body emits the same one-instruction code under both backends after
 * inlining.  Use the intrinsics in plain C; reserve `__naked` for
 * ISRs and ABI shims that need custom prologues/epilogues.
 * ================================================================ */
#if defined(__SDCC) || defined(__SCCZ80)
#  include <intrinsic.h>       /* z88dk: intrinsic_di / _ei / _halt / _nop */
#  ifndef intrinsic_im_2
#    define intrinsic_im_2()   __asm__("im 2")
#  endif
#  ifndef intrinsic_ld_i_a
/* SDCC: A holds the byte under sdcccall(1); ASM_VOLATILE preserves
 * the instruction even though the C-level compiler has no constraint
 * machinery for register-bound args.  Caller must already have the
 * value in A — true because this is invoked as `intrinsic_ld_i_a(p)`
 * with p as the only arg under sdcccall(1). */
#    define intrinsic_ld_i_a(p) do { (void)(p); __asm__("ld i, a"); } while (0)
#  endif

#elif defined(__clang__) && defined(__z80__)
static inline void intrinsic_di  (void) { ASM_VOLATILE("di"); }
static inline void intrinsic_ei  (void) { ASM_VOLATILE("ei"); }
static inline void intrinsic_halt(void) { ASM_VOLATILE("halt"); }
static inline void intrinsic_nop (void) { ASM_VOLATILE("nop"); }
static inline void intrinsic_im_2(void) { ASM_VOLATILE("im 2"); }
/* clang Z80: pass the page in A using the address_space-style hack
 * isn't available; use a constraint so the value is in A on entry. */
static inline void intrinsic_ld_i_a(uint8_t page) {
    ASM_VOLATILE("ld i, a" :: "{a}"(page));
}

#else
/* Host (no z80 target): make the intrinsics swallow their args and
 * compile to nothing.  Lets the IDE LSP parse cpnos-rom sources
 * without target-specific diagnostics. */
static inline void intrinsic_di  (void) {}
static inline void intrinsic_ei  (void) {}
static inline void intrinsic_halt(void) {}
static inline void intrinsic_nop (void) {}
static inline void intrinsic_im_2(void) {}
static inline void intrinsic_ld_i_a(uint8_t page) { (void)page; }
#endif

#endif /* CPNOS_COMPAT_H */
