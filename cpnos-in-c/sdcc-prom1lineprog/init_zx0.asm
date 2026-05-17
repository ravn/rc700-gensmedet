; init_zx0.asm -- INCBIN wrapper for the ZX0-compressed init image.
; Pass-1 stub (empty body) lets the link complete so we can extract
; the real init bytes from the linker output.  Pass 2 regenerates
; this file with `binary "init.zx0"` to embed the actual blob.

    SECTION LINEPROG_ENTRY

    PUBLIC __init_zx0_start
__init_zx0_start:
    binary "../sdcc-prom1lineprog/init.zx0"
