; boot.asm -- Boot entry point and ZX0 decompressor for zsdcc autoload PROM
;
; Reset vector at 0x0000: disables interrupts, initializes SP to 0xBFFF,
; decompresses ZX0 payload into RAM at 0x6000, zeros BSS, and jumps to _main_relocated.
; dzx0_standard and BSS clearing all fit before NMI vector at 0x0066 (padded with 0xFF + retn).

	SECTION _BOOT

	EXTERN __bss_compiler_head
	EXTERN __bss_compiler_size
	EXTERN _main_relocated

	PUBLIC _start
_start:
	di
	ld sp, 0xBFFF
	ld hl, text_compressed
	ld de, 0x6000
	call dzx0_standard

	; zero BSS in RAM using LDIR
	ld hl, __bss_compiler_head
	ld de, __bss_compiler_head + 1
	ld bc, __bss_compiler_size - 1
	ld (hl), 0
	ldir
	jp _main_relocated

dzx0_standard:
	ld bc, 0xFFFF
	push bc
	inc bc
	ld a, 0x80
dzx0s_literals:
	call dzx0s_elias
	ldir
	add a, a
	jr c, dzx0s_new_offset
	call dzx0s_elias
dzx0s_copy:
	ex (sp), hl
	push hl
	add hl, de
	ldir
	pop hl
	ex (sp), hl
	add a, a
	jr nc, dzx0s_literals
dzx0s_new_offset:
	call dzx0s_elias
	ex af, af'
	pop af
	xor a
	sub c
	ret z
	ld b, a
	ex af, af'
	ld c, (hl)
	inc hl
	rr b
	rr c
	push bc
	ld bc, 1
	call nc, dzx0s_elias_backtrack
	inc bc
	jr dzx0s_copy

dzx0s_elias:
	inc c
dzx0s_elias_loop:
	add a, a
	jr nz, dzx0s_elias_skip
	ld a, (hl)
	inc hl
	rla
dzx0s_elias_skip:
	ret c
dzx0s_elias_backtrack:
	add a, a
	rl c
	rl b
	jr dzx0s_elias_loop

	; NMI pad: hardware vectors NMI to 0x0066
	defs 0x0066 - $, 0xFF
	retn

text_compressed:
	BINARY "zsdcc/text_compressed.zx0"
