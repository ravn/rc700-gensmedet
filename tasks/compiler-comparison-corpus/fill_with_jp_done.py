#!/usr/bin/env python3
"""
Post-build padding: extend a .bin with the pattern `c3 LO HI` (Z80
`JP <done_addr>`) from the end of the binary up to byte 0xBFFD, so
ticks loads the entire 0..0xBFFF address range with valid instructions.

The point: when a buggy binary's control flow escapes into "uninitialized"
RAM (e.g. via a corrupted return address from a clang +static-stack
miscompile), execution lands on one of these JP instructions and jumps
to _done within at most 2 instruction fetches. z88dk-ticks then exits
via its -end <done_addr> mechanism within a few cycles instead of
running forever (or worse, hitting the default -start=0x0000 reset of
the tstate counter on PC wraparound, which masks counter-limit
termination — see the ticks behaviour we tripped over).

Without this padding, a miscompile that escapes into the NOP-sled of
uninitialized RAM (all 0x00 = NOP) walks through tens of thousands of
NOPs, then wraps PC from 0xFFFF→0x0000. At pc==start (default 0x0000)
ticks RESETS the tstate counter, so any finite counter never fires.
Reproducer in clang sweep: config 09_Oz_prod_like ran 7+ minutes at
100% CPU with -counter 100M before being killed by wallclock alarm.

Usage:
    fill_with_jp_done.py <in.bin> <out.bin> <done_addr_hex>

`done_addr_hex` is the PC value to JP to — should match the -end addr
passed to ticks (e.g. 0x0007 for clang's reset_clang.s _done; 0x00B7
for z88dk's +z80 crt0 post-main HALT).

Leaves bytes >= 0xBFFE unpatched (last 2 bytes are dead space; results
vector is at 0xC000+ and must be reachable for the test harness to
write into).
"""
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    in_path, out_path, done_hex = sys.argv[1], sys.argv[2], sys.argv[3]
    done = int(done_hex, 16)
    if not 0 <= done <= 0xFFFF:
        print(f"done_addr 0x{done:04X} not in 0..0xFFFF", file=sys.stderr)
        return 2

    data = bytearray(open(in_path, "rb").read())
    # Fill from end of bin up to 0xBFFD with `JP done` (3 bytes).
    lo = done & 0xFF
    hi = (done >> 8) & 0xFF
    pattern = bytes([0xC3, lo, hi])

    end_fill = 0xBFFE  # leave 0xBFFE, 0xBFFF as 0 — irrelevant either way
    if len(data) >= end_fill:
        # Binary already larger than fill target — nothing to do.
        out_data = data
    else:
        n_bytes = end_fill - len(data)
        # Pattern is 3 bytes; emit floor(n/3) copies then floor(remainder)
        # NOTE: ticks decodes the JP at whatever PC it lands at, so we
        # don't need PC-alignment — the worst case is landing on the
        # `LO` or `HI` byte mid-pattern (an opcode 0x07=RLCA or
        # 0x00=NOP), which advances PC by 1; the next decode then hits
        # the next pattern's leading 0xC3 and JPs to done.
        repeats = n_bytes // 3
        rem = n_bytes % 3
        fill = pattern * repeats + pattern[:rem]
        out_data = data + fill

    open(out_path, "wb").write(out_data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
