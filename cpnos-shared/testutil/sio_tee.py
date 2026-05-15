#!/usr/bin/env python3
"""TCP tee/proxy for the MAME <-> z80pack-MP/M SIO-A null_modem link.

MAME connects here (listen port); we connect onward to z80pack-MP/M
(upstream host:port).  Every byte is forwarded transparently and logged
with direction + monotonic timestamp + offset.

Usage:
    sio_tee.py [--listen PORT] [--upstream HOST:PORT] [--log FILE]

Defaults: listen 4012, upstream 127.0.0.1:4002, log /tmp/cpnos_sio_tee.log

The log is single-line records:
    <t_ms> <dir> <off> <byte>
  dir is M> (MAME -> MP/M) or <M (MP/M -> MAME)
  off is the cumulative byte offset in that direction
  byte is two-hex-digit value with printable ASCII in parens when applicable
"""

import argparse
import socket
import threading
import time


def pump(src: socket.socket, dst: socket.socket, label: str,
         counters: dict, t0: float, lock: threading.Lock,
         log_fh, peer: socket.socket):
    while True:
        try:
            chunk = src.recv(4096)
        except OSError:
            break
        if not chunk:
            break
        try:
            dst.sendall(chunk)
        except OSError:
            break
        with lock:
            for b in chunk:
                counters[label] += 1
                t_ms = (time.monotonic() - t0) * 1000.0
                ascii_repr = chr(b) if 0x20 <= b < 0x7F else '.'
                log_fh.write(f"{t_ms:9.2f} {label} {counters[label]:5d} "
                             f"{b:02X} ({ascii_repr})\n")
            log_fh.flush()
    # break peer side too so the other pump returns immediately
    try:
        peer.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, default=4012,
                    help="port we accept MAME on (default 4012)")
    ap.add_argument("--upstream", default="127.0.0.1:4002",
                    help="z80pack endpoint (default 127.0.0.1:4002)")
    ap.add_argument("--log", default="/tmp/cpnos_sio_tee.log",
                    help="byte log path")
    args = ap.parse_args()

    up_host, up_port = args.upstream.split(":")
    up_port = int(up_port)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.listen))
    srv.listen(1)
    print(f"sio_tee listening on :{args.listen}, upstream {up_host}:{up_port}",
          flush=True)

    mame, _ = srv.accept()
    srv.close()
    print("MAME connected", flush=True)

    upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    upstream.connect((up_host, up_port))
    print("upstream connected", flush=True)

    counters = {"M>": 0, "<M": 0}
    lock = threading.Lock()
    t0 = time.monotonic()

    log_fh = open(args.log, "w", buffering=1)
    log_fh.write("# sio_tee streaming log  t_ms dir n hex (ascii)\n")

    t_a = threading.Thread(target=pump,
                           args=(mame, upstream, "M>", counters, t0, lock,
                                 log_fh, upstream),
                           daemon=True)
    t_b = threading.Thread(target=pump,
                           args=(upstream, mame, "<M", counters, t0, lock,
                                 log_fh, mame),
                           daemon=True)
    t_a.start()
    t_b.start()
    t_a.join()
    t_b.join()

    log_fh.write(f"# closed  M>{counters['M>']} bytes  "
                 f"<M{counters['<M']} bytes\n")
    log_fh.close()
    print(f"log written: {args.log} "
          f"(M>{counters['M>']}, <M{counters['<M']})", flush=True)


if __name__ == "__main__":
    main()
