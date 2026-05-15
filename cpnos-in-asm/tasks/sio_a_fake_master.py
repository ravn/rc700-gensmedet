#!/usr/bin/env python3
"""Fake CP/NET master for cpnos-in-asm phase 3d-β/γ end-to-end test.

Acts as the host side of MAME's `-rs232a null_modem -bitb1
socket.127.0.0.1:PORT`: MAME dials out, we listen.  Drives both
directions of a CP/NET 1.2 frame exchange:

  Phase A (slave -> master, exercises send handshake from phase 3d-β):
    slave sends ENQ                   master replies ACK
    slave sends SOH FMT DID SID FNC SIZ HCS
                                      master verifies + replies ACK
    slave sends STX DAT[0] ETX CKS EOT
                                      master verifies + replies ACK

  Phase B (master -> slave, exercises receive state machine from
  phase 3d-γ):
    master sends ENQ                  slave replies ACK
    master sends SOH FMT DID SID FNC SIZ HCS
                                      slave verifies + replies ACK
    master sends STX DAT[0] ETX CKS EOT
                                      slave verifies + replies ACK

PASS if all six ACKs arrived as expected.
"""
import socket
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4446
RESULT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/cpnos_asm_cpnet_result.txt"

SOH, STX, ETX, EOT, ENQ, ACK, NAK = 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x15

# Slave's LOGIN request (phase 3e): FMT=0 req, DID=0 master,
# SID=0x01 RC702_SLAVEID, FNC=64 LOGIN, SIZ=7 -> 8 password bytes
# DAT = "PASSWORD" (the mpm-net2 default for slave 0x01).
# HCS over SOH+FMT+DID+SID+FNC+SIZ = 01+00+00+01+40+07 = 0x49
#   -> HCS = -0x49 mod 256 = 0xB7
# CKS over STX+DAT[0..7]+ETX
#   STX(2) + "PASSWORD"(0x273) + ETX(3) = 0x278 mod 256 = 0x78
#   -> CKS = -0x78 mod 256 = 0x88
EXPECT_SLAVE_HEADER = bytes([SOH, 0x00, 0x00, 0x01, 64, 7, 0xB7])
EXPECT_SLAVE_DATA   = bytes([STX]) + b"PASSWORD" + bytes([ETX, 0x88, EOT])

# Master's LOGIN response: FMT=1 resp, DID=0x01 to-us, SID=0 master,
# FNC=64 LOGIN, SIZ=0 -> 1 DAT byte = 0x00 (return code 0 = success
# per CP/NET BDOS convention).
# HCS over 01+01+01+00+40+00 = 0x43 -> HCS = -0x43 = 0xBD
# CKS over STX+0x00+ETX = 0x05 -> CKS = -0x05 = 0xFB
MASTER_HEADER = bytes([SOH, 0x01, 0x01, 0x00, 64, 0x00, 0xBD])
MASTER_DATA   = bytes([STX, 0x00, ETX, 0xFB, EOT])

ACCEPT_TIMEOUT = 30.0
RECV_TIMEOUT   = 3.0

def _log(s):
    print(s, flush=True)

def _result(verdict, note=""):
    with open(RESULT, "w") as f:
        f.write(f"{verdict}: {note}\n")
    _log(f"{verdict}: {note}")
    sys.exit(0 if verdict == "PASS" else 1)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(1)
_log(f"fake-master listening on 127.0.0.1:{PORT}")

srv.settimeout(ACCEPT_TIMEOUT)
try:
    conn, peer = srv.accept()
except socket.timeout:
    _result("FAIL", f"MAME did not connect within {ACCEPT_TIMEOUT}s")
_log(f"slave connected from {peer}")
conn.settimeout(RECV_TIMEOUT)

def recv_exact(n, what):
    buf = b""
    while len(buf) < n:
        try:
            chunk = conn.recv(n - len(buf))
        except socket.timeout:
            _result("FAIL", f"timeout reading {what}, got {buf.hex()}")
        if not chunk:
            _result("FAIL", f"connection closed while reading {what}, got {buf.hex()}")
        buf += chunk
    return buf

# --- Phase A: slave -> master ---
b = recv_exact(1, "slave ENQ")
if b[0] != ENQ:
    _result("FAIL", f"expected slave ENQ 0x05, got 0x{b[0]:02x}")
_log("phase-A: got slave ENQ")
conn.sendall(bytes([ACK]))

hdr = recv_exact(7, "slave header")
_log(f"phase-A: got slave header {hdr.hex()}")
if hdr != EXPECT_SLAVE_HEADER:
    _result("FAIL", f"slave header mismatch: {hdr.hex()} != {EXPECT_SLAVE_HEADER.hex()}")
if sum(hdr) % 256 != 0:
    _result("FAIL", f"slave header HCS invalid (sum {sum(hdr) % 256})")
conn.sendall(bytes([ACK]))

dat = recv_exact(len(EXPECT_SLAVE_DATA), "slave data")
_log(f"phase-A: got slave data {dat.hex()}")
if dat != EXPECT_SLAVE_DATA:
    _result("FAIL", f"slave data mismatch: {dat.hex()} != {EXPECT_SLAVE_DATA.hex()}")
# Bracket bytes for CKS = STX + DAT[0..SIZ] + ETX + CKS (everything
# except the trailing EOT, which is a delimiter not in the checksum).
cks_bracket = dat[:-1]
if sum(cks_bracket) % 256 != 0:
    _result("FAIL", f"slave data CKS invalid (sum {sum(cks_bracket) % 256})")
if dat[-1] != EOT:
    _result("FAIL", f"slave EOT missing (got 0x{dat[-1]:02x})")
conn.sendall(bytes([ACK]))
_log("phase-A: slave INIT request received with all 3 ACKs")

# Settle delay so the slave is firmly in the combined poll loop
# before we initiate phase B.
time.sleep(0.5)

# --- Phase B: master -> slave ---
_log("phase-B: sending master ENQ")
conn.sendall(bytes([ENQ]))
b = recv_exact(1, "slave ACK for master ENQ")
if b[0] != ACK:
    _result("FAIL", f"slave did not ACK master ENQ (got 0x{b[0]:02x})")
_log("phase-B: got slave ACK on ENQ")

_log(f"phase-B: sending master header {MASTER_HEADER.hex()}")
conn.sendall(MASTER_HEADER)
b = recv_exact(1, "slave ACK/NAK on header")
if b[0] == NAK:
    _result("FAIL", "slave NAK'd master header (HCS mismatch on slave side?)")
if b[0] != ACK:
    _result("FAIL", f"unexpected response to master header: 0x{b[0]:02x}")
_log("phase-B: got slave ACK on header")

_log(f"phase-B: sending master data {MASTER_DATA.hex()}")
conn.sendall(MASTER_DATA)
b = recv_exact(1, "slave ACK/NAK on data")
if b[0] == NAK:
    _result("FAIL", "slave NAK'd master data (CKS or EOT mismatch on slave side?)")
if b[0] != ACK:
    _result("FAIL", f"unexpected response to master data: 0x{b[0]:02x}")
_log("phase-B: got slave ACK on data -- receive state machine works")

_result("PASS", "bidirectional CP/NET 1.2 frame exchange complete (6/6 ACKs)")
