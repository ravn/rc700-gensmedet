#!/usr/bin/env python3
"""bin2inc.py — convert a binary file to a comma-separated C byte
initializer suitable for `#include` inside a `const uint8_t name[] = { ... };`.

Why: SDCC (z88dk-zsdcc) does not implement C23 `#embed`.  Replacing
`#embed "x.bin" if_empty(0)` with `#include "x.inc"` lets both clang
and SDCC consume the same C source, with the per-compiler difference
hidden in the build (each compiler dir generates its own .inc from
its own .bin).

Layout: 16 bytes per line, all-hex (`0x12,`), with a no-op `0,` for
the zero-byte case (mirrors the `if_empty(0)` of the original
`#embed` directives — keeps the surrounding `[]` array initializer
syntactically valid).

Usage:  bin2inc.py INPUT.bin OUTPUT.inc
"""
from __future__ import annotations

import pathlib
import sys


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: bin2inc.py INPUT.bin OUTPUT.inc", file=sys.stderr)
        return 2

    src = pathlib.Path(argv[1])
    dst = pathlib.Path(argv[2])
    data = src.read_bytes()

    if not data:
        # `#embed "x.bin" if_empty(0)` -> a single 0 byte.  Equivalent.
        dst.write_text("0\n")
        return 0

    lines = []
    for offset in range(0, len(data), 16):
        chunk = data[offset:offset + 16]
        lines.append(",".join(f"0x{b:02x}" for b in chunk))
    dst.write_text(",\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
