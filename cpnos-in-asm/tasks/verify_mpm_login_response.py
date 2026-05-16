#!/usr/bin/env python3
"""Verify that cpnos-in-asm's netboot against z80pack mpm-net2 completes.

Looks at the SIO-B capture for the LOGIN OK + 25 dots + FETCH OK
sequence emitted by do_netboot in prom1.asm.  Phases:

  1. Banner line ends with CRLF.
  2. "LOGIN OK\r\n" -- LOGIN cpnet_xact returned rc = 0.
  3. >=1 '.' chars -- one per READ-SEQ sector loaded.
  4. "FETCH OK\r\n" -- whole netboot loop reached CLOSE successfully.

PASS if all four signals appear in order.
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cpnos_asm_mpm_siob.raw"
d = open(path, "rb").read()
text = d.decode("latin-1", errors="replace")

def need(marker, after=0):
    idx = text.find(marker, after)
    if idx < 0:
        print(f"FAIL: '{marker!r}' not found in SIO-B capture after offset {after}")
        sys.exit(1)
    return idx + len(marker)

i = need("RC702 CP/NOS asm")
i = need("\r\n", i)
i = need("LOGIN OK\r\n", i)
# Find at least one '.' between LOGIN OK and FETCH OK.
fetch = text.find("FETCH OK", i)
if fetch < 0:
    print("FAIL: 'FETCH OK' not found after LOGIN OK")
    sys.exit(1)
dots = text[i:fetch].count(".")
if dots < 1:
    print(f"FAIL: no '.' progress markers between LOGIN OK and FETCH OK (got {dots})")
    sys.exit(1)
print(f"PASS: banner -> LOGIN OK -> {dots} dots -> FETCH OK on SIO-B "
      f"({len(d)} B capture)")
