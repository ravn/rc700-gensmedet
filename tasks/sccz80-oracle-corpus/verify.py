#!/usr/bin/env python3
"""Compare each compiler's 33-byte results at 0xC000 against expected."""
import sys

expected = [
    10, 20, 30, 40, 0,
    1, 5, 255,
    0x11, 0x22, 0x33, 0x44,
    0, 0, 21, 0, 255, 0, 1, 0xFE,
    0, 1, 1,
    36,
    0, 1, 1,
    0xAA, 0xAA,
    0, 0, 1,
    0xA5,
]

LABELS = [
    "sw_dense(0)", "sw_dense(1)", "sw_dense(2)", "sw_dense(3)", "sw_dense(99)",
    "djnz_count(1)", "djnz_count(5)", "djnz_count(255)",
    "seq_bss[0]", "seq_bss[1]", "seq_bss[2]", "seq_bss[3]",
    "mul(0,0).lo", "mul(0,0).hi",
    "mul(3,7).lo", "mul(3,7).hi",
    "mul(15,17).lo", "mul(15,17).hi",
    "mul(255,255).lo", "mul(255,255).hi",
    "set_flag(0)", "set_flag(1)", "set_flag(99)",
    "copy8 sum",
    "test_bit3(0)", "test_bit3(0x08)", "test_bit3(0xFF)",
    "fill_buf[0]", "fill_buf[7]",
    "is_ff(0)", "is_ff(0xFE)", "is_ff(0xFF)",
    "sentinel(0xA5)",
]

fail = False
for c in ("zsdcc", "sccz80", "clang"):
    try:
        d = open(f"{c}.ram", "rb").read()
    except FileNotFoundError:
        print(f"{c}: SKIP (no .ram)")
        continue
    got = list(d[0xC000:0xC000 + len(expected)])
    diffs = [(i, LABELS[i], expected[i], got[i]) for i in range(len(expected)) if got[i] != expected[i]]
    if not diffs:
        print(f"{c}: PASS ({len(expected)}/{len(expected)})")
    else:
        fail = True
        print(f"{c}: FAIL ({len(diffs)} divergences)")
        for i, label, exp, g in diffs:
            print(f"  [{i:2}] {label:22} expected=0x{exp:02X}  got=0x{g:02X}")

sys.exit(1 if fail else 0)
