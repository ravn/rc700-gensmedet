#!/usr/bin/env python3
"""patch_prom_checksum.py <prom.bin>

Pads prom.bin to 2047 bytes with 0xFF, then appends one checksum byte at
0x07FF such that XOR of all 2048 bytes equals 0xA5.

The PROM code (check_prom_integrity in rom.c) reads 2048 bytes from address
0x0000 (the physical PROM, still mapped before prom_disable()), XORs them,
and halts with **PROM CHECKSUM ERROR** if the result is not 0xA5.

0xA5 is chosen because a blank (all-0xFF) EPROM gives XOR=0x00, which
would falsely pass a 0x00 target.
"""

import sys

PROM_SIZE = 2048
MAGIC     = 0xA5

path = sys.argv[1]
data = open(path, 'rb').read()
n = len(data)

if n > PROM_SIZE - 1:
    sys.exit(f"ERROR: {path} is {n} bytes, no room for checksum byte at 0x07FF")

padded = data + bytes([0xFF] * (PROM_SIZE - 1 - n))
xor_val = 0
for b in padded:
    xor_val ^= b
chk = xor_val ^ MAGIC

full = padded + bytes([chk])
assert len(full) == PROM_SIZE
assert (xor_val ^ chk) == MAGIC

open(path, 'wb').write(full)
print(f"  checksum 0x{chk:02X} patched at 0x07FF  "
      f"(payload {n} B, {PROM_SIZE-1-n} B padding, XOR of all {PROM_SIZE} B = 0x{MAGIC:02X})")
