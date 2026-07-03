#!/usr/bin/env python3
"""Host-side SIO-B driver for the cpnos PPAS + TOD regression test.

Why no MAME autoboot Lua: any `-autoboot_script` (even an empty one) puts
MAME's Lua engine in the emulation loop, which perturbs device/scheduler
timing enough to break the wall-clock-coupled PIO cpnet_bridge netboot on a
fast host -- the slave stalls after the first LOGIN byte and never reaches
E>.  Verified 2026-07-03: no-autoboot boots to E> reliably (3367+ bridge
bytes); ANY autoboot stalls at 1 byte, independent of MAME speed.  So we
drive the slave entirely from OUTSIDE MAME, over the joined-console SIO-B
link (cpnos impl_conin reads SIO_B_DATA when console_joined, resident.c),
exactly like the rcbios polypascal_pio_inject.py harness.

Wire topology (set by the shell wrapper):
    PIO-B  -> cpnet_bridge      -> :4002  (mpm-net2 master; CP/NET frames)
    SIO-B  -> null_modem socket -> this script (joined console: CONOUT
                                    mirror out + keyboard inject in)

Flow (markers are literal substrings of the SIO-B CONOUT mirror):
    E>       boot prompt         -> send "PPAS\\r"
    >>       PPAS ready          -> send "L PRIMES\\r"
    >>       PRIMES loaded       -> send "R\\r"
    29989    last prime printed  -> (advance)
    >>       post-run prompt     -> send "Q\\r"
    E>       back at CCP         -> send "TODGET\\r"
    YYYY-MM-DD HH:MM:SS          -> TOD via CP/NET FN-105 confirmed
    E>       back at CCP         -> PASS

TOD works WITHOUT the slave logging in: the master's SERVER.RSP gated every
request behind chklog except LOGIN, so gettod used to return 0xff ("not
logged in").  cpnet/mpm-server/server.asm now exempts gettod (FN 105 -> 55)
from that check -- a clock read needs no authentication -- so any slave can
ask the time directly (ravn 2026-07-03).  Requires MPM.SYS rebuilt via
cpnet/mpm-server/rebuild-mpm-sys.sh --install.

Writes /tmp/cpnos_inject_result.txt with PASS or FAIL+reason.
"""
import argparse
import re
import socket
import sys
import time

RESULT = "/tmp/cpnos_inject_result.txt"
DATE_RE = re.compile(rb"20[0-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]")

# (deadline_sec, marker, cmd_after, name).  marker=bytes to wait for;
# cmd_after=bytes to send once matched (or None to just advance);
# DATE marker is a regex handled specially.
STAGES = [
    (60.0,  b"E>",    b"PPAS\r",     "boot E> -> PPAS"),
    (90.0,  b">>",    b"L PRIMES\r", "PPAS ready -> L PRIMES"),
    (90.0,  b">>",    b"R\r",        "PRIMES loaded -> R"),
    (180.0, b"29989", None,          "PRIMES output complete (29989)"),
    (30.0,  b">>",    b"Q\r",        "post-run >> -> Q"),
    (30.0,  b"E>",    b"TODGET\r",   "back at E> -> TODGET"),
    (60.0,  b"DATE",  None,          "TOD via FN-105 (YYYY-MM-DD HH:MM:SS)"),
    (30.0,  b"E>",    None,          "back at E> after TODGET"),
]


def write_result(text):
    with open(RESULT, "w") as f:
        f.write(text + "\n")


def find_marker(marker, buf):
    """Return end-index of marker in buf, or -1.  Handles the DATE regex."""
    if marker == b"DATE":
        m = DATE_RE.search(buf)
        return m.end() if m else -1
    idx = buf.find(marker)
    return -1 if idx < 0 else idx + len(marker)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", type=int, default=9100, nargs="?")
    ap.add_argument("--log", default="/tmp/cpnos_inject_siob.raw")
    ap.add_argument("--accept-timeout", type=float, default=120.0)
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    print(f"cpnos_inject listening on :{args.port}", flush=True)
    srv.settimeout(args.accept_timeout)
    try:
        conn, peer = srv.accept()
    except socket.timeout:
        write_result("FAIL: no MAME connection within accept timeout")
        sys.exit(1)
    print(f"MAME connected from {peer}", flush=True)
    conn.settimeout(0.3)

    log = open(args.log, "wb", buffering=0)
    buf = bytearray()
    stage_idx = 0
    t0 = time.monotonic()
    stage_deadline = t0 + STAGES[0][0]
    print(f"[stage 0] waiting for {STAGES[0][1]!r} ({STAGES[0][3]})", flush=True)

    while stage_idx < len(STAGES):
        try:
            data = conn.recv(64)
        except socket.timeout:
            data = b""
        if data:
            log.write(data)
            buf.extend(data)
            if len(buf) > 8192:
                del buf[:4096]

        deadline_s, marker, cmd, name = STAGES[stage_idx]
        end = find_marker(marker, bytes(buf))
        if end >= 0:
            elapsed = time.monotonic() - t0
            matched = bytes(buf[max(0, end - 10):end])
            print(f"[stage {stage_idx}] matched ...{matched!r} (t={elapsed:.2f}s) -> "
                  f"{'send ' + repr(cmd) if cmd else 'advance'}", flush=True)
            if cmd:
                # Pace bytes so we never overrun the slave's SIO-B RX FIFO.
                for b in cmd:
                    conn.sendall(bytes([b]))
                    time.sleep(0.02)
            del buf[:end]
            stage_idx += 1
            if stage_idx < len(STAGES):
                nd, nm, _, nn = STAGES[stage_idx]
                stage_deadline = time.monotonic() + nd
                print(f"[stage {stage_idx}] waiting for {nm!r} ({nn})", flush=True)
            continue

        if time.monotonic() > stage_deadline:
            elapsed = time.monotonic() - t0
            reason = (f"timeout at stage {stage_idx} ({name}); wanted {marker!r}; "
                      f"last 80 B = {bytes(buf[-80:])!r}")
            print(f"FAIL: {reason}", flush=True)
            write_result(f"FAIL: {reason}")
            sys.exit(1)

    elapsed = time.monotonic() - t0
    print(f"PASS: all {len(STAGES)} stages green (t={elapsed:.2f}s)", flush=True)
    write_result(f"PASS: cpnos PPAS PRIMES->29989 + Q->E> and TODGET FN-105 "
                 f"date returned (t={elapsed:.2f}s)")


if __name__ == "__main__":
    main()
