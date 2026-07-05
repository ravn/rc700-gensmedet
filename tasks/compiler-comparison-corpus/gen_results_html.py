#!/usr/bin/env python3
"""gen_results_html.py -- render sweep/results.tsv into sweep/results.html.

Called at the end of sweep.sh so the HTML view can never drift from the TSV.
Green cell = best (minimum) value in a (bench, column) group that verified
PASS.  Verify cells are coloured PASS/XFAIL/FAIL.  bin/ts are compared; text
is shown but never marked best (SDCC-map/.COM lanes report n/a there).
"""
import sys, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
TSV = os.path.join(HERE, "sweep", "results.tsv")
OUT = os.path.join(HERE, "sweep", "results.html")

# compiler -> (dot colour, legend note)
COMPILERS = {
    "llvm-z80":   ("#2563eb", "freestanding (direct ELF link)"),
    "zsdcc":      ("#059669", ""),
    "dcc":        ("#d97706", ""),
    "llvm-z88dk": ("#db2777", "clang &rarr; z88dk clib .COM; bin includes full RTL, text n/a"),
    "xcc":        ("#0891b2", "XYZ Suite; SDCC-ABI .COM, bin includes libc/RTL, text n/a"),
}


def is_pass(v):
    return v == "PASS"


def as_int(s):
    try:
        return int(s)
    except (TypeError, ValueError):
        return None


def main():
    with open(TSV) as f:
        rows = [ln.rstrip("\n").split("\t") for ln in f if ln.strip()]
    header, data = rows[0], rows[1:]

    # group rows by bench (preserve first-seen order)
    benches = []
    by_bench = {}
    for r in data:
        b = r[0]
        if b not in by_bench:
            by_bench[b] = []
            benches.append(b)
        by_bench[b].append(r)

    # per (bench, numeric column) -> best value among PASS/XPASS rows.
    # column index map in the TSV.
    idx = {name: i for i, name in enumerate(header)}
    best_cols = ["size_bin", "size_ts", "speed_bin", "speed_ts"]
    ver_of = {"size_bin": "size_verify", "size_ts": "size_verify",
              "speed_bin": "speed_verify", "speed_ts": "speed_verify"}
    best = {}  # (bench, col) -> best int
    for b in benches:
        for col in best_cols:
            vals = []
            for r in by_bench[b]:
                verify = r[idx[ver_of[col]]]
                if is_pass(verify):
                    v = as_int(r[idx[col]])
                    if v is not None:
                        vals.append(v)
            if vals:
                best[(b, col)] = min(vals)

    def vcell(v):
        cls = "pass" if v == "PASS" else ("xfail" if v.startswith("XFAIL") or v.startswith("XPASS") else "fail")
        return f'<td class="{cls}">{v}</td>'

    def numcell(b, col, raw):
        v = as_int(raw)
        klass = "best" if (v is not None and best.get((b, col)) == v) else ""
        attr = f' class="{klass}"' if klass else ""
        return f"<td{attr}>{raw}</td>"

    out = []
    out.append('<!doctype html><meta charset="utf-8">')
    out.append("<title>Z80 compiler sweep</title>")
    out.append("""<style>
 body{font:14px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;margin:2rem;color:#0f172a}
 h1{font-size:1.3rem} .sub{color:#64748b;margin-bottom:1rem}
 table{border-collapse:collapse;font-variant-numeric:tabular-nums}
 th,td{padding:.35rem .6rem;text-align:right;border:1px solid #e2e8f0}
 th{background:#f1f5f9;position:sticky;top:0}
 td.bench,td.comp,th.l{text-align:left}
 td.bench{font-weight:600}
 .best{background:#dcfce7;font-weight:700}
 .pass{color:#059669;font-weight:600} .xfail{color:#d97706} .fail{color:#dc2626;font-weight:700}
 .grp{background:#e0e7ff} .leg{margin:.8rem 0;color:#475569}
 .leg b{color:#0f172a}
</style>""")
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    n = len(COMPILERS)
    out.append(f"<h1>Z80 compiler comparison sweep &mdash; {n}-way</h1>")
    out.append(f'<div class="sub">{ts} &nbsp;|&nbsp; {len(benches)} benchmarks &times; '
               '{size, speed} &nbsp;|&nbsp; green cell = best (min) that verified PASS</div>')
    leg = ['<div class="leg">']
    for name, (colour, note) in COMPILERS.items():
        note_html = f" {note} " if note else " "
        leg.append(f'<span style="color:{colour}">&#9679;</span> <b>{name}</b>{note_html}&nbsp;')
    leg.append("</div>")
    out.append("".join(leg))

    out.append("<table>")
    out.append("<thead>")
    out.append('<tr><th class="l">bench</th><th class="l">compiler</th>'
               '<th class="grp" colspan="4">size mode</th>'
               '<th class="grp" colspan="4">speed mode</th></tr>')
    out.append('<tr><th></th><th></th>'
               "<th>bin</th><th>text</th><th>tstates</th><th>verify</th>"
               "<th>bin</th><th>text</th><th>tstates</th><th>verify</th></tr>")
    out.append("</thead>")
    out.append("<tbody>")
    for bi, b in enumerate(benches):
        for ri, r in enumerate(by_bench[b]):
            comp = r[idx["compiler"]]
            colour = COMPILERS.get(comp, ("#334155", ""))[0]
            style = ' style="border-top:2px solid #cbd5e1"' if (bi > 0 and ri == 0) else ""
            tr = [f"<tr{style}>"]
            tr.append(f'<td class="bench">{b}</td>')
            tr.append(f'<td class="comp"><span style="color:{colour}">&#9679;</span> {comp}</td>')
            tr.append(numcell(b, "size_bin", r[idx["size_bin"]]))
            tr.append(f'<td>{r[idx["size_text"]]}</td>')
            tr.append(numcell(b, "size_ts", r[idx["size_ts"]]))
            tr.append(vcell(r[idx["size_verify"]]))
            tr.append(numcell(b, "speed_bin", r[idx["speed_bin"]]))
            tr.append(f'<td>{r[idx["speed_text"]]}</td>')
            tr.append(numcell(b, "speed_ts", r[idx["speed_ts"]]))
            tr.append(vcell(r[idx["speed_verify"]]))
            tr.append("</tr>")
            out.append("".join(tr))
    out.append("</tbody></table>")

    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"Wrote {os.path.relpath(OUT, HERE)}")


if __name__ == "__main__":
    main()
