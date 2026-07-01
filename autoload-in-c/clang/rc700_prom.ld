/* RC700 autoload PROM linker script for LLVM-Z80 (ld.lld)
 *
 * ROM layout (physical PROM0 is 2 KB / 0x0000..0x07FF; no A11 bridge on the
 * hardware, so the 4 KB .ic66 file is a MAME-only padding artifact):
 *   0x0000  .boot -- start() (DI, SP, reloc_zx0, jump)          (~33 B)
 *   0x0021  .zx0_decoder -- ZX0 decoder main loop (pre-NMI)      (~57 B)
 *   0x0066  NMI handler (RETN)
 *   0x0068  .zx0_decoder_hi -- ZX0 decoder elias tail (post-NMI) (~15 B)
 *   0x0077  ZX0-compressed .text payload (~1524 B, incl. banner)
 *   0x066B  end of PROM image (~1643 B used, ~405 B free to the 2 KB cap)
 *
 * RAM layout (after ZX0 self-decompression by start()):
 *   0x6000  .text (IVT + C code + rodata + banner) by dzx0_standard (~1996 B)
 *   0x67CC  .bss (~53 B)
 *   0x7830  display framebuffer 80x25 = 2000 B (ends at 0x8000; DSPSTR_ADDR)
 *   0xBFFF  Stack (grows downward)
 *
 * The decoder is split around the 0x0066 NMI vector to fill the pre-NMI ROM;
 * the split is clean (dzx0s_new_offset ends in an unconditional jr, so the
 * elias tail is CALL-only).  ASSERT below fails the build on pre-NMI overrun.
 * See ../BOOT_SEQUENCE.md "Memory map" for the full annotated table.
 *
 * Two-pass build: pass 1 produces raw .text bytes; the Makefile
 * compresses them with z88dk-zx0 into clang/text_compressed.zx0; pass 2
 * incbins the result and re-links.  llvm-objcopy emits only the
 * ROM-resident sections to the .bin -- .text VMA in RAM is excluded.
 */

ENTRY(_start)

MEMORY {
  ROM (rx)  : ORIGIN = 0x0000, LENGTH = 4096
  RAM (rwx) : ORIGIN = 0x6000, LENGTH = 0x6000
}

SECTIONS {
  /* BOOT section -- runs from ROM at 0x0000.
   * start() at 0x0000 (DI is the first instruction). */
  .boot : {
    KEEP(*boot.o(.pagezero.text))
    KEEP(*boot.o(.pagezero.data))
  } > ROM

  /* ZX0 decoder, main-loop part -- placed immediately after start() so it
   * fills the pre-NMI ROM that used to hold the (now payload-resident) banner.
   * _reloc_zx0 is its entry.  The elias subroutine is in .zx0_decoder_hi after
   * the NMI vector; the split is clean because dzx0s_new_offset ends in an
   * unconditional jr (see dzx0_standard.s), so nothing falls through the gap. */
  .zx0_decoder : {
    KEEP(*dzx0_standard.o(.zx0_decoder))
  } > ROM
  ASSERT(. <= 0x0066,
    "ZX0 decoder main-loop (.zx0_decoder) overran the 0x0066 NMI vector")

  /* NMI handler at Z80 hardwired vector 0x0066. */
  .nmi 0x0066 : {
    KEEP(*boot.o(.nmi*))
  } > ROM

  /* ZX0 decoder tail (elias subroutine), after the NMI vector. */
  .zx0_decoder_hi 0x0068 : {
    KEEP(*dzx0_standard.o(.zx0_decoder_hi))
  } > ROM

  /* ZX0-compressed .text payload, immediately after the decoder tail.
   * __text_zx0_start is consumed by _reloc_zx0 (in dzx0_standard.s). */
  .text_compressed : {
    __text_zx0_start = .;
    KEEP(*text_compressed.o(.text_compressed*))
    __text_zx0_end = .;
  } > ROM

  /* .text VMA in RAM at 0x6000.  No AT() -- bytes live ZX0-compressed
   * in .text_compressed above; this section is excluded from the
   * .bin by llvm-objcopy --only-section in the Makefile. */
  .text 0x6000 : {
    __code_start = .;
    KEEP(*intvec.o(.rodata*))  /* IVT: function pointers to ISRs */
    KEEP(*intvec.o(.text*))    /* IVT code */
    *rom.o(.text*)             /* All C code (GC'd by reachability) */
    *rom.o(.rodata*)           /* Constants, strings */
    *runtime.o(.text*)         /* Runtime stubs */
    KEEP(*boot.o(.textbanner)) /* banner: moved out of BOOT into the payload */
    __code_end = .;
  } > RAM

  .data : {
    *(.data*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  __bss_size = __bss_end - __bss_start;
  __code_size = __code_end - __code_start;
  __text_zx0_size = __text_zx0_end - __text_zx0_start;

  /* Verify ROM payload (decoder + compressed blob) fits in 2 KB. */
  __prom_end = __text_zx0_end;
  ASSERT(__prom_end <= 2048, "PROM0 socket exceeds 2048 bytes after ZX0!")

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
