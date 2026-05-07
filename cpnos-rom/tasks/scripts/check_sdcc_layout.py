#!/usr/bin/env python3
"""Audit cpnos.map (z88dk-z80asm output) for symbols that the build will
silently misroute at runtime.

z88dk inserts standard-library sections (`code_string`, `code_clib`,
`code_l_sccz80`, `code_home`, `code_crt_init`) into address gaps when
they are not explicitly placed.  In the cpnos-rom layout that puts them
in the SCRATCH_BSS chain at 0xEDF1+, which is OUTSIDE the resident
range (0xEE00..0xF7FF) that prom_loader copies to RAM.  Calls to those
symbols at runtime hit uninitialised RAM.

Detect this by checking every `addr, public` symbol falls inside one of
the legal ranges:

    0x0000..0x07FF  PROM0 (RESET, INIT_CODE)
    0xEC00..0xEDFF  bss_compiler ONLY (zero-initialised at boot)
    0xEE00..0xF7FF  resident (LDIRed by prom_loader)

A symbol in a `code_*` or `RESIDENT_*` or `SECTION` flagged section
must live in 0x0000..0x07FF (init/reset code) or 0xEE00..0xF7FF
(resident).  A symbol in `bss_compiler` is allowed in 0xEC00..0xEDFF.

Also flag any section whose head/tail straddles the resident boundary
at 0xEE00 (overlaps with RESIDENT_JUMPTABLE).

Exit non-zero if violations are found.
"""
import re
import sys
from pathlib import Path

RESIDENT_LO = 0xEE00
RESIDENT_HI = 0xF7FF      # inclusive
PROM0_LO = 0x0000
PROM0_HI = 0x07FF
BSS_LO = 0xEC00
BSS_HI = 0xEDFF

# Sections that are allowed to live outside the resident range.
BSS_SECTIONS = {"bss_compiler", "SCRATCH_BSS"}
PROM0_SECTIONS = {"RESET", "INIT_CODE", "INIT_RODATA", "PAYLOAD_HEADER"}

# Const/equ symbols (no real address, just a numeric definition).
def is_const(line: str) -> bool:
    return ", const," in line


def addr_in(addr: int, lo: int, hi: int) -> bool:
    return lo <= addr <= hi


def parse_map(path: Path):
    """Yield (name, addr, kind, scope, defined, section, source_loc)."""
    rx = re.compile(
        r"^(\S+)\s*=\s*\$([0-9A-Fa-f]+)\s*;\s*"
        r"(addr|const)\s*,\s*(\S+?)\s*,\s*(\S*?)\s*,\s*(\S*?)\s*,\s*(\S*?)\s*,\s*(.*)$"
    )
    for line in path.read_text().splitlines():
        m = rx.match(line)
        if not m:
            continue
        name, addr_hex, kind, scope, defined, module, section, src = m.groups()
        yield {
            "name": name,
            "addr": int(addr_hex, 16),
            "kind": kind,
            "scope": scope,
            "defined": defined,
            "module": module,
            "section": section,
            "src": src,
            "raw": line,
        }


def parse_section_extents(path: Path):
    """Pick out __FOO_head / __FOO_size / __FOO_tail synthesised by z80asm
    and return {section_name: (head, size, tail)}."""
    rx = re.compile(
        r"^__(\S+?)_(head|size|tail)\s*=\s*\$([0-9A-Fa-f]+)\s*;"
    )
    sec = {}
    for line in path.read_text().splitlines():
        m = rx.match(line)
        if not m:
            continue
        name, kind, hex_v = m.groups()
        sec.setdefault(name, {})[kind] = int(hex_v, 16)
    return {n: (d.get("head"), d.get("size"), d.get("tail")) for n, d in sec.items()}


def main(map_path: str) -> int:
    p = Path(map_path)
    if not p.exists():
        print(f"check_sdcc_layout: missing map {p}", file=sys.stderr)
        return 1

    violations = []
    warnings = []

    # --- Section-extent audit -------------------------------------------------
    sections = parse_section_extents(p)
    for name, (head, size, tail) in sorted(sections.items()):
        if head is None or tail is None:
            continue
        if size == 0:
            continue
        # Sections we control directly
        if name in PROM0_SECTIONS:
            if not (addr_in(head, PROM0_LO, PROM0_HI)
                    and addr_in(tail - 1, PROM0_LO, PROM0_HI)):
                violations.append(
                    f"section {name} ({head:04X}..{tail-1:04X}) "
                    f"outside PROM0 range")
            continue
        if name in BSS_SECTIONS:
            if not (addr_in(head, BSS_LO, BSS_HI + 1)
                    and addr_in(tail, BSS_LO, BSS_HI + 1)):
                violations.append(
                    f"section {name} ({head:04X}..{tail:04X}) "
                    f"outside BSS range")
            continue
        if name.startswith("RESIDENT_"):
            if not (addr_in(head, RESIDENT_LO, RESIDENT_HI + 1)
                    and addr_in(tail, RESIDENT_LO, RESIDENT_HI + 1)):
                violations.append(
                    f"section {name} ({head:04X}..{tail:04X}) "
                    f"outside resident range "
                    f"{RESIDENT_LO:04X}..{RESIDENT_HI:04X}")
            continue
        # Compiler runtime CODE sections — these MUST live inside the
        # resident range for their symbols to be reachable from RAM.
        if name.startswith("code_"):
            if not (addr_in(head, RESIDENT_LO, RESIDENT_HI + 1)
                    and addr_in(tail, RESIDENT_LO, RESIDENT_HI + 1)):
                violations.append(
                    f"runtime section {name} ({head:04X}..{tail:04X}) "
                    f"placed OUTSIDE resident range — symbols there are "
                    f"NOT loaded into RAM by prom_loader; calls will jump "
                    f"into uninitialised memory")
            continue
        # Compiler runtime RODATA / DATA — also need to be loaded.
        if name.startswith("rodata_") or name.startswith("data_"):
            if not (addr_in(head, RESIDENT_LO, RESIDENT_HI + 1)
                    and addr_in(tail, RESIDENT_LO, RESIDENT_HI + 1)):
                violations.append(
                    f"runtime section {name} ({head:04X}..{tail:04X}) "
                    f"placed OUTSIDE resident range — read-only / data "
                    f"there is NOT loaded into RAM, reads will return "
                    f"uninitialised values")
            continue
        # Compiler runtime BSS — must live inside BSS scratch range
        # (zeroed at boot).  Outside that range, initial values are
        # whatever the netboot LDIR happened to leave behind.
        if name.startswith("bss_"):
            if not (addr_in(head, BSS_LO, BSS_HI + 1)
                    and addr_in(tail, BSS_LO, BSS_HI + 1)):
                violations.append(
                    f"runtime section {name} ({head:04X}..{tail:04X}) "
                    f"placed OUTSIDE bss range {BSS_LO:04X}..{BSS_HI:04X} "
                    f"— variables there start with garbage, not zero")
            continue
        # Any other section (IGNORE etc.) — warn only
        warnings.append(
            f"unhandled section {name} ({head:04X}..{tail:04X})")

    # --- Per-symbol audit -----------------------------------------------------
    for s in parse_map(p):
        if s["kind"] != "addr":
            continue
        addr = s["addr"]
        sect = s["section"]
        if not sect:
            # Linker-synthesised symbol (e.g., __FOO_head) — covered above.
            continue
        # Derived high-byte constants (e.g., `_pio_rx_buf_page = HIGH(_pio_rx_buf)`)
        # appear in the map with the section of their `defc` site but a value
        # < 0x100 because they're a single byte, not an address.  Skip them —
        # by convention these symbols end in `_page` or `_PAGE`.
        if s["name"].lower().endswith("_page") and addr < 0x100:
            continue
        # Allow PROM0 ranges for boot code only
        if sect in PROM0_SECTIONS:
            ok = addr_in(addr, PROM0_LO, PROM0_HI)
        elif sect in BSS_SECTIONS or sect.startswith("bss_"):
            ok = addr_in(addr, BSS_LO, BSS_HI)
        elif (sect.startswith("RESIDENT_")
              or sect.startswith("code_")
              or sect.startswith("rodata_")
              or sect.startswith("data_")):
            ok = addr_in(addr, RESIDENT_LO, RESIDENT_HI)
        else:
            # Unknown section — let it pass with a note
            ok = True
            warnings.append(
                f"symbol {s['name']:30s} @ {addr:04X} in unknown "
                f"section {sect!r}")
            continue
        if not ok:
            violations.append(
                f"symbol {s['name']:30s} @ {addr:04X} in section "
                f"{sect!r} — addr outside the legal range for that section "
                f"(defined {s['src']})")

    # --- Cross-section overlap check -----------------------------------------
    # Every byte at a given address should be claimed by at most one
    # *non-zero-size* section.  Catch the code_string vs RESIDENT_JUMPTABLE
    # collision.
    spans = []
    for name, (head, size, tail) in sections.items():
        if size and size > 0 and head is not None and tail is not None:
            # Tails are exclusive (head + size).
            if head < tail:
                spans.append((head, tail, name))
    spans.sort()
    for i in range(len(spans)):
        a_lo, a_hi, a_n = spans[i]
        for j in range(i + 1, len(spans)):
            b_lo, b_hi, b_n = spans[j]
            if b_lo >= a_hi:
                break
            if a_n == b_n:
                continue
            ov_lo = max(a_lo, b_lo)
            ov_hi = min(a_hi, b_hi)
            if ov_lo < ov_hi:
                violations.append(
                    f"section overlap: {a_n} ({a_lo:04X}..{a_hi-1:04X}) "
                    f"vs {b_n} ({b_lo:04X}..{b_hi-1:04X}) at "
                    f"{ov_lo:04X}..{ov_hi-1:04X}")

    # --- Report --------------------------------------------------------------
    if warnings:
        print("warnings:", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)
    if violations:
        print(f"check_sdcc_layout: {len(violations)} VIOLATION(S):",
              file=sys.stderr)
        for v in violations:
            print(f"  {v}", file=sys.stderr)
        return 2
    print("check_sdcc_layout: layout OK")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <cpnos.map>", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
