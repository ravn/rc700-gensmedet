;; sem702-raster/bench.asm -- SEM702 wait-state mikrobench.
;;
;; Measures effective T-states per OUT to the AWR port (D3) under two
;; conditions:
;;   Mode 0 (blank): screen filled with glyph 0 (blank); glyph 65 NEVER
;;                   read by 8275 during the bench.  Baseline.
;;   Mode 1 (contended): screen filled with glyph 65; while we hammer
;;                       glyph 65 line 5 via OUT (D3), 8275 is reading
;;                       SAME location for every visible cell.  If the
;;                       SEM702 board inserts wait-states under read/
;;                       write contention, mode 1 takes MORE frames
;;                       than mode 0 for the same M iterations.
;;
;; Methodology per mode:
;;   A: BASELINE loop -- M iterations of [nop nop / dec bc / ld a,b /
;;      or c / jr nz].  Times the loop overhead alone.
;;   B: AWR loop     -- same but [out (D3),a] instead of [nop nop].
;;
;; Wait-state inference per mode:
;;   T per OUT (D3) = (B_frames - A_frames) * 80000 / M + (OUT_baseline_T)
;;   With M=20000 and 1 wait-state ~= 0.5 frame at 4 MHz / 50 Hz.
;;
;; *** MAME caveat ***
;; MAME's 8275 model is functional, not cycle-accurate, and the SEM702
;; add-on board (custom TTL latches + 2 KB SRAM piggybacked on ic82
;; chargen-ROM socket + ic68 DMA socket) is NOT modelled at all.  Any
;; wait-state delta MAME reports here is an artifact of its emulation,
;; not a hardware measurement.  This .COM exists to be RUN ON PHYSICAL
;; HARDWARE -- the lua harness validates the methodology + result-table
;; readback; the numbers only matter from the real RC702 console
;; (read result table from RAM via the MP/M debug link or transcribe
;; from a hexdump utility).
;;
;; Visual: during mode-1 bench, every visible cell shows glyph 65 whose
;; line 5 is being rewritten ~10x per scan-line.  Stripe pattern on the
;; 10 stable lines (set before bench), random/torn pattern on line 5.
;; On real hardware that's the visual contention test.

        .Z80
        ORG     0100h

ACHAR   EQU     0D1h
ALINE   EQU     0D2h
AWR     EQU     0D3h
VRAM    EQU     0F800h

BENCH_M EQU     20000           ; iterations per bench pass

;;; =====================================================================
;;; Entry
;;; =====================================================================
start:
        di

        ;; Install our display ISR, chained to BIOS handler.  Same pattern
        ;; as raster.asm: read I register, slot at I*256+0x04 (CTC1 ch.2).
        ld      a, i
        ld      (i_reg_save), a
        ld      h, a
        ld      l, 004h
        ld      (ivt_ptr), hl

        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      (saved_disint), de
        ld      (isr_chain + 1), de

        ld      hl, (ivt_ptr)
        ld      de, isr
        ld      (hl), e
        inc     hl
        ld      (hl), d

        call    init_vram_blank
        call    blank_all_glyphs
        call    preload_glyph65    ; stripe pattern except line 5

        ;; Pre-set ACHAR=65, ALINE=5 so the bench loop only does AWR writes.
        ld      a, 65
        out     (ACHAR), a
        ld      a, 5
        out     (ALINE), a

        xor     a
        ld      (tick_lo), a
        ld      (tick_hi), a

        ei

        ;; Settle a few frames so any pending IRQ noise drains.
        call    wait_8_frames

;;; ---- Mode 0: blank screen ----
        call    fill_vram_glyph0
        call    wait_8_frames

        ld      hl, mode0_a
        call    bench_baseline
        ld      hl, mode0_b
        call    bench_awr

;;; ---- Mode 1: full screen of glyph 65 (CONTENDED) ----
        call    fill_vram_glyph65
        call    wait_8_frames

        ld      hl, mode1_a
        call    bench_baseline
        ld      hl, mode1_b
        call    bench_awr

;;; Restore + warm boot.
        di
        ld      hl, (ivt_ptr)
        ld      de, (saved_disint)
        ld      (hl), e
        inc     hl
        ld      (hl), d
        ei

        ;; Sit for ~2 s so lua has time to read results before warm-boot
        ;; clobbers our TPA.
        ld      bc, 100
.r_settle:
        push    bc
        ei
        halt
        pop     bc
        dec     bc
        ld      a, b
        or      c
        jr      nz, .r_settle

        jp      0

;;; =====================================================================
;;; ISR -- bump 16-bit tick counter, JP to BIOS handler.
;;; =====================================================================
isr:
        ;; The BIOS chained handler is allowed to clobber any register; we
        ;; need BC preserved (the bench loop's count) so save the lot.
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, tick_lo
        inc     (hl)
        jr      nz, .i_no_carry
        inc     hl
        inc     (hl)
.i_no_carry:
        pop     hl
        pop     de
        pop     bc
        pop     af
isr_chain:
        jp      0000h

;;; =====================================================================
;;; wait_8_frames -- HALT 8 times.
;;; =====================================================================
wait_8_frames:
        ld      b, 8
.w_loop:
        halt
        djnz    .w_loop
        ret

;;; =====================================================================
;;; bench_baseline -- M iterations of [nop nop / dec bc / loop tail].
;;; Saves frame delta to (HL), (HL+1) as little-endian 16-bit count.
;;; =====================================================================
bench_baseline:
        push    hl
        di
        ld      a, (tick_lo)
        ld      e, a
        ld      a, (tick_hi)
        ld      d, a
        ei

        ld      bc, BENCH_M
.bb_loop:
        nop
        nop
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bb_loop

        di
        ld      a, (tick_lo)
        ld      l, a
        ld      a, (tick_hi)
        ld      h, a
        or      a
        sbc     hl, de
        ex      de, hl
        pop     hl
        ld      (hl), e
        inc     hl
        ld      (hl), d
        ei
        ret

;;; =====================================================================
;;; bench_awr -- M iterations of [out (D3),a / dec bc / loop tail].
;;; =====================================================================
bench_awr:
        push    hl
        di
        ld      a, (tick_lo)
        ld      e, a
        ld      a, (tick_hi)
        ld      d, a
        ei

        ld      bc, BENCH_M
.ba_loop:
        out     (AWR), a
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ba_loop

        di
        ld      a, (tick_lo)
        ld      l, a
        ld      a, (tick_hi)
        ld      h, a
        or      a
        sbc     hl, de
        ex      de, hl
        pop     hl
        ld      (hl), e
        inc     hl
        ld      (hl), d
        ei
        ret

;;; =====================================================================
;;; init_vram_blank: GPA0 attr + clear screen to glyph 0.
;;; =====================================================================
init_vram_blank:
        ld      a, 084h
        ld      (VRAM), a
        ld      hl, VRAM + 1
        ld      de, VRAM + 2
        ld      bc, 80 * 25 - 2
        ld      (hl), 0
        ldir
        ret

;;; =====================================================================
;;; fill_vram_glyph0: every cell = code 0 (blank).  (0,0) stays 0x84.
;;; =====================================================================
fill_vram_glyph0:
        ld      hl, VRAM + 1
        ld      de, VRAM + 2
        ld      bc, 80 * 25 - 2
        ld      (hl), 0
        ldir
        ret

;;; =====================================================================
;;; fill_vram_glyph65: every cell = code 65 (max contention).
;;; =====================================================================
fill_vram_glyph65:
        ld      hl, VRAM + 1
        ld      de, VRAM + 2
        ld      bc, 80 * 25 - 2
        ld      (hl), 65
        ldir
        ret

;;; =====================================================================
;;; blank_all_glyphs: zero all 128 x 11 SEM702 cells.
;;; =====================================================================
blank_all_glyphs:
        ld      d, 0
.bag_outer:
        ld      a, d
        out     (ACHAR), a
        ld      c, 11
        ld      e, 0
.bag_inner:
        ld      a, e
        out     (ALINE), a
        xor     a
        out     (AWR), a
        inc     e
        dec     c
        jr      nz, .bag_inner
        inc     d
        ld      a, d
        cp      128
        jr      nz, .bag_outer
        ret

;;; =====================================================================
;;; preload_glyph65: lines 0..4 + 6..10 = 0xAA (stripe), line 5 = 0x00.
;;; The bench will overwrite line 5 with junk; the 10 stripe lines stay
;;; stable, so a snapshot shows a frame of stable horizontal stripes
;;; with one ragged middle band (line 5) on every visible cell.
;;; =====================================================================
preload_glyph65:
        ld      a, 65
        out     (ACHAR), a
        ld      e, 0
.pg_loop:
        ld      a, e
        out     (ALINE), a
        cp      5
        jr      z, .pg_blank
        ld      a, 0AAh
        jr      .pg_wr
.pg_blank:
        xor     a
.pg_wr:
        out     (AWR), a
        inc     e
        ld      a, e
        cp      11
        jr      nz, .pg_loop
        ret

;;; =====================================================================
;;; Variables (results last so they're at predictable offsets)
;;; =====================================================================
saved_disint:   dw      0
ivt_ptr:        dw      0
i_reg_save:     db      0
tick_lo:        db      0
tick_hi:        db      0

results_base:
mode0_a:        dw      0
mode0_b:        dw      0
mode1_a:        dw      0
mode1_b:        dw      0
