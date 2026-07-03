#!/usr/bin/env python3
"""Block until the z80pack mpm-net2 CP/NET master is ready, or time out.

The polypascal / netboot tests used to `sleep N` after `nc -z :4002`
succeeded.  But `nc -z` only proves the TCP socket is *bound* -- it says
nothing about whether MP/M's SERVER RSP has cold-booted far enough to
answer a CP/NET request, and a fixed sleep is either too short (slave's
no-timeout RECVBY hangs at the boot banner) or wastefully long.

This probe speaks the CP/NET link handshake instead: it connects to the
master's raw console socket (z80pack net_server console 3), sends ENQ
(0x05), and waits for the master's ACK (0x06).  Once the master ACKs,
its SERVER RSP is live and the subsequent slave LOGIN will be answered.

Verified non-contaminating (2026-07-03): a slave booted immediately after
this probe reaches the CP/M E> prompt normally -- the ENQ/ACK is a
link-level exchange that leaves no half-frame in the master's state, and
the probe fully closes its connection before MAME connects (z80pack's
console port accepts one connection at a time).

Exit 0 when the master ACKs; exit 1 on timeout.

Usage:  wait_mpm_ready.py [host] [port] [timeout_seconds]
Defaults: 127.0.0.1 4002 30
"""
import socket
import sys
import time

host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 4002
timeout_s = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0

start = time.time()
while time.time() - start < timeout_s:
    try:
        s = socket.socket()
        s.settimeout(0.5)
        s.connect((host, port))
        s.sendall(b"\x05")          # ENQ
        r = s.recv(1)
        s.close()
        if r == b"\x06":            # ACK
            print(f"mpm-ready: master ACKed ENQ {time.time()-start:.2f}s after probe start")
            sys.exit(0)
    except (socket.timeout, ConnectionRefusedError, OSError):
        pass
    time.sleep(0.3)

print(f"mpm-ready: TIMEOUT -- no ACK within {timeout_s:.0f}s", file=sys.stderr)
sys.exit(1)
