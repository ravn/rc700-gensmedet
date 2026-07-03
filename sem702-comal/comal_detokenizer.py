#!/usr/bin/env python3
"""Detokenizer for RC700 standalone COMAL80 (rev 1.07) saved programs.

COMAL80 stores a program as a binary "SAVE" image, not source text.  This tool
reconstructs the source by decoding that image.  The keyword token values are
taken from the interpreter's own keyword table, found in the `SYSTEM` file of the
education disk (Bits:30003268) at offset ~0x1C00: entries are
`<class byte><KEYWORD letters>[<0x00 pad>]<token byte>`, and the value a *program*
uses is that token byte minus 1 (verified against logon: DIM=0x67, END=0x6b,
DIR=0x6f, PRINT=0x86, INPUT=0x87, CHAIN=0x8a).

Image layout (little-endian):
  [0]   09 81                      magic
  [2]   6 header bytes             (workspace ptrs / checksum — not needed here)
  [8]   "d/NAME" padded            program name, d = drive digit
  then  line records               <linenum:2> <tokens...>  separated by 01 00
  then  symbol table               variable names (referenced from lines)

Usage:
    comal_detokenizer.py <program-file> [--bytes] [--system SYSTEM]
    comal_detokenizer.py --dump-tokens [--system SYSTEM]

Status: reconstructs keywords, string constants and line structure; numbers,
operators and variable references are partially decoded and otherwise shown as
`{XX}` so nothing is silently lost.  Unknown/newer tokens are flagged — this is
how the tool exposes what a newer save format adds (e.g. EXTERNAL procedures).
"""
import sys

# --- program token map (token byte in a program -> keyword) --------------------
# Generated from the SYSTEM keyword table (see build_token_map); embedded so the
# tool is self-contained.  program token = table token - 1.
TOKENS = {
    0x00: "SIZE", 0x02: "AUTO", 0x03: "OUTPUT", 0x04: "EDIT", 0x05: "SAVE",
    0x06: "LIST", 0x07: "ENDFUNC", 0x08: "NEW", 0x09: "DUMP", 0x0A: "RUN",
    0x0B: "CON", 0x0C: "DEL", 0x0D: "OPEN", 0x38: "OR", 0x39: "IN", 0x3A: "AT",
    0x3B: "TO", 0x3C: "DO", 0x3E: "IF", 0x5A: "TAB", 0x5B: "REF", 0x5C: "STEP",
    0x5D: "ELSE", 0x5E: "FOR", 0x60: "NEXT", 0x61: "CASE", 0x62: "WHEN",
    0x63: "PROC", 0x65: "EXEC", 0x66: "GOTO", 0x67: "DIM", 0x68: "DATA",
    0x69: "READ", 0x6A: "STOP", 0x6B: "END", 0x6C: "ZONE", 0x6E: "COPY",
    0x6F: "DIR", 0x70: "FILE", 0x71: "THEN", 0x73: "STR", 0x74: "KEY",
    0x76: "VAL", 0x77: "SYS", 0x78: "ERR", 0x7A: "GET", 0x7E: "LOAD",
    0x7F: "CLOSED", 0x80: "ENDIF", 0x81: "WHILE", 0x83: "REPEAT", 0x84: "UNTIL",
    0x85: "GLOBAL", 0x86: "PRINT", 0x87: "INPUT", 0x88: "SELECT", 0x89: "MARGIN",
    0x8A: "CHAIN", 0x8B: "MOUNT", 0x8C: "PREFIX", 0x8D: "CLOSE", 0x8F: "CREATE",
    0x90: "DELETE", 0x91: "APPEND", 0x92: "RANDOM", 0x93: "WRITE", 0x94: "RENAME",
    0x95: "FALSE", 0x96: "ENABLE", 0x98: "USING", 0x9F: "RETURN", 0xA0: "ENTER",
    0xA1: "ENDWHILE", 0xA2: "ENDCASE", 0xA3: "ENDPROC", 0xA4: "RESTORE",
    0xA5: "DISMOUNT", 0xA6: "DISABLE", 0xA7: "CONTINUE", 0xA8: "HANDLER",
    0xA9: "EXTERNAL", 0xAF: "RENUMBER", 0xB0: "OTHERWISE", 0xB1: "RANDOMIZE",
}

# Statement-type codes: a line's FIRST byte.  For a statement that begins with a
# spelled keyword it is that keyword's token (e.g. PRINT=0x86); for statements
# with no leading keyword it is a code in the 0xC0-0xFF range.  Decoded empirically
# from LIST output of programs on the education disk (logon, opgave7, eks9.4):
STMT = {
    0xD1: ":=",     # assignment  (opgave7: a:=7)
    0xD3: "//",     # comment     (opgave7: // opgave 7 ...)
    0xD8: "FUNC",   # FUNC definition (eks9.4: FUNC k(n,r) EXTERNAL "...")
}

# RC700 national character substitution for display (COMAL stores ASCII bracket
# codes that render as ÆØÅæøå on the RC700 screen).
NAT = str.maketrans("[\\]{|}", "ÆØÅæøå")


def build_token_map(system_path):
    """Re-derive the token map from a SYSTEM interpreter file (for provenance)."""
    d = open(system_path, "rb").read()
    tab, kw, i = {}, b"", 0x1C00
    while i < 0x2010:
        b = d[i]
        if 0x41 <= b <= 0x5A:
            kw += bytes([b])
        elif b == 0x00:
            pass
        else:
            if len(kw) >= 2:
                tab[b - 1] = kw.decode("latin1")  # program token = table token - 1
            kw = b""
        i += 1
    return tab


def find_body(data):
    """Return offset of the first line record (just past the 'd/NAME' field)."""
    # name starts at 8 as "d/" then letters/spaces, terminated by the first
    # line's low linenum byte.  The name field is padded with spaces; the body
    # begins at the first <linenum:2> whose value is small and ascending.
    i = 10   # 10-byte header: 09 81 + 6 ptr/checksum bytes
    # skip "d/"
    if data[i + 1:i + 2] == b"/":
        i += 2
    # skip name chars (printable) and trailing spaces
    while i < len(data) and 0x20 <= data[i] < 0x7F:
        i += 1
    return i


def read_lines(data):
    """Yield (linenum, token_bytes).

    Lines are split on ascending line-number *anchors* (a plausible 16-bit
    line number that sits at the body start or right after a 01 00 link).  This
    is more robust than splitting on 01 00 alone, because 01 00 also occurs
    *inside* statements (as operand/pointer bytes), which truncated large
    programs (e.g. RACE.PRG) at the first internal 01 00.
    """
    body = find_body(data)
    n = len(data)
    cands = []
    for p in range(body, n - 2):
        if p == body or (data[p - 2] == 1 and data[p - 1] == 0):
            v = data[p] | (data[p + 1] << 8)
            if 0 < v <= 9999:
                cands.append((p, v))
    last = -1
    for idx, (p, v) in enumerate(cands):
        if v > last:
            end = cands[idx + 1][0] - 2 if idx + 1 < len(cands) else n
            # trim trailing zero padding / symbol-table start
            yield v, data[p + 2:end]
            last = v


def decode_tokens(tok):
    """Best-effort render of one line's token bytes to source text."""
    out, i, n = [], 0, len(tok)
    # comment lines: first byte 0xD3, then <len> 01 01 <text>
    if n and tok[0] == 0xD3:
        j = 2
        while j < n and tok[j] != 0x01:
            j += 1
        text = tok[j + 2:] if j + 2 <= n else b""
        text = bytes(c for c in text if 0x20 <= c < 0x7F)
        return "// " + text.decode("latin1").translate(NAT).strip()
    first = True
    while i < n:
        b = tok[i]
        # string constant: <ptr_lo> BF <len:2> <chars>
        if i + 3 < n and tok[i + 1] == 0xBF:
            slen = tok[i + 2] | (tok[i + 3] << 8)
            s = tok[i + 4:i + 4 + slen]
            if 0 < slen < 256 and all(0x20 <= c < 0x7F for c in s):
                out.append('"' + s.decode("latin1").translate(NAT) + '"')
                i += 4 + slen
                first = False
                continue
        # small-integer constant: 7F <v> <lo>, value = 0x8F - <v>  (1..~99)
        if b == 0x7F and i + 2 < n:
            val = 0x8F - tok[i + 1]
            if 0 <= val <= 99:
                out.append(str(val))
                i += 3
                first = False
                continue
        # variable reference: <idx> FF  (idx indexes the symbol table; the same
        # variable always gets the same idx, so vXX is a stable placeholder name)
        if i + 1 < n and tok[i + 1] == 0xFF and b >= 0xE0:
            out.append("v%02X" % b)
            i += 2
            first = False
            continue
        if first and b in STMT:
            out.append(STMT[b])
        elif b in TOKENS:
            out.append(TOKENS[b])
        elif 0x20 <= b < 0x7F:            # literal ASCII (punctuation, digits)
            out.append(chr(b))
        else:
            out.append("{%02X}" % b)
        i += 1
        first = False
    return " ".join(p for p in out if p != "")


def detokenize(data):
    name = ""
    if data[11:12] == b"/":
        j = 10
        while j < len(data) and 0x20 <= data[j] < 0x7F:
            j += 1
        name = data[8:j].decode("latin1").rstrip()
    lines = []
    unknown = set()
    for linenum, tok in read_lines(data):
        for b in tok:
            if b not in TOKENS and not (0x20 <= b < 0x7F):
                unknown.add(b)
        lines.append("%04d %s" % (linenum, decode_tokens(tok)))
    return name, lines, unknown


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="RC700 COMAL80 program detokenizer")
    ap.add_argument("file", nargs="?")
    ap.add_argument("--system", help="derive token map from a SYSTEM file")
    ap.add_argument("--dump-tokens", action="store_true")
    ap.add_argument("--bytes", action="store_true", help="also show raw line bytes")
    a = ap.parse_args(argv)
    if a.system:
        TOKENS.clear()
        TOKENS.update(build_token_map(a.system))
    if a.dump_tokens:
        for t in sorted(TOKENS):
            print("0x%02X %s" % (t, TOKENS[t]))
        return
    if not a.file:
        ap.error("program file required")
    data = open(a.file, "rb").read()
    name, lines, unknown = detokenize(data)
    print("# program: %s   (%d bytes)" % (name, len(data)))
    for ln in lines:
        print(ln)
    if unknown:
        print("# unknown/undecoded tokens: " +
              " ".join("0x%02X" % b for b in sorted(unknown)))


if __name__ == "__main__":
    main(sys.argv[1:])
