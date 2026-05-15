#!/usr/bin/env python3
"""dri_split.py -- convert DRI-MAC source to one-statement-per-line.

DRI MAC uses '!' as a compact statement-AND-comment terminator:

    nosub:  ;no submit file! call del$sub
            xra a! ret

That is: everything after ';' is a comment until '!' or end of line;
'!' starts a fresh statement even inside a comment.

This preprocessor turns every '!' into a newline (plus a tab) so each
statement lives on its own line, while preserving CRLF line endings
required by RMAC.

Usage:
    dri_split.py input.asm output.mac
"""
import sys


def split_line(line: str) -> list[str]:
    """Split a single source line on '!' statement terminators.
    Honours semicolon-comments: within a comment, '!' still breaks
    to a new statement (because in DRI MAC the '!' terminates comments
    too). String literals ('...') cannot contain '!' in CCP.ASM but
    we skip them defensively anyway."""
    out: list[str] = []
    buf = []
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "'" and not in_str:
            in_str = True
            buf.append(c)
        elif c == "'" and in_str:
            in_str = False
            buf.append(c)
        elif c == '!' and not in_str:
            out.append(''.join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1
    out.append(''.join(buf))
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: dri_split.py <input.asm> <output.mac>")
    inp, outp = sys.argv[1], sys.argv[2]
    with open(inp) as f:
        src = f.read().replace('\r\n', '\n')
    out_lines = []
    for raw in src.split('\n'):
        parts = split_line(raw)
        if len(parts) == 1:
            out_lines.append(raw)
        else:
            # First sub-statement keeps the original leading whitespace;
            # the rest are indented with a tab so they read as body.
            out_lines.append(parts[0].rstrip())
            for p in parts[1:]:
                out_lines.append('\t' + p.strip())
    with open(outp, 'wb') as f:
        f.write('\r\n'.join(out_lines).encode())
        f.write(b'\r\n')


if __name__ == '__main__':
    main()
