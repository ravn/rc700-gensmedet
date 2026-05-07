#!/usr/bin/env python3
"""Assemble a PROM image from one or more byte sources at fixed offsets.

Each source is `OFFSET:PATH`.  Missing source files are silently
skipped (z88dk emits per-section .bin files only when the section
has content — RESIDENT_PRE_CODE may be empty in some configs).
The output is padded to TOTAL_SIZE with 0xFF (EPROM erased state).

Usage:
    build_prom_image.py OUTPUT TOTAL_SIZE OFFSET:PATH [OFFSET:PATH ...]

Errors out if any source overflows its slot or the total image.
"""

import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(f"usage: {argv[0]} OUTPUT TOTAL_SIZE OFFSET:PATH [OFFSET:PATH ...]",
              file=sys.stderr)
        return 2

    out = Path(argv[1])
    total = int(argv[2], 0)
    image = bytearray(b"\xff" * total)

    chunks = []
    for spec in argv[3:]:
        off_str, _, path_str = spec.partition(":")
        if not path_str:
            print(f"error: malformed spec {spec!r}, expected OFFSET:PATH",
                  file=sys.stderr)
            return 2
        chunks.append((int(off_str, 0), Path(path_str)))

    chunks.sort()
    for i, (offset, path) in enumerate(chunks):
        if not path.exists():
            continue
        data = path.read_bytes()
        end = offset + len(data)
        if end > total:
            print(f"error: {path} ({len(data)} B) at offset 0x{offset:X} "
                  f"overflows image size 0x{total:X}", file=sys.stderr)
            return 1
        if i + 1 < len(chunks):
            next_offset = chunks[i + 1][0]
            if end > next_offset:
                print(f"error: {path} ({len(data)} B) at offset 0x{offset:X} "
                      f"overlaps next chunk at 0x{next_offset:X}",
                      file=sys.stderr)
                return 1
        image[offset:end] = data

    out.write_bytes(bytes(image))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
