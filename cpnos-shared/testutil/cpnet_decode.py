#!/usr/bin/env python3
"""Decode an sio_tee.py byte log into CP/NET 1.2 messages.

Usage:
    cpnet_decode.py [--in /tmp/cpnos_sio_tee.log] [--out /tmp/cpnos_cpnet.log]

Wire framing (DRI SNIOS, half-duplex):
    sender -> ENQ (0x05)
    recipient -> ACK (0x06)  [or NAK 0x15 -> retry]
    sender -> SOH (0x01)
    sender -> FMT DID SID FNC SIZ          (5-byte header)
    sender -> STX (0x02)
    sender -> DAT[SIZ+1]                    (payload)
    sender -> ETX (0x03)
    sender -> CK1 CK2                       (16-bit checksum)
    recipient -> ACK (0x06)
    [reply role-swaps]

The sio_tee.py log lines look like:
    <t_ms>  <dir>  <n>  <hex> (<ascii>)
where <dir> is "M>" (MAME->MPM) or "<M" (MPM->MAME).

Output is one line per logical CP/NET message:
    [t=12.34s] M->S  FMT=00 DID=00 SID=01 FNC=0x40 SIZ=08 DAT=...   (LOGIN)
"""

import argparse
import re
from typing import List, Tuple

# ---------------------------------------------------------------- decoding

ENQ = 0x05
ACK = 0x06
NAK = 0x15
SOH = 0x01
STX = 0x02
ETX = 0x03

CPNET_FNC = {
    # CP/M BDOS calls forwarded by NDOS (subset).  Names per cpnet.h /
    # cpnet-z80 spec; "?" for ones we haven't seen documented.
    0x00: "NETWORK_STATUS_REQ",
    0x06: "CONFIG_TABLE_REQ",
    0x0C: "BDOS_VERSION",          # 12
    0x0D: "BDOS_DISK_RESET",       # 13
    0x0E: "BDOS_SELDSK",           # 14
    0x0F: "BDOS_OPEN",             # 15
    0x10: "BDOS_CLOSE",             # 16
    0x11: "BDOS_SEARCH_FIRST",     # 17
    0x13: "BDOS_DELETE",            # 19
    0x14: "BDOS_READ_SEQ",          # 20
    0x15: "BDOS_WRITE_SEQ",         # 21
    0x1A: "BDOS_SET_DMA",           # 26
    0x20: "BDOS_GET_USER",          # 32
    0x27: "BDOS_RESET_DRIVE",       # 39   ← prominent in our trace
    0x40: "LOGIN",
    0x41: "LOGOFF",
    0x42: "SEND_MAIL",
    0x44: "RECEIVE_MAIL",
    0x46: "DEVICE_STATUS",          # ?    ← prominent in our trace
}


def decode_fnc(fnc: int) -> str:
    return CPNET_FNC.get(fnc, "?")


# ---------------------------------------------------------------- parsing

LINE_RE = re.compile(r"^\s*([\d.]+)\s+(M>|<M)\s+\d+\s+([0-9A-Fa-f]{2})")


def parse_log(path: str) -> List[Tuple[float, str, int]]:
    out = []
    with open(path) as f:
        for line in f:
            m = LINE_RE.match(line)
            if not m:
                continue
            t_ms = float(m.group(1))
            d = m.group(2)
            b = int(m.group(3), 16)
            out.append((t_ms, d, b))
    return out


# Walk the byte stream, splitting into messages.  A message ends with
# ETX + 2 checksum bytes; the receiver's ACK belongs to the message that
# just finished from the OTHER direction.

def fmt_hex(bs):
    return " ".join(f"{b:02X}" for b in bs)


def fmt_ascii(bs):
    return "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in bs)


def decode_stream(events: List[Tuple[float, str, int]]):
    msgs = []  # (t_start, dir, header, dat, ck, t_end)
    # state machine for each direction independently
    states = {"M>": [], "<M": []}
    starts = {"M>": None, "<M": None}
    for t, d, b in events:
        # ENQ / ACK / NAK as their own pseudo-messages
        if not states[d] and b == ENQ:
            msgs.append((t, d, "ENQ", [], []))
            continue
        if not states[d] and b == ACK:
            msgs.append((t, d, "ACK", [], []))
            continue
        if not states[d] and b == NAK:
            msgs.append((t, d, "NAK", [], []))
            continue
        if not states[d] and b == SOH:
            states[d] = [SOH]
            starts[d] = t
            continue
        if states[d]:
            states[d].append(b)
            # full frame: SOH + 5-hdr + STX + DAT(>=1) + ETX + CK1 + CK2.
            # Find ETX after STX, then expect 2 more bytes.
            buf = states[d]
            if STX in buf:
                stx_at = buf.index(STX)
                # Look for ETX after STX (skip STX itself)
                if ETX in buf[stx_at + 1:]:
                    etx_at = buf.index(ETX, stx_at + 1)
                    # Need 2 bytes of checksum after ETX
                    if len(buf) >= etx_at + 3:
                        # Frame complete
                        hdr = buf[1:stx_at]                # FMT DID SID FNC SIZ
                        dat = buf[stx_at + 1:etx_at]
                        ck = buf[etx_at + 1:etx_at + 3]
                        msgs.append((starts[d], d, "MSG", hdr, dat, ck, t))
                        states[d] = []
                        starts[d] = None
    return msgs


def render(msgs, out):
    for m in msgs:
        t = m[0]
        d = m[1]
        kind = m[2]
        if kind in ("ENQ", "ACK", "NAK"):
            out.write(f"[t={t/1000:7.3f}s] {d}  {kind}\n")
            continue
        hdr = m[3]
        dat = m[4]
        ck = m[5]
        if len(hdr) >= 5:
            fmt, did, sid, fnc, siz = hdr[:5]
            arrow = "S->M" if d == "M>" else "M->S"
            name = decode_fnc(fnc)
            dat_short = fmt_hex(dat[:24])
            if len(dat) > 24:
                dat_short += f" ...({len(dat)} B total)"
            ascii_short = fmt_ascii(dat[:24])
            out.write(
                f"[t={t/1000:7.3f}s] {d} {arrow}  "
                f"FMT={fmt:02X} DID={did:02X} SID={sid:02X} "
                f"FNC=0x{fnc:02X} ({name}) SIZ={siz:02X}  "
                f"DAT[{dat_short}]  '{ascii_short}'  CK={fmt_hex(ck)}\n")
        else:
            out.write(f"[t={t/1000:7.3f}s] {d}  partial  hdr={fmt_hex(hdr)}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", default="/tmp/cpnos_sio_tee.log")
    ap.add_argument("--out", dest="dst", default="/tmp/cpnos_cpnet.log")
    args = ap.parse_args()

    events = parse_log(args.src)
    msgs = decode_stream(events)

    with open(args.dst, "w") as f:
        f.write(f"# {len(events)} byte events -> {len(msgs)} cp/net frames\n")
        render(msgs, f)
    print(f"wrote {args.dst}: {len(msgs)} frames from {len(events)} byte events")


if __name__ == "__main__":
    main()
