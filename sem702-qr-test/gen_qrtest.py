#!/usr/bin/env python3
"""Generate qrtest.asm -- a small CP/M .COM that paints two QR codes
of the same URL side-by-side on the RC702 display via SEM702 sextants:
the left one at 1x sub-pixel scale, the right one at 2x.  Useful for
A/B-comparing scannability at different physical sizes.

Each char cell is a 2-sub-col x 3-sub-row mosaic of sextants; with
scale s, a QR module occupies s x s sub-pixels.  The 8275 cell is 7
dots x 11 lines, so a sub-pixel is ~3.5 x 3.67 dots -- close to square.

After paint, the .COM busy-waits ~10 s then JP 0 (warm boot back to
CCP) so the user can run something else without resetting.
"""
import argparse
import os
import sys

try:
    import qrcode
except ImportError:
    sys.stderr.write("error: qrcode module not installed (pip install qrcode)\n")
    sys.exit(1)


def pattern_to_charcode(pattern: int) -> int:
    """Map a 6-bit sextant pattern (bit 0 = top-left) to its ROA327 codepoint.
    Matches autoload's define_sextants() exactly: 0x20-0x3F + 0x60-0x7F."""
    if pattern == 0:
        return 0x20
    if pattern < 32:
        return 0x20 + pattern
    return 0x60 + (pattern - 32)


def render_qr(url: str, scale: int, quiet_modules: int = 2):
    """Render a QR at `scale`x sub-pixels per module.  Return
    (codes, cols, rows, qr_version)."""
    qr = qrcode.QRCode(
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=1, border=0,
    )
    qr.add_data(url)
    qr.make(fit=True)
    matrix = qr.modules
    size = len(matrix)
    qr_version = (size - 17) // 4

    quiet_sub = quiet_modules * scale
    img_sub   = size * scale + 2 * quiet_sub
    cols = (img_sub + 1) // 2
    rows = (img_sub + 2) // 3

    codes = []
    for row in range(rows):
        for col in range(cols):
            pattern = 0
            for py in range(3):
                for px in range(2):
                    iy = row * 3 + py
                    ix = col * 2 + px
                    if iy < quiet_sub or ix < quiet_sub:
                        continue
                    qy = iy - quiet_sub
                    qx = ix - quiet_sub
                    if qy >= size * scale or qx >= size * scale:
                        continue
                    if matrix[qy // scale][qx // scale]:
                        pattern |= 1 << (py * 2 + px)
            codes.append(pattern_to_charcode(pattern))
    return codes, cols, rows, qr_version


def emit_asm(url, qr1, qr2, gap, top_row, out_path):
    """qrN = (codes, cols, rows, version).  qr1 placed at (top_row, 0),
    qr2 placed at (top_row, qr1.cols + gap)."""
    c1, w1, h1, v1 = qr1
    c2, w2, h2, v2 = qr2
    col1 = 0
    col2 = w1 + gap
    total_w = col2 + w2

    if total_w > 80:
        sys.stderr.write(f"error: combined QRs need {total_w} cols (>80)\n")
        sys.exit(1)
    if top_row + max(h1, h2) > 25:
        sys.stderr.write(f"error: rows overflow ({top_row + max(h1, h2)} > 25)\n")
        sys.exit(1)

    with open(out_path, "w") as f:
        f.write(f""";; {os.path.basename(out_path)} -- paint two QR codes side-by-side on RC702 via SEM702.
;;   URL          = {url}
;;   left  (1x)   = v{v1}, {w1} cells x {h1} rows at (row {top_row}, col {col1})
;;   right (2x)   = v{v2}, {w2} cells x {h2} rows at (row {top_row}, col {col2})
;;   field-attr 0x84 at (row 0, col 0) flips GPA0=1 for the rest of screen
;; After paint: ~10 s busy-wait then JP 0 (CP/M warm boot) -> back to CCP.

        .Z80
        ORG     0100h

        ;; clear 80*25 = 2000 cells to sextant pattern 0 (code 0x20 = blank)
        ld      hl, 0F800h
        ld      de, 0F801h
        ld      bc, 1999
        ld      (hl), 020h
        ldir

        ;; field-attribute byte at (0,0): bit 2 = GPA0 = 1 (SEM702 half).
        ;; Persists across rows for the rest of the screen.
        ld      a, 084h
        ld      (0F800h), a

        ;; left QR (1x)
        ld      hl, qr1_data
        ld      de, 0F800h + {top_row} * 80 + {col1}
        ld      a, {h1}
qr1_loop:
        push    af
        ld      bc, {w1}
        ldir
        ex      de, hl
        ld      bc, {80 - w1}
        add     hl, bc
        ex      de, hl
        pop     af
        dec     a
        jr      nz, qr1_loop

        ;; right QR (2x)
        ld      hl, qr2_data
        ld      de, 0F800h + {top_row} * 80 + {col2}
        ld      a, {h2}
qr2_loop:
        push    af
        ld      bc, {w2}
        ldir
        ex      de, hl
        ld      bc, {80 - w2}
        add     hl, bc
        ex      de, hl
        pop     af
        dec     a
        jr      nz, qr2_loop

        ;; ~10 s at 4 MHz: 24 outer x 65536 inner x ~26 T = ~40.9M T = ~10.23 s.
        ;; IRQs stay enabled so the 8275 ISR keeps DMA refreshing the display.
        ld      b, 24
delay_outer:
        ld      hl, 0
delay_inner:
        dec     hl
        ld      a, h
        or      l
        jr      nz, delay_inner
        djnz    delay_outer

        jp      0                  ; CP/M warm-boot vector -> back to CCP

qr1_data:
""")
        def dump(codes):
            for i in range(0, len(codes), 16):
                chunk = codes[i:i + 16]
                f.write("        defb    " + ", ".join(f"0{b:02X}h" for b in chunk) + "\n")
        dump(c1)
        f.write("\nqr2_data:\n")
        dump(c2)
        f.write("        end\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--gap",   type=int, default=3,
                    help="blank columns between the two QRs (default 3)")
    ap.add_argument("--top",   type=int, default=1,
                    help="top screen row for both QRs (default 1)")
    args = ap.parse_args()

    qr1 = render_qr(args.url, 1)
    qr2 = render_qr(args.url, 2)
    print(f"left  (1x): v{qr1[3]}, {qr1[1]}x{qr1[2]} cells, {len(qr1[0])} codes")
    print(f"right (2x): v{qr2[3]}, {qr2[1]}x{qr2[2]} cells, {len(qr2[0])} codes")

    emit_asm(args.url, qr1, qr2, args.gap, args.top, args.output)


if __name__ == "__main__":
    main()
