#!/usr/bin/env python3
"""Build a CP/M .COM that mimics cold-boot from the cpnos-rom PROMs.

Layout of the .COM (loads at 0x0100 in TPA):

    0x0100  JP 0x1103            ; hop to stub above the copy zones
    0x0103  prom0 payload (2 KB) ; becomes 0x0000..0x07FF after copy
    0x0903  prom1 payload (2 KB) ; becomes 0x2000..0x27FF after copy
    0x1103  stub:
              di
              ld   hl, 0x0103 ; src = prom0 blob
              ld   de, 0x0000 ; dst = reset vector / page zero
              ld   bc, 0x0800
              ldir            ; dst < src so the overlapping copy is safe
              ld   hl, 0x0903
              ld   de, 0x2000
              ld   bc, 0x0800
              ldir            ; non-overlapping
              jp   0x0000     ; re-enter cpnos reset path

The stub sits above both overwrite regions, so it survives both LDIRs.
PROMs are already disabled at this point (CP/M is running); the underlying
RAM at 0x0000..0x07FF and 0x2000..0x27FF is writable, and the cpnos reset
vector at 0x0000 starts its normal init sequence after we jp there.
"""

import sys

def main(prom0_path, prom1_path, out_path):
    prom0 = open(prom0_path, 'rb').read()
    prom1 = open(prom1_path, 'rb').read()
    if len(prom0) != 2048 or len(prom1) != 2048:
        sys.exit(f"expected 2048-byte PROMs, got {len(prom0)} + {len(prom1)}")

    stub = bytes([
        0xF3,                           # di
        0x21, 0x03, 0x01,               # ld hl, 0x0103
        0x11, 0x00, 0x00,               # ld de, 0x0000
        0x01, 0x00, 0x08,               # ld bc, 0x0800
        0xED, 0xB0,                     # ldir
        0x21, 0x03, 0x09,               # ld hl, 0x0903
        0x11, 0x00, 0x20,               # ld de, 0x2000
        0x01, 0x00, 0x08,               # ld bc, 0x0800
        0xED, 0xB0,                     # ldir
        0xC3, 0x00, 0x00,               # jp 0x0000
    ])

    com = bytearray()
    com += bytes([0xC3, 0x03, 0x11])    # jp 0x1103 (entry)
    com += prom0                        # 0x0103..0x0902
    com += prom1                        # 0x0903..0x1102
    assert len(com) == 0x1003, f"pre-stub size wrong: {len(com):#x}"
    com += stub                         # 0x1103..

    open(out_path, 'wb').write(com)
    print(f"wrote {out_path}: {len(com)} bytes "
          f"(prom0 2K + prom1 2K + {len(stub)} B stub + 3 B entry)")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(f"usage: {sys.argv[0]} prom0.bin prom1.bin out.com")
    main(*sys.argv[1:])
