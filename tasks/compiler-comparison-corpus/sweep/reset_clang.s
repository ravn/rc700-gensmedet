    .extern __bss_start__
    .extern __bss_end__

    .section .reset, "ax"
    .global _start
_start:
    di
    ld sp, 0xFFFE
    ; Zero BSS — workaround for ravn/llvm-z80#182 (SCEV crash on
    ; explicit zero-init loops at -O1+).  Benchmarks can rely on
    ; zeroed globals without writing init loops in C.
    ld hl, __bss_start__
    ld de, __bss_end__
.bss_clear_loop:
    ld a, l
    cp e
    jr nz, .bss_clear_byte
    ld a, h
    cp d
    jr z, .bss_done
.bss_clear_byte:
    ld (hl), 0
    inc hl
    jr .bss_clear_loop
.bss_done:
    call _main
    ; Safety net: test_main.c traps to ticks inside main() before
    ; returning.  If for any reason main() returns here, hit the
    ; same ED FE trap so ticks still exits cleanly (with whatever
    ; A holds -- harness will see a non-zero exit code).
_done:
    xor a               ; A = CMD_EXIT (0)
    .byte 0xED, 0xFE    ; ticks syscall trap -> cmd_exit -> exit(L)
