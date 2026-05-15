#!/usr/bin/env python3
# license: BSD-3-Clause
"""CP/NET fast-link bring-up smoke test (MAME-side, end-to-end).

Verifies the host -> Z80 byte path of Option P
(see ../../docs/cpnet_fast_link.md):

    Python harness -> TCP localhost:4003
        -> rc702_pio_cpnet_bridge_device  (MAME slot card on PIO-B)
            -> Z80 PIO-B Mode 1 input + ISR fires
                -> isr_pio_par stores byte at 0xEA39, bumps counter at 0xEA3A
                    -> tap.lua write-tap appends to /tmp/cpnos_bridge_tap.log
                       -> harness reads the log, asserts byte sequence

Self-contained orchestration:
    1. Build cpnos-rom (incremental `make cpnos`).
    2. Build z80pack cpmsim if the binary is missing.
    3. Kill any stale process holding the MP/M TCP port.
    4. Launch z80pack-as-MP/M-master (z80pack/cpmsim/mpm-net2).
    5. Launch MAME with `-piob cpnet_bridge` + the standard CP/NET
       null_modem wiring to MP/M.
    6. Wait for tap.lua to detect the CPNOS banner.
    7. Connect to bridge :4003, send bytes, verify against tap log.
    8. Tear down both child process groups cleanly.

Usage:
    python3 harness.py                  # run the smoke test
    python3 harness.py --keep-alive     # leave processes running

Exit codes:
    0  PASS
    1  FAIL
"""

import argparse
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT  = Path(__file__).resolve().parents[2]
CPNOS_DIR  = REPO_ROOT / "cpnos-in-c"
Z80PACK    = REPO_ROOT / "z80pack" / "cpmsim"
MAME_DIR   = REPO_ROOT.parent / "mame"
MAME_BIN   = MAME_DIR / "regnecentralend"
LLVM_NM    = REPO_ROOT.parent / "llvm-z80" / "build-macos" / "bin" / "llvm-nm"
ROMS_DIR   = Path(os.environ.get("MAME_ROMS", Path.home() / "git" / "mame" / "roms"))
TAP_LUA    = Path(__file__).parent / "tap.lua"
PAYLOAD_ELF = CPNOS_DIR / "clang" / "payload.elf"

MPM_PORT     = 4002
BRIDGE_PORT  = 4003

READY_FILE      = Path("/tmp/cpnos_bridge_ready.txt")
TAP_LOG         = Path("/tmp/cpnos_bridge_tap.log")
ADDRS_LUA       = Path("/tmp/cpnos_bridge_addrs.lua")
MPM_LOG         = Path("/tmp/cpnos_bridge_mpm.log")
MAME_LOG        = Path("/tmp/cpnos_bridge_mame.log")
LOOPBACK_RESULT = Path("/tmp/cpnos_loopback_result.txt")

TEST_BYTES = bytes([0x55, 0xAA, 0x42, 0x00, 0xFF, 0x10])


# ---------------------------------------------------------------------------
# helpers

class Cleanup:
	"""LIFO stack of teardown callbacks."""
	def __init__(self):
		self.stack = []
	def push(self, fn):
		self.stack.append(fn)
	def run(self):
		while self.stack:
			try: self.stack.pop()()
			except Exception as e:
				print(f"[harness] cleanup error: {e}", file=sys.stderr)


def fail(msg, cleanup=None):
	print(f"FAIL: {msg}", file=sys.stderr)
	if cleanup is not None:
		cleanup.run()
	sys.exit(1)


def reset_state():
	for p in (READY_FILE, TAP_LOG, MPM_LOG, MAME_LOG, LOOPBACK_RESULT,
	          BOOT_MARKS_FILE, Path("/tmp/cpnos_boot_marks.log"),
	          Path("/tmp/cpnos_pio_server.log")):
		try: p.unlink()
		except FileNotFoundError: pass


def port_listener_pids(port: int) -> list[int]:
	"""Return PIDs of processes currently LISTENing on `port`."""
	try:
		out = subprocess.check_output(
			["lsof", "-nP", "-iTCP", f"-iTCP:{port}", "-sTCP:LISTEN", "-Fp"],
			stderr=subprocess.DEVNULL).decode()
	except subprocess.CalledProcessError:
		return []
	pids = []
	for line in out.splitlines():
		if line.startswith("p"):
			try: pids.append(int(line[1:]))
			except ValueError: pass
	return pids


def kill_stale(port: int):
	"""Kill any process holding `port` so a fresh server can bind."""
	pids = port_listener_pids(port)
	for pid in pids:
		print(f"[harness] killing stale listener PID {pid} on :{port}")
		try: os.kill(pid, signal.SIGTERM)
		except ProcessLookupError: continue
	if pids:
		# Give them a moment to release.
		end = time.time() + 3.0
		while time.time() < end:
			if not port_listener_pids(port): return
			time.sleep(0.2)
		# SIGKILL stragglers.
		for pid in port_listener_pids(port):
			try: os.kill(pid, signal.SIGKILL)
			except ProcessLookupError: pass


def wait_for_listen(port: int, deadline_s: float):
	end = time.time() + deadline_s
	while time.time() < end:
		if port_listener_pids(port):
			return
		time.sleep(0.1)
	raise TimeoutError(f"nothing listening on :{port} after {deadline_s}s")


def run(cmd, cwd=None, check=True) -> subprocess.CompletedProcess:
	print(f"[harness] $ {' '.join(str(c) for c in cmd)}"
	      f"{' (in ' + str(cwd) + ')' if cwd else ''}")
	return subprocess.run(cmd, cwd=cwd, check=check)


def spawn_group(cmd, cwd=None, log_path=None):
	"""Spawn a child in its own process group so we can SIGTERM the
	whole tree on cleanup (kills shell wrappers + their children)."""
	stdout = open(log_path, "w") if log_path else subprocess.DEVNULL
	print(f"[harness] $ {' '.join(str(c) for c in cmd)}"
	      f"{' (in ' + str(cwd) + ')' if cwd else ''}"
	      f"{' -> ' + str(log_path) if log_path else ''}")
	return subprocess.Popen(cmd, cwd=cwd, stdout=stdout,
		stderr=subprocess.STDOUT, start_new_session=True)


def kill_group(p: subprocess.Popen):
	if p.poll() is not None:
		return
	try: os.killpg(p.pid, signal.SIGTERM)
	except ProcessLookupError: return
	try: p.wait(timeout=3.0)
	except subprocess.TimeoutExpired:
		try: os.killpg(p.pid, signal.SIGKILL)
		except ProcessLookupError: pass


# ---------------------------------------------------------------------------
# build steps

def ensure_cpnos_built(extra_make_args=()):
	"""Run `make cpnos-install` so the freshly built PROMs land in MAME's
	rom directory and cpnos.com lands on the MP/M test disks.  Just `make
	cpnos` only builds artefacts in clang/; MAME would then boot stale
	PROM bytes from a previous install."""
	run(["make", "-s", "cpnos-install", *extra_make_args],
	    cwd=str(CPNOS_DIR))


def ensure_cpmsim_built():
	cpmsim_bin = Z80PACK / "cpmsim"
	if cpmsim_bin.exists() and os.access(cpmsim_bin, os.X_OK):
		return
	srcsim = Z80PACK / "srcsim"
	if not srcsim.exists():
		fail(f"{srcsim} missing — z80pack submodule not initialised")
	# z80pack/cpmsim/srcsim/Makefile knows how to produce ../cpmsim.
	run(["make"], cwd=str(srcsim))


def emit_addrs_lua():
	"""Extract BSS addresses from the freshly built payload.elf and write
	them as a Lua table tap.lua dofile()s.  Avoids the silent-drift trap
	that hardcoded addresses caused before.

	Required symbols: _pio_par_byte, _pio_par_count (host-send mode).
	Optional symbols: _pio_test_done, _pio_test_recv, _pio_test_passed
	(loopback/frame mode — only present with PIO_LOOPBACK_TEST=1).
	"""
	out = subprocess.check_output(
		[str(LLVM_NM), str(PAYLOAD_ELF)]).decode()
	required = {"_pio_par_byte", "_pio_par_count"}
	optional = {"_pio_test_done", "_pio_test_recv", "_pio_test_passed"}
	found = {}
	for line in out.splitlines():
		parts = line.split()
		if len(parts) >= 3 and parts[2] in required | optional:
			found[parts[2]] = int(parts[0], 16)
	missing = required - found.keys()
	if missing:
		fail(f"symbols not found in {PAYLOAD_ELF}: {sorted(missing)}")
	lines = [
		"return {",
		f"  pio_par_byte  = 0x{found['_pio_par_byte']:04X},",
		f"  pio_par_count = 0x{found['_pio_par_count']:04X},",
	]
	for sym in ("_pio_test_done", "_pio_test_recv", "_pio_test_passed"):
		if sym in found:
			# Strip leading underscore for the Lua table key.
			lines.append(f"  {sym[1:]} = 0x{found[sym]:04X},")
	lines.append("}")
	ADDRS_LUA.write_text("\n".join(lines) + "\n")
	print(f"[harness] addrs: " +
	      ", ".join(f"{k}=0x{v:04X}" for k, v in sorted(found.items())))
	return found


def free_bridge_port_in_mpm_conf():
	"""z80pack's cpmsim/conf/net_server.conf binds consoles 1..4 to TCP
	ports 4000..4003 — console 4 collides with MAME's cpnet_bridge
	(default :4003).  Rewrite the conf to drop console 4 for the test
	run; restore on cleanup so the submodule isn't left modified.
	Returns the restore callback."""
	conf = Z80PACK / "conf" / "net_server.conf"
	original = conf.read_text()
	pruned = "\n".join(
		line for line in original.splitlines()
		if not line.lstrip().startswith("4\t"))
	if pruned != original:
		conf.write_text(pruned + "\n")
		print(f"[harness] dropped console 4 from {conf} for the test run")
	return lambda: conf.write_text(original)


def warn_ndos_freshness():
	"""NDOS lives inside z80pack/cpmsim/disks/library/mpm-net2-1.dsk.
	If cpnos-rom build artefacts are newer than the .dsk file, the
	NDOS on the disk may be out of date for the slave's expectations.
	Print a warning; don't auto-rebuild — that's a separate workflow
	the user manages."""
	dsk = Z80PACK / "disks" / "library" / "mpm-net2-1.dsk"
	cpnos = CPNOS_DIR / "clang" / "cpnos.bin"
	if not dsk.exists() or not cpnos.exists():
		return
	if cpnos.stat().st_mtime > dsk.stat().st_mtime + 5:
		print(f"[harness] WARNING: {dsk} is older than fresh cpnos.bin; "
		      f"NDOS on the MP/M disk may be stale.  Rebuild that disk "
		      f"if the test fails with a NDOS-side error.")


# ---------------------------------------------------------------------------
# test bodies

def parse_taps(text):
	"""Parse tap.lua's count/byte log lines into (count, byte) tuples."""
	out = []
	for line in text.splitlines():
		try:
			parts = dict(p.split("=") for p in line.split())
			out.append((int(parts["count"]), int(parts["byte"], 16)))
		except (ValueError, KeyError):
			pass
	return out


def run_hostsend_test(cleanup):
	"""Original test: harness sends 6 bytes -> Z80 ISR -> verify count + last."""
	pre_taps = parse_taps(TAP_LOG.read_text() if TAP_LOG.exists() else "")
	print(f"[harness] {len(pre_taps)} pre-existing tap entries; "
	      f"will look for new entries after byte send")

	print("[harness] step 8: connect to bridge, send bytes")
	try:
		bridge = socket.create_connection(("127.0.0.1", BRIDGE_PORT),
			timeout=2.0)
	except OSError as e:
		fail(f"bridge :{BRIDGE_PORT} connect failed: {e}", cleanup)

	print(f"[harness] sending {len(TEST_BYTES)} bytes: {TEST_BYTES.hex()}")
	bridge.sendall(TEST_BYTES)
	bridge.close()

	# Verify: net count advanced by len(TEST_BYTES), last observed
	# byte == TEST_BYTES[-1].  Intermediate bytes 1..N-1 are lost
	# to the Lua tap's ~50 Hz polling rate (all ISR fires happen
	# within a single video frame at -nothrottle), so we cannot
	# observe per-byte ordering here.  Ordering is implicit from
	# the bridge's std::deque FIFO discipline (cpnet_bridge.cpp).
	print("[harness] step 9: verify tap log (net count + last byte)")
	expected_delta = len(TEST_BYTES)
	expected_last  = TEST_BYTES[-1]
	end = time.time() + 10.0
	new_taps = []
	while time.time() < end:
		all_taps = parse_taps(
			TAP_LOG.read_text() if TAP_LOG.exists() else "")
		new_taps = all_taps[len(pre_taps):]
		if new_taps:
			latest_count = new_taps[-1][0]
			pre_count = pre_taps[-1][0] if pre_taps else 0
			if (latest_count - pre_count) % 256 >= expected_delta:
				break
		time.sleep(0.1)

	if not new_taps:
		fail(f"no new tap lines (pre-send had {len(pre_taps)})", cleanup)

	latest_count, latest_byte = new_taps[-1]
	pre_count = pre_taps[-1][0] if pre_taps else 0
	actual_delta = (latest_count - pre_count) % 256
	if actual_delta < expected_delta:
		fail(f"counter advanced by {actual_delta}, expected "
		     f"{expected_delta} (pre={pre_count}, latest={latest_count})",
		     cleanup)
	if latest_byte != expected_last:
		fail(f"latest byte=0x{latest_byte:02X}, want 0x{expected_last:02X}",
		     cleanup)

	print(f"PASS: {expected_delta} bytes reached Z80 isr_pio_par "
	      f"(count {pre_count}->{latest_count}, last byte "
	      f"0x{latest_byte:02X})")


PIO_FRAME_LEN = 10

# Speed-test byte counts.  TX modes (variants 1+2) use 100 KiB.  RX
# (variant 3) uses 65536 bytes because the Z80-side ISR uses a
# uint16_t counter that signals done via wrap (65536 -> 0).
PIO_SPEED_BYTES    = 100 * 1024  # 102400 (TX)
PIO_SPEED_RX_BYTES = 65536       # 64 KiB (RX, uint16_t wrap)


def build_response_frame(request: bytes) -> bytes:
	"""Mirror a CP/NET request into a response frame.

	Request layout (10 bytes): [FMT, DID, SID, FNC, SIZ, payload*4, CKS]
	Response: FMT toggled to 0x81, DID/SID swapped, payload echoed,
	checksum recomputed (sum-to-zero, two's complement).
	"""
	if len(request) != PIO_FRAME_LEN:
		raise ValueError(f"frame is {len(request)} bytes, want {PIO_FRAME_LEN}")
	resp = bytearray(request)
	resp[0] = 0x81           # FMT response
	resp[1] = request[2]     # DID = was SID
	resp[2] = request[1]     # SID = was DID
	# resp[3..8] unchanged (FNC, SIZ, payload echoed)
	# Recompute checksum so sum(resp) == 0 mod 256.
	body_sum = sum(resp[:-1]) & 0xFF
	resp[-1] = (-body_sum) & 0xFF
	return bytes(resp)


def run_loopback_test(cleanup):
	"""Frame-level test: Z80 sends a 10-byte CP/NET-shaped request via
	PIO-B Mode 0; harness reads it off :4003, mirrors it as a response
	(FMT toggled to 0x81, DID/SID swapped, checksum recomputed) and
	writes the response back; Z80 reads the response via Mode 1, then
	validates structure + checksum and sets pio_test_passed.

	PASS = pio_test_passed reads 1 AND the harness's view of the wire
	matches what we expect (request frame on the way out matches
	cpnos_main's pio_test_request_frame; response we sent back equals
	what Z80 logged into pio_test_recv)."""
	print(f"[harness] step 8a: connect to bridge, expect {PIO_FRAME_LEN} "
	      f"bytes (CP/NET request frame) from Z80")
	try:
		bridge = socket.create_connection(("127.0.0.1", BRIDGE_PORT),
			timeout=2.0)
	except OSError as e:
		fail(f"bridge :{BRIDGE_PORT} connect failed: {e}", cleanup)

	# Read PIO_FRAME_LEN + 1 to capture the documented Z80-PIO Mode 1->0
	# transition artifact (one stale-latch 0x00 byte before the first
	# real CPU OUT — see transport_pio.c::transport_pio_send_byte).  We
	# strip the leading 0x00 if present and verify the remaining 10
	# bytes match the request frame.
	bridge.settimeout(10.0)
	wire = bytearray()
	want = PIO_FRAME_LEN + 1
	try:
		while len(wire) < want:
			chunk = bridge.recv(want - len(wire))
			if not chunk:
				break
			wire.extend(chunk)
	except socket.timeout:
		# It's OK to time out at PIO_FRAME_LEN if the chip didn't emit
		# the prefix this run.
		pass
	if len(wire) >= 1 and wire[0] == 0x00 and len(wire) == PIO_FRAME_LEN + 1:
		print(f"[harness] stripping chip-artifact 0x00 prefix (documented)")
		received = bytes(wire[1:])
	elif len(wire) == PIO_FRAME_LEN:
		received = bytes(wire)
	else:
		fail(f"received {len(wire)} bytes from Z80, expected "
		     f"{PIO_FRAME_LEN} or {PIO_FRAME_LEN + 1}: {bytes(wire).hex()}",
		     cleanup)

	# Verify the request frame structure on the wire matches the
	# constant in cpnos_main.c::pio_test_request_frame.
	expected_request = bytes([0x80, 0x00, 0x01, 0x05, 0x04,
	                          0xDE, 0xAD, 0xBE, 0xEF, 0xC4])
	if received != expected_request:
		fail(f"request frame on wire = {received.hex()}, "
		     f"expected {expected_request.hex()} "
		     f"(byte-level corruption past the chip prefix)", cleanup)
	print(f"[harness] received request from Z80: {received.hex()}")

	response = build_response_frame(bytes(received))
	print(f"[harness] step 8b: send response frame: {response.hex()}")
	bridge.sendall(response)
	bridge.close()

	print("[harness] step 9: wait for Z80 frame validation to complete")
	end = time.time() + 10.0
	while time.time() < end:
		if LOOPBACK_RESULT.exists():
			break
		time.sleep(0.1)
	if not LOOPBACK_RESULT.exists():
		fail(f"{LOOPBACK_RESULT} never appeared — Z80 frame test "
		     f"didn't complete (check {MAME_LOG} for boot trace)", cleanup)

	# Format: "<HEX> passed=<0|1>"
	result = LOOPBACK_RESULT.read_text().strip()
	parts = result.split()
	if len(parts) != 2 or not parts[1].startswith("passed="):
		fail(f"malformed result line: {result!r}", cleanup)
	got_hex = parts[0]
	passed = int(parts[1].split("=", 1)[1])
	expected_hex = response.hex().upper()
	if got_hex != expected_hex:
		fail(f"pio_test_recv = {got_hex}, expected {expected_hex} "
		     f"(host response != what Z80 saw on the wire)", cleanup)
	if passed != 1:
		fail(f"Z80-side validation failed (pio_test_passed = {passed}; "
		     f"frame structure or checksum did not validate)", cleanup)

	print(f"PASS: CP/NET frame round-trip over PIO-B")
	print(f"       request:  {bytes(received).hex()}")
	print(f"       response: {response.hex()}")
	print(f"       Z80 saw:  {got_hex} (passed={passed})")


PING_BYTES = bytes([0x00, 0x00, 0x01, 0xC0, 0x00, 0x50, 0xEF])
PONG_BYTES = bytes([0x01, 0x01, 0x00, 0xC0, 0x00, 0x4F, 0xEF])
BOOT_MARKS_FILE = Path("/tmp/cpnos_boot_marks.txt")


def run_probe_test(cleanup):
	"""Probe test: harness plays a CP/NET PIO peer for one round-trip.
	Z80's pio_probe() sends a 7-byte PING SCB
	(FMT=0 DID=0 SID=01 FNC=C0 SIZ=0 'P' CKS); we reply with the
	mirrored PONG (FMT=01 DID=01 SID=0 FNC=C0 SIZ=0 'O' CKS).  After
	~3 s wall (giving Z80 time to BOOT_MARK 'P' at col 67), we read
	the boot-marker strip tap.lua dumps to /tmp/cpnos_boot_marks.txt
	and assert col-7 == 'P'.

	Caveat: this test does NOT also serve PIO netboot.  After probe
	succeeds and active_transport switches to PIO, netboot_mpm tries
	LOGIN over PIO — the harness doesn't answer, so the Z80 hangs in
	the for(;;) at the end of cpnos_cold_entry.  The probe + 'P'
	marker are the assertion; netboot is verified separately (Phase B,
	next session)."""
	print(f"[harness] step 8: connect to bridge, expect PING SCB "
	      f"{PING_BYTES.hex()}")
	try:
		bridge = socket.create_connection(("127.0.0.1", BRIDGE_PORT),
			timeout=2.0)
	except OSError as e:
		fail(f"bridge :{BRIDGE_PORT} connect failed: {e}", cleanup)

	# Z80-PIO Mode 1 -> Mode 0 transition emits a stale-latch byte
	# (m_output after reset = 0) before any CPU OUT; absorb up to 8
	# bytes and strip the leading 0 if present.  Documented in
	# transport_pio.c (and ravn/mame#7).
	bridge.settimeout(15.0)
	wire = bytearray()
	want = len(PING_BYTES) + 1
	try:
		while len(wire) < want:
			chunk = bridge.recv(want - len(wire))
			if not chunk: break
			wire.extend(chunk)
	except socket.timeout:
		pass
	if len(wire) == len(PING_BYTES) + 1 and wire[0] == 0x00:
		print("[harness] stripping chip-artifact 0x00 prefix")
		ping = bytes(wire[1:])
	elif len(wire) == len(PING_BYTES):
		ping = bytes(wire)
	else:
		fail(f"received {len(wire)} bytes, expected "
		     f"{len(PING_BYTES)} or {len(PING_BYTES)+1}: {bytes(wire).hex()}",
		     cleanup)

	if ping != PING_BYTES:
		fail(f"PING mismatch: got {ping.hex()}, want {PING_BYTES.hex()}",
		     cleanup)
	# Sum-to-zero CKS sanity check on what arrived.
	if (sum(ping) & 0xFF) != 0:
		fail(f"PING CKS bad: sum={sum(ping)&0xFF:#04x} (must be 0)", cleanup)

	print(f"[harness] PING ok: {ping.hex()}; replying PONG {PONG_BYTES.hex()}")
	if (sum(PONG_BYTES) & 0xFF) != 0:
		fail(f"PONG CKS bad in test constant", cleanup)
	bridge.sendall(PONG_BYTES)
	bridge.close()

	# Wait for Z80 to set BOOT_MARK at col 67 (idx 7 in the strip).
	# pio_probe returns within ~ms of receiving the 7th PONG byte; the
	# marker write follows immediately.  Pad to 5 s wall to be safe.
	print("[harness] step 9: poll for 'P' marker at strip idx 7")
	end = time.time() + 10.0
	last_strip = None
	while time.time() < end:
		if BOOT_MARKS_FILE.exists():
			last_strip = BOOT_MARKS_FILE.read_text().strip()
			if len(last_strip) >= 8 and last_strip[7] in ("P", "S"):
				break
		time.sleep(0.1)
	if not last_strip:
		fail(f"{BOOT_MARKS_FILE} never appeared (tap.lua not running?)",
		     cleanup)
	if len(last_strip) < 8:
		fail(f"boot-marker strip too short: {last_strip!r}", cleanup)
	mark = last_strip[7]
	if mark != "P":
		fail(f"transport-select marker = {mark!r} (want 'P'); "
		     f"strip = {last_strip!r}", cleanup)

	print(f"PASS: PIO probe round-trip succeeded; Z80 selected PIO transport")
	print(f"       boot strip: {last_strip!r}")


def run_pio_netboot_test(cleanup):
	"""Phase-B end-to-end: PIO probe wins, then full CP/NET netboot
	runs over the parallel link.  cpnet_pio_server.py acts as the
	master, connects to MAME's bridge :4003, replies to PING and then
	serves the standard CP/NET netboot sequence (LOGIN / OPEN
	A:CPNOS.IMG / READ-SEQ * N / CLOSE).  Z80 reaches NDOS COLDST
	via the parallel transport.

	Pass condition: boot-strip column 17 (J marker = "about to JP NDOS
	COLDST") observed within mame-seconds.  Same final marker as the
	SIO success path."""
	# cpnet_pio_server.py is launched in step 5c (in main() — see below
	# for the spawn).  By the time this test runs, MAME has bound :4003
	# and the server has connected, so probe + netboot can already be in
	# flight.  We just poll the boot-marker strip.
	print("[harness] step 8: poll boot-marker strip until NDOS COLDST 'J'")
	end = time.time() + 60.0
	last_strip = ""
	while time.time() < end:
		if BOOT_MARKS_FILE.exists():
			last_strip = BOOT_MARKS_FILE.read_text().strip()
			# 19-char strip; idx 7=transport, 8..14=netboot, 15=netboot-rc,
			# 16=PROM-disable, 17=SNIOS-primed, 18=JP-NDOS-COLDST.
			if len(last_strip) >= 19 and last_strip[18] == 'J':
				break
		time.sleep(0.1)
	if not last_strip:
		fail(f"{BOOT_MARKS_FILE} never appeared (tap.lua not running?)",
		     cleanup)
	if len(last_strip) < 8 or last_strip[7] != 'P':
		fail(f"transport-select marker = {last_strip[7] if len(last_strip) > 7 else '?'!r}; "
		     f"want 'P' (PIO selected); strip = {last_strip!r}", cleanup)
	if len(last_strip) < 19 or last_strip[18] != 'J':
		fail(f"NDOS COLDST marker (idx 18) = {last_strip[18] if len(last_strip) > 18 else '?'!r}; "
		     f"want 'J'; strip = {last_strip!r}", cleanup)

	print(f"PASS: CP/NET netboot via PIO completed; NDOS COLDST reached")
	print(f"       boot strip: {last_strip!r}")


def run_speed_test(cleanup, mode="speed"):
	"""Stream PIO_SPEED_BYTES (100 KiB) from Z80 over PIO-B; count and
	time on the host side; report throughput.

	Patterns by mode:
	  speed (variant 1, C-loop):  byte i = (i // 1024) ^ (i & 0xFF)
	  speed-otir (variant 2):     byte i = i & 0xFF (256-byte ramp x400)

	At -nothrottle MAME the wall throughput is dominated by emulator
	overhead.  At real-time (the speed* modes use real-time) wall
	throughput equals what a 4-MHz Z80 delivers."""
	print(f"[harness] step 8: connect to bridge, expect {PIO_SPEED_BYTES} "
	      f"bytes (100 KiB) from Z80")
	try:
		bridge = socket.create_connection(("127.0.0.1", BRIDGE_PORT),
			timeout=2.0)
	except OSError as e:
		fail(f"bridge :{BRIDGE_PORT} connect failed: {e}", cleanup)

	bridge.settimeout(60.0)
	# Read PIO_SPEED_BYTES + 1 to absorb the documented chip-emulation
	# 0x00 prefix on first Mode 1->0 transition.  We strip it after.
	want = PIO_SPEED_BYTES + 1
	buf = bytearray()
	t_first = None
	t_last  = None
	try:
		while len(buf) < want:
			chunk = bridge.recv(min(65536, want - len(buf)))
			if not chunk:
				break
			if t_first is None:
				t_first = time.monotonic()
			t_last = time.monotonic()
			buf.extend(chunk)
	except socket.timeout:
		pass
	bridge.close()

	if len(buf) >= 1 and buf[0] == 0x00 and len(buf) == PIO_SPEED_BYTES + 1:
		print(f"[harness] stripping chip-artifact 0x00 prefix")
		buf = buf[1:]
	if len(buf) != PIO_SPEED_BYTES:
		fail(f"received {len(buf)} bytes, expected {PIO_SPEED_BYTES} "
		     f"(or {PIO_SPEED_BYTES + 1} with prefix)", cleanup)

	# Verify ordering with the variant-specific pattern.
	if mode == "speed-otir":
		# Pattern: 32-byte ramp 0..31 repeated.  Byte 0 also includes
		# the C-path init send (also 0), so byte 0 == 0 either way.
		expect = lambda i: i & 0x1F
	else:
		expect = lambda i: (i // 1024) ^ (i & 0xFF)
	mismatches = 0
	first_mismatch = None
	for i, got in enumerate(buf):
		want_byte = expect(i) & 0xFF
		if got != want_byte:
			mismatches += 1
			if first_mismatch is None:
				first_mismatch = (i, got, want_byte)
	if mismatches:
		idx, got, want_byte = first_mismatch
		preview = buf[:32].hex()
		fail(f"{mismatches}/{len(buf)} byte mismatches; first at offset "
		     f"{idx}: got 0x{got:02X}, want 0x{want_byte:02X}. "
		     f"First 32 bytes received: {preview}", cleanup)

	# At MAME 100% throttle, wall == Z80 emulated.  Reporting wall as
	# the Z80 throughput is meaningful only in this regime.
	wall_sec = (t_last - t_first) if (t_first and t_last) else 0.0
	rate = (PIO_SPEED_BYTES / wall_sec / 1024.0) if wall_sec > 0 else 0

	print()
	variant = "C-loop" if mode == "speed" else "OTIR"
	print(f"PASS: 100 KiB streamed Z80 -> host over PIO-B ({variant})")
	print(f"       Z80 throughput:  {rate:.1f} KiB/s "
	      f"(100 KiB in {wall_sec*1000:.0f} ms emulated at 4 MHz)")


def run_speed_rx_test(cleanup, mode="speed-rx"):
	"""Stream PIO_SPEED_RX_BYTES (64 KiB) from host into Z80 over
	PIO-B.  Z80 ISR (isr_pio_par) increments uint16_t pio_rx_count
	per byte; on wrap it sets pio_test_done = 1.  We send exactly
	65536 bytes so the ISR signals on the last one.  Time wall-clock
	from "started sending" to "Z80 set pio_test_done = 1" (observed
	via tap.lua marker file).

	The recv_byte ring path is bypassed — at high RX rates back-to-
	back ISRs starve the mainline (chip's BRDY toggle in data_read
	immediately triggers the next bridge strobe), so the ring
	overruns and the recv loop stalls.  Counting in the ISR itself
	measures pure chip+ISR throughput."""
	bytes_to_send = PIO_SPEED_RX_BYTES
	print(f"[harness] step 8: connect to bridge, stream {bytes_to_send} "
	      f"bytes (64 KiB) -> Z80")
	try:
		bridge = socket.create_connection(("127.0.0.1", BRIDGE_PORT),
			timeout=5.0)
	except OSError as e:
		fail(f"bridge :{BRIDGE_PORT} connect failed: {e}", cleanup)

	# Build the payload: 0..255 ramp x 256.  In INIR mode the Z80
	# busy-polls for a 0xAA sentinel that demarcates the start; prepend
	# it so the timed phase begins when the Z80 sees data.
	one_chunk = bytes(range(256))
	payload = one_chunk * (bytes_to_send // 256)
	assert len(payload) == bytes_to_send
	if mode == "speed-rx-inir":
		payload = b"\xAA" + payload

	# Z80 reaches pio_loopback_test ~3-4 emulated seconds after MAME
	# start.  At real-time MAME that's 3-4 wall seconds.  Wait for
	# the recv loop to be primed before timing — we don't want host
	# fill-time to be conflated with Z80-side processing time.
	print("[harness] step 8a: wait 4 s for Z80 to enter recv loop")
	time.sleep(4.0)

	# Send the full 100 KiB.  TCP buffering means sendall returns
	# when the kernel accepts the data, not when Z80 has read it.
	# Real "done" signal comes from pio_test_done observed via Lua.
	print("[harness] step 8b: send 100 KiB over TCP")
	t_start = time.monotonic()
	bridge.sendall(payload)
	t_send_done = time.monotonic()
	bridge.close()

	# pio_test_done flag is set by Z80 after the last recv_byte
	# returns.  tap.lua writes a marker (LOOPBACK_RESULT exists)
	# when it observes pio_test_done == 1.  Speed-rx tap path
	# doesn't write recv content; existence of the file is the
	# done-signal.
	print("[harness] step 9: wait for Z80 to drain (pio_test_done flips)")
	end = time.time() + 60.0
	while time.time() < end:
		if LOOPBACK_RESULT.exists():
			break
		time.sleep(0.05)
	t_done = time.monotonic()
	if not LOOPBACK_RESULT.exists():
		fail(f"{LOOPBACK_RESULT} never appeared after 60 s — Z80 did "
		     f"not finish draining.  Check {MAME_LOG} for boot trace.",
		     cleanup)

	# At MAME 100% throttle, wall == Z80 emulated.  TCP send-buffer
	# fill on localhost completes in single-digit ms, dominated by the
	# Z80's drain — so wall total = Z80 throughput.
	wall = t_done - t_start
	rate = (bytes_to_send / wall / 1024.0) if wall > 0 else 0

	variant = "INIR busy-poll" if mode == "speed-rx-inir" else "ISR-only"
	print()
	print(f"PASS: 64 KiB streamed host -> Z80 over PIO-B ({variant})")
	print(f"       Z80 throughput:  {rate:.1f} KiB/s "
	      f"(64 KiB in {wall*1000:.0f} ms emulated at 4 MHz)")


# ---------------------------------------------------------------------------
# main

def main():
	ap = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--keep-alive", action="store_true",
		help="leave processes running for manual poking")
	ap.add_argument("--mame-bin", default=str(MAME_BIN))
	ap.add_argument("--roms", default=str(ROMS_DIR))
	ap.add_argument("--boot-timeout", type=float, default=60.0,
		help="how long to wait for CPNOS banner (default 60s)")
	ap.add_argument("--mame-seconds", type=int, default=120,
		help="MAME -seconds_to_run (default 120)")
	ap.add_argument("--mode",
		choices=("hostsend", "loopback", "probe", "pio-netboot",
		         "speed", "speed-otir", "speed-rx", "speed-rx-inir"),
		default="hostsend",
		help="hostsend: harness sends 6 bytes -> Z80 ISR; "
		     "loopback: Z80 sends 10-byte CP/NET frame -> harness mirrors -> Z80 validates; "
		     "probe: Z80 pio_probe() sends PING SCB -> harness replies PONG -> verify 'P' marker; "
		     "pio-netboot: full CP/NET netboot over the parallel link (cpnet_pio_server.py); "
		     "speed: Z80 streams 100 KiB via C-loop transport_pio_send_byte; "
		     "speed-otir: Z80 streams 100 KiB via inline OTIR (raw OUT (C),(HL)); "
		     "speed-rx: harness sends 64 KiB -> Z80 ISR drain (counter wrap); "
		     "speed-rx-inir: harness sends 64 KiB -> Z80 INIR busy-poll (no IRQ)")
	args = ap.parse_args()

	mame = Path(args.mame_bin)
	if not mame.exists():
		fail(f"{mame} not found — build ravn/mame:cpnet-fast-link first")
	if not TAP_LUA.exists():
		fail(f"{TAP_LUA} missing")
	netboot_py = CPNOS_DIR / "netboot_server.py"
	if not netboot_py.exists():
		fail(f"{netboot_py} missing — cpnos-rom layout changed?")

	cleanup = Cleanup()

	try:
		print("[harness] step 1: ensure cpnos-rom built")
		# Speed mode needs the streaming send body; loopback mode needs
		# the frame body.  Force clean+rebuild when mode changes so we
		# don't inherit stale objects from a previous build with the
		# other test compiled in.
		extra_make_args = ()
		speed_variant = {"speed": 1, "speed-otir": 2,
		                 "speed-rx": 3, "speed-rx-inir": 4}.get(args.mode)
		if speed_variant is not None:
			run(["make", "-s", "cpnos-clean"], cwd=str(CPNOS_DIR))
			extra_make_args = (f"PIO_SPEED_TEST={speed_variant}",
			                   "PIO_LOOPBACK_TEST=0")
		elif args.mode == "loopback":
			run(["make", "-s", "cpnos-clean"], cwd=str(CPNOS_DIR))
			extra_make_args = ("PIO_SPEED_TEST=0", "PIO_LOOPBACK_TEST=1")
		ensure_cpnos_built(extra_make_args)

		print("[harness] step 1b: extract live BSS addrs into addrs.lua")
		addrs = emit_addrs_lua()
		if args.mode == "loopback":
			missing = {"_pio_test_done", "_pio_test_recv"} - addrs.keys()
			if missing:
				fail(f"loopback mode requires PIO_LOOPBACK_TEST=1 build "
				     f"(missing symbols: {sorted(missing)})")

		print(f"[harness] step 4: kill stale listener on :{MPM_PORT}")
		kill_stale(MPM_PORT)
		# Bridge port is bound by MAME's rc702_state directly (osd_file
		# socket, no slot card) — but kill any straggler just in case.
		kill_stale(BRIDGE_PORT)

		reset_state()

		# netboot_server.py is the synthetic CP/NET responder that
		# cpnos-netboot uses; mpm-net2 is the real-but-slow MP/M which
		# does not currently boot cpnos-rom in MAME within the test
		# window (verified 2026-04-26 — black screen against mpm-net2,
		# clean banner against netboot_server.py).
		print(f"[harness] step 5: launch netboot_server.py (-> :{MPM_PORT})")
		mpm = spawn_group(["python3", "-u", str(netboot_py), str(MPM_PORT)],
		                  cwd=str(CPNOS_DIR), log_path=MPM_LOG)
		cleanup.push(lambda: kill_group(mpm) if not args.keep_alive else None)

		# MAME's bridge (bitbanger-backed) connects to :BRIDGE_PORT at
		# start-up; if nothing's listening, MAME aborts before cpnos
		# even begins.  So every mode that uses cpnet_bridge needs a
		# listener on :BRIDGE_PORT *before* MAME launches.
		#
		# pio-netboot: full CP/NET PIO server.
		# everything else: passive dummy listener (accept + drop) so
		#                  MAME starts but PIO probe sees no PONG and
		#                  falls back to SIO.  hostsend/loopback/speed
		#                  modes bind their own protocol on top later
		#                  (those modes are bring-up scaffolding, not
		#                  exercised after the bitbanger refactor).
		kill_stale(BRIDGE_PORT)
		if args.mode == "pio-netboot":
			pio_server = CPNOS_DIR / "cpnet_pio_server.py"
			print(f"[harness] step 5c: spawn cpnet_pio_server -> "
			      f":{BRIDGE_PORT}")
			pio_p = spawn_group(
				["python3", "-u", str(pio_server), str(BRIDGE_PORT)],
				cwd=str(CPNOS_DIR),
				log_path=Path("/tmp/cpnos_pio_server.log"))
			cleanup.push(lambda: kill_group(pio_p) if not args.keep_alive else None)
		else:
			print(f"[harness] step 5c: spawn dummy listener -> "
			      f":{BRIDGE_PORT} (PIO probe will time out -> "
			      f"SIO fallback)")
			dummy_code = (
				"import socket,sys;"
				f"s=socket.socket(socket.AF_INET, socket.SOCK_STREAM);"
				"s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);"
				f"s.bind(('127.0.0.1',{BRIDGE_PORT}));"
				"s.listen(1);"
				"c,_=s.accept();c.settimeout(120.0);"
				"\nwhile True:\n"
				"  try:\n"
				"    d=c.recv(4096);\n"
				"    if not d: break\n"
				"  except Exception: break"
			)
			dummy_p = spawn_group(
				["python3", "-u", "-c", dummy_code],
				log_path=Path("/tmp/cpnos_bridge_dummy.log"))
			cleanup.push(lambda: kill_group(dummy_p) if not args.keep_alive else None)
		# Give listener a moment to bind before MAME tries to connect.
		time.sleep(0.3)
		try:
			wait_for_listen(BRIDGE_PORT, deadline_s=5.0)
		except TimeoutError as e:
			fail(f"listener on :{BRIDGE_PORT} never bound: {e}", cleanup)

		try:
			wait_for_listen(MPM_PORT, deadline_s=10.0)
		except TimeoutError as e:
			fail(f"MP/M did not start: {e}; see {MPM_LOG}", cleanup)

		# SIO-B sink: mirror cpnos-netboot Makefile target which spawns
		# sio_b_driver.py.  Without it, MAME's rs232b null_modem has no
		# host connection and cpnos-rom hangs early in boot (verified
		# 2026-04-26: -rs232a only -> "client closed waiting for ENQ").
		SIOB_PORT = 9001
		print(f"[harness] step 5b: launch sio_b_driver.py (-> :{SIOB_PORT})")
		kill_stale(SIOB_PORT)
		siob_py = CPNOS_DIR / "sio_b_driver.py"
		siob = spawn_group(["python3", "-u", str(siob_py), str(SIOB_PORT)],
		                   cwd=str(CPNOS_DIR), log_path=Path("/tmp/cpnos_bridge_siob.log"))
		cleanup.push(lambda: kill_group(siob) if not args.keep_alive else None)
		wait_for_listen(SIOB_PORT, deadline_s=5.0)

		# In speed modes, run at real-time (no -nothrottle) so wall
		# elapsed equals Z80 emulated elapsed.  Measured throughput
		# then matches what real 4-MHz hardware would deliver.
		realtime = args.mode in ("speed", "speed-otir",
		                          "speed-rx", "speed-rx-inir")
		throttle_args = [] if realtime else ["-nothrottle"]

		print("[harness] step 6: launch MAME with -piob cpnet_bridge "
		      f"({'real-time' if realtime else 'nothrottle'})")
		mame_p = spawn_group([
			str(mame), "rc702",
			"-rompath", args.roms,
			*throttle_args,
			"-window",
			"-skip_gameinfo",
			"-log",
			"-seconds_to_run", str(args.mame_seconds),
			"-rs232a", "null_modem",
			"-bitb1", f"socket.127.0.0.1:{MPM_PORT}",
			"-rs232b", "null_modem",
			"-bitb2", f"socket.127.0.0.1:{SIOB_PORT}",
			"-piob", "cpnet_bridge",
			# cpnet_bridge wraps a bitbanger sub-device (model
			# matches null_modem's :rs232X:stream); it's the third
			# bitbanger in the system after :rs232a:stream and
			# :rs232b:stream, so -bitb3 wires it to localhost:4003.
			"-bitb3", f"socket.127.0.0.1:{BRIDGE_PORT}",
			"-autoboot_script", str(TAP_LUA),
		], log_path=MAME_LOG, cwd=str(MAME_DIR))
		cleanup.push(lambda: kill_group(mame_p) if not args.keep_alive else None)

		# Step 7: wait until rc702_state's machine_start opens the
		# osd_file listening socket on :4003.  That happens during MAME
		# init, well before cpnos-rom enables interrupts.  We don't need
		# cpnos-rom to be "ready" — any pre-EI byte will sit in the rx
		# queue and get strobed in the moment cpnos_main calls
		# enable_interrupts() and BRDY rises.
		# Step 7 used to wait for a TCP LISTEN on :BRIDGE_PORT before
		# proceeding.  The previous cpnet_bridge.cpp opened its socket
		# eagerly in device_start; the current bitbanger-based device
		# defers the bind until first I/O (which happens during cpnos's
		# pio_probe ~0.04 s wall after MAME launch — too late for an
		# lsof-poll loop to reliably catch).  The test bodies below
		# tolerate "not yet bound" — the PIO server's connect-retry
		# loop covers it.  Skip the gate.
		print(f"[harness] step 7: bridge listener (lazy-bound by bitbanger; "
		      f"no pre-flight gate)")

		if args.mode == "pio-netboot":
			# Z80's probe runs ~24 ms wall-clock after MAME launches
			# (relocator + init_hardware at -nothrottle ~5×).  Python
			# import netboot_server + socket.create_connection takes
			# ~80 ms wall — if we spawn AFTER MAME, the server isn't
			# connected when probe runs and probe falls back to SIO.
			# Wait a moment so the server's connect-retry loop has a
			# real chance to attach to the bridge listener.
			print("[harness] step 7c: hold briefly so PIO server "
			      "completes import + connect before Z80 probes")
			time.sleep(0.5)
			run_pio_netboot_test(cleanup)
		elif args.mode == "probe":
			# Probe runs early in cpnos_cold_entry; connect immediately
			# so PONG is queued before Z80 finishes pio_send_msg.
			run_probe_test(cleanup)
		elif args.mode == "hostsend":
			# Give cpnos-rom a chance to actually call enable_interrupts.
			# This requires netboot to complete: ~1-3 emulated seconds
			# at ~1400% speed = <1 wall second.  Pad to 5s for safety.
			time.sleep(5.0)
			run_hostsend_test(cleanup)
		elif args.mode == "loopback":
			# Loopback: connect immediately and let recv block.  Z80
			# sends 10-byte frame a few hundred ms wall-clock after
			# MAME launch.  At ~1400% speed Z80's per-byte recv
			# timeout is too short to wait long, so we must echo
			# before Z80 enters its recv loop — connect straight
			# away to maximise the host-side wall-clock budget.
			run_loopback_test(cleanup)
		elif args.mode in ("speed-rx", "speed-rx-inir"):
			run_speed_rx_test(cleanup, mode=args.mode)
		else:  # speed, speed-otir
			run_speed_test(cleanup, mode=args.mode)

	finally:
		if not args.keep_alive:
			cleanup.run()


if __name__ == "__main__":
	main()
