#!/usr/bin/env python3
"""SDCC frame-pointer audit.

Z80's IX/IY-displacement addressing modes (`ld a,(ix+5)` etc.) are 3-4
bytes and 19 T-states per access -- substantially worse than register
or absolute addressing.  We compile cpnos-rom under z88dk-zsdcc with
`--fomit-frame-pointer` so the codegen is supposed to keep locals in
registers or in absolute scratch BSS, never on the stack.

Reality: SDCC's register allocator falls back to IX-relative stack
spills when a function has too many simultaneously-live locals.
There is no command-line way to prohibit it; the only fix is to
rewrite the function (split into smaller pieces, fewer locals, or
inline asm).

This audit greps every per-source .s file for `(ix+/-d)` or
`(iy+/-d)` operand syntax and identifies the function each violator
is in.  Build gate behaviour:

  * If any violator function is NOT on the known-violators list ->
    fail the build (catches regressions).
  * If a known violator's count grows -> fail (catches subtle
    spill-pressure increases that would compound over time).
  * If a known violator's count *shrinks* -> warn (suggests the
    list should be updated -- a successful refactor).

Inputs:
  - one or more .s files produced by `zcc ... -S ...`.
  - tasks/check_no_frame_ptr_baseline.txt with one line per known
    violator: `<file>:<function>:<count>`.

Usage:
  check_no_frame_ptr.py <baseline.txt> <audit.s> [<audit.s> ...]
"""
from __future__ import annotations
import re
import sys
from pathlib import Path


# Match GAS-style `(ix+5)`, `(ix-2)`, `(iy+0x80)` etc. in operand
# position.  The space between `ix` and the sign is optional (z88dk
# emits no space; some assemblers add one).
IX_RE = re.compile(r'\((ix|iy)\s*[+-]\s*[0-9]')

# Function label: a line that starts at column 0 with `_name:` (z88dk
# z80asm syntax).  Anything indented or labelled `l_<name>_NNN` is a
# basic-block label, not a function entry.
FN_RE = re.compile(r'^_(\w+):\s*$')
LOCAL_LABEL_RE = re.compile(r'^l_\w+:\s*$')


def scan_file(path: Path) -> dict[str, int]:
    """Return {function_name: violation_count} for one .s file."""
    counts: dict[str, int] = {}
    current = None
    for line in path.read_text().splitlines():
        m = FN_RE.match(line)
        if m and not LOCAL_LABEL_RE.match(line):
            current = m.group(1)
            continue
        if IX_RE.search(line) and current is not None:
            counts[current] = counts.get(current, 0) + 1
    return counts


def parse_baseline(path: Path) -> dict[tuple[str, str], int]:
    """Read baseline file -- one entry per line: `file.s:function:count`."""
    out: dict[tuple[str, str], int] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        try:
            f, fn, c = line.split(':')
            out[(f.strip(), fn.strip())] = int(c.strip())
        except ValueError:
            sys.exit(f"check_no_frame_ptr: malformed baseline line: {line!r}")
    return out


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    baseline_path = Path(sys.argv[1])
    s_paths = [Path(p) for p in sys.argv[2:]]
    baseline = parse_baseline(baseline_path)

    actual: dict[tuple[str, str], int] = {}
    for s in s_paths:
        for fn, n in scan_file(s).items():
            actual[(s.name, fn)] = n

    fail = False
    # New violators (not in baseline)
    new_v = [k for k in actual if k not in baseline]
    if new_v:
        fail = True
        print("FAIL: new IX+/IY+ frame-pointer use in:")
        for f, fn in sorted(new_v):
            print(f"  {f}:{fn}: {actual[(f, fn)]} hits")

    # Known violators whose count grew
    grew = [k for k in actual if k in baseline and actual[k] > baseline[k]]
    if grew:
        fail = True
        print("FAIL: known IX+/IY+ violator count grew (regression):")
        for f, fn in sorted(grew):
            print(f"  {f}:{fn}: was {baseline[(f, fn)]} -> now {actual[(f, fn)]}")

    # Known violators that disappeared or shrank -- warn (update baseline)
    shrunk_or_gone = [
        k for k in baseline
        if k not in actual or actual[k] < baseline[k]
    ]
    if shrunk_or_gone:
        print("WARN: baseline overstates current violators -- consider updating:")
        for f, fn in sorted(shrunk_or_gone):
            now = actual.get((f, fn), 0)
            print(f"  {f}:{fn}: baseline {baseline[(f, fn)]} -> actual {now}")

    if fail:
        print()
        print("To resolve a new IX+/IY+ violator: refactor the function so "
              "SDCC's register allocator keeps locals in registers (split "
              "into smaller pieces, reduce simultaneously-live values), or "
              "rewrite the hot bits in inline asm.  Adding the violator to "
              "the baseline file silences the gate but is technical debt.")
        return 1

    total = sum(actual.values())
    print(f"check_no_frame_ptr: OK ({total} known IX+/IY+ hits, "
          f"all on the allowlist)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
