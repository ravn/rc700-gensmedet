#!/usr/bin/env python3
"""Diagnostic probe for SIO-A RX corruption (task #66).

Does phase A normally, then sends a known sequence of non-ENQ bytes
to the slave's SIO-A.  Slave's combined_io_loop should forward each
to SIO-B verbatim (phase 3d-α behavior).  Inspect the SIO-B capture
to see if the bytes arrived intact.
"""
import socket, sys, time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4446
PROBE = bytes(range(0x30, 0x38))         # ASCII '0'..'7' = 0x30..0x37
SOH, STX, ETX, EOT, ENQ, ACK = 0x01, 0x02, 0x03, 0x04, 0x05, 0x06
EXPECT_SLAVE_HEADER = bytes([SOH, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x01])
EXPECT_SLAVE_DATA   = bytes([STX, 0x00, ETX, 0xFB, EOT])

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(1)
print(f"probe listening on :{PORT}", flush=True)
srv.settimeout(30)
conn, peer = srv.accept()
print(f"slave connected from {peer}", flush=True)
conn.settimeout(3.0)

def recv_exact(n, what):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            print(f"FAIL: connection closed reading {what}", flush=True)
            sys.exit(1)
        buf += chunk
    return buf

# Phase A: consume slave's INIT request.
b = recv_exact(1, "slave ENQ")
print(f"got slave ENQ 0x{b[0]:02x}", flush=True)
conn.sendall(bytes([ACK]))
hdr = recv_exact(7, "slave header")
print(f"got slave header {hdr.hex()}", flush=True)
conn.sendall(bytes([ACK]))
dat = recv_exact(5, "slave data")
print(f"got slave data {dat.hex()}", flush=True)
conn.sendall(bytes([ACK]))
print("phase A complete -- slave should now be in combined_io_loop", flush=True)

time.sleep(0.5)

print(f"sending probe {PROBE.hex()} (bytes 0x30..0x37, all non-ENQ)", flush=True)
conn.sendall(PROBE)
print("probe sent; sleeping 2s for forward to settle", flush=True)
time.sleep(2.0)
print("probe done -- check /tmp/cpnos_asm_cpnet_siob.raw for forwarded bytes", flush=True)
