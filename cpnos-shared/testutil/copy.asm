; copy.com -- minimal CP/M transient that exercises the canonical
; file-write ABI (MAKE -> READ SEQ / WRITE SEQ / CLOSE).
;
; Usage:  A>COPY DEST SRC
;
; CCP parses "DEST SRC" into FCB1 at 0x005C (DEST) and FCB2 at 0x006C
; (SRC) before passing control to us at 0x0100.  We exercise the
; same BDOS calls PIPNET would, but using a SINGLE FCB pointer per
; file across the MAKE/WRITE (dest) and OPEN/READ (src) sequences
; -- matching the CP/M 2.2 ABI exactly.  If this works against our
; server, PIPNET's failure is a PIPNET-specific deviation rather
; than a server bug.

        org 0100h

bdos    equ 0005h
fcb1    equ 005ch       ; CCP-parsed dest FCB
fcb2    equ 006ch       ; CCP-parsed src FCB
buff    equ 0080h       ; default DMA buffer

; BDOS function numbers
fn_print  equ 9
fn_open   equ 15
fn_close  equ 16
fn_read   equ 20
fn_write  equ 21
fn_make   equ 22
fn_setdma equ 26

start:
        ; NOTE: Don't clear FCB1+12..+35 ourselves -- FCB1 and FCB2
        ; overlap in CP/M page zero (FCB2 at 0x006C lives inside
        ; FCB1's alloc-map territory), so clearing FCB1's dynamic
        ; fields wipes FCB2's name+ext.  CCP leaves ex/cr as zero
        ; after fillfcb's padname pass, which is all MAKE/OPEN need.
        ; Same reason 0x006C..0x0077 also wouldn't be safe to touch.

        ; MAKE destination
        ld c, fn_make
        ld de, fcb1
        call bdos
        inc a                   ; 0xFF -> 0 with Z set
        jp z, fail

        ; OPEN source
        ld c, fn_open
        ld de, fcb2
        call bdos
        inc a
        jp z, fail

loop:
        ; Each record: DMA -> READ src into DMA, WRITE DMA to dest.
        ld c, fn_setdma
        ld de, buff
        call bdos

        ld c, fn_read
        ld de, fcb2
        call bdos
        or a                    ; 0 = record read, 1 = EOF, 0xFF = error
        jr nz, done             ; any non-zero -> stop

        ld c, fn_write
        ld de, fcb1
        call bdos
        or a
        jp nz, fail

        jr loop

done:
        ; Dest side: close so the directory entry flushes.
        ld c, fn_close
        ld de, fcb1
        call bdos

        ld de, msg_ok
        jr print_exit

fail:
        ld de, msg_fail
print_exit:
        ld c, fn_print
        call bdos
        jp 0                    ; warm boot = return to CCP

; Fill B bytes at HL with zero.
clear:
        xor a
clear0:
        ld (hl), a
        inc hl
        djnz clear0
        ret

msg_ok:    db 'COPIED', 13, 10, '$'
msg_fail:  db 'COPY FAILED', 13, 10, '$'

        end start
