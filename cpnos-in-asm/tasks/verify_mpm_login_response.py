#!/usr/bin/env python3
"""Verify that the slave's SIO-B capture contains a valid CP/NET LOGIN
response frame from z80pack mpm-net2 (cpnos-mpm-test).

Look for the 0xAA framing marker emitted by dump_rx_to_siob (only
written on a successfully validated received frame), followed by the
LOGIN-response header (FMT=1, DID=1, SID=0, FNC=0x40, SIZ=0).
Re-validate HCS and CKS independently of the slave's own check.
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cpnos_asm_mpm_siob.raw"
d = open(path, "rb").read()

# 0xAA marker + the LOGIN-response header prefix (SOH + FMT + DID + SID
# + FNC + SIZ).  Last byte is HCS, included in the sum check below.
PREFIX = b"\xaa\x01\x01\x01\x00\x40\x00"

i = d.find(PREFIX)
if i < 0:
    print(f"FAIL: 0xAA + LOGIN response header not found in {path}")
    sys.exit(1)

hdr = d[i + 1 : i + 8]
if sum(hdr) % 256 != 0:
    print(f"FAIL: response HCS invalid; bytes={hdr.hex()} sum={sum(hdr) % 256}")
    sys.exit(1)

dat_section = d[i + 8 : i + 13]
if len(dat_section) < 5:
    print(f"FAIL: data section truncated; got {dat_section.hex()}")
    sys.exit(1)
if dat_section[0] != 0x02:
    print(f"FAIL: STX missing at +8; got 0x{dat_section[0]:02x}")
    sys.exit(1)
if dat_section[2] != 0x03:
    print(f"FAIL: ETX missing at +10; got 0x{dat_section[2]:02x}")
    sys.exit(1)
if dat_section[4] != 0x04:
    print(f"FAIL: EOT missing at +12; got 0x{dat_section[4]:02x}")
    sys.exit(1)
if sum(dat_section[:4]) % 256 != 0:
    print(f"FAIL: response CKS invalid; bracket={dat_section[:4].hex()}")
    sys.exit(1)

print(
    f"master LOGIN response received: hdr={hdr.hex()} data={dat_section.hex()}; "
    f"DAT[0]=0x{dat_section[1]:02x} (0 = LOGIN OK)"
)
