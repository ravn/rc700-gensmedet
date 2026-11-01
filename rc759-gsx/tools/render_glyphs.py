#!/usr/bin/env python3
"""Render source glyphs: python3 tools/render_glyphs.py > docs/glyphs.svg."""

import html
import re
from pathlib import Path


def main():
    source = (Path(__file__).resolve().parents[1] / "src/glyphs.a86").read_text()
    table = source.split("glyph_offsets:", 1)[1].split("; Signed-nibble vectors;", 1)[0]
    names = re.findall(r"\bdw\s+offset\s+(glyph_\w+)", table)
    if len(names) != 128:
        raise ValueError("Expected 128 glyph pointers")

    colors = ["#0072b2", "#d55e00", "#009e73", "#cc79a7", "#8a6700", "#6b50a1"]
    width, height = 1840, 1984
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'width="{width}" height="{height}">',
        "<title>RC759 GSX H1 vector glyphs</title>",
        "<desc>128 glyphs in character-code order. Stroke colors distinguish "
        "pen-down paths; arrows show direction on every segment.</desc>",
        '<rect width="100%" height="100%" fill="white"/>',
        '<g font-family="monospace" fill="#222">',
        '<text x="16" y="25" font-size="18">RC759 GSX H1: vector glyphs</text>',
        '<text x="16" y="47" font-size="12">Each stroke has a distinct color; '
        'arrows show segment direction. Circles mark stroke starts. '
        'Geometry only, before scaling/rotation/rasterization.</text>',
        "</g>",
        "<defs>",
    ]
    for index, color in enumerate(colors):
        out.append(
            f'<marker id="arrow{index}" viewBox="0 0 6 6" refX="5" refY="3" '
            f'markerWidth="5" markerHeight="5" orient="auto">'
            f'<path d="M0,0 L6,3 L0,6 Z" fill="{color}"/></marker>'
        )
    out.append("</defs>")

    for code, name in enumerate(names):
        match = re.search(
            r"^" + re.escape(name) + r":\n((?:\s*db\s+[^\n]+\n)+)", source, re.M
        )
        if match is None:
            raise ValueError(f"Missing definition: {name}")
        values = [
            int(value.strip()[:-1], 16)
            for line in match[1].splitlines()
            for value in line.strip().split(None, 1)[1].split(",")
        ]
        strokes, current = [], []
        for value in values:
            if value in (128, 136):
                if current:
                    strokes.append(current)
                    current = []
                if value == 136:
                    break
            else:
                current.append(tuple(n if n < 8 else n - 16
                                     for n in (value >> 4, value & 15)))
        else:
            raise ValueError(f"Missing glyph terminator: {name}")

        left, top = 16 + (code % 8) * 228, 64 + (code // 8) * 120
        caption = f"{code}" + (f" ({chr(code)})" if 33 <= code <= 126 else "")
        out.extend([
            f'<g id="{name}"><title>{html.escape(name)}</title>',
            f'<rect x="{left}" y="{top}" width="224" height="116" '
            'rx="3" fill="#fafafa" stroke="#ddd"/>',
            f'<text x="{left + 6}" y="{top + 15}" font-family="monospace" '
            f'font-size="12">{html.escape(caption)}</text>',
            f'<text x="{left + 6}" y="{top + 29}" font-family="monospace" '
            f'font-size="9">{html.escape(name)}</text>',
        ])
        points = [point for stroke in strokes for point in stroke]
        if points:
            xmin, xmax = min(x for x, y in points), max(x for x, y in points)
            ymin, ymax = min(y for x, y in points), max(y for x, y in points)
            scale = 4
            cx, cy = left + 112, top + 74

            def position(point):
                x, y = point
                return cx + (x - (xmin + xmax) / 2) * scale, \
                    cy - (y - (ymin + ymax) / 2) * scale

            for index, stroke in enumerate(strokes):
                color_index = index % len(colors)
                color = colors[color_index]
                for a, b in zip(stroke, stroke[1:]):
                    x1, y1 = position(a)
                    x2, y2 = position(b)
                    out.append(
                        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
                        f'stroke="{color}" stroke-width="1.2" '
                        f'marker-end="url(#arrow{color_index})"/>'
                    )
                x, y = position(stroke[0])
                out.append(f'<circle cx="{x}" cy="{y}" r="2" fill="{color}">'
                           f'<title>Stroke {index + 1} start</title></circle>')
        else:
            out.append(f'<text x="{left + 90}" y="{top + 76}" '
                       'font-family="monospace" font-size="12" fill="#777">'
                       "empty</text>")
        out.append("</g>")
    out.append("</svg>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
