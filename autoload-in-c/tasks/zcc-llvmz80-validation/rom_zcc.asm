	SECTION	code_compiler
	GLOBAL	_fdc_write_when_ready           ; -- Begin function fdc_write_when_ready
_fdc_write_when_ready:                  ; @fdc_write_when_ready
; %bb.0:                                ; %entry
	ld	b,a
	ld	de,0
LBB0_1:                                 ; %do.body
                                        ; =>This Inner Loop Header: Depth=1
	;APP
	in	a,(4)
	;NO_APP
	xor	128
	cp	64
	jr	c,LBB0_4
; %bb.2:                                ; %do.cond
                                        ;   in Loop: Header=BB0_1 Depth=1
	dec	de
	ld	a,e
	or	d
	jr	nz,LBB0_1
; %bb.3:                                ; %cleanup
	ret
LBB0_4:                                 ; %if.then
	ld	a,b
	;APP
	out	(5),a
	;NO_APP
	ret
                                        ; -- End function
	GLOBAL	_fdc_read_when_ready            ; -- Begin function fdc_read_when_ready
_fdc_read_when_ready:                   ; @fdc_read_when_ready
; %bb.0:                                ; %entry
	ld	bc,0
LBB1_1:                                 ; %do.body
                                        ; =>This Inner Loop Header: Depth=1
	;APP
	in	a,(4)
	;NO_APP
	cp	192
	jr	nc,LBB1_4
; %bb.2:                                ; %do.cond
                                        ;   in Loop: Header=BB1_1 Depth=1
	dec	bc
	ld	a,c
	or	b
	jr	nz,LBB1_1
; %bb.3:
	ld	a,255
	ret
LBB1_4:                                 ; %if.then
	;APP
	in	a,(5)
	;NO_APP
	ret
                                        ; -- End function
	GLOBAL	_delay                          ; -- Begin function delay
_delay:                                 ; @delay
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	dec	sp
	ld	(ix+-1),l                       ; 1-byte Folded Spill
	or	a
	jr	z,LBB2_7
; %bb.1:                                ; %do.body.preheader
	ld	c,a
LBB2_2:                                 ; %do.body
                                        ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB2_3 Depth 2
                                        ;       Child Loop BB2_4 Depth 3
	ld	l,c
	ld	h,(ix+-1)                       ; 1-byte Folded Reload
LBB2_3:                                 ; %do.body1
                                        ;   Parent Loop BB2_2 Depth=1
                                        ; =>  This Loop Header: Depth=2
                                        ;       Child Loop BB2_4 Depth 3
	ld	e,0
LBB2_4:                                 ; %do.body2
                                        ;   Parent Loop BB2_2 Depth=1
                                        ;     Parent Loop BB2_3 Depth=2
                                        ; =>    This Inner Loop Header: Depth=3
	;APP
	;NO_APP
	ld	d,0
	inc	de
	ld	a,e
	xor	e
	or	d
	call	_OUTLINED_FUNCTION_2
	jr	nz,LBB2_4
; %bb.5:                                ; %do.end
                                        ;   in Loop: Header=BB2_3 Depth=2
	dec	h
	jr	nz,LBB2_3
; %bb.6:                                ; %do.end7
                                        ;   in Loop: Header=BB2_2 Depth=1
	ld	c,l
	dec	c
	jr	nz,LBB2_2
LBB2_7:                                 ; %do.end11
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_lookup_sectors_and_gap3_for_current_track ; -- Begin function lookup_sectors_and_gap3_for_current_track
_lookup_sectors_and_gap3_for_current_track: ; @lookup_sectors_and_gap3_for_current_track
; %bb.0:                                ; %entry
	ld	bc,_is_mini
	ld	a,(bc)
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	c,l
	ld	b,h
	ld	hl,_eot_gap3_table
	add	hl,bc
	ld	c,l
	ld	b,h
	ld	de,_fdc_cmd+3
	ld	a,(de)
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	ex	de,hl
	ld	l,c
	ld	h,b
	add	hl,de
	ld	c,l
	ld	b,h
	ld	de,_is_mfm
	ld	a,(de)
	ld	l,a
	ld	h,0
	add	hl,hl
	ex	de,hl
	ld	l,c
	ld	h,b
	add	hl,de
	ld	a,(hl)
	ld	bc,_fdc_cmd+4
	ld	(bc),a
	inc	hl
	ld	a,(hl)
	ld	bc,_fdc_cmd+5
	ld	(bc),a
	ld	bc,_fdc_cmd+6
	ld	a,128
	ld	(bc),a
	ret
                                        ; -- End function
	GLOBAL	_calc_size_of_current_track     ; -- Begin function calc_size_of_current_track
_calc_size_of_current_track:            ; @calc_size_of_current_track
; %bb.0:                                ; %entry
	ld	bc,_disk_type
	ld	a,(bc)
	add	a,a
	jr	nc,LBB4_2
; %bb.1:                                ; %land.lhs.true
	ld	bc,_fdc_cmd+1
	ld	a,(bc)
	ld	hl,10
	cp	1
	jr	z,LBB4_3
LBB4_2:                                 ; %cond.false
	ld	bc,_fdc_cmd+4
	ld	a,(bc)
	ld	b,a
	ld	de,_fdc_cmd+2
	ld	a,(de)
	ld	c,a
	inc	b
	ld	a,b
	sub	c
	ld	l,a
	ld	h,0
LBB4_3:                                 ; %cond.end
	ld	bc,_fdc_cmd+3
	ld	a,(bc)
	add	a,7
	ld	b,a
LBB4_4:                                 ; %for.cond
                                        ; =>This Inner Loop Header: Depth=1
	ld	a,b
	or	a
	jr	z,LBB4_6
; %bb.5:                                ; %for.body
                                        ;   in Loop: Header=BB4_4 Depth=1
	add	hl,hl
	dec	b
	jr	LBB4_4
LBB4_6:                                 ; %for.cond.cleanup
	ld	(_dma_transfer_size),hl
	ret
                                        ; -- End function
	GLOBAL	_fdc_sense_interrupt            ; -- Begin function fdc_sense_interrupt
_fdc_sense_interrupt:                   ; @fdc_sense_interrupt
; %bb.0:                                ; %entry
	ld	a,8
	call	_fdc_write_when_ready
	call	_fdc_read_when_ready
	ld	bc,_fdc_result
	ld	(bc),a
	xor	128
	cp	64
	jr	c,LBB5_2
; %bb.1:                                ; %if.then
	call	_fdc_read_when_ready
	ld	bc,_fdc_result+1
	ld	(bc),a
LBB5_2:                                 ; %if.end
	ret
                                        ; -- End function
	GLOBAL	_fdc_read_result                ; -- Begin function fdc_read_result
_fdc_read_result:                       ; @fdc_read_result
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	dec	sp
	ld	bc,_fdc_result
	ld	d,7
LBB6_1:                                 ; %for.cond
                                        ; =>This Inner Loop Header: Depth=1
	ld	a,d
	or	a
	jr	z,LBB6_4
; %bb.2:                                ; %for.body
                                        ;   in Loop: Header=BB6_1 Depth=1
	call	_OUTLINED_FUNCTION_6
	ld	(ix+-3),d                       ; 1-byte Folded Spill
	call	_fdc_read_when_ready
	ld	d,(ix+-3)                       ; 1-byte Folded Reload
	call	_OUTLINED_FUNCTION_1
	ld	(bc),a
	;APP
	in	a,(4)
	;NO_APP
	and	16
	inc	bc
	dec	d
	or	a
	jr	nz,LBB6_1
; %bb.3:                                ; %if.then
	;APP
	in	a,(248)
	;NO_APP
	ld	(bc),a
	jr	LBB6_5
LBB6_4:                                 ; %for.end
	ld	bc,_error_saved
	ld	a,254
	ld	(bc),a
	call	_error_display_halt
LBB6_5:                                 ; %cleanup
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_error_display_halt             ; -- Begin function error_display_halt
_error_display_halt:                    ; @error_display_halt
; %bb.0:                                ; %entry
	ld	bc,_error_saved
	ld	(bc),a
	;APP
	ei
	;NO_APP
	ld	bc,_disk_type
	ld	a,(bc)
	and	1
	jr	z,LBB7_2
; %bb.1:                                ; %do.end
	ret
LBB7_2:                                 ; %if.end
	xor	a
	;APP
	out	(28),a
	;NO_APP
	ld	hl,L__str
	ld	de,30928
	ld	bc,19
	ldir
	call	_halt_forever
                                        ; -- End function
	GLOBAL	_wait_fdc_ready                 ; -- Begin function wait_fdc_ready
_wait_fdc_ready:                        ; @wait_fdc_ready
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	dec	sp
	ld	b,a
	ld	h,1
LBB8_1:                                 ; %while.cond
                                        ; =>This Inner Loop Header: Depth=1
	dec	b
	jr	z,LBB8_4
; %bb.2:                                ; %while.body
                                        ;   in Loop: Header=BB8_1 Depth=1
	ld	a,1
	ld	l,2
	ld	(ix+-1),b                       ; 1-byte Folded Spill
	call	_delay
	ld	b,(ix+-1)                       ; 1-byte Folded Reload
	ld	h,1
	ld	de,_floppy_operation_completed_flag
	ld	a,(de)
	or	a
	jr	z,LBB8_1
; %bb.3:                                ; %if.then
	;APP
	di
	;NO_APP
	ld	bc,_floppy_operation_completed_flag
	ld	h,0
	ld	a,h
	ld	(bc),a
	;APP
	ei
	;NO_APP
LBB8_4:                                 ; %return
	ld	a,h
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_fdc_select_drive_cylinder_head ; -- Begin function fdc_select_drive_cylinder_head
_fdc_select_drive_cylinder_head:        ; @fdc_select_drive_cylinder_head
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	ld	bc,_fdc_cmd+1
	ld	a,(bc)
	add	a,a
	add	a,a
	ld	b,a
	ld	de,_drive_select
	ld	a,(de)
	ld	c,a
	ld	a,b
	or	c
	ld	(ix+-2),a                       ; 1-byte Folded Spill
	ld	bc,_fdc_cmd
	ld	a,(bc)
	ld	(ix+-1),a                       ; 1-byte Folded Spill
	ld	a,15
	call	_fdc_write_when_ready
	ld	a,(ix+-2)                       ; 1-byte Folded Reload
	and	7
	call	_fdc_write_when_ready
	ld	a,(ix+-1)                       ; 1-byte Folded Reload
	call	_fdc_write_when_ready
	ld	bc,_fdc_cmd
	ld	a,(bc)
	call	_verify_seek_result
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
_verify_seek_result:                    ; -- Begin function verify_seek_result
                                        ; @verify_seek_result
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	dec	sp
	ld	(ix+-1),a                       ; 1-byte Folded Spill
	ld	a,255
	call	_wait_fdc_ready
	ld	b,1
	or	a
	jr	nz,LBB10_4
; %bb.1:                                ; %if.end
	ld	bc,_drive_select
	ld	a,(bc)
	ld	l,a
	ld	h,0
	ld	bc,32
	add	hl,bc
	ld	bc,_fdc_result
	ld	a,(bc)
	ld	e,a
	ld	b,2
	ld	a,l
	xor	e
	or	h
	jr	nz,LBB10_4
; %bb.2:                                ; %lor.lhs.false
	ld	de,_fdc_result+1
	ld	a,(de)
	ld	c,a
	ld	a,(ix+-1)                       ; 1-byte Folded Reload
	cp	c
	jr	nz,LBB10_4
; %bb.3:                                ; %if.end8
	ld	b,0
LBB10_4:                                ; %return
	ld	a,b
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_fdc_write_full_cmd             ; -- Begin function fdc_write_full_cmd
_fdc_write_full_cmd:                    ; @fdc_write_full_cmd
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	dec	sp
	ld	h,a
	ld	bc,_is_mfm
	ld	a,(bc)
	or	a
	jr	z,LBB11_2
; %bb.1:                                ; %select.false
	ld	b,64
	jr	LBB11_3
LBB11_2:
	ld	b,0
LBB11_3:                                ; %select.end
	ld	de,_fdc_cmd+1
	ld	a,(de)
	add	a,a
	add	a,a
	ld	c,a
	ld	de,_drive_select
	ld	a,(de)
	ld	d,a
	ld	a,c
	or	d
	ld	(ix+-1),a                       ; 1-byte Folded Spill
	;APP
	di
	;NO_APP
	ld	a,b
	add	a,h
	ld	(ix+-3),h                       ; 1-byte Folded Spill
	call	_fdc_write_when_ready
	ld	a,(ix+-1)                       ; 1-byte Folded Reload
	call	_fdc_write_when_ready
	ld	a,(ix+-3)                       ; 1-byte Folded Reload
	and	15
	cp	6
	jr	nz,LBB11_7
; %bb.4:                                ; %for.cond.preheader
	ld	b,7
	ld	de,_fdc_cmd
LBB11_5:                                ; %for.cond
                                        ; =>This Inner Loop Header: Depth=1
	ld	a,b
	or	a
	jr	z,LBB11_7
; %bb.6:                                ; %for.body
                                        ;   in Loop: Header=BB11_5 Depth=1
	ld	a,(de)
	ld	(ix+-1),b                       ; 1-byte Folded Spill
	ld	(ix+-3),e                       ; 2-byte Folded Spill
	ld	(ix+-2),d                       ; 2-byte Folded Spill
	call	_fdc_write_when_ready
	ld	e,(ix+-3)                       ; 2-byte Folded Reload
	ld	d,(ix+-2)                       ; 2-byte Folded Reload
	ld	b,(ix+-1)                       ; 1-byte Folded Reload
	inc	de
	dec	b
	jr	LBB11_5
LBB11_7:                                ; %if.end
	;APP
	ei
	;NO_APP
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_check_fdc_result               ; -- Begin function check_fdc_result
_check_fdc_result:                      ; @check_fdc_result
; %bb.0:                                ; %entry
	ld	bc,_fdc_result
	ld	a,(bc)
	and	195
	ld	b,a
	ld	de,_drive_select
	ld	a,(de)
	ld	c,a
	ld	a,b
	cp	c
	jr	nz,LBB12_3
; %bb.1:                                ; %land.lhs.true
	ld	bc,_fdc_result+1
	ld	a,(bc)
	or	a
	jr	nz,LBB12_3
; %bb.2:                                ; %land.lhs.true6
	ld	bc,_fdc_result+2
	ld	a,(bc)
	and	191
	jr	z,LBB12_6
LBB12_3:                                ; %if.else
	ld	bc,_retry_count
	ld	a,(bc)
	dec	a
	ld	(bc),a
	jr	z,LBB12_5
; %bb.4:                                ; %select.false
	ld	a,1
	ret
LBB12_5:
	ld	a,2
	ret
LBB12_6:
	xor	a
	ret
                                        ; -- End function
	GLOBAL	_fdc_get_result_bytes           ; -- Begin function fdc_get_result_bytes
_fdc_get_result_bytes:                  ; @fdc_get_result_bytes
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	dec	sp
	ld	bc,_saved_fdc_command
	ld	(bc),a
	ld	bc,_retry_count
	ld	a,l
	ld	(bc),a
LBB13_1:                                ; %while.cond
                                        ; =>This Inner Loop Header: Depth=1
	;APP
	di
	;NO_APP
	xor	a
	ld	bc,_floppy_operation_completed_flag
	ld	(bc),a
	;APP
	ei
	;NO_APP
	ld	bc,_saved_fdc_command
	ld	a,(bc)
	ld	b,a
	and	15
	cp	10
	jr	z,LBB13_3
; %bb.2:                                ; %if.then
                                        ;   in Loop: Header=BB13_1 Depth=1
	;APP
	di
	;NO_APP
	ld	a,5
	;APP
	out	(250),a
	;NO_APP
	ld	a,69
	;APP
	out	(251),a
	;NO_APP
	xor	a
	;APP
	out	(252),a
	;NO_APP
	ld	bc,(_dma_transfer_address)
	ld	a,c
	;APP
	out	(242),a
	;NO_APP
	ld	a,b
	;APP
	out	(242),a
	;NO_APP
	ld	bc,(_dma_transfer_size)
	dec	bc
	ld	a,c
	;APP
	out	(243),a
	;NO_APP
	ld	a,b
	;APP
	out	(243),a
	;NO_APP
	ld	a,1
	;APP
	out	(250),a
	;NO_APP
	;APP
	ei
	;NO_APP
	ld	bc,_saved_fdc_command
	ld	a,(bc)
	ld	b,a
LBB13_3:                                ; %if.end
                                        ;   in Loop: Header=BB13_1 Depth=1
	ld	a,b
	call	_fdc_write_full_cmd
	ld	a,255
	call	_wait_fdc_ready
	ld	(ix+-1),1                       ; 1-byte Folded Spill
	or	a
	jr	nz,LBB13_7
; %bb.4:                                ; %if.end12
                                        ;   in Loop: Header=BB13_1 Depth=1
	call	_check_fdc_result
	cp	2
	jr	z,LBB13_7
; %bb.5:                                ; %if.end12
                                        ;   in Loop: Header=BB13_1 Depth=1
	ld	b,a
	or	a
	jr	nz,LBB13_1
; %bb.6:                                ; %cleanup.loopexit
	ld	(ix+-1),b                       ; 1-byte Folded Spill
LBB13_7:                                ; %cleanup
	ld	a,(ix+-1)                       ; 1-byte Folded Reload
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_fdc_detect_sector_size_and_density ; -- Begin function fdc_detect_sector_size_and_density
_fdc_detect_sector_size_and_density:    ; @fdc_detect_sector_size_and_density
; %bb.0:                                ; %entry
	ld	d,0
	ld	bc,_is_mfm
LBB14_1:                                ; %while.body
                                        ; =>This Inner Loop Header: Depth=1
	ld	a,d
	ld	(bc),a
	call	_fdc_select_drive_cylinder_head
	or	a
	jr	nz,LBB14_4
; %bb.2:                                ; %if.end
                                        ;   in Loop: Header=BB14_1 Depth=1
	ld	bc,4
	ld	(_dma_transfer_size),bc
	ld	a,10
	ld	l,1
	call	_fdc_get_result_bytes
	or	a
	jr	z,LBB14_5
; %bb.3:                                ; %if.end7
                                        ;   in Loop: Header=BB14_1 Depth=1
	ld	bc,_is_mfm
	ld	a,(bc)
	ld	d,1
	or	a
	jr	z,LBB14_1
	jr	LBB14_6
LBB14_4:
	ld	d,1
	jr	LBB14_6
LBB14_5:                                ; %while.end
	ld	bc,_fdc_result+6
	ld	a,(bc)
	and	7
	ld	bc,_fdc_cmd+3
	ld	(bc),a
	call	_lookup_sectors_and_gap3_for_current_track
	call	_calc_size_of_current_track
	ld	d,0
LBB14_6:                                ; %return
	ld	a,d
	ret
                                        ; -- End function
	GLOBAL	_halt_forever                   ; -- Begin function halt_forever
_halt_forever:                          ; @halt_forever
; %bb.0:                                ; %entry
	ld	a,3
	;APP
	out	(15),a
	;NO_APP
	ld	a,5
	;APP
	out	(250),a
	;NO_APP
	;APP
	ei
	;NO_APP
LBB15_1:                                ; %for.cond
                                        ; =>This Inner Loop Header: Depth=1
	jp	LBB15_1
                                        ; -- End function
	GLOBAL	_compare_6bytes                 ; -- Begin function compare_6bytes
_compare_6bytes:                        ; @compare_6bytes
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	ld	c,250
LBB16_1:                                ; %do.body
                                        ; =>This Inner Loop Header: Depth=1
	ld	a,(hl)
	ld	(ix+-2),a                       ; 1-byte Folded Spill
	ld	a,(de)
	ld	b,a
	ld	a,(ix+-2)                       ; 1-byte Folded Reload
	cp	b
	jr	nz,LBB16_4
; %bb.2:                                ; %do.cond
                                        ;   in Loop: Header=BB16_1 Depth=1
	inc	hl
	call	_OUTLINED_FUNCTION_8
	inc	de
	ld	b,0
	inc	bc
	ld	a,c
	xor	c
	ld	l,(ix+-2)                       ; 2-byte Folded Reload
	or	b
	call	_OUTLINED_FUNCTION_2
	jr	nz,LBB16_1
; %bb.3:
	xor	a
	jr	LBB16_5
LBB16_4:
	ld	a,1
LBB16_5:                                ; %cleanup
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_check_sysfile                  ; -- Begin function check_sysfile
_check_sysfile:                         ; @check_sysfile
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	push	af
	push	af
	call	_OUTLINED_FUNCTION_5
	ld	c,252
	call	_OUTLINED_FUNCTION_4
LBB17_1:                                ; %do.body
                                        ; =>This Inner Loop Header: Depth=1
	inc	hl
	ld	(ix+-4),l                       ; 2-byte Folded Spill
	ld	(ix+-3),h                       ; 2-byte Folded Spill
	ld	a,(hl)
	ld	l,a
	ld	h,0
	ld	e,(ix+-2)                       ; 2-byte Folded Reload
	ld	d,(ix+-1)                       ; 2-byte Folded Reload
	ld	a,(de)
	ld	e,a
	rlca
	sbc	a,a
	ld	b,a
	ld	a,l
	xor	e
	or	b
	jr	nz,LBB17_4
; %bb.2:                                ; %do.cond
                                        ;   in Loop: Header=BB17_1 Depth=1
	ld	e,(ix+-2)                       ; 2-byte Folded Reload
	ld	d,(ix+-1)                       ; 2-byte Folded Reload
	inc	de
	call	_OUTLINED_FUNCTION_5
	ld	b,0
	inc	bc
	ld	a,c
	xor	c
	or	b
	call	_OUTLINED_FUNCTION_2
	ld	l,(ix+-4)                       ; 2-byte Folded Reload
	ld	h,(ix+-3)                       ; 2-byte Folded Reload
	jr	nz,LBB17_1
; %bb.3:                                ; %do.end
	ld	bc,8
	ld	l,(ix+-6)                       ; 2-byte Folded Reload
	ld	h,(ix+-5)                       ; 2-byte Folded Reload
	add	hl,bc
	ld	a,(hl)
	and	63
	sub	19
	add	a,255
	sbc	a,a
	and	1
	jr	LBB17_5
LBB17_4:
	ld	a,1
LBB17_5:                                ; %cleanup
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_prom1_if_present               ; -- Begin function prom1_if_present
_prom1_if_present:                      ; @prom1_if_present
; %bb.0:                                ; %entry
	;APP
	in	a,(20)
	;NO_APP
	and	2
	jr	nz,LBB18_3
; %bb.1:                                ; %land.lhs.true
	ld	hl,8194
	ld	de,_msg_rc702
	call	_compare_6bytes
	or	a
	jr	nz,LBB18_3
; %bb.2:                                ; %if.then
	ld	hl,8192
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	de
	pop	iy
	call	__call_iy
	ret
LBB18_3:                                ; %do.body
	ld	hl,L__str_1
	ld	de,30928
	ld	bc,30
	ldir
	call	_halt_forever
                                        ; -- End function
	GLOBAL	_floppy_legacy_boot             ; -- Begin function floppy_legacy_boot
_floppy_legacy_boot:                    ; @floppy_legacy_boot
; %bb.0:                                ; %entry
	ld	bc,_is_mini
	ld	a,(bc)
	rrca
	and	128
	ld	b,a
	ld	de,_disk_type
	ld	a,(de)
	ld	c,a
	ld	a,b
	or	c
	dec	a
	ld	(de),a
	call	_fdc_detect_sector_size_and_density
	ld	bc,0
	ld	(_dma_transfer_address),bc
	ld	hl,24576
	call	_fdc_read_data_from_current_location
	ld	a,1
	ld	bc,_disk_type
	ld	(bc),a
	ld	bc,4096
	push	bc
	pop	iy
	call	__call_iy
	ret
                                        ; -- End function
_fdc_read_data_from_current_location:   ; -- Begin function fdc_read_data_from_current_location
                                        ; @fdc_read_data_from_current_location
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	ld	(_bytes_left_to_read),hl
LBB20_1:                                ; %while.body
                                        ; =>This Inner Loop Header: Depth=1
	call	_fdc_select_drive_cylinder_head
	or	a
	jp	nz,LBB20_9
; %bb.2:                                ; %if.end6
                                        ;   in Loop: Header=BB20_1 Depth=1
	call	_calc_size_of_current_track
	ld	hl,(_bytes_left_to_read)
	ld	de,(_dma_transfer_size)
	call	_OUTLINED_FUNCTION_8
	and	a
	sbc	hl,de
	ld	c,l
	ld	b,h
	ld	a,h
	xor	128
	ld	h,a
	ld	d,1
	ld	a,l
	sub	1
	ld	a,h
	sbc	a,128
	jr	nc,LBB20_4
; %bb.3:                                ; %if.else
                                        ;   in Loop: Header=BB20_1 Depth=1
	call	_OUTLINED_FUNCTION_1
	ld	(_dma_transfer_size),bc
	ld	bc,0
	ld	d,0
LBB20_4:                                ; %if.end10
                                        ;   in Loop: Header=BB20_1 Depth=1
	ld	a,d
	ld	de,_more_tracks_to_read
	ld	(de),a
	ld	(_bytes_left_to_read),bc
	ld	a,6
	ld	l,5
	call	_fdc_get_result_bytes
	or	a
	jr	nz,LBB20_12
; %bb.5:                                ; %if.end16
                                        ;   in Loop: Header=BB20_1 Depth=1
	ld	bc,(_dma_transfer_size)
	ld	hl,(_dma_transfer_address)
	add	hl,bc
	ld	(_dma_transfer_address),hl
	ld	bc,0
	ld	(_dma_transfer_size),bc
	ld	a,1
	ld	bc,_fdc_cmd+2
	ld	(bc),a
	ld	bc,_is_double_sided
	ld	a,(bc)
	ld	c,a
	ld	de,_fdc_cmd+1
	ld	a,(de)
	cp	c
	jr	nz,LBB20_7
; %bb.6:                                ; %if.then21
                                        ;   in Loop: Header=BB20_1 Depth=1
	ld	bc,_fdc_cmd
	ld	a,(bc)
	inc	a
	ld	(bc),a
	ld	b,0
	jr	LBB20_8
LBB20_7:                                ; %if.else22
                                        ;   in Loop: Header=BB20_1 Depth=1
	ld	b,a
	inc	b
LBB20_8:                                ; %cleanup
                                        ;   in Loop: Header=BB20_1 Depth=1
	ld	a,b
	ld	(de),a
	ld	bc,_more_tracks_to_read
	ld	a,(bc)
	or	a
	jr	z,LBB20_14
; %bb.17:                               ; %cleanup
                                        ;   in Loop: Header=BB20_1 Depth=1
	jp	LBB20_1
LBB20_9:                                ; %while.body
	cp	1
	jr	nz,LBB20_11
; %bb.10:                               ; %if.then
	call	_prom1_if_present
	jr	LBB20_14
LBB20_11:                               ; %if.then5
	ld	a,6
	jr	LBB20_13
LBB20_12:                               ; %if.then15
	ld	a,40
LBB20_13:                               ; %return
	call	_error_display_halt
LBB20_14:                               ; %return
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_syscall                        ; -- Begin function syscall
_syscall:                               ; @syscall
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	ld	c,l
	ld	b,h
	ld	l,d
	ld	h,0
	ld	(_dma_transfer_address),bc
	res	7,e
	ld	bc,_fdc_cmd+2
	ld	a,e
	ld	(bc),a
	res	7,d
	ld	bc,_fdc_cmd
	ld	a,d
	ld	(bc),a
	ld	c,l
	ld	b,h
	call	_OUTLINED_FUNCTION_0
	call	_OUTLINED_FUNCTION_0
	call	_OUTLINED_FUNCTION_0
	srl	b
	rr	c
	call	_OUTLINED_FUNCTION_6
	or	h
	jr	z,LBB21_2
; %bb.1:                                ; %if.end19.critedge
	call	_OUTLINED_FUNCTION_3
	call	_fdc_read_data_from_current_location
	jr	LBB21_3
LBB21_2:                                ; %if.then
	call	_fdc_detect_sector_size_and_density
	call	_OUTLINED_FUNCTION_3
	call	_fdc_read_data_from_current_location
	ld	a,1
	ld	bc,_fdc_cmd
	ld	(bc),a
	call	_fdc_detect_sector_size_and_density
LBB21_3:                                ; %if.end19
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
	GLOBAL	_nothing_int                    ; -- Begin function nothing_int
_nothing_int:                           ; @nothing_int
; %bb.0:                                ; %entry
	;APP
	ei
	;NO_APP
	reti
                                        ; -- End function
	GLOBAL	_refresh_crt_dma_50hz_interrupt ; -- Begin function refresh_crt_dma_50hz_interrupt
_refresh_crt_dma_50hz_interrupt:        ; @refresh_crt_dma_50hz_interrupt
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	hl
	ld	hl,65528
	add	hl,sp
	ld	sp,hl
	ld	l,(ix+-2)
	ld	h,(ix+-1)
	push	af
	push	bc
	push	de
	push	hl
	push	iy
	call	_refresh_crt_dma_50hz_body
	;APP
	ei
	;NO_APP
	pop	iy
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp,ix
	pop	ix
	reti
                                        ; -- End function
_refresh_crt_dma_50hz_body:             ; -- Begin function refresh_crt_dma_50hz_body
                                        ; @refresh_crt_dma_50hz_body
; %bb.0:                                ; %entry
	;APP
	in	a,(1)
	;NO_APP
	ld	a,6
	;APP
	out	(250),a
	;NO_APP
	xor	a
	;APP
	out	(252),a
	;NO_APP
	ld	a,48
	;APP
	out	(244),a
	;NO_APP
	ld	a,120
	;APP
	out	(244),a
	;NO_APP
	ld	a,207
	;APP
	out	(245),a
	;NO_APP
	ld	a,7
	;APP
	out	(245),a
	;NO_APP
	ld	a,2
	;APP
	out	(250),a
	;NO_APP
	ld	a,215
	;APP
	out	(14),a
	;NO_APP
	ld	a,1
	;APP
	out	(14),a
	;NO_APP
	ret
                                        ; -- End function
	GLOBAL	_floppy_completed_operation_interrupt ; -- Begin function floppy_completed_operation_interrupt
_floppy_completed_operation_interrupt:  ; @floppy_completed_operation_interrupt
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	hl
	ld	hl,65528
	add	hl,sp
	ld	sp,hl
	ld	l,(ix+-2)
	ld	h,(ix+-1)
	push	af
	push	bc
	push	de
	push	hl
	push	iy
	ld	bc,_floppy_operation_completed_flag
	ld	a,2
	ld	(bc),a
	;APP
	in	a,(4)
	;NO_APP
	and	16
	jr	nz,LBB25_2
; %bb.1:                                ; %if.else.i
	call	_fdc_sense_interrupt
	jr	LBB25_3
LBB25_2:                                ; %if.then.i
	call	_fdc_read_result
LBB25_3:                                ; %floppy_completed_operation_body.exit
	;APP
	ei
	;NO_APP
	pop	iy
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp,ix
	pop	ix
	reti
                                        ; -- End function
	GLOBAL	_main_relocated                 ; -- Begin function main_relocated
_main_relocated:                        ; @main_relocated
; %bb.0:                                ; %entry
	ld	a,96
	;APP
	ld	i,a
	;NO_APP
	;APP
	im	2
	;NO_APP
	ld	a,2
	;APP
	out	(18),a
	;NO_APP
	ld	a,4
	;APP
	out	(19),a
	;NO_APP
	ld	a,79
	;APP
	out	(18),a
	;NO_APP
	ld	a,15
	;APP
	out	(19),a
	;NO_APP
	ld	a,131
	;APP
	out	(18),a
	;NO_APP
	;APP
	out	(19),a
	;NO_APP
	ld	a,8
	;APP
	out	(12),a
	;NO_APP
	ld	a,71
	;APP
	out	(12),a
	;NO_APP
	ld	a,32
	;APP
	out	(12),a
	;NO_APP
	ld	a,71
	;APP
	out	(13),a
	;NO_APP
	ld	a,32
	;APP
	out	(13),a
	;NO_APP
	ld	a,215
	;APP
	out	(14),a
	;NO_APP
	ld	a,1
	;APP
	out	(14),a
	;NO_APP
	ld	a,215
	;APP
	out	(15),a
	;NO_APP
	ld	a,1
	;APP
	out	(15),a
	;NO_APP
	ld	a,32
	;APP
	out	(248),a
	;NO_APP
	ld	a,192
	;APP
	out	(251),a
	;NO_APP
	xor	a
	;APP
	out	(250),a
	;NO_APP
	ld	a,74
	;APP
	out	(251),a
	;NO_APP
	xor	a
	;APP
	out	(1),a
	;NO_APP
	ld	a,79
	;APP
	out	(0),a
	;NO_APP
	ld	a,152
	;APP
	out	(0),a
	;NO_APP
	ld	a,122
	;APP
	out	(0),a
	;NO_APP
	ld	a,93
	;APP
	out	(0),a
	;NO_APP
	ld	a,128
	;APP
	out	(1),a
	;NO_APP
	xor	a
	;APP
	out	(0),a
	;NO_APP
	;APP
	out	(0),a
	;NO_APP
	ld	a,224
	;APP
	out	(1),a
	;NO_APP
	call	_load_chargen_font
	ld	a,2
	ld	l,190
	call	_delay
LBB26_1:                                ; %while.cond.i
                                        ; =>This Inner Loop Header: Depth=1
	;APP
	in	a,(4)
	;NO_APP
	and	31
	jr	nz,LBB26_1
; %bb.2:                                ; %init_fdc.exit
	ld	a,3
	call	_fdc_write_when_ready
	ld	a,79
	call	_fdc_write_when_ready
	ld	a,32
	call	_fdc_write_when_ready
	ld	hl,30768
	ld	de,32
	ld	bc,2000
	call	___z80_memset_builtin
	call	_display_banner_and_start_crt
	ld	bc,_fdc_isr_delay
	ld	a,3
	ld	(bc),a
	ld	bc,_fdc_result_delay
	ld	a,4
	ld	(bc),a
	;APP
	in	a,(20)
	;NO_APP
	rlca
	and	1
	ld	bc,_is_mini
	ld	(bc),a
	;APP
	ei
	;NO_APP
	ld	a,1
	;APP
	out	(20),a
	;NO_APP
	ld	bc,_retry_count
	ld	a,5
	ld	(bc),a
	call	_boot_from_floppy_or_jump_prom1
LBB26_3:                                ; %for.cond
                                        ; =>This Inner Loop Header: Depth=1
	jp	LBB26_3
                                        ; -- End function
_load_chargen_font:                     ; -- Begin function load_chargen_font
                                        ; @load_chargen_font
; %bb.0:                                ; %entry
	ld	de,_sem702_font
	ld	b,0
LBB27_1:                                ; %for.cond
                                        ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB27_3 Depth 2
	ld	a,b
	cp	11
	jr	z,LBB27_6
; %bb.2:                                ; %for.body
                                        ;   in Loop: Header=BB27_1 Depth=1
	ld	a,b
	;APP
	out	(210),a
	;NO_APP
	ld	c,0
LBB27_3:                                ; %for.cond2
                                        ;   Parent Loop BB27_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ld	a,c
	cp	128
	jr	z,LBB27_5
; %bb.4:                                ; %for.body6
                                        ;   in Loop: Header=BB27_3 Depth=2
	ld	a,c
	;APP
	out	(209),a
	;NO_APP
	ld	a,(de)
	;APP
	out	(211),a
	;NO_APP
	inc	c
	inc	de
	jr	LBB27_3
LBB27_5:                                ; %for.inc7
                                        ;   in Loop: Header=BB27_1 Depth=1
	inc	b
	jr	LBB27_1
LBB27_6:                                ; %for.end9
	ret
                                        ; -- End function
_display_banner_and_start_crt:          ; -- Begin function display_banner_and_start_crt
                                        ; @display_banner_and_start_crt
; %bb.0:                                ; %entry
	ld	hl,30814
	ld	de,32
	ld	bc,1954
	call	___z80_memset_builtin
	ld	hl,_banner_string
	ld	de,30768
	ld	bc,46
	ldir
	call	_display_sw1_status
	call	_draw_qr
	ld	a,6
	;APP
	out	(250),a
	;NO_APP
	xor	a
	;APP
	out	(252),a
	;NO_APP
	ld	a,48
	;APP
	out	(244),a
	;NO_APP
	ld	a,120
	;APP
	out	(244),a
	;NO_APP
	ld	a,207
	;APP
	out	(245),a
	;NO_APP
	ld	a,7
	;APP
	out	(245),a
	;NO_APP
	ld	a,2
	;APP
	out	(250),a
	;NO_APP
	ld	a,35
	;APP
	out	(1),a
	;NO_APP
	ret
                                        ; -- End function
_display_sw1_status:                    ; -- Begin function display_sw1_status
                                        ; @display_sw1_status
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	push	af
	push	af
	;APP
	in	a,(20)
	;NO_APP
	ld	(ix+-2),a                       ; 1-byte Folded Spill
	ld	hl,_display_sw1_status_prefix
	ld	de,30826
	ld	bc,14
	ldir
	ld	bc,30840
	ld	(ix+-4),c                       ; 2-byte Folded Spill
	ld	(ix+-3),b                       ; 2-byte Folded Spill
	ld	(ix+-1),8                       ; 1-byte Folded Spill
	ld	b,0
LBB29_1:                                ; %for.cond
                                        ; =>This Inner Loop Header: Depth=1
	ld	a,(ix+-1)                       ; 1-byte Folded Reload
	or	a
	jr	z,LBB29_3
; %bb.2:                                ; %for.body
                                        ;   in Loop: Header=BB29_1 Depth=1
	ld	d,(ix+-2)                       ; 1-byte Folded Reload
	ld	a,d
	and	1
	or	48
	ld	e,b
	ld	l,b
	ld	h,0
	call	_OUTLINED_FUNCTION_4
	ld	hl,30841
	ld	c,(ix+-6)                       ; 2-byte Folded Reload
	ld	b,(ix+-5)                       ; 2-byte Folded Reload
	add	hl,bc
	call	_OUTLINED_FUNCTION_4
	ld	c,(ix+-4)                       ; 2-byte Folded Reload
	ld	b,(ix+-3)                       ; 2-byte Folded Reload
	ld	(bc),a
	ld	c,(ix+-1)                       ; 1-byte Folded Reload
	srl	d
	ld	(ix+-2),d                       ; 1-byte Folded Spill
	inc	e
	ld	b,e
	dec	c
	ld	(ix+-1),c                       ; 1-byte Folded Spill
	ld	e,l
	ld	d,h
	ld	(ix+-4),e                       ; 2-byte Folded Spill
	ld	(ix+-3),d                       ; 2-byte Folded Spill
	jr	LBB29_1
LBB29_3:                                ; %for.end
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
_draw_qr:                               ; -- Begin function draw_qr
                                        ; @draw_qr
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	push	af
	ld	bc,32032
	ld	a,132
	ld	(bc),a
	ld	hl,32033
	ld	de,_qr_screen
	call	_OUTLINED_FUNCTION_5
	xor	a
LBB30_1:                                ; %for.cond
                                        ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB30_3 Depth 2
	ld	(ix+-4),a                       ; 1-byte Folded Spill
	cp	9
	jr	z,LBB30_6
; %bb.2:                                ; %for.cond2.preheader
                                        ;   in Loop: Header=BB30_1 Depth=1
	ld	bc,67
	add	hl,bc
	ld	b,13
LBB30_3:                                ; %for.cond2
                                        ;   Parent Loop BB30_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ld	a,b
	or	a
	jr	z,LBB30_5
; %bb.4:                                ; %for.body6
                                        ;   in Loop: Header=BB30_3 Depth=2
	ld	e,l
	ld	d,h
	ld	(ix+-3),b                       ; 1-byte Folded Spill
	ld	bc,65469
	add	hl,bc
	call	_OUTLINED_FUNCTION_1
	ld	a,(bc)
	ld	(hl),a
	ex	de,hl
	inc	bc
	call	_OUTLINED_FUNCTION_6
	ld	b,(ix+-3)                       ; 1-byte Folded Reload
	inc	hl
	dec	b
	jr	LBB30_3
LBB30_5:                                ; %for.end
                                        ;   in Loop: Header=BB30_1 Depth=1
	ld	a,(ix+-4)                       ; 1-byte Folded Reload
	inc	a
	jr	LBB30_1
LBB30_6:                                ; %for.end10
	ld	sp,ix
	pop	ix
	ret
                                        ; -- End function
_boot_from_floppy_or_jump_prom1:        ; -- Begin function boot_from_floppy_or_jump_prom1
                                        ; @boot_from_floppy_or_jump_prom1
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	dec	sp
	ld	a,2
	ld	l,190
	call	_delay
	ld	a,4
	call	_fdc_write_when_ready
	ld	bc,_drive_select
	ld	a,(bc)
	call	_fdc_write_when_ready
	call	_fdc_read_when_ready
	ld	bc,_fdc_result
	ld	(bc),a
	and	35
	ld	(ix+-1),a                       ; 1-byte Folded Spill
	ld	a,7
	call	_fdc_write_when_ready
	ld	bc,_drive_select
	ld	a,(bc)
	call	_fdc_write_when_ready
	ld	de,_drive_select
	ld	a,(de)
	ld	l,a
	ld	h,0
	ld	de,32
	add	hl,de
	ld	a,l
	xor	(ix+-1)                         ; 1-byte Folded Reload
	or	h
	jr	nz,LBB31_5
; %bb.1:                                ; %lor.lhs.false
	xor	a
	call	_verify_seek_result
	or	a
	jr	nz,LBB31_5
; %bb.2:                                ; %if.end
	ld	bc,_fdc_cmd
	xor	a
	ld	(bc),a
	ld	de,_fdc_cmd+1
	ld	a,1
	ld	(de),a
	ld	de,_fdc_cmd+2
	ld	(de),a
	call	_fdc_detect_sector_size_and_density
	or	a
	jr	nz,LBB31_4
; %bb.3:                                ; %if.then13
	ld	bc,_is_double_sided
	ld	a,1
	ld	(bc),a
LBB31_4:                                ; %if.end14
	xor	a
	ld	bc,_fdc_cmd+1
	ld	(bc),a
	call	_fdc_detect_sector_size_and_density
	or	a
	jr	z,LBB31_6
LBB31_5:                                ; %cleanup
	call	_prom1_if_present
	ld	sp,ix
	pop	ix
	ret
LBB31_6:                                ; %if.end20
	ld	a,1
	;APP
	out	(24),a
	;NO_APP
LBB31_7:                                ; %while.cond
                                        ; =>This Inner Loop Header: Depth=1
	ld	hl,(_dma_transfer_size)
	call	_fdc_read_data_from_current_location
	ld	bc,_fdc_cmd
	ld	a,(bc)
	or	a
	jr	nz,LBB31_9
; %bb.8:                                ; %if.end25
                                        ;   in Loop: Header=BB31_7 Depth=1
	call	_fdc_detect_sector_size_and_density
	jr	LBB31_7
LBB31_9:                                ; %while.end
	ld	bc,_disk_type
	ld	a,1
	ld	(bc),a
	call	_boot_floppy_or_prom
                                        ; -- End function
_boot_floppy_or_prom:                   ; -- Begin function boot_floppy_or_prom
                                        ; @boot_floppy_or_prom
; %bb.0:                                ; %entry
	push	ix
	ld	ix,0
	add	ix,sp
	push	af
	ld	hl,2
	ld	de,L__str_2
	call	_compare_6bytes
	or	a
	jr	nz,LBB32_5
; %bb.1:                                ; %while.cond.preheader
	ld	hl,2976
	ld	bc,32
LBB32_2:                                ; %while.cond
                                        ; =>This Inner Loop Header: Depth=1
	call	_OUTLINED_FUNCTION_8
	ld	de,65504
	add	hl,de
	ld	(_boot_dir),hl
	ld	de,3328
	ld	a,l
	sub	e
	ld	a,h
	sbc	a,d
	jr	nc,LBB32_12
; %bb.3:                                ; %while.body
                                        ;   in Loop: Header=BB32_2 Depth=1
	ld	a,(hl)
	or	a
	jr	nz,LBB32_8
; %bb.4:                                ; %if.then7
                                        ;   in Loop: Header=BB32_2 Depth=1
	call	_OUTLINED_FUNCTION_7
	add	hl,bc
	jr	LBB32_2
LBB32_5:                                ; %if.end24
	ld	hl,8
	ld	de,_msg_rc702
	call	_compare_6bytes
	or	a
	jr	nz,LBB32_7
; %bb.6:                                ; %if.then29
	ld	hl,0
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	de
	pop	iy
	call	__call_iy
LBB32_7:                                ; %do.body31
	ld	hl,L__str_6
	ld	de,30928
	ld	bc,16
	jr	LBB32_13
LBB32_8:                                ; %if.end
	ld	bc,65504
	call	_OUTLINED_FUNCTION_7
	add	hl,bc
	ld	de,L__str_3
	call	_check_sysfile
	or	a
	jr	nz,LBB32_12
; %bb.9:                                ; %if.then12
	call	_OUTLINED_FUNCTION_1
	ld	(_boot_dir),bc
	ld	a,(bc)
	or	a
	jr	z,LBB32_12
; %bb.10:                               ; %land.lhs.true
	call	_OUTLINED_FUNCTION_7
	ld	de,L__str_4
	call	_check_sysfile
	or	a
	jr	nz,LBB32_12
; %bb.11:                               ; %if.then21
	call	_floppy_legacy_boot
LBB32_12:                               ; %do.body
	ld	hl,L__str_5
	ld	de,30928
	ld	bc,21
LBB32_13:                               ; %do.body
	ldir
	call	_halt_forever
                                        ; -- End function
_OUTLINED_FUNCTION_0:                   ; -- Begin function OUTLINED_FUNCTION_0
                                        ; @OUTLINED_FUNCTION_0
; %bb.0:
	srl	b
	rr	c
	srl	b
	rr	c
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_1:                   ; -- Begin function OUTLINED_FUNCTION_1
                                        ; @OUTLINED_FUNCTION_1
; %bb.0:
	ld	c,(ix+-2)
	ld	b,(ix+-1)
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_2:                   ; -- Begin function OUTLINED_FUNCTION_2
                                        ; @OUTLINED_FUNCTION_2
; %bb.0:
	add	a,255
	sbc	a,a
	and	1
	xor	1
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_3:                   ; -- Begin function OUTLINED_FUNCTION_3
                                        ; @OUTLINED_FUNCTION_3
; %bb.0:
	ld	bc,_fdc_cmd+1
	ld	a,(ix+-2)
	ld	(bc),a
	ld	hl,0
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_4:                   ; -- Begin function OUTLINED_FUNCTION_4
                                        ; @OUTLINED_FUNCTION_4
; %bb.0:
	ld	(ix+-6),l
	ld	(ix+-5),h
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_5:                   ; -- Begin function OUTLINED_FUNCTION_5
                                        ; @OUTLINED_FUNCTION_5
; %bb.0:
	ld	(ix+-2),e
	ld	(ix+-1),d
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_6:                   ; -- Begin function OUTLINED_FUNCTION_6
                                        ; @OUTLINED_FUNCTION_6
; %bb.0:
	ld	(ix+-2),c
	ld	(ix+-1),b
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_7:                   ; -- Begin function OUTLINED_FUNCTION_7
                                        ; @OUTLINED_FUNCTION_7
; %bb.0:
	ld	l,(ix+-2)
	ld	h,(ix+-1)
	ret
                                        ; -- End function
_OUTLINED_FUNCTION_8:                   ; -- Begin function OUTLINED_FUNCTION_8
                                        ; @OUTLINED_FUNCTION_8
; %bb.0:
	ld	(ix+-2),l
	ld	(ix+-1),h
	ret
                                        ; -- End function
	SECTION	rodata_compiler
_eot_gap3_table:                        ; @eot_gap3_table
	DEFB	26                              ; 0x1a
	DEFB	7                               ; 0x7
	DEFB	52                              ; 0x34
	DEFB	7                               ; 0x7
	DEFB	15                              ; 0xf
	DEFB	14                              ; 0xe
	DEFB	26                              ; 0x1a
	DEFB	14                              ; 0xe
	DEFB	8                               ; 0x8
	DEFB	27                              ; 0x1b
	DEFB	15                              ; 0xf
	DEFB	27                              ; 0x1b
	DEFS	2
	DEFB	8                               ; 0x8
	DEFB	53                              ; 0x35
	DEFB	16                              ; 0x10
	DEFB	7                               ; 0x7
	DEFB	32                              ; 0x20
	DEFB	7                               ; 0x7
	DEFB	9                               ; 0x9
	DEFB	14                              ; 0xe
	DEFB	16                              ; 0x10
	DEFB	14                              ; 0xe
	DEFB	5                               ; 0x5
	DEFB	27                              ; 0x1b
	DEFB	9                               ; 0x9
	DEFB	27                              ; 0x1b
	DEFS	2
	DEFB	5                               ; 0x5
	DEFB	53                              ; 0x35

	SECTION	bss_compiler
	GLOBAL	_is_mini
_is_mini:
	DEFS	1
	GLOBAL	_fdc_cmd
_fdc_cmd:
	DEFS	7
	GLOBAL	_is_mfm
_is_mfm:
	DEFS	1
	GLOBAL	_disk_type
_disk_type:
	DEFS	1
	GLOBAL	_dma_transfer_size
_dma_transfer_size:
	DEFS	2
	GLOBAL	_fdc_result
_fdc_result:
	DEFS	8
	GLOBAL	_error_saved
_error_saved:
	DEFS	1
	GLOBAL	_floppy_operation_completed_flag
_floppy_operation_completed_flag:
	DEFS	1
	GLOBAL	_drive_select
_drive_select:
	DEFS	1
	GLOBAL	_retry_count
_retry_count:
	DEFS	1
_saved_fdc_command:
	DEFS	1
	GLOBAL	_dma_transfer_address
_dma_transfer_address:
	DEFS	2
	GLOBAL	_fdc_isr_delay
_fdc_isr_delay:
	DEFS	1
	GLOBAL	_fdc_result_delay
_fdc_result_delay:
	DEFS	1
	GLOBAL	_more_tracks_to_read
_more_tracks_to_read:
	DEFS	1
	GLOBAL	_bytes_left_to_read
_bytes_left_to_read:
	DEFS	2
	SECTION	rodata_compiler
L__str:                                 ; @.str
	DEFM	"**DISKETTE ERROR** \000"

	SECTION	rodata_compiler
_msg_rc702:                             ; @msg_rc702
	DEFM	" RC702\000"

	SECTION	rodata_compiler
L__str_1:                               ; @.str.1
	DEFM	" **NO DISKETTE NOR LINEPROG** \000"

	SECTION	rodata_compiler
	GLOBAL	_code_end                       ; @code_end
_code_end:
	DEFB	255                             ; 0xff

	SECTION	bss_compiler
_is_double_sided:
	DEFS	1
	SECTION	rodata_compiler
_sem702_font:                           ; @sem702_font
	DEFM	"\000\000\b\b\000\b\b\b\000\b\b\001@\001@\000\000A\000\001@\000\000A\b\b\001@\b\b\000\034\000\017p\177\000\017p\177\000\017p\177\000\017p\177"
	DEFM	"\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000"
	DEFM	"\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\000\b\b\000\b\b\b\000\b\b\002 \002 \000"
	DEFM	"\000\"\000\002 \000\000\"\b\b\001@\b\b\000\034\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177"
	DEFM	"\024\b\036\034\036>><\"\034 \"\002\"\">\036\034\036\034>\"\"\"\"\"><\034\034\b\000\000\017p\177\000\017p\177\000\017p\177\000\017p\177"
	DEFM	"\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\000\b\b\000\b\b\b\000\b\b\002 \004\020\000\000\034\000\004\020\000\000\"\b\b\002 \034\0346\b"
	DEFM	"\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\024$\"$\002\002\002\"\b \022\0026&\""
	DEFM	"\"\"\"\"\b\"\"\"\"\" \n\"\024\034\000\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177\000\017p\177"
	DEFM	"\000\000\b\b\000\b\b\b\000\b\b\004\020\030\f\000\000\000\000\b\b\000\000\024\b\b\002 >>6k\000\000\000\000\017\017\017\017pppp\177\177\177\177"
	DEFM	"\000\000\000\000\017\017\017\017pppp\177\177\177\177\"\"$\002$\002\002\002\"\b \n\002**\"\"\"\"\002\b\"\"\"\024\024\020\n2>*\000"
	DEFM	"\000\000\000\000\017\017\017\017pppp\177\177\177\177\000\000\000\000\017\017\017\017pppp\177\177\177\177\000\000\b\b\000\b\b\b\000\b\b\004\020 \002\000"
	DEFM	"\000\000\000\020\004\000\000\024\b\b\004\020\177\177\177\177\000\000\000\000\017\017\017\017pppp\177\177\177\177\000\000\000\000\017\017\017\017pppp\177\177\177\177"
	DEFM	"\"\"\034\002$\016\0162>\b \006\002*2\"\036\"\036\034\b\"\024\"\b\b\b\036*\"\b\000\000\000\000\000\017\017\017\017pppp\177\177\177\177"
	DEFM	"\000\000\000\000\017\017\017\017pppp\177\177\177\177x\017x\017\177\017x\177\177\b\177\b\b@\001\001@\000\000`\003\003`\b\004\020\004\020>\177\177k"
	DEFM	"\000\000\000\000\017\017\017\017pppp\177\177\177\177\000\000\000\000\017\017\017\017pppp\177\177\177\1772>$\002$\002\002\"\"\b \n\002\"\"\""
	DEFM	"\002*\n \b\"\024*\024\b\004\n&>\b\000\000\000\000\000\017\017\017\017pppp\177\177\177\177\000\000\000\000\017\017\017\017pppp\177\177\177\177"
	DEFM	"\b\b\000\000\b\b\b\000\000\b\b\020\004\000\000\002 \000\000\000\000\004\020\024\004\020\b\b\034\177>\b\000\000\000\000\017\017\017\017pppp\177\177\177\177"
	DEFM	"\000\000\000\000\017\017\017\017pppp\177\177\177\177.\"$\"$\002\002\"\"\b\"\022\002\"\"\"\002\022\022\"\b\"\b6\"\b\002\n\"\"\b\000"
	DEFM	"\000\000\000\000\017\017\017\017pppp\177\177\177\177\000\000\000\000\017\017\017\017pppp\177\177\177\177\b\b\000\000\b\b\b\000\000\b\b\020\004\000\000\004"
	DEFM	"\020\000\000\000\000\b\b\024\002 \b\b\034*\034\b\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017"
	DEFM	" \"\036\034\036>\002<\"\034\034\">\"\">\002,\"\034\b\034\b\"\"\b>:\034\"\b\000pppppppppppppppp"
	DEFM	"\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177\b\b\000\000\b\b\b\000\000\b\b \002\000\000\030\f\000\034\000\000\020\004\"\002 \b\b\b\b\b\034"
	DEFM	"\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000"
	DEFM	"\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\177pppppppppppppppp\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177"
	DEFM	"\b\b\000\000\b\b\b\000\000\b\b \002\000\000 \002\000\"\000\000 \002\"\001@\b\b\b\034\b\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000"
	DEFM	"\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000"
	DEFM	"pppppppppppppppp\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177\b\b\000\000\b\b\b\000\000\b\b@\001\000\000@"
	DEFM	"\001\000A\000\000@\001A\001@\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017\017"
	DEFM	"\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000pppppppppppppppp"
	DEFM	"\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177\177"

	SECTION	rodata_compiler
_display_sw1_status_prefix:             ; @display_sw1_status.prefix
	DEFM	"SW1 12345678: \000"

	SECTION	rodata_compiler
_qr_screen:                             ; @qr_screen
	DEFM	"7s353.xt17s355/%5%%7:%5/%5ss#119%iu#s31}fk&y>te`"
	DEFM	".pr cpwq\"#w(|=7}$!$).sk=d?,|607s35*a%9uq=b55/%5="
	DEFM	".|0\"m7>!###!# #! \"##!"

	SECTION	rodata_compiler
L__str_2:                               ; @.str.2
	DEFM	" RC700\000"

	SECTION	bss_compiler
_boot_dir:
	DEFS	2
	SECTION	rodata_compiler
L__str_3:                               ; @.str.3
	DEFM	"SYSM\000"

L__str_4:                               ; @.str.4
	DEFM	"SYSC\000"

L__str_5:                               ; @.str.5
	DEFM	" **NO SYSTEM FILES** \000"

L__str_6:                               ; @.str.6
	DEFM	" **NO KATALOG** \000"

	EXTERN	___z80_memset_builtin
	EXTERN	__call_iy
	EXTERN	_banner_string
	EXTERN	_llvm_memcpy_p0_p0_i16
	EXTERN	_llvm_memset_p0_i16
	EXTERN	_llvm_uadd_with_overflow_i8
