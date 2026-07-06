/* Minimal repro: zsdcc --sdcccall 1 + z88dk default stdlib -> signed modulo
 * runtime helper (__modsint) return-register mismatch.
 *
 * Root cause of the fannkuch + pi corpus XFAILs (confirmed 2026-07-06).
 * The caller reads the __modsint remainder from E; with the default-
 * convention stdlib linked under --sdcccall 1 that register is 0, so
 * `p % dv` yields 0 for every p.  z88dk warns about the mismatch
 * (warning 296), which sweep.sh suppresses via --disable-warning 296.
 *
 * Expected (x86 gcc, and zsdcc --sdcccall 0): 01010101
 * Observed (zsdcc --sdcccall 1, sweep flags):  00000000
 *
 * Build (matches sweep zsdcc lane):
 *   zcc +z80 -compiler=sdcc -clib=sdcc_iy --opt-code-size -SO3 \
 *       -Cs"--sdcccall 1" -Cs"--max-allocs-per-node 25000" \
 *       -Cs"--fomit-frame-pointer" -create-app -o r modsint_sdcccall1.c
 *   z88dk-ticks -mz80 -iochar 1 r.bin        # prints 00000000 (bug)
 *   # flip to -Cs"--sdcccall 0" -> prints 01010101 (correct)
 *
 * emit() writes emit_ch to port 1 (ticks -iochar 1); robust across ABIs
 * because it reads a global, not an argument register.
 */
volatile unsigned char emit_ch;
volatile int dv = 2;
static void emit(void){
  __asm
    ld a,(_emit_ch)
    out (#1),a
  __endasm;
}
static void done(void){ __asm xor a,a
    .db #0xED,#0xFE
  __endasm; }
int main(void){
  int p;
  for (p = 0; p < 8; p++){ int m = p % dv; emit_ch = '0' + (m & 0xf); emit(); }
  emit_ch = '\n'; emit(); done(); return 0;
}
