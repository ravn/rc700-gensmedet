#!/usr/bin/env python3
"""Stamp a 24-byte timestamp + git-hash into the trailing 0x1A padding
of cpnos.com.  Output is byte-identical to input except the last 24
bytes, which the cpnos-rom netboot prints after the READ-SEQ loop so
operators see exactly which build of the cpnos monolith landed.

Usage: stamp_cpnos.py <input.com> <output.com> [<stamp>]

If <stamp> is omitted, build it as 'YYYY-MM-DD HH:MM <git-hash>' from
the current LOCAL time and the working tree's git HEAD.  Local time
matches the operator's wall clock when verifying a build off the
bench (e.g., "I burned this PROM at 11:47 -- which cpnos.com is in
that image?"); UTC was tried and dropped 2026-05-08.

Layout (last 24 B of the .COM file, byte-stable across builds):
  +0..+22  ASCII text (right-padded with spaces if shorter)
  +23      0x00 sentinel (guards a misread / printf overrun)
"""
import os, sys, time, subprocess

LEN = 24

def make_default_stamp() -> str:
    ts = time.strftime("%Y-%m-%d %H:%M", time.localtime())
    try:
        h = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=os.path.dirname(os.path.abspath(sys.argv[1])) or ".",
            stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        h = "????"
    return f"{ts} {h}"

def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(f"usage: {sys.argv[0]} <input.com> <output.com> [<stamp>]")
    src, dst = sys.argv[1], sys.argv[2]
    stamp = sys.argv[3] if len(sys.argv) == 4 else make_default_stamp()

    with open(src, "rb") as f:
        data = bytearray(f.read())

    if len(data) < LEN:
        sys.exit(f"{src}: too short ({len(data)} B; need >= {LEN})")

    text = stamp.encode("ascii", errors="replace")[:LEN - 1]
    text = text.ljust(LEN - 1, b" ")
    payload = bytes(text) + b"\x00"
    data[-LEN:] = payload

    with open(dst, "wb") as f:
        f.write(data)

    print(f"  stamped {dst} with: {stamp!r}")

if __name__ == "__main__":
    main()
