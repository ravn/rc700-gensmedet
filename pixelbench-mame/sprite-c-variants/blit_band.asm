;
;   blit_band -- the "assembler stump inner leaf" for the C-outer sprite blit.
;
;   The C outer routine (sprite_or_leaf) owns all the readable structure: it
;   unpacks the sprite, iterates bands, walks the running VRAM base (+80/band),
;   and asserts the gfx page once. For each band it fills a 6-byte block and
;   calls here. This leaf owns ONLY the inner, register-pressure-critical part
;   that llvmz80 cannot express well: it keeps the 3 sprite row bytes resident
;   in B,C,D, builds the 6-bit sextant mask in E, and does the read-modify-write
;   using ONLY A and HL so B,C,D,E survive across the RMW -- exactly the two
;   levers (register-resident mask + A+HL RMW) that a pure-C body spills.
;
;   __z88dk_fastcall, HL -> block:
;       +0 r0   (sprite row byte, band's top row,   MSB = leftmost pixel)
;       +1 r1   (sprite row byte, band's middle row)
;       +2 r2   (sprite row byte, band's bottom row)
;       +3 wcells  (cells to draw across the band = width/2)
;       +4 addr    (word LE: VRAM address of the band's first cell = base+ccol0)
;
        SECTION code_clib

        PUBLIC  blit_band
        PUBLIC  _blit_band
        EXTERN  textpixl

blit_band:
_blit_band:
        ; ---- load the block into registers (B,C,D = rows) ----
        ld      b, (hl)                 ; r0
        inc     hl
        ld      c, (hl)                 ; r1
        inc     hl
        ld      d, (hl)                 ; r2
        inc     hl
        ld      a, (hl)                 ; wcells
        ld      (bl_cnt), a
        inc     hl
        ld      a, (hl)                 ; addr lo
        inc     hl
        ld      h, (hl)                 ; addr hi (reads before H overwritten)
        ld      l, a                    ; HL = current cell VRAM address
        ld      (bl_addr), hl

cellloop:
        ; ---- build the 6-bit cell mask from B,C,D, in-register ----
        ld      e, 0
        sla     b
        jr      nc, l_n0
        set     0, e
l_n0:
        sla     b
        jr      nc, l_n1
        set     1, e
l_n1:
        sla     c
        jr      nc, l_n2
        set     2, e
l_n2:
        sla     c
        jr      nc, l_n3
        set     3, e
l_n3:
        sla     d
        jr      nc, l_n4
        set     4, e
l_n4:
        sla     d
        jr      nc, l_n5
        set     5, e
l_n5:
        ld      a, e
        or      a
        jr      z, nextc                ; empty cell -> skip RMW

        ; ---- RMW at (bl_addr), A+HL only so B,C,D,E survive ----
        ld      hl, (bl_addr)
        ld      a, (hl)                 ; current glyph
        ; reverse-map glyph -> mask (A-only): $20..$3F->0..31, $60..$7F->32..63
        cp      $60
        jr      c, r_low
        cp      $80
        jr      nc, r_zero
        sub     $40
        jr      r_ok
r_low:
        cp      $20
        jr      c, r_zero
        cp      $40
        jr      nc, r_zero
        sub     $20
        jr      r_ok
r_zero:
        xor     a
r_ok:
        or      e                       ; OR in sprite cell mask
        ld      hl, textpixl            ; forward-map mask -> glyph
        add     a, l
        ld      l, a
        jr      nc, f_nc
        inc     h
f_nc:
        ld      a, (hl)
        ld      hl, (bl_addr)
        ld      (hl), a                 ; write glyph

nextc:
        ld      hl, (bl_addr)
        inc     hl                      ; next cell = next VRAM byte
        ld      (bl_addr), hl
        ld      a, (bl_cnt)
        dec     a
        ld      (bl_cnt), a
        jr      nz, cellloop
        ret

        SECTION bss_clib
bl_cnt:  defb 0
bl_addr: defw 0
