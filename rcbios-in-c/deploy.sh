#!/bin/bash
# deploy.sh — Automated BIOS build + deploy to RC700 over serial
#
# Fully automated after user resets the RC700:
#   1. Build BIOS (SDCC or clang)
#   2. Generate Intel HEX with validator
#   3. Wait for RC700 boot (A> prompt on serial)
#   4. Send SUBMIT B (which runs: switch CON:=CRT, PIP from RDR:,
#      switch CON:=TTY, MLOAD, verify, SYSGEN)
#   5. Send HEX data when PIP reads from RDR:
#   6. Send SYSGEN answers (A, Enter, Enter)
#   7. Prompt user to reset for next cycle
#
# Prerequisites:
#   - B.SUB on RC700 disk with correct content
#   - BIOS with CON:=TTY default (IOBYTE 0x94)
#   - cpm56_original.com + bdosccp.com on RC700 disk
#   - pyserial installed
#
# Usage:
#   ./deploy.sh              Build SDCC + deploy
#   ./deploy.sh clang        Build clang + deploy
#   ./deploy.sh --send-only  Skip build, send existing hex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

COMPILER="${1:-sdcc}"
PORT="${RC700_PORT:-/dev/ttyUSB1}"
BAUD="${RC700_BAUD:-38400}"
HEX_FILE=/tmp/cpm56.hex

if [ "$COMPILER" != "--send-only" ]; then
    echo "=== Building BIOS ($COMPILER) ==="
    make bios COMPILER="$COMPILER"
    echo ""

    CIM="$COMPILER/bios.cim"
    if [ ! -f "$CIM" ]; then
        echo "ERROR: $CIM not found"
        exit 1
    fi

    echo "=== Generating Intel HEX ==="
    python3 mk_cpm56.py cpm56_original.com "$CIM" /tmp/cpm56
    echo ""
fi

if [ ! -f "$HEX_FILE" ]; then
    echo "ERROR: $HEX_FILE not found"
    exit 1
fi

LINES=$(wc -l < "$HEX_FILE")
echo "=== Ready: $LINES HEX lines ==="
echo ""
echo "Please reset the RC700."
echo ""

# The main automation — all serial interaction in one Python script
python3 - "$PORT" "$BAUD" "$HEX_FILE" <<'PYEOF'
import serial, sys, time, threading

port = sys.argv[1]
baud = int(sys.argv[2])
hexfile = sys.argv[3]

s = serial.Serial(port, baud, timeout=1, rtscts=True)
s.dtr = True
time.sleep(0.1)
s.read(s.in_waiting or 1)

def read_until(marker, timeout=120):
    """Read serial until marker found, printing everything."""
    buf = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = s.read(s.in_waiting or 1)
        if data:
            text = data.decode("ascii", errors="replace")
            sys.stdout.write(text)
            sys.stdout.flush()
            buf += text
            if marker in buf:
                return buf
        time.sleep(0.05)
    return buf

def send(text, delay=0.3):
    """Send text over serial."""
    s.write(text.encode("ascii"))
    s.flush()
    time.sleep(delay)

# Step 1: Wait for boot
print("--- Waiting for RC700 boot ---")
buf = read_until("A>")
if "A>" not in buf:
    print("\nERROR: Timeout waiting for A> prompt")
    s.close()
    sys.exit(1)
print("\n--- RC700 booted ---")
time.sleep(0.5)

# Step 2: Send SUBMIT B
print("\n--- Sending SUBMIT B ---")
send("SUBMIT B\r")
# SUBMIT creates $$$.SUB then warm boots.
# After warm boot, CCP reads from $$$.SUB:
#   1. STAT CON:=CRT:  (frees serial for RDR:)
#   2. PIP CPM56.HEX=RDR:  (reads hex from serial)
# Wait for the warm boot A> and STAT to execute, then PIP starts reading.
# We won't see output after STAT CON:=CRT: switches console away from serial.
buf = read_until("A>", timeout=10)
# After warm boot + STAT CON:=CRT, serial goes quiet. PIP is now reading RDR:.
time.sleep(3)

# Step 3: Send HEX file
print("\n--- Sending HEX file ---")
with open(hexfile) as f:
    lines = f.readlines()

cts_drops = 0
stop_monitor = False
def monitor_cts():
    global cts_drops
    prev = s.cts
    while not stop_monitor:
        cur = s.cts
        if cur != prev:
            if not cur:
                cts_drops += 1
            prev = cur
        time.sleep(0.0005)

t = threading.Thread(target=monitor_cts, daemon=True)
t.start()
t0 = time.time()

for i, line in enumerate(lines):
    line = line.rstrip("\r\n")
    s.write((line + "\r\n").encode("ascii"))
    s.flush()
    if (i + 1) % 100 == 0:
        elapsed = time.time() - t0
        print(f"  {i+1}/{len(lines)} sent, {elapsed:.1f}s, CTS={s.cts}, drops={cts_drops}")

time.sleep(0.5)
s.write(b"\x1a")
s.flush()

stop_monitor = True
t.join()
elapsed = time.time() - t0
print(f"\nTransfer: {len(lines)} lines in {elapsed:.1f}s, {cts_drops} CTS drops")

# Step 4: After PIP, B.SUB runs: STAT CON:=TTY:, MLOAD, CPM56 (verify), SYSGEN
# Once CON:=TTY is restored, we see output again.
# Wait for "OK" or "FAIL" from the validator (CPM56.COM)
print("\n--- Waiting for verify result ---")
buf = read_until("OK", timeout=120)
if "OK" in buf:
    print("\n\n*** BIOS VERIFIED OK ***")
elif "FAIL" in buf:
    print("\n\n*** BIOS VERIFY FAILED ***")
    s.close()
    sys.exit(1)
else:
    print("\n\nWARNING: No verify result seen")

# Step 5: SYSGEN CPM56.COM — skips source prompt, goes straight to DESTINATION
print("\n--- Answering SYSGEN ---")
# Wait for "DESTINATION DRIVE NAME"
buf = read_until("DESTINATION", timeout=30)
send("A", 1)          # drive letter A (no Enter — single char read)

# Wait for "THEN TYPE RETURN"
buf = read_until("RETURN", timeout=10)
send("\r", 3)          # Enter to write

# Wait for second "DESTINATION DRIVE NAME (OR RETURN TO REBOOT)"
buf = read_until("DESTINATION", timeout=15)
send("\r", 1)          # Enter to warm boot

# Wait for reboot prompt
print("\n--- SYSGEN complete ---")
buf = read_until("A>", timeout=30)

s.close()

print("\n\n========================================")
print("  DEPLOY COMPLETE — new BIOS installed")
print("  Reset RC700 to boot the new BIOS.")
print("========================================")
PYEOF
