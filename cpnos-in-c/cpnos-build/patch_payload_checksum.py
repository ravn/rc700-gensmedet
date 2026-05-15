#!/usr/bin/env python3
"""Post-link tool: patch payload.bin's last 2 bytes so the 16-bit
WORD-additive sum of the whole file equals 0xCAFE.

Scheme: treat payload.bin as a sequence of little-endian 16-bit
words.  Sum them mod 65536.  The last word is a "correction" set so
the total equals 0xCAFE.

    sum_words(payload.bin) mod 65536 == 0xCAFE

Why words and not bytes: byte-additive sum can be adjusted by at
most 0..510 with two patch bytes, which is not enough to reach an
arbitrary 16-bit target.  Word-additive: one 16-bit correction word
can adjust by any 0..65535.

Why a fixed magic instead of "sum equals stored checksum": the
runtime needs no separate "expected" word — the magic is hardcoded
in the relocator (PAYLOAD_CHECKSUM_MAGIC).  Fewer addresses to
track, fewer places for bugs.

Why 0xCAFE: distinctive in a hex dump (so the operator can verify
the image checksum manually), 16-bit, conventional.  Change it here
AND in relocator.c if you ever want a different magic.

Usage:
    patch_payload_checksum.py <payload.bin>

Reads <payload.bin> (size must be even, >= 4), computes the
word-additive sum of words [0 .. N/2 - 2] (i.e. all words except
the last), writes the correction word at offset N-2..N-1
little-endian so the total word-sum equals 0xCAFE.
"""
from __future__ import annotations
import sys


MAGIC = 0xCAFE


def word_sum(data: bytes) -> int:
    """16-bit additive sum, treating data as little-endian words."""
    if len(data) % 2 != 0:
        raise ValueError("data length must be even")
    total = 0
    for i in range(0, len(data), 2):
        total += data[i] | (data[i + 1] << 8)
    return total & 0xFFFF


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: patch_payload_checksum.py <payload.bin>\n")
        return 2

    path = sys.argv[1]
    with open(path, "rb") as f:
        data = bytearray(f.read())

    if len(data) < 4 or len(data) % 2 != 0:
        sys.stderr.write(
            f"error: {path}: size {len(data)} is not even and >= 4\n")
        return 1

    correction_offset = len(data) - 2
    body_sum = word_sum(bytes(data[:correction_offset]))
    correction = (MAGIC - body_sum) & 0xFFFF

    data[correction_offset]     = correction & 0xFF
    data[correction_offset + 1] = (correction >> 8) & 0xFF

    new_total = word_sum(bytes(data))
    if new_total != MAGIC:
        sys.stderr.write(
            f"BUG: post-patch word-sum 0x{new_total:04X} != magic 0x{MAGIC:04X}\n")
        return 1

    with open(path, "wb") as f:
        f.write(bytes(data))

    print(f"patched {path}: body word-sum = 0x{body_sum:04X}, "
          f"correction = 0x{correction:04X}, total = 0x{new_total:04X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
