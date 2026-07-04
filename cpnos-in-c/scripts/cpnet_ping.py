#!/usr/bin/env python3
"""Liveness probe for the CP/NET master (z80pack mpm-net2) over its raw
TCP console port (default 127.0.0.1:4002).

Unlike a bare TCP connect-check (which only proves mpm-net2 is
*listening*), this speaks one real CP/NET 1.2 frame end-to-end:

    slave -> ENQ                                (are you there?)
    master -> ACK
    slave -> SOH FMT DID SID FNC SIZ HCS         (LOGIN, FNC=0x40)
    master -> ACK                                (header accepted)
    slave -> STX DAT[0..7] ETX CKS EOT           (8-byte password)
    master -> ACK                                (data accepted)
    master -> ENQ                                (here's your reply)
    slave -> ACK
    master -> SOH FMT DID SID FNC SIZ HCS
    slave -> ACK
    master -> STX DAT ETX CKS EOT
    slave -> ACK

We deliberately send a WRONG password ("PINGPING" instead of the real
"PASSWORD").  A failed login is fine -- and actually preferable, since
it proves the whole stack (network driver + BDOS + NDOS + login
validation) round-tripped a real message without ever establishing a
session or touching any master-side state.  See
cpnos-shared/docs/CPNET_WIRE_PROTOCOL.md for the wire-level spec this
implements.

Exit 0 (PASS) only if every ACK/response step above completes within
the per-step timeout.  Exit 1 (FAIL) with a message naming the first
step that didn't respond -- this is what should gate any cpnos test
that depends on a live MP/M, instead of `nc -z` (which only checks the
kernel accepted the SYN, not that MP/M itself is processing frames).

Usage: cpnet_ping.py [host] [port] [--timeout SECS]
"""
import socket
import sys

ENQ, ACK, NAK, SOH, STX, ETX, EOT = 0x05, 0x06, 0x15, 0x01, 0x02, 0x03, 0x04

# Deliberately NOT the real "PASSWORD" -- see module docstring.
PROBE_PASSWORD = b"PINGPING"
assert len(PROBE_PASSWORD) == 8

# Slave-visible identity for this probe frame.  SID=1 matches the
# production RC702_SLAVEID (cpnos-in-c/src/init.c); a rejected LOGIN
# doesn't mutate any master-side session state, so re-using it here is
# safe even if the real slave is also connected as SID=1.
FMT, DID, SID, FNC = 0x00, 0x00, 0x01, 0x40  # 0x40 = LOGIN


def recv_exact(sock, n, deadline_desc):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise TimeoutError(f"connection closed while waiting for {deadline_desc}")
        buf += chunk
    return buf


def expect_ack(sock, what):
    try:
        b = recv_exact(sock, 1, what)
    except (socket.timeout, TimeoutError) as e:
        raise TimeoutError(f"no response waiting for {what}: {e}") from None
    if (b[0] & 0x7F) != ACK:
        raise TimeoutError(f"expected ACK for {what}, got 0x{b[0]:02x}")


def ping(host, port, timeout):
    sock = socket.create_connection((host, port), timeout=timeout)
    sock.settimeout(timeout)
    try:
        # --- slave -> master: LOGIN request (wrong password) ---
        sock.sendall(bytes([ENQ]))
        expect_ack(sock, "ENQ ack")

        siz = len(PROBE_PASSWORD) - 1
        hcs = (-(SOH + FMT + DID + SID + FNC + siz)) & 0xFF
        sock.sendall(bytes([SOH, FMT, DID, SID, FNC, siz, hcs]))
        expect_ack(sock, "header ack")

        cks = (-(STX + sum(PROBE_PASSWORD) + ETX)) & 0xFF
        sock.sendall(bytes([STX]) + PROBE_PASSWORD + bytes([ETX, cks, EOT]))
        expect_ack(sock, "data ack")

        # --- master -> slave: response frame (LOGIN result) ---
        b = recv_exact(sock, 1, "response ENQ")
        if (b[0] & 0x7F) != ENQ:
            raise TimeoutError(f"expected response ENQ, got 0x{b[0]:02x}")
        sock.sendall(bytes([ACK]))

        hdr = recv_exact(sock, 7, "response header")
        if hdr[0] != SOH:
            raise TimeoutError(f"expected response SOH, got 0x{hdr[0]:02x}")
        resp_siz = hdr[5]
        sock.sendall(bytes([ACK]))

        data = recv_exact(sock, 5 + resp_siz, "response data")
        sock.sendall(bytes([ACK]))

        return hdr, data
    finally:
        sock.close()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--timeout")]
    timeout = 5.0
    for a in sys.argv[1:]:
        if a.startswith("--timeout"):
            timeout = float(a.split("=", 1)[1]) if "=" in a else float(sys.argv[sys.argv.index(a) + 1])
    host = args[0] if len(args) > 0 else "127.0.0.1"
    port = int(args[1]) if len(args) > 1 else 4002

    try:
        hdr, data = ping(host, port, timeout)
    except (TimeoutError, ConnectionRefusedError, OSError) as e:
        print(f"FAIL: cpnet ping to {host}:{port} did not complete: {e}")
        sys.exit(1)

    rc = data[-1] if data else None
    print(f"PASS: MP/M answered a full CP/NET LOGIN round-trip "
          f"({host}:{port}); reply FNC=0x{hdr[3]:02x} rc=0x{rc:02x}"
          if rc is not None else
          f"PASS: MP/M answered a full CP/NET LOGIN round-trip ({host}:{port})")
    sys.exit(0)


if __name__ == "__main__":
    main()
