#!/usr/bin/env python3
"""Emit the 384-byte locale-table prefix that the master prepends to
cpnos.img.  The PROM1-only cpnos slave loads cpnos.img at IMG_BASE -
384 so the 384 B prefix lands in the TPA region just below NDOS;
after EOF, the slave LDIRs the prefix into its runtime home at
0xF680..0xF7FF (rcbios-compatible layout, freed by the v3 PROM1-only
linker rearrangement).

Prefix layout (in cpnos.img byte order, == slave memory order after
the LDIR):

    bytes 0..127     outcon[128]   US-ASCII identity (output conversion).
                                   Lands at 0xF680..0xF6FF.
    bytes 128..383   inconv[256]   Danish-keyboard input conversion
                                   (lower 128 identity, upper 128
                                   Danish-specific).  Lands at
                                   0xF700..0xF7FF.

This is the rcbios-compatible layout (see rcbios-in-c/bios.h:85), so
CONFI.COM-style address-based table patching works against the cpnos
slave once it can be loaded onto the slave at runtime.

To switch locales, regenerate the prefix by editing this script to
point at a different rcbios-in-c/locale/*_tables.h source and rerun
cpnos-disk-install.

Usage:
    gen_locale_prefix.py <output.bin>
"""
import os
import re
import sys


SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
DANISH_HDR  = os.path.normpath(os.path.join(
    SCRIPT_DIR, "..", "..", "rcbios-in-c", "locale", "danish_tables.h"))


def parse_byte_blocks(text):
    text_nc = re.sub(r"/\*.*?\*/", "\n", text, flags=re.DOTALL)
    bytes_ = [int(m.group(1), 16)
              for m in re.finditer(r"0x([0-9A-Fa-f]{2})", text_nc)]
    if len(bytes_) % 128 != 0:
        raise SystemExit(f"unexpected byte count {len(bytes_)}")
    return [bytes_[i:i + 128] for i in range(0, len(bytes_), 128)]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen_locale_prefix.py <output.bin>")
    out_path = sys.argv[1]

    with open(DANISH_HDR) as f:
        blocks = parse_byte_blocks(f.read())
    if len(blocks) != 3:
        sys.exit(f"danish_tables.h: expected 3 x 128 B blocks, got {len(blocks)}")
    # blocks[0] = outcon[128]              (Danish outcon -- NOT what we want)
    # blocks[1] = inconv lower[128]        (identity in Danish)
    # blocks[2] = inconv upper[128]        (Danish overrides)

    # outcon = US-ASCII identity (user request: "us-ascii output table for now")
    outcon_us_ascii = bytes(range(128))

    inconv = bytes(blocks[1] + blocks[2])  # 256 B
    prefix = outcon_us_ascii + inconv      # 128 + 256 = 384 B
    assert len(prefix) == 384

    with open(out_path, "wb") as f:
        f.write(prefix)
    print(f"wrote {out_path}: 384 B prefix (128 B US-ASCII outcon + "
          f"256 B Danish inconv)")


if __name__ == "__main__":
    main()
