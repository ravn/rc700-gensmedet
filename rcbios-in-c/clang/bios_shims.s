; bios_shims.s — Assembly shims for clang/LLVM-Z80 build of RC700 CP/M BIOS
;
; These replace the __naked functions in bios.c.  The SDCC build uses
; inline asm in bios.c; the clang build uses this file instead.
; The clang jump vector table (bios_jump_vector_table.c) references
; the _shim symbols for entry points needing register translation.
;
; Calling convention: sdcccall(1)
;   1st byte param in A, 1st word param in HL
;   2nd byte param in E, 2nd word param in DE
;   3rd+ on stack (callee cleanup)
;   Return: byte in A, word in HL (or DE for pointers)

; ================================================================
; Constants (must match bios.h)
; ================================================================
.equ BIOS_STACK,  0xF500
.equ ISTACK_ADDR, 0xF600
.equ WARMJP_ADDR, 0xFFE5
.equ TIMER1_ADDR, 0xFFDF
.equ RTC0_ADDR,   0xFFFC
.equ RTC2_ADDR,   0xFFFE

; ================================================================
; Cold boot (BOOT_CODE section — runs at physical address)
; ================================================================

	.section .text.coldboot,"ax",@progbits
	.globl	_coldboot
_coldboot:
	di
	call	_relocate_bios
	call	_verify_relocation
	call	_bios_hw_init
	ld	sp, BIOS_STACK
	jp	_bios_boot_c

; ================================================================
; Boot / warm boot shims
; ================================================================

	.section .text._bios_boot_shim,"ax",@progbits
	.globl	_bios_boot_shim
_bios_boot_shim:
	ld	sp, BIOS_STACK
	jp	_bios_boot_c

	.section .text._bios_wboot_shim,"ax",@progbits
	.globl	_bios_wboot_shim
_bios_wboot_shim:
	ld	sp, BIOS_STACK
	jp	_wboot_c

	.section .text._jump_ccp,"ax",@progbits
	.globl	_jump_ccp
_jump_ccp:
	; sdcccall(1): drive in A → CP/M: drive in C
	ld	c, a
	jp	_ccp_entry_point

; ================================================================
; CP/M ABI shims — byte parameter C→A
; ================================================================

	.section .text._bios_conout_shim,"ax",@progbits
	.globl	_bios_conout_shim
_bios_conout_shim:
	ld	a, c
	jp	_bios_conout_c

	.section .text._bios_list_shim,"ax",@progbits
	.globl	_bios_list_shim
_bios_list_shim:
	ld	a, c
	jp	_bios_list_body

	.section .text._bios_write_shim,"ax",@progbits
	.globl	_bios_write_shim
_bios_write_shim:
	ld	a, c
	jp	_bios_write_c

	.section .text._bios_punch_shim,"ax",@progbits
	.globl	_bios_punch_shim
_bios_punch_shim:
	push	hl
	ld	a, c
	call	_bios_punch_body
	pop	hl
	ret

; ================================================================
; CP/M ABI shims — word parameter BC→memory
; ================================================================

	.section .text._bios_settrk_shim,"ax",@progbits
	.globl	_bios_settrk_shim
_bios_settrk_shim:
	ld	(_cpm_track), bc
	ret

	.section .text._bios_setsec_shim,"ax",@progbits
	.globl	_bios_setsec_shim
_bios_setsec_shim:
	ld	(_cpm_sector), bc
	ret

	.section .text._bios_setdma_shim,"ax",@progbits
	.globl	_bios_setdma_shim
_bios_setdma_shim:
	ld	(_cpm_dma_addr), bc
	ret

; ================================================================
; CP/M ABI shims — return value translation
; ================================================================

	.section .text._bios_seldsk_shim,"ax",@progbits
	.globl	_bios_seldsk_shim
_bios_seldsk_shim:
	; CP/M: drive in C → sdcccall(1): byte in A
	; Return: disk_parameter_header pointer in HL (sdcccall(1) returns word in DE)
	ld	a, c
	call	_bios_seldsk_c
	ex	de, hl		; sdcccall(1) returns pointer in DE → CP/M expects HL
	ret

	.section .text._bios_sectran_shim,"ax",@progbits
	.globl	_bios_sectran_shim
_bios_sectran_shim:
	; CP/M: logical sector in BC → return physical in HL
	; This BIOS has no sector translation — identity map
	ld	h, b
	ld	l, c
	ret

	.section .text._bios_reader_shim,"ax",@progbits
	.globl	_bios_reader_shim
_bios_reader_shim:
	push	hl
	call	_bios_reader_body
	pop	hl
	ld	c, a		; CP/M expects char in both A and C
	ret

; ================================================================
; SNIOS HL-preserving shim
; ================================================================

	.section .text._bios_reads_shim,"ax",@progbits
	.globl	_bios_reads_shim
_bios_reads_shim:
	push	hl
	call	_bios_reads_body
	pop	hl
	ld	c, a
	ret

; ================================================================
; Extended BIOS shims
; ================================================================

	.section .text._bios_wfitr_shim,"ax",@progbits
	.globl	_bios_wfitr_shim
_bios_wfitr_shim:
	call	_fdc_irq_wait_rearm
	ld	a, (_fdc_result)
	ld	b, a
	ld	a, (_fdc_result + 1)
	ld	c, a
	ret

	.section .text._bios_linsel_shim,"ax",@progbits
	.globl	_bios_linsel_shim
_bios_linsel_shim:
	; A=port, B=line
	ld	(_ls_port), a
	ld	a, b
	ld	(_ls_line), a
	jp	_bios_linsel_body

	.section .text._bios_exit_shim,"ax",@progbits
	.globl	_bios_exit_shim
_bios_exit_shim:
	; HL=callback address, DE=countdown ticks
	ld	(WARMJP_ADDR), hl
	ex	de, hl
	ld	(TIMER1_ADDR), hl
	ret

	.section .text._bios_clock_shim,"ax",@progbits
	.globl	_bios_clock_shim
_bios_clock_shim:
	; A=0: SET clock from DE(low) HL(high)
	; A!=0: GET clock → DE(low) HL(high)
	or	a
	jr	z, .Lclock_set
	di
	ld	de, (RTC0_ADDR)
	ld	hl, (RTC2_ADDR)
	ei
	ret
.Lclock_set:
	ld	(RTC0_ADDR), de
	ld	(RTC2_ADDR), hl
	ret

; ================================================================
; Miscellaneous
; ================================================================

	.section .text._set_i_reg,"ax",@progbits
	.globl	_set_i_reg
_set_i_reg:
	; sdcccall(1): byte param in A
	ld	i, a
	ret

; ================================================================
; ISR wrappers — stack-switching interrupt handlers
;
; Pattern: save SP, switch to interrupt stack, save registers,
; call C body, restore registers, restore SP, EI, RETI.
;
; The C body functions (isr_crt, isr_floppy, etc.) are compiled as
; regular functions by clang — their isr_enter_full/isr_exit_full
; calls are no-ops, so they contain only the ISR logic.
; ================================================================

	.section .text._isr_crt_wrapper,"ax",@progbits
	.globl	_isr_crt_wrapper
_isr_crt_wrapper:
	ld	(_sp_sav), sp
	ld	sp, ISTACK_ADDR
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_crt
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp, (_sp_sav)
	ei
	reti

	.section .text._isr_floppy_wrapper,"ax",@progbits
	.globl	_isr_floppy_wrapper
_isr_floppy_wrapper:
	ld	(_sp_sav), sp
	ld	sp, ISTACK_ADDR
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_floppy
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp, (_sp_sav)
	ei
	reti

	.section .text._isr_pio_kbd_wrapper,"ax",@progbits
	.globl	_isr_pio_kbd_wrapper
_isr_pio_kbd_wrapper:
	ld	(_sp_sav), sp
	ld	sp, ISTACK_ADDR
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_pio_kbd
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp, (_sp_sav)
	ei
	reti

	.section .text._isr_sio_a_rx_wrapper,"ax",@progbits
	.globl	_isr_sio_a_rx_wrapper
_isr_sio_a_rx_wrapper:
	ld	(_sp_sav), sp
	ld	sp, ISTACK_ADDR
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_a_rx
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp, (_sp_sav)
	ei
	reti

; ================================================================
; ISR wrappers — non-stack-switching interrupt handlers
;
; Pattern: save caller-saved registers, call the C body, restore
; them, EI, RETI.  These handlers run on the interrupted program's
; stack (no ISTACK switch) — mirroring the previous __critical
; __interrupt behaviour.  The C body is a plain function (clang's
; __critical/__interrupt macros expand to nothing, see intrinsic.h),
; so it preserves its own callee-saved registers (IX/IY); the wrapper
; only saves the caller-saved set (AF/BC/DE/HL).
;
; EI is delayed one instruction, so no interrupt can fire between EI
; and RETI.  On Z80, RETI does NOT restore IFF, so this explicit EI is
; what re-enables interrupts on handler exit.
; ================================================================

	.section .text._isr_dummy_wrapper,"ax",@progbits
	.globl	_isr_dummy_wrapper
_isr_dummy_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_dummy
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_hd_wrapper,"ax",@progbits
	.globl	_isr_hd_wrapper
_isr_hd_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_hd
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_b_tx_wrapper,"ax",@progbits
	.globl	_isr_sio_b_tx_wrapper
_isr_sio_b_tx_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_b_tx
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_b_ext_wrapper,"ax",@progbits
	.globl	_isr_sio_b_ext_wrapper
_isr_sio_b_ext_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_b_ext
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_b_rx_wrapper,"ax",@progbits
	.globl	_isr_sio_b_rx_wrapper
_isr_sio_b_rx_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_b_rx
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_b_spec_wrapper,"ax",@progbits
	.globl	_isr_sio_b_spec_wrapper
_isr_sio_b_spec_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_b_spec
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_a_tx_wrapper,"ax",@progbits
	.globl	_isr_sio_a_tx_wrapper
_isr_sio_a_tx_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_a_tx
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_a_ext_wrapper,"ax",@progbits
	.globl	_isr_sio_a_ext_wrapper
_isr_sio_a_ext_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_a_ext
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_sio_a_spec_wrapper,"ax",@progbits
	.globl	_isr_sio_a_spec_wrapper
_isr_sio_a_spec_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_sio_a_spec
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

	.section .text._isr_pio_par_wrapper,"ax",@progbits
	.globl	_isr_pio_par_wrapper
_isr_pio_par_wrapper:
	push	af
	push	bc
	push	de
	push	hl
	call	_isr_pio_par
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	reti

