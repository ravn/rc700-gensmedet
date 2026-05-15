#!/usr/bin/env python3
"""Assemble cpnos PROM1 from z88dk's per-section .bin outputs.

PROM1 layout (2048 bytes total):
  0x000..0x3FF  RESIDENT_PRE_CODE (org 0xEE00) bytes, padded with 0xFF
  0x400..0x7FF  RESIDENT_JUMPTABLE (org 0xF200) bytes, padded with 0xFF

Either input may be missing or empty (z88dk only emits .bin files for
sections that actually have content).

Usage: build_prom1.py <pre_code.bin> <jumptable.bin> <output.bin>
"""

import sys
from pathlib import Path


PROM1_HALF = 0x400


def read_or_empty(path: Path) -> bytes:
    if not path.exists():
        return b""
    return path.read_bytes()


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(f"usage: {argv[0]} <pre_code.bin> <jumptable.bin> <output.bin>",
              file=sys.stderr)
        return 2

    pre = read_or_empty(Path(argv[1]))
    jt = read_or_empty(Path(argv[2]))
    dst = Path(argv[3])

    if len(pre) > PROM1_HALF:
        print(f"error: RESIDENT_PRE_CODE is {len(pre)} B, exceeds {PROM1_HALF} B",
              file=sys.stderr)
        return 1
    if len(jt) > PROM1_HALF:
        print(f"error: RESIDENT_JUMPTABLE is {len(jt)} B, exceeds {PROM1_HALF} B",
              file=sys.stderr)
        return 1

    pre_padded = pre + b"\xff" * (PROM1_HALF - len(pre))
    jt_padded = jt + b"\xff" * (PROM1_HALF - len(jt))
    dst.write_bytes(pre_padded + jt_padded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
