#!/usr/bin/env python3
"""Pad a binary file to a target size with 0xFF (EPROM erased state).

Usage: pad_rom.py <input.bin> <target_bytes> <output.bin>

Errors out if the input is already larger than target_bytes.
"""

import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(f"usage: {argv[0]} <input.bin> <target_bytes> <output.bin>",
              file=sys.stderr)
        return 2

    src = Path(argv[1])
    target = int(argv[2], 0)
    dst = Path(argv[3])

    data = src.read_bytes()
    if len(data) > target:
        print(f"error: {src} is {len(data)} B, exceeds target {target} B",
              file=sys.stderr)
        return 1

    padded = data + b"\xff" * (target - len(data))
    dst.write_bytes(padded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
