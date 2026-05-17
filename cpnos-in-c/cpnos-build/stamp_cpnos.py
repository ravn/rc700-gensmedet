#!/usr/bin/env python3
"""Stamp a 32-byte build line + locale tag into the trailing 0x1A
padding of cpnos.com.  Output is byte-identical to input except the
last 32 bytes, which the cpnos-rom netboot prints after the READ-SEQ
loop so operators see exactly which build of the cpnos monolith
landed AND which locale tables travel with it.

Usage:
    stamp_cpnos.py <input.com> <output.com> [<stamp>] [--locale TAG]

If <stamp> is omitted, build it as 'YYYY-MM-DD HH:MM <git-hash>' from
the current LOCAL time and the working tree's git HEAD.  Local time
matches the operator's wall clock when verifying a build off the
bench; UTC was tried and dropped 2026-05-08.

If --locale TAG is given (e.g. da_US, da_DK), it's appended to the
text after a space.  The locale tag travels with cpnos.img because
the slave PROM1 doesn't know which tables the master prepended;
print_banner (which runs before netboot) therefore can't print it.

Layout (last 32 B of the .COM file, byte-stable across builds):
  +0..+30  ASCII text (right-padded with spaces if shorter)
  +31      0x00 sentinel (guards a misread / printf overrun)
"""
import os, sys, time, subprocess

LEN = 32

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
    args = sys.argv[1:]
    locale = None
    if "--locale" in args:
        i = args.index("--locale")
        if i + 1 >= len(args):
            sys.exit("--locale requires a tag argument")
        locale = args[i + 1]
        del args[i:i + 2]
    if len(args) not in (2, 3):
        sys.exit("usage: stamp_cpnos.py <input.com> <output.com> "
                 "[<stamp>] [--locale TAG]")
    src, dst = args[0], args[1]
    stamp = args[2] if len(args) == 3 else make_default_stamp()
    if locale:
        stamp = f"{stamp} {locale}"

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
