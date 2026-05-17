; ZX0-compressed .text payload, incbin'd from a side file produced
; by the two-pass build (see Makefile: clang/text_compressed.zx0).
;
; Layout: linker script places this section in ROM immediately after
; .zx0_decoder; symbols __text_zx0_start / __text_zx0_end (defined by
; the linker script) bracket the blob.  _reloc_zx0 in dzx0_standard.s
; loads HL with __text_zx0_start and DE with __code_start, then jumps
; into the decoder.

	.section .text_compressed,"a",@progbits
	.incbin	"clang/text_compressed.zx0"
