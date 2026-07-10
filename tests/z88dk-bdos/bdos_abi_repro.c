/*
 * bdos_abi_repro.c -- minimal repro: llvm-z88dk (zcc +cpm -compiler=llvmz80)
 * miscompiles EVERY bdos() call: the wrong BDOS function number is issued.
 *
 * Build:
 *   zcc +cpm -compiler=llvmz80 --opt-code-size bdos_abi_repro.c -o repro -create-app
 *
 * Expected: bdos(12,0) asks CP/M for its version (BDOS function 12) and
 * returns e.g. 0x22 for CP/M 2.2.
 *
 * Actual: at runtime the program issues a BDOS call with a GARBAGE function
 * number (observed on a real BDOS trace: C=25, C=252, C=196, and eventually
 * C=0).  C=0 is BDOS "system reset" = warm boot, so the program reboots.
 *
 * Root cause: for the clang toolchain, include/sys/compiler.h strips the
 * __smallc / __z88dk_callee attributes to nothing and selects clang's
 * register calling convention, so zcc emits the call as
 *     ld hl,12   ; func -> HL
 *     ld de,0    ; arg  -> DE
 *     call _bdos_callee   ; NOTHING pushed on the stack
 * but the implementation in libsrc/target/cpm/fcntl/bdos.c reads its
 * parameters OFF THE STACK (smallc convention):
 *     ld hl,2 ; add hl,sp ; ld e,(hl) ; inc hl ; ld d,(hl) ; inc hl ; ld c,(hl)
 * so C (the BDOS function) is loaded from stack garbage instead of from HL.
 *
 * A correct clang-ABI implementation would take func in HL, arg in DE:
 *     ld c,l ; push ix ; push iy ; call 5 ; pop iy ; pop ix ; ld l,a ; ld h,0
 */
#include <cpm.h>

int main(void)
{
    return bdos(12, 0) & 0xFF;   /* should be the CP/M version, e.g. 0x22 */
}
