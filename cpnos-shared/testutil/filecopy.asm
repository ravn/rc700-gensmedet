; filecopy.asm — CP/NOS file-I/O bench (read + write over CP/NET).
;
; Reads SUMTEST.ASM (staged on master drive A:) record-by-record via
; BDOS F_READ, writes each record back to SUMTEST.CPY via BDOS F_WRITE.
; Wire shape: ~360 CP/NET read RTTs followed by ~360 write RTTs for a
; ~46 KB sumtest source.  Pure file-I/O, no m80/l80 in the timed window.
;
; Pass criterion (host-side, post-run):
;   1. slave printed "FILECOPY OK <hex_count>" before warm-boot
;   2. cpmcp-extracted SUMTEST.CPY is byte-identical to SUMTEST.ASM
;
; Pre-assembled on the host with `zmac --dri filecopy.asm` and staged
; as 0:FILECOPY.COM in cpnetsmk-1.dsk by mksmokedisk.sh.

BDOS    equ     0005h
CONOUT  equ     2
PRINTS  equ     9
F_OPEN  equ     15
F_CLOSE equ     16
F_DELETE equ    19
F_READ  equ     20
F_WRITE equ     21
F_MAKE  equ     22
SETDMA  equ     26

        aseg
        org     0100h

FRAMES  equ     0fffch          ; cpnos isr_crt 32-bit frame counter (50 Hz)

start:
        ; Snapshot frame counter at entry (4 bytes from 0xFFFC).
        lhld    FRAMES
        shld    FRM_START
        lhld    FRAMES+2
        shld    FRM_START+2

        ; DMA buffer for reads + writes.
        lxi     d, BUFFER
        mvi     c, SETDMA
        call    BDOS

        ; Open SUMTEST.ASM.  Returns A=0xFF if not found.
        lxi     d, SRC_FCB
        mvi     c, F_OPEN
        call    BDOS
        cpi     0ffh
        jz      no_src

        ; Best-effort delete of any prior SUMTEST.CPY (ignore result).
        lxi     d, DST_FCB
        mvi     c, F_DELETE
        call    BDOS

        ; Make SUMTEST.CPY.  Returns A=0xFF if directory full.
        lxi     d, DST_FCB
        mvi     c, F_MAKE
        call    BDOS
        cpi     0ffh
        jz      no_dst

        ; HL = record counter, starts at 0.
        lxi     h, 0
        shld    REC_COUNT

cp_loop:
        lxi     d, SRC_FCB
        mvi     c, F_READ
        call    BDOS
        ora     a               ; 0=ok, 1=EOF, other=error → end either way
        jnz     done

        lxi     d, DST_FCB
        mvi     c, F_WRITE
        call    BDOS
        ora     a
        jnz     wr_err

        lhld    REC_COUNT
        inx     h
        shld    REC_COUNT
        jmp     cp_loop

done:
        lxi     d, SRC_FCB
        mvi     c, F_CLOSE
        call    BDOS

        lxi     d, DST_FCB
        mvi     c, F_CLOSE
        call    BDOS

        ; Snapshot frame counter at finish.
        lhld    FRAMES
        shld    FRM_END
        lhld    FRAMES+2
        shld    FRM_END+2

        ; Print "FILECOPY OK " <records-hex16> " S=" <start-hex32>
        ;       " E=" <end-hex32> CRLF.  Harness greps for FILECOPY OK
        ;       and computes frames = E - S (32-bit, mod 2^32).
        lxi     d, msg_ok
        mvi     c, PRINTS
        call    BDOS

        lhld    REC_COUNT
        call    print_hl16

        lxi     d, msg_s
        mvi     c, PRINTS
        call    BDOS
        lhld    FRM_START+2
        call    print_hl16
        lhld    FRM_START
        call    print_hl16

        lxi     d, msg_e
        mvi     c, PRINTS
        call    BDOS
        lhld    FRM_END+2
        call    print_hl16
        lhld    FRM_END
        call    print_hl16

        lxi     d, msg_crlf
        mvi     c, PRINTS
        call    BDOS

        jmp     0               ; warm boot

; print_hl16 — print HL as 4 hex digits.
print_hl16:
        push    h
        mov     a, h
        rrc
        rrc
        rrc
        rrc
        call    pnib
        mov     a, h
        call    pnib
        mov     a, l
        rrc
        rrc
        rrc
        rrc
        call    pnib
        mov     a, l
        call    pnib
        pop     h
        ret

no_src:
        lxi     d, msg_no_src
        jmp     err_print
no_dst:
        lxi     d, msg_no_dst
        jmp     err_print
wr_err:
        lxi     d, msg_wr_err
err_print:
        mvi     c, PRINTS
        call    BDOS
        jmp     0

pnib:
        ani     0fh
        adi     '0'
        cpi     '9'+1
        jc      pok
        adi     7
pok:
        push    h
        push    b
        mov     e, a
        mvi     c, CONOUT
        call    BDOS
        pop     b
        pop     h
        ret

msg_ok:     db      'FILECOPY OK $'
msg_s:      db      ' S=$'
msg_e:      db      ' E=$'
msg_crlf:   db      0dh, 0ah, '$'
msg_no_src: db      'ERR: open SUMTEST.ASM failed', 0dh, 0ah, '$'
msg_no_dst: db      'ERR: make SUMTEST.CPY failed', 0dh, 0ah, '$'
msg_wr_err: db      'ERR: write failed', 0dh, 0ah, '$'

REC_COUNT:  dw      0
FRM_START:  ds      4
FRM_END:    ds      4

SRC_FCB:    db      1                       ; drive A:
            db      'SUMTEST '               ; 8 chars padded
            db      'ASM'                    ; 3-char ext
            ds      24                       ; rest of FCB zeroed at load

DST_FCB:    db      1
            db      'SUMTEST '
            db      'CPY'
            ds      24

BUFFER:     ds      128

            end
