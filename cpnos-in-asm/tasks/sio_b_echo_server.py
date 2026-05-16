#!/usr/bin/env python3
"""SIO-B echo verifier for cpnos-in-asm phase 2b.

Acts as the host side of MAME's `-rs232b null_modem -bitb2
socket.127.0.0.1:PORT`: MAME dials out, we listen.  We:

  1. Wait for the slave's banner to arrive (proves boot + SIO-B TX).
  2. Send a probe ("PING\r\n").
  3. Read back the echoed probe -- this is what phase 2b's RX -> TX
     loop is supposed to produce.

Phase 3c (CP/NET on SIO-A) note: the CP/NET INIT frame is emitted
on SIO-A, NOT SIO-B.  SIO-B carries only the banner + the echo loop
output.  This server therefore expects banner + CRLF and nothing
else before the probe round-trip.

Exits with 0 on PASS, 1 on FAIL.  Designed to be launched in the
background by the Makefile target BEFORE MAME starts so we're already
listening when MAME connects.
"""
import socket
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4445
RESULT_PATH = sys.argv[2] if len(sys.argv) > 2 else "/tmp/cpnos_asm_echo_result.txt"

PROBE = b"PING\r\n"
BANNER_MATCH = b"RC702 CP/NOS asm"
BANNER_TAIL  = b"\r\n"             # banner is terminated with CRLF;
                                   # CP/NET frame (formerly here) now
                                   # lives on SIO-A.
ACCEPT_TIMEOUT = 30.0              # waiting for MAME to dial in
BANNER_TIMEOUT = 8.0               # waiting for banner after connect
ECHO_TIMEOUT = 4.0                 # waiting for the probe to come back

def _log(s):
    print(s, flush=True)

def _result(verdict, note=""):
    with open(RESULT_PATH, "w") as f:
        f.write(f"{verdict}: {note}\n")
    _log(f"{verdict}: {note}")
    sys.exit(0 if verdict == "PASS" else 1)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(1)
_log(f"listening on 127.0.0.1:{PORT}")

srv.settimeout(ACCEPT_TIMEOUT)
try:
    conn, peer = srv.accept()
except socket.timeout:
    _result("FAIL", f"MAME did not connect within {ACCEPT_TIMEOUT}s")
_log(f"MAME connected from {peer}")

# 1. Drain banner.
buf = b""
deadline = time.time() + BANNER_TIMEOUT
conn.settimeout(0.5)
while time.time() < deadline:
    try:
        chunk = conn.recv(256)
    except socket.timeout:
        if BANNER_MATCH in buf and BANNER_TAIL in buf[buf.find(BANNER_MATCH):]:
            break
        continue
    if not chunk:
        break
    buf += chunk

if BANNER_MATCH not in buf:
    _result("FAIL", f"banner not seen.  received {len(buf)} B: {buf[:60]!r}")
_log(f"banner received on SIO-B ({len(buf)} B)")

# Phase 3f delay: slave's send_cpnet_init_frame_retry burns
# ~3 * 250 ms = 750 ms simulated on SIO-A with no master present
# (MAXRETRY = 3 today; see prom1.asm comment).  At MAME's
# -nothrottle ~5x speed that's ~150 ms wall.  During this window
# the slave's combined_io_loop isn't running, so SIO-B RX bytes
# arrive at the SIO chip's tiny FIFO and get dropped on overrun.
# Sleep covers the burn with plenty of margin.
_log("waiting 0.5 s wall for slave to finish phase-3f SIO-A retry burn...")
time.sleep(0.5)

# 2. Send probe.
conn.sendall(PROBE)
_log(f"sent probe {PROBE!r}")

# 3. Read echo.
echo_buf = b""
deadline = time.time() + ECHO_TIMEOUT
while time.time() < deadline:
    try:
        chunk = conn.recv(256)
    except socket.timeout:
        if PROBE in echo_buf:
            break
        continue
    if not chunk:
        break
    echo_buf += chunk
    if PROBE in echo_buf:
        break

if PROBE not in echo_buf:
    _result("FAIL", f"probe not echoed.  received {echo_buf!r}")

_result("PASS", f"probe round-tripped via SIO-B echo loop: {PROBE!r}")
