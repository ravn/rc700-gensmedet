#!/bin/bash
# Build REL30 BIOS, patch onto 8" maxi disk image, launch MAME with serial terminal.
#
# Usage:
#   cd rcbios && bash run_mame.sh [-f] [-2 image.imd]
#
#   -f          Force re-copy and re-patch of working image
#   -2 FILE     Mount FILE as second floppy drive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAME_DIR="${MAME_DIR:-$(cd "$SCRIPT_DIR/../../mame" && pwd)}"
SOURCE_IMAGE="${HOME}/Downloads/SW1711-I8.imd"
WORK_IMAGE="/tmp/cpm22_rel30_maxi.imd"
SERIAL_PORT=4321
TERMINAL_CMD=""    # override, e.g. "socat TCP:localhost:\$PORT -,raw,echo=0"

# ── Parse arguments ──

FORCE=false
FLOP2=""

while getopts "f2:" opt; do
    case "$opt" in
        f) FORCE=true ;;
        2) FLOP2="$OPTARG" ;;
        *) echo "Usage: $0 [-f] [-2 image.imd]"; exit 1 ;;
    esac
done

# ── Build MAME (ensure binary is up to date) ──

echo "Building MAME regnecentralen subtarget..."
make -C "$MAME_DIR" SUBTARGET=regnecentralen DEBUG=1 \
    TOOLS=1 SYMLEVEL=3 SYMBOLS=1 OSD=sdl -j$(sysctl -n hw.ncpu) \
    2>&1 | tail -5

MAME="${MAME_DIR}/regnecentralend"
if [ ! -x "$MAME" ]; then
    MAME="${MAME_DIR}/regnecentralen"
fi
if [ ! -x "$MAME" ]; then
    echo "ERROR: MAME binary not found at ${MAME_DIR}/regnecentralen{,d}"
    exit 1
fi

# Verify RS232 slot exists (added in commit 993b6da)
# Note: avoid piping -listslots to grep directly — grep -q closes the pipe
# early, MAME gets SIGPIPE, and pipefail treats exit 141 as failure.
SLOTS=$("$MAME" rc702 -listslots 2>&1) || true
if ! echo "$SLOTS" | grep -q rs232a; then
    echo "ERROR: MAME binary lacks rs232a slot — rebuild needed"
    exit 1
fi

# ── Build REL30 BIOS ──

echo "Building rel30-maxi..."
make -C "$SCRIPT_DIR" rel30-maxi

# ── Patch onto working image ──

CIM="${SCRIPT_DIR}/zout/BIOS.cim"

if [ ! -f "$WORK_IMAGE" ] || [ "$FORCE" = true ]; then
    if [ ! -f "$SOURCE_IMAGE" ]; then
        echo "ERROR: Source image not found: ${SOURCE_IMAGE}"
        exit 1
    fi
    echo "Copying ${SOURCE_IMAGE} -> ${WORK_IMAGE}"
    cp "$SOURCE_IMAGE" "$WORK_IMAGE"
fi

if [ ! -f "$WORK_IMAGE" ]; then
    echo "ERROR: Work image not found: ${WORK_IMAGE}"
    exit 1
fi

if [ "$FORCE" = true ] || [ "$CIM" -nt "$WORK_IMAGE" ]; then
    echo "Patching BIOS onto working image..."
    python3 "${SCRIPT_DIR}/patch_bios.py" "$WORK_IMAGE" "$CIM"
else
    echo "BIOS unchanged, skipping patch."
fi

# ── Write Lua autoboot script (set null_modem to 38400 + RTS flow control) ──

LUA_SCRIPT="/tmp/set_38400.lua"
cat > "$LUA_SCRIPT" << 'LUAEOF'
-- set null_modem TX/RX baud to 38400 and enable RTS flow control
local log = io.open("/tmp/mame_serial_setup.log", "w")
local ports = manager.machine.ioport.ports
for tag, port in pairs(ports) do
    if tag:find("RS232_TXBAUD") or tag:find("RS232_RXBAUD") then
        for name, field in pairs(port.fields) do
            field.user_value = 0x0b  -- RS232_BAUD_38400
            log:write(string.format("SET %s : %s = 0x0b\n", tag, name))
        end
    end
    if tag:find("FLOW_CONTROL") then
        for name, field in pairs(port.fields) do
            log:write(string.format("FOUND %s : %s (defvalue=0x%x)\n", tag, name, field.defvalue))
            if name:find("Flow Control") then
                field.user_value = 0x01  -- RTS
                log:write(string.format("SET %s : %s = 0x01 (RTS)\n", tag, name))
            end
        end
    end
end
log:close()
LUAEOF

# ── Launch MAME ──

MAME_ARGS=(
    rc702
    -rompath "${MAME_DIR}/roms"
    -flop "$WORK_IMAGE"
    -bitb1 "socket.localhost:${SERIAL_PORT}"
    -skip_gameinfo -window -nomaximize -resolution0 1100x720
    -autoboot_script "$LUA_SCRIPT"
)

if [ -n "$FLOP2" ]; then
    MAME_ARGS+=(-flop2 "$FLOP2")
fi

# ── Start serial terminal + MAME ──
#
# The Python terminal runs in the FOREGROUND (needs stdin for keyboard).
# It listens on the TCP port, launches MAME as a subprocess, then accepts
# the connection and enters the interactive loop.

if [ -n "$TERMINAL_CMD" ]; then
    eval "$TERMINAL_CMD" &
    TERM_PID=$!
    sleep 1
    echo "Starting MAME: rc702 with serial on port ${SERIAL_PORT}..."
    "$MAME" "${MAME_ARGS[@]}"
    kill "$TERM_PID" 2>/dev/null || true
    wait "$TERM_PID" 2>/dev/null || true
else
    echo "Starting serial terminal + MAME on port ${SERIAL_PORT}..."
    TERM_SCRIPT="/tmp/rc702_terminal.py"
    cat > "$TERM_SCRIPT" << 'PYEOF'
import socket, sys, os, select, subprocess, time

PORT = int(os.environ["SERIAL_PORT"])
BAUD = 38400
with open(os.environ["MAME_CMD_FILE"]) as f:
    MAME_CMD = [line.rstrip("\n") for line in f]

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("localhost", PORT))
server.listen(1)

# Launch MAME now that the socket is listening
mame_proc = subprocess.Popen(MAME_CMD)
print(f"Listening on localhost:{PORT} — waiting for MAME to connect...")
sys.stdout.flush()

conn, addr = server.accept()
print(f"MAME connected from {addr}")
print("Serial terminal active  (Ctrl-] for menu, Ctrl-C to quit)")
print("---")
sys.stdout.flush()

fd = sys.stdin.fileno()
is_tty = os.isatty(fd)
old_settings = None
if is_tty:
    import tty, termios
    old_settings = termios.tcgetattr(fd)
    tty.setraw(fd)

def send_file(conn, old_settings, fd):
    """Escape to cooked mode, prompt for filename, send file over serial."""
    import termios
    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    print("\r")
    print("--- Send file over serial ---")
    print("  On CP/M side, run:  pip filename=rdr:")
    print("  (text mode adds CR before LF, appends Ctrl-Z EOF)")
    path = input("File path (empty to cancel): ").strip()
    if not path:
        print("Cancelled.")
        tty.setraw(fd)
        return
    try:
        raw = open(path, "rb").read()
    except FileNotFoundError:
        print(f"Not found: {path}")
        tty.setraw(fd)
        return
    # Detect binary vs text: if any non-text bytes, send raw
    is_text = all(b in (0x09, 0x0A, 0x0D) or 0x20 <= b <= 0x7E for b in raw)
    if is_text:
        # Convert LF -> CR LF for CP/M, append Ctrl-Z
        data = raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n") + b"\x1a"
        desc = "text"
    else:
        data = raw
        desc = "binary"
    # Pace at baud rate: MAME processes at emulated speed, so match it.
    # 10 bits/char (8N1 + start + stop) → chars_per_sec = BAUD / 10
    chars_per_sec = BAUD / 10
    chunk = 32  # send in small bursts
    delay = chunk / chars_per_sec  # time per chunk at baud rate
    print(f"Sending {len(data)} bytes ({desc}) at {BAUD} baud...")
    sent = 0
    t0 = time.monotonic()
    while sent < len(data):
        end = min(sent + chunk, len(data))
        conn.sendall(data[sent:end])
        sent = end
        # drain any incoming data (CP/M echoes)
        while True:
            rd, _, _ = select.select([conn], [], [], 0.001)
            if not rd:
                break
            try:
                echo = conn.recv(4096)
                if echo:
                    os.write(sys.stdout.fileno(), echo)
            except (ConnectionResetError, OSError):
                break
        # pace: sleep until we've caught up with the baud rate clock
        expected = sent / chars_per_sec
        elapsed = time.monotonic() - t0
        if expected > elapsed:
            time.sleep(expected - elapsed)
    elapsed = time.monotonic() - t0
    print(f"Done — {sent} bytes sent in {elapsed:.1f}s.")
    tty.setraw(fd)

try:
    conn.setblocking(False)
    inputs = [conn] + ([sys.stdin] if is_tty else [])
    while True:
        readable, _, _ = select.select(inputs, [], [], 0.1)
        for r in readable:
            if r is conn:
                try:
                    data = conn.recv(4096)
                except (ConnectionResetError, OSError):
                    data = b""
                if not data:
                    msg = b"\r\nConnection closed.\r\n" if is_tty else b"\nConnection closed.\n"
                    os.write(sys.stdout.fileno(), msg)
                    raise SystemExit
                os.write(sys.stdout.fileno(), data)
            elif r is sys.stdin:
                ch = os.read(fd, 1)
                if not ch:
                    raise SystemExit
                if ch == b"\x1d" and old_settings:  # Ctrl-]
                    send_file(conn, old_settings, fd)
                else:
                    conn.sendall(ch)
        # Exit if MAME has quit
        if mame_proc.poll() is not None:
            msg = b"\r\nMAME exited.\r\n" if is_tty else b"\nMAME exited.\n"
            os.write(sys.stdout.fileno(), msg)
            break
except (KeyboardInterrupt, SystemExit):
    pass
finally:
    if old_settings:
        import termios
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    conn.close()
    server.close()
    mame_proc.terminate()
    mame_proc.wait()
    print("Disconnected.")
PYEOF
    # Write MAME command to a file (one arg per line) for Python to read
    MAME_CMD_FILE="/tmp/rc702_mame_cmd.txt"
    printf '%s\n' "$MAME" "${MAME_ARGS[@]}" > "$MAME_CMD_FILE"
    MAME_CMD_FILE="$MAME_CMD_FILE" SERIAL_PORT=$SERIAL_PORT exec python3 -u "$TERM_SCRIPT"
fi
