#!/usr/bin/env python3
"""Build-time guard: the SDCC PROM1 resident must leave enough stack room.

The slave runs with SP = STACK_TOP (0xF680, just below the locale tables at
0xF680..0xF7FF; display is at 0xF800, so the stack cannot move higher). The
stack grows DOWN toward the top of the resident image. If the resident is too
large, a deep call chain during netboot overruns the stack INTO the resident's
RODATA/DATA/CHECKSUM, silently corrupting the SNIOS data -- the slave netboots
fully (dots + locale line) but then hangs at the cpnos.sys handoff (no E>),
because cpnos.sys calls the now-corrupt resident SNIOS and its CP/NET frame is
never ACKed.

clang keeps the resident below __stack_low = 0xF60E (>= 114 B stack) and boots
to E>; SDCC's less-dense output overran this (resident top 0xF62A, only 86 B
stack) which is exactly the 2026-07-28 hang. This guard fails the build LOUDLY
so the overrun can never ship as a silently-broken binary.

Usage: check_sdcc_stack_room.py <cpnos_lp.map>
"""
import re
import sys

STACK_TOP = 0xF680                  # SP init (sdcc-prom1lineprog/bootstrap.asm)
MIN_STACK = 0x72                    # 114 B -- the clang-proven reservation
STACK_LOW = STACK_TOP - MIN_STACK   # 0xF60E: resident must end at or below this


def main(mapfile: str) -> int:
    try:
        txt = open(mapfile).read()
    except OSError as e:
        print(f"check_sdcc_stack_room: cannot read {mapfile}: {e}", file=sys.stderr)
        return 2
    m = re.search(r'__RESIDENT_CHECKSUM_tail\s*=\s*\$([0-9A-Fa-f]+)', txt)
    if not m:
        print(f"check_sdcc_stack_room: __RESIDENT_CHECKSUM_tail not found in "
              f"{mapfile}", file=sys.stderr)
        return 2
    top = int(m.group(1), 16)
    free = STACK_TOP - top
    if top > STACK_LOW:
        over = top - STACK_LOW
        print(
            "ERROR: SDCC PROM1 resident overruns the stack zone.\n"
            f"  resident top (__RESIDENT_CHECKSUM_tail) = 0x{top:04X}\n"
            f"  SP init (stack top)                     = 0x{STACK_TOP:04X}\n"
            f"  required floor (>= {MIN_STACK} B stack)          = 0x{STACK_LOW:04X}\n"
            f"  -> only {free} B of stack; overruns the floor by {over} B.\n"
            "The slave will netboot but HANG at the cpnos.sys handoff (stack\n"
            "overflow corrupts resident SNIOS data). Shave >= "
            f"{over} B from the SDCC\nresident (RESIDENT_CODE / z88dk library "
            "pull-ins) to clear 0x{:04X}.\n".format(STACK_LOW) +
            "See tasks/todo-mpm-disk-build-2026-07-27.md (SDCC slave known gap).",
            file=sys.stderr)
        return 1
    print(f"  SDCC stack room OK: resident top 0x{top:04X}, {free} B stack to "
          f"SP 0x{STACK_TOP:04X} (floor 0x{STACK_LOW:04X})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: check_sdcc_stack_room.py <cpnos_lp.map>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
