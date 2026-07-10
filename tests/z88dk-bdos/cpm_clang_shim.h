/*
 * cpm_clang_shim.h -- interim clang/llvm-z80 ABI shim for z88dk#20.
 *
 * Under clang, z88dk strips __smallc/__z88dk_callee to nothing, so clang passes
 * the fixed args of bdos_callee()/bdosh_callee() in registers (func->HL,
 * arg->DE) while the prebuilt classic cpm_clib expects them on the stack.
 * Result: garbage BDOS function numbers and a warm-boot reboot.
 *
 * This header (included AFTER <cpm.h>) redirects the bdos()/bdosh() macros --
 * and therefore getuid()/setuid(), which expand to bdos() -- to register-ABI
 * entry points implemented in cpm_bdos_clang.asm.  z88dk is left untouched;
 * link cpm_bdos_clang.asm into the program to supply _bdos_clang/_bdosh_clang.
 *
 * The mergeable z88dk version of this fix moves the redirect into include/cpm.h
 * (guarded by the clang macro) and ships the asm inside cpm_clib.
 */
#ifndef CPM_CLANG_SHIM_H
#define CPM_CLANG_SHIM_H

#if defined(__clang__) || defined(__STDC_ABI_ONLY)

#include <cpm.h>

extern int bdos_clang(int func, int arg);   /* clang ABI: func->HL, arg->DE */
extern int bdosh_clang(int func, int arg);

#undef bdos
#undef bdosh
#define bdos(a, b)   bdos_clang((a), (b))
#define bdosh(a, b)  bdosh_clang((a), (b))

/* getuid()/setuid() in cpm.h expand to bdos(), so they follow automatically. */

/* Hand-asm stdio (fputc/fgetc/fclose) is stack-ABI too (z88dk#22) -- redirect
 * to the register-ABI bridges in cpm_stdio_clang.asm.  fopen is pure C-source
 * (recompiled to clang ABI via __ZPROTO), so it is left alone; fclose looks
 * like C but its body is #asm that pops the arg off the stack, so it needs a
 * bridge too. */
#include <stdio.h>
extern int fputc_clang(int c, FILE *fp);    /* clang ABI: c->HL, fp->DE */
extern int fgetc_clang(FILE *fp);           /* clang ABI: fp->HL       */
extern int fclose_clang(FILE *fp);          /* clang ABI: fp->HL       */

#undef fputc
#undef putc
#undef fgetc
#undef getc
#undef fclose
#define fputc(a, b)  fputc_clang((a), (b))
#define putc(a, b)   fputc_clang((a), (b))
#define fgetc(f)     fgetc_clang((f))
#define getc(f)      fgetc_clang((f))
#define fclose(f)    fclose_clang((f))

#endif /* clang */

#endif /* CPM_CLANG_SHIM_H */
