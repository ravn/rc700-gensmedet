#!/usr/bin/env python3
"""SDCC unreferenced-PUBLIC audit.

z88dk's z80asm has no function-level dead-code elimination: every
PUBLIC symbol declared in a user .asm file gets linked into the
binary at full size, whether or not anything references it.

This bit us during #77 (mem_copy_backwards): after migrating
insert_line, the only caller of `_memmove_callee` (a 33 B helper
added one commit earlier) was gone, but `_memmove_callee` was still
linked into the resident at full cost.  Caught by accident reading
cpnos.map.

This audit parses cpnos.map for every PUBLIC symbol that originates
from a user-tracked .asm file under sdcc/, then greps every
build-tree .s and .asm file for a real *use* of the symbol
(distinct from PUBLIC/EXTERN/GLOBAL declarations and from the
defining label).  Build gate behaviour:

  * PUBLIC user symbol with zero uses anywhere -> fail (unless on
    allowlist for hardware/external-ABI entry points).
  * Allowlisted symbol that NOW has uses -> warn (entry can be
    removed from the allowlist).

Inputs:
  - allowlist file: one symbol per line, optional `# justification`.
  - cpnos.map: z88dk's link map.
  - reference files (.s, .asm) to grep.

Usage:
  check_unreferenced_publics.py <allowlist.txt> <cpnos.map> <ref> ...
"""
from __future__ import annotations
import re
import sys
from pathlib import Path


# Map line: `_name      = $HEX ; type, scope, def?, module, section, source:line`
MAP_RE = re.compile(
    r'^(\S+)\s*=\s*\$[0-9A-Fa-f]+\s*;\s*'
    r'(?:addr|const)\s*,\s*public\s*,\s*'
    r'[^,]*,\s*[^,]*,\s*[^,]*,\s*'
    r'(.+?)\s*$'
)


def parse_map(path: Path) -> list[tuple[str, str]]:
    """Return [(symbol, source)] for PUBLIC symbols defined under sdcc/."""
    out = []
    for line in path.read_text().splitlines():
        m = MAP_RE.match(line)
        if not m:
            continue
        sym, src = m.group(1), m.group(2).strip()
        if '/sdcc/' not in src and not src.startswith('sdcc/'):
            # Generated files in BUILDDIR (xport_aliases.asm, cpnos_layout.asm,
            # payload_header_data.s) have bare filenames -- skip; they're
            # auto-generated and their PUBLICs are deliberate.
            continue
        out.append((sym, src))
    return out


def parse_allowlist(path: Path) -> set[str]:
    out: set[str] = set()
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if line:
            out.add(line)
    return out


def is_use(line: str, sym: str) -> bool:
    """Does this line use `sym` (vs. declare or define it)?"""
    code = line.split(';', 1)[0]
    pat = re.compile(rf'\b{re.escape(sym)}\b')
    if not pat.search(code):
        return False
    # PUBLIC / EXTERN / GLOBAL / .globl declaration line (z88dk allows
    # comma-separated lists, so the symbol may appear after PUBLIC).
    if re.match(r'\s*(PUBLIC|EXTERN|GLOBAL|\.globl)\b', code):
        return False
    # Label line: `_sym:` (possibly indented, possibly followed by
    # an instruction on the same line).
    if re.match(rf'\s*{re.escape(sym)}\s*:', code):
        return False
    # Assignment forms: `defc _sym = ...`, `_sym equ ...`, `_sym = ...`,
    # `_sym defl ...`.
    if re.match(rf'\s*defc\s+{re.escape(sym)}\b', code, re.IGNORECASE):
        return False
    if re.match(rf'\s*{re.escape(sym)}\s*(=|\bequ\b|\bdefl\b)',
                code, re.IGNORECASE):
        return False
    return True


def has_use(sym: str, files: list[Path]) -> bool:
    for f in files:
        try:
            text = f.read_text()
        except OSError:
            continue
        for line in text.splitlines():
            if is_use(line, sym):
                return True
    return False


def main() -> int:
    if len(sys.argv) < 4:
        sys.stderr.write(__doc__)
        return 2
    allow_path = Path(sys.argv[1])
    map_path = Path(sys.argv[2])
    ref_paths = [Path(p) for p in sys.argv[3:] if Path(p).exists()]

    allowlist = parse_allowlist(allow_path)
    publics = parse_map(map_path)

    seen: set[str] = set()
    dead: list[tuple[str, str]] = []
    stale_allow: list[str] = []
    live_count = 0

    for sym, src in publics:
        if sym in seen:
            continue
        seen.add(sym)
        used = has_use(sym, ref_paths)
        if used:
            live_count += 1
            if sym in allowlist:
                stale_allow.append(sym)
        else:
            if sym not in allowlist:
                dead.append((sym, src))

    fail = False
    if dead:
        fail = True
        print("FAIL: PUBLIC symbols with no references in build tree:")
        for sym, src in sorted(dead):
            print(f"  {sym}  (defined in {src})")
        print()
        print("Either delete the symbol (and its body) or add it to the "
              "allowlist with a comment explaining the external caller "
              "(hardware boot vector, fixed ABI address, post-link patch "
              "tool, header-emit script, etc.).")

    if stale_allow:
        print("WARN: allowlist entries that now have references — "
              "consider removing:")
        for sym in sorted(stale_allow):
            print(f"  {sym}")

    if fail:
        return 1

    print(f"check_unreferenced_publics: OK ({live_count} live, "
          f"{len(allowlist)} allowlisted)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
