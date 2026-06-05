;; sem702-raster -- minimal "is the SEM702 pipeline working?" demo.
;;
;; Validates pre-variant-A (single phase, no race-the-beam yet):
;;   - ISR install at IVT slot 0x14 (CTC ch.2 / display IRQ)
;;   - GPA0=1 field attribute -> SEM702 chargen routes per cell
;;   - OUT D1/D2/D3 sequence loads SEM702 RAM correctly
;;   - HALT + EI + RETI frame sync from the 50 Hz display IRQ
;;
;; If you see 4 distinct moving patterns in cells (row 10, cols 30..33),
;; the full pipeline works.  Glyphs 1..4 are each reprogrammed every frame:
;;   1: 0x55 / 0xAA stripes scrolling vertically (~25 Hz)
;;   2: full on/off blink (~3 Hz)
;;   3: single-bit diagonal sweep
;;   4: line counter (line N = counter + N)
;;
;; Runtime: 500 frames (~10 s @ 50 Hz) then warm boot back to CCP.

        .Z80
        ORG     0100h

ACHAR   EQU     0D1h            ; SEM702: character index
ALINE   EQU     0D2h            ; SEM702: dot line index
AWR     EQU     0D3h            ; SEM702: pixel data byte

VRAM    EQU     0F800h          ; RC702 display memory (CP/M-context)

NUM_FRAMES EQU  500             ; ~10 s @ 50 Hz

;;; =====================================================================
;;; Entry
;;; =====================================================================
start:
        di

        ;; Find the IVT at runtime via the I register, then locate the
        ;; CTC ch.2 (display) slot.  rcbios sets the CTC1 base vector to
        ;; 0x00, so ch.2 lands at offset 0x04.  (The autoload PROM IVT
        ;; uses base 0x10 -> offset 0x14, hence the CLAUDE.md table; that
        ;; layout is NOT in effect in CP/M context.)
        ld      a, i                    ; A = I register (high byte of IVT base)
        ld      (i_reg_save), a
        ld      h, a
        ld      l, 004h                 ; HL = IVT_base + 0x04 (CTC1 ch.2)
        ld      (ivt_disint_ptr), hl

        ;; Save the original display ISR vector so we can restore on exit.
        ;; Also patch our ISR's tail-JP to chain to the BIOS handler -- the
        ;; BIOS ISR reprograms DMA ch.2 every frame; if we don't keep it
        ;; alive the next BRDY never fires and HALT hangs forever.
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = original ISR address
        ld      (saved_disint), de
        ld      (isr_chain + 1), de

        ;; Patch IVT slot to our ISR.
        ld      hl, (ivt_disint_ptr)
        ld      de, isr
        ld      (hl), e
        inc     hl
        ld      (hl), d

        call    init_vram
        call    blank_all_glyphs

        xor     a
        ld      (frame_tick), a
        ld      (frame_counter), a

        ei

        ;; Main loop: wait for next frame tick, advance animation, reprogram.
        ld      bc, NUM_FRAMES
mainloop:
        push    bc

        ld      a, (frame_tick)
        ld      b, a
.r_wait:
        halt                    ; sleep until next IRQ
        ld      a, (frame_tick)
        cp      b
        jr      z, .r_wait

        ld      hl, frame_counter
        inc     (hl)
        call    reprogram_4

        pop     bc
        dec     bc
        ld      a, b
        or      c
        jr      nz, mainloop

        ;; Restore original display ISR and warm-boot.
        di
        ld      hl, (ivt_disint_ptr)
        ld      de, (saved_disint)
        ld      (hl), e
        inc     hl
        ld      (hl), d
        ei
        jp      0

;;; =====================================================================
;;; Display ISR -- bump frame_tick, then JP into BIOS's original handler
;;; (which does the DMA refresh + its own EI/RETI).  The JP target is
;;; patched at install time from the saved IVT slot.
;;; =====================================================================
isr:
        push    af
        push    hl
        ld      hl, frame_tick
        inc     (hl)
        pop     hl
        pop     af
isr_chain:
        jp      0000h           ; operand patched to original BIOS ISR addr

;;; =====================================================================
;;; init_vram: blank screen, set GPA0 field-attr, place 4 anchor cells.
;;; =====================================================================
init_vram:
        ;; Field-attribute 0x84 at (0,0): bit 2 = GPA0 = 1.  Sticky for
        ;; the rest of the screen -> all subsequent cells use SEM702 RAM
        ;; as chargen (instead of ROA327 ROM).  Mirrors qrtest.asm.
        ld      a, 084h
        ld      (VRAM), a

        ;; Clear rest of screen to glyph code 0 (we blank glyph 0 below).
        ld      hl, VRAM + 1
        ld      de, VRAM + 2
        ld      bc, 80 * 25 - 2
        ld      (hl), 0
        ldir

        ;; Place codes 1..4 at row 10, cols 30..33 (centered-ish, easy to see).
        ld      hl, VRAM + 10 * 80 + 30
        ld      (hl), 1
        inc     hl
        ld      (hl), 2
        inc     hl
        ld      (hl), 3
        inc     hl
        ld      (hl), 4
        ret

;;; =====================================================================
;;; blank_all_glyphs: write 0x00 to every SEM702 cell (128 glyphs x 11 lines).
;;; One-time setup; ~22 ms.  Without this, undefined chargen-RAM contents
;;; would show as visible noise behind our 4 anchor cells.
;;; =====================================================================
blank_all_glyphs:
        ld      d, 0                    ; D = glyph code (0..127)
.b_outer:
        ld      a, d
        out     (ACHAR), a
        ld      c, 11                   ; line count
        ld      e, 0                    ; ALINE counter
.b_inner:
        ld      a, e
        out     (ALINE), a
        xor     a
        out     (AWR), a
        inc     e
        dec     c
        jr      nz, .b_inner
        inc     d
        ld      a, d
        cp      128
        jr      nz, .b_outer
        ret

;;; =====================================================================
;;; reprogram_4: reprogram glyphs 1..4 from frame_counter, each frame.
;;; Cost: ~2700 T (~675 us) total -- trivially fits in vblank (3.2 ms).
;;; =====================================================================
reprogram_4:
        ld      a, (frame_counter)
        ld      d, a                    ; D = counter, preserved across glyphs

;;; --- Glyph 1: 0x55 / 0xAA stripes scrolling vertically ---
        ld      a, 1
        out     (ACHAR), a
        ld      c, 11
        ld      e, 0
.g1:
        ld      a, e
        out     (ALINE), a
        ld      a, e
        add     a, d
        and     1
        jr      nz, .g1_aa
        ld      a, 055h
        jr      .g1_wr
.g1_aa:
        ld      a, 0AAh
.g1_wr:
        out     (AWR), a
        inc     e
        dec     c
        jr      nz, .g1

;;; --- Glyph 2: full on / full off, toggles every 8 frames (~3 Hz) ---
        ld      a, 2
        out     (ACHAR), a
        ld      a, d
        and     8
        jr      nz, .g2_on
        ld      b, 0
        jr      .g2_loop
.g2_on:
        ld      b, 0FFh
.g2_loop:
        ld      c, 11
        ld      e, 0
.g2_l:
        ld      a, e
        out     (ALINE), a
        ld      a, b
        out     (AWR), a
        inc     e
        dec     c
        jr      nz, .g2_l

;;; --- Glyph 3: single-bit diagonal sweep ---
;;; line N pixel = 1 << ((N + counter) & 7)
        ld      a, 3
        out     (ACHAR), a
        ld      c, 11
        ld      e, 0
.g3:
        ld      a, e
        out     (ALINE), a
        ld      a, e
        add     a, d
        and     7                       ; B = shift count; Z set if zero
        ld      b, a
        ld      a, 1
        jr      z, .g3_wr               ; if B=0, pixel = 1<<0 = 1
.g3_sh:
        add     a, a
        djnz    .g3_sh
.g3_wr:
        out     (AWR), a
        inc     e
        dec     c
        jr      nz, .g3

;;; --- Glyph 4: line counter (line N pixel = counter + N) ---
        ld      a, 4
        out     (ACHAR), a
        ld      c, 11
        ld      e, 0
.g4:
        ld      a, e
        out     (ALINE), a
        ld      a, d
        add     a, e
        out     (AWR), a
        inc     e
        dec     c
        jr      nz, .g4

        ret

;;; =====================================================================
;;; Variables
;;; =====================================================================
saved_disint:   dw      0
ivt_disint_ptr: dw      0       ; runtime-computed (I<<8 | 0x14)
i_reg_save:     db      0       ; I register value at entry (for diagnostics)
frame_tick:     db      0
frame_counter:  db      0
