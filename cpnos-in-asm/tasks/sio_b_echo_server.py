#!/usr/bin/env python3
"""SIO-B echo verifier for cpnos-in-asm phase 2b.

Acts as the host side of MAME's `-rs232b null_modem -bitb2
socket.127.0.0.1:PORT`: MAME dials out, we listen.  We:

  1. Wait for the slave's banner to arrive (proves boot + SIO-B TX).
  2. Skip past the trailing CP/NET INIT frame (12 bytes) from
     phase 3a/3b.
  3. Send a probe ("PING\r\n").
  4. Read back the echoed probe -- this is what phase 2b's RX -> TX
     loop is supposed to produce.

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
BANNER_MATCH = b"RC702 CP/NOS asm phase"
CPNET_FRAME_LEN = 12               # SOH + 5 hdr + HCS + STX + 1 dat + ETX + CKS + EOT
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

# 1. Drain banner + CP/NET frame.
buf = b""
deadline = time.time() + BANNER_TIMEOUT
conn.settimeout(0.5)
while time.time() < deadline:
    try:
        chunk = conn.recv(256)
    except socket.timeout:
        if BANNER_MATCH in buf and len(buf) >= buf.find(BANNER_MATCH) + len(BANNER_MATCH) + 4 + CPNET_FRAME_LEN:
            break
        continue
    if not chunk:
        break
    buf += chunk

if BANNER_MATCH not in buf:
    _result("FAIL", f"banner not seen.  received {len(buf)} B: {buf[:60]!r}")

# Locate frame and trim everything up through its EOT.
end_of_banner = buf.find(BANNER_MATCH) + len(BANNER_MATCH)
# Skip the "\r\n" + 12-byte CP/NET frame.
post_frame_idx = end_of_banner
# Look for the SOH that starts the CP/NET header within ~10 B after banner.
soh_idx = buf.find(b"\x01", post_frame_idx)
if soh_idx < 0 or len(buf) < soh_idx + CPNET_FRAME_LEN:
    _result("FAIL", f"CP/NET frame not found after banner")

# Anything beyond the EOT is unexpected pre-echo noise.
extra = buf[soh_idx + CPNET_FRAME_LEN:]
if extra:
    _log(f"note: {len(extra)} extra byte(s) after EOT, before probe: {extra!r}")
_log(f"banner + 12-byte CP/NET frame received cleanly")

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
