#!/usr/bin/env python3
"""Print expected 33-byte results vector for the corpus test."""

expected = [
    # sw_dense(0..3, 99)
    10, 20, 30, 40, 0,
    # djnz_count(1, 5, 255)
    1, 5, 255,
    # seq_bss -> bss_buf[0..3]
    0x11, 0x22, 0x33, 0x44,
    # mul_8x8(0,0)=0, (3,7)=21, (15,17)=255, (255,255)=65025 — lo/hi
    0, 0,
    21, 0,
    255, 0,
    1, 0xFE,
    # set_flag(0,1,99) -> flag
    0, 1, 1,
    # copy8 sum 1..8 = 36
    36,
    # test_bit3(0, 0x08, 0xFF)
    0, 1, 1,
    # fill_buf -> bss_buf[0], bss_buf[7]
    0xAA, 0xAA,
    # is_ff(0, 0xFE, 0xFF)
    0, 0, 1,
    # sentinel
    0xA5,
]

print(' '.join(f'{b:02x}' for b in expected))
