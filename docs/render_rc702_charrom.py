#!/usr/bin/env python3
"""Render RC702 character ROM glyphs as ASCII-art bitmaps.

Each glyph in ROA296 / ROA327 occupies 16 bytes (16 scan lines of
8 pixels each).  LSB is the LEFTMOST pixel on the screen -- the
i8275 CRT controller shifts bits out from bit 0 toward bit 7.

Usage:
    render_rc702_charrom.py [--rom path/to/roa296.rom] [--cp 0xNN ...]
    render_rc702_charrom.py --all-printable
    render_rc702_charrom.py --markdown > docs/ROA296_GLYPH_BITMAPS.md

`--markdown` re-generates the companion `ROA296_GLYPH_BITMAPS.md`
table from the current ROM bytes; commit both together so the doc
stays in sync with the ROM.
"""

import argparse
import os
import sys


DEFAULT_ROM = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "mame", "roms", "rc702", "roa296.rom",
)

GLYPH_BYTES = 16     # 16 scan lines per glyph
GLYPH_COUNT = 128    # codepoints 0x00..0x7F


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    expected = GLYPH_BYTES * GLYPH_COUNT
    if len(data) < expected:
        sys.exit(f"{path}: expected at least {expected} B, got {len(data)} B")
    return data


def render_lines(rom, cp):
    """Yield 16 strings of 8 chars each, '#' for set pixels, '.' for clear."""
    base = cp * GLYPH_BYTES
    for row in range(GLYPH_BYTES):
        b = rom[base + row]
        yield "".join("#" if (b >> i) & 1 else "." for i in range(8))


def dump_text(rom, cps):
    for cp in cps:
        ch = chr(cp) if 0x20 <= cp <= 0x7E else "?"
        print(f"=== 0x{cp:02X} ({ch}) ===")
        for line in render_lines(rom, cp):
            print(line)
        print()


def dump_markdown(rom):
    print("# ROA296 Glyph Bitmaps")
    print()
    print("Auto-generated from `mame/roms/rc702/roa296.rom` by")
    print("`docs/render_rc702_charrom.py`.  Re-run after any ROM update:")
    print()
    print("```")
    print("python3 docs/render_rc702_charrom.py --markdown \\")
    print("    > docs/ROA296_GLYPH_BITMAPS.md")
    print("```")
    print()
    print("Each glyph is a 16 scan-line by 8-pixel cell.  The i8275 CRT")
    print("controller shifts pixels LSB-first, so bit 0 of each ROM byte is")
    print("the LEFTMOST pixel on screen.  `.` = clear, `#` = set.")
    print()
    print("## Codepoints 0x00..0x1F -- Danish accents, brackets, typographic")
    print()
    print("Many of these are the glyphs that US-ASCII outcon tables remap to")
    print("(e.g. `[\\]` live at 0x0B/0x0C/0x0D, `{|}~` at 0x1B/0x1C/0x1D/0x0F,")
    print("`@` at 0x05, acute accent at 0x16).  See")
    print("`rcbios-in-c/locale/us_ascii_tables.h`.")
    print()
    for cp in range(0x00, 0x20):
        print(f"### 0x{cp:02X}")
        print()
        print("```")
        for line in render_lines(rom, cp):
            print(line)
        print("```")
        print()
    print("## Codepoints 0x20..0x7F -- ASCII range (Danish national variant)")
    print()
    print("`@A-Z` at 0x40..0x5A is identical to US-ASCII.  Positions 0x5B,")
    print("0x5C, 0x5D, 0x7B, 0x7C, 0x7D carry Danish glyphs (Æ, Ø, Å, æ, ø,")
    print("å); to display the US-ASCII `[\\]{|}` glyphs the outcon table must")
    print("remap them into 0x0B/0x0C/0x0D/0x1B/0x1C/0x1D.")
    print()
    for cp in range(0x20, 0x80):
        ch = chr(cp)
        # Escape backtick and pipe so they don't break the markdown header.
        safe = {"`": "\\`", "|": "\\|"}.get(ch, ch)
        print(f"### 0x{cp:02X} (`{safe}`)")
        print()
        print("```")
        for line in render_lines(rom, cp):
            print(line)
        print("```")
        print()


def parse_cps(args):
    if args.all_printable:
        return list(range(0x20, 0x80))
    if not args.cp:
        # Default: the codepoints that US-ASCII outcon cares about.
        return [0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x16,
                0x1B, 0x1C, 0x1D,
                0x40, 0x5B, 0x5C, 0x5D, 0x60, 0x7B, 0x7C, 0x7D, 0x7E]
    out = []
    for raw in args.cp:
        out.append(int(raw, 0))
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rom", default=DEFAULT_ROM,
                   help=f"ROM file (default: {DEFAULT_ROM})")
    p.add_argument("--cp", action="append",
                   help="Codepoint to render (hex 0xNN ok). Repeatable.")
    p.add_argument("--all-printable", action="store_true",
                   help="Render every codepoint 0x20..0x7F.")
    p.add_argument("--markdown", action="store_true",
                   help="Emit the full ROA296_GLYPH_BITMAPS.md doc.")
    args = p.parse_args()

    rom = load(args.rom)
    if args.markdown:
        dump_markdown(rom)
    else:
        dump_text(rom, parse_cps(args))


if __name__ == "__main__":
    main()
