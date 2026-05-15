#!/usr/bin/env python3
"""Build-time guard: forbid arch-helper calls in cpnos-rom artifacts.

Why this exists
---------------
cpnos-rom production builds with `-Cs"--sdcccall 1"` plus
`-Cs"--disable-warning 296"`.  Under z88dk's stock SDCC stdlib this
is unsafe: every runtime helper in `libsrc/l/sdcc/` (__moduchar,
__mulint, __divuchar, ...) was hand-written for sdcccall-0 (stack-
passed args).  Calling one of them from sdcccall-1 user code passes
args in registers, the helper pops random bytes off the stack as
"args", and the result is a silent miscompile.  Caught twice in
sccz80-oracle-corpus (__mulint, then __moduchar) — both miscompiled
identically with garbage results.

Production works today because every source path is helper-free
(audited 2026-05-13: zero `call __mul/__div/__mod` in any built
.s/.lis).  This script enforces that property going forward: a new
`x % N` for non-power-of-2 N, a 16-bit multiply, or a division
silently introduced into a future commit triggers a build failure
instead of a silent miscompile.

Background
----------
See `rc700-gensmedet/tasks/sccz80-oracle-corpus/sdcccall-research-2026-05-14.md`
for the four documented paths to use --sdcccall 1.  cpnos-rom is on
Path C (workaround-by-avoidance), and this script is the workaround's
safety net.

Allowed exceptions
------------------
The clang build of rcbios-in-c reaches `___umodqi3` (clang's own
compiler-rt umodqi3, which IS register-ABI-compatible).  cpnos-rom
production does not reach it, and we want to keep it that way for
size reasons (a helper-call site costs ~10 B per call + 30+ B for
the helper body).  Allowlist is empty by default; add entries here
if a future intentional helper-call is approved.

Usage
-----
  check_no_helper_calls.py <file.s|.lis|.lst> [<file2> ...]

Scans each input file for `call X` or `jp X` where X is a known
SDCC / clang arch helper.  Exits 1 on any hit.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path


# SDCC z88dk stdlib helpers (from libsrc/l/sdcc/).  Each helper has a
# `_callee` variant with the same prefix; matched separately below.
_SDCC_STEMS = [
    "moduchar", "modschar", "moduschar", "modsuchar",
    "muluchar", "mulschar",
    "divuchar", "divschar", "divuschar", "divsuchar",
    "mulint",   "moduint",   "modsint",   "divuint",   "divsint",
    "mullong",  "modulong",  "modslong",  "divulong",  "divslong",
    "mullonglong", "modulonglong", "modslonglong",
    "divulonglong", "divslonglong",
]
SDCC_HELPERS = [f"__{h}" for h in _SDCC_STEMS] + \
               [f"__{h}_callee" for h in _SDCC_STEMS]

# clang compiler-rt helpers (note: triple underscore in objdump
# output because llvm-objdump prepends `_` to C symbol that already
# has its own `_` prefix).  Listed here both ways so we catch either
# the disasm form (`___umodqi3`) or the EXTERN-declaration form
# (`__umodqi3`).
_CLANG_STEMS = [
    "mulhi3", "mulsi3", "muldi3", "multi3",
    "udivqi3", "udivhi3", "udivsi3", "udivdi3",
    "divqi3",  "divhi3",  "divsi3",  "divdi3",
    "umodqi3", "umodhi3", "umodsi3", "umoddi3",
    "modqi3",  "modhi3",  "modsi3",  "moddi3",
]
CLANG_HELPERS = [f"__{h}" for h in _CLANG_STEMS] + \
                [f"___{h}" for h in _CLANG_STEMS]

ALL_HELPERS = SDCC_HELPERS + CLANG_HELPERS

# Approved helper-call sites (empty for cpnos-rom — no production
# code currently reaches one, and we want to keep it that way).
ALLOWED: set[str] = set()

# Match `call X` or `jp X` where X is one of the helpers.  Word-boundary
# at the right edge keeps user functions like `_mul_8x8` (which would
# appear as `__mul_8x8` in asm) from false-positive matching `__mul`.
_HELPERS_RE = re.compile(
    r"\b(?:call|jp)\s+(" +
    "|".join(re.escape(h) for h in ALL_HELPERS) +
    r")\b"
)


def scan(paths: list[Path]) -> list[tuple[Path, int, str, str]]:
    hits: list[tuple[Path, int, str, str]] = []
    for p in paths:
        try:
            for n, line in enumerate(p.read_text().splitlines(), 1):
                m = _HELPERS_RE.search(line)
                if m and m.group(1) not in ALLOWED:
                    hits.append((p, n, m.group(1), line.strip()))
        except (FileNotFoundError, UnicodeDecodeError):
            # Binary / missing files: skip silently.  Caller decides
            # which files to pass in.
            continue
    return hits


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__ or "")
        return 2
    paths = [Path(p) for p in sys.argv[1:]]
    hits = scan(paths)
    if hits:
        print("FAIL: arch-helper call detected — sdcccall(1) miscompile risk")
        print("See tasks/sccz80-oracle-corpus/sdcccall-research-2026-05-14.md")
        print()
        for p, n, helper, line in hits:
            print(f"  {p}:{n}: {helper}")
            print(f"      {line}")
        print()
        print("To resolve: rewrite the source to avoid the helper.  Common")
        print("triggers and fixes:")
        print("  - `x % N` for non-power-of-2 N -> use `x & (N-1)` if N is a")
        print("    power of 2; otherwise refactor algorithm.")
        print("  - 16-bit multiply -> shift+add inline, or use 8-bit ops.")
        print("  - Division -> reciprocal multiply, or shift if power-of-2.")
        print("  - If the call is legitimate, add to ALLOWED in this script.")
        return 1
    print(f"check_no_helper_calls: OK ({len(paths)} file(s), 0 helper calls)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
