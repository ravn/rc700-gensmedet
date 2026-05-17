; payload_zx0.asm -- INCBIN wrapper for the ZX0-compressed resident.
; Pass-1 stub points at an empty placeholder so the link can complete
; and we can extract the real resident bytes from the linker output.

    SECTION LINEPROG_ENTRY

    PUBLIC __payload_zx0_start
__payload_zx0_start:
    binary "../sdcc-prom1lineprog/payload.zx0"
