/* RC700 autoload PROM linker script for LLVM-Z80 (ld.lld)
 *
 * ROM layout (2 KB PROM0, padded to 4 KB file format):
 *   0x0000  BOOT section (entry, init_fdc, banner, NMI handler)
 *   0x0066  NMI handler (RETN)
 *   0x0068  ZX0 decoder + _reloc_zx0 wrapper (~74 B)
 *   0x00B2  ZX0-compressed .text payload (~1331 B)
 *
 * RAM layout (after self-decompression by _start):
 *   0x6000  .text (IVT + C code + rodata) decompressed by dzx0_standard
 *   0xBFFF  Stack (grows downward)
 *
 * Two-pass build: pass 1 produces raw .text bytes; the Makefile
 * compresses them with z88dk-zx0 into clang/text_compressed.zx0; pass 2
 * incbins the result and re-links.  llvm-objcopy emits only the four
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

  /* NMI handler at Z80 hardwired vector 0x0066. */
  .nmi 0x0066 : {
    KEEP(*boot.o(.nmi*))
  } > ROM

  /* ZX0 decoder at 0x0068 -- callable from BOOT via _reloc_zx0. */
  .zx0_decoder 0x0068 : {
    KEEP(*dzx0_standard.o(.zx0_decoder*))
  } > ROM

  /* ZX0-compressed .text payload, immediately after the decoder.
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
