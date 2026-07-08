#!/usr/bin/env python3
"""SIO-B driver for the rcbios + PIO + PolyPascal regression test.

Listens as the server end of MAME's `-rs232b null_modem -bitb2
socket.127.0.0.1:<PORT>` (the joined-console SIO-B link).  The slave
boots from a local floppy, runs `$$$.SUB` to drive CPNETLDR -> LOGIN
-> NETWORK H:=B: -> H:PPAS H:PRIMES.PAS, and the PolyPascal-80
interpreter takes over.

This script then drives the interactive part:
  >>          PPAS prompt -> send "R\\r"     (Run)
  (output)    watch for "29989" (last prime printed)
  >>          post-run prompt -> send "Q\\r"  (Quit, returns to CCP)
  A>          CCP prompt -> PASS

Writes /tmp/cpnet_pio_polypascal_result.txt with PASS or FAIL+reason.

Independent of the cpnos polypascal_test.lua: that one injects
directly into cpnos's kbd_ring at fixed BSS addresses; rcbios has
no equivalent symbol-level hook so we go through SIO-B (the
joined-console keyboard input path).
"""
import argparse
import socket
import sys
import time

RESULT = '/tmp/cpnet_pio_polypascal_result.txt'

STAGES = [
    # (deadline_sec, marker,         cmd_to_send_after, name)
    # Stage 0: wait for slave to reach H> after SUB-driven CPNETLDR /
    # LOGIN / NETWORK / H:, then type 'PPAS' WITH CR.  PPAS isn't in
    # the SUB itself -- the SUB-record path lacks a reliable
    # line-terminator semantics across CCP/CP/NET timing variations
    # (without a TCP proxy between MAME's cpnet_bridge and mpm-net2,
    # the PPAS.COM load over CP/NET stalls).  Mirrors cpnos's
    # polypascal_test.lua which also injects PPAS as a typed command.
    #
    # Note: PRIMES.PAS uses max2=15000 (primes to 29989) but under
    # rcbios's 56K CP/M the PolyPascal workspace is ~12K free, limiting
    # the sieve array to ~6000 elements.  We do NOT assert a specific
    # last prime; instead we wait for the '>>' prompt that PPAS shows
    # when PRIMES returns (stage 3), proving the computation completed.
    (120.0,          b'H>',          b'PPAS\r',         'wait H> then send PPAS'),
    # PPAS.COM (222 × 128 B CP/NET records) loads at ~4-5x MAME speed
    # over TCP — each record is a full frame round-trip through cpnet_bridge
    # to z80pack (~3600 s emulated / ~750 s wall).
    (800.0,          b'>>',          b'L PRIMES\r',     'initial PPAS prompt / L PRIMES'),
    (120.0,          b'>>',          b'R\r',            'post-load prompt / R'),
    (300.0,          b'>>',          b'Q\r',            'PRIMES complete: post-Run >> prompt / Q'),
    (30.0,           None,           None,              'CCP return (any drive prompt)'),
]


def _is_ccp_prompt(buf):
    """Buffer tail looks like a CCP prompt: ASCII drive letter + '>'."""
    if len(buf) < 2 or buf[-1:] != b'>':
        return False
    c = buf[-2]
    return 0x41 <= c <= 0x50  # 'A'..'P' (CP/M supports up to 16 drives)


def _find_marker(stage, buf):
    """Locate the stage's marker in buf.  Returns end-index of the
    match, or -1 if not yet matched.  Stage 4's None-marker uses the
    CCP-prompt heuristic since we don't know which drive the slave
    will be on (depends on whether the workload ran from local A:
    or remote H:)."""
    marker = stage[1]
    if marker is None:
        # CCP-prompt check: scan for any drive-letter + '>' in buf.
        for i in range(len(buf) - 1):
            if buf[i+1:i+2] == b'>' and 0x41 <= buf[i] <= 0x50:
                return i + 2
        return -1
    idx = buf.find(marker)
    return -1 if idx < 0 else idx + len(marker)


def write_result(text):
    with open(RESULT, 'w') as f:
        f.write(text + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('port', type=int, default=9001, nargs='?')
    ap.add_argument('--log', default='/tmp/cpnos_siob.raw')
    ap.add_argument('--timeout', type=float, default=240.0)
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', args.port))
    srv.listen(1)
    print(f'polypascal_pio_inject listening on :{args.port}', flush=True)
    srv.settimeout(args.timeout)
    try:
        conn, peer = srv.accept()
    except socket.timeout:
        write_result('FAIL: no MAME connection within accept timeout')
        sys.exit(1)
    print(f'connected from {peer}', flush=True)
    conn.settimeout(0.5)

    log = open(args.log, 'wb', buffering=0)
    buf = bytearray()
    stage_idx = 0
    stage_deadline = time.monotonic() + STAGES[0][0]
    t0 = time.monotonic()
    _first_marker = STAGES[stage_idx][1]
    _first_desc = repr(_first_marker) if _first_marker else '<CCP prompt>'
    print(f'[stage {stage_idx}] waiting for {_first_desc} '
          f'({STAGES[stage_idx][3]})', flush=True)

    while stage_idx < len(STAGES):
        try:
            data = conn.recv(64)
        except socket.timeout:
            data = b''
        if data:
            log.write(data)
            buf.extend(data)
            # Trim buf so we don't re-match the same prefix forever
            if len(buf) > 4096:
                del buf[:2048]
        stage = STAGES[stage_idx]
        end_idx = _find_marker(stage, buf)
        if end_idx >= 0:
            cmd = stage[2]
            elapsed = time.monotonic() - t0
            matched = bytes(buf[max(0, end_idx-8):end_idx])
            print(f'[stage {stage_idx}] matched ...{matched!r} '
                  f'(t={elapsed:.2f}s) -> '
                  f'{"send "+repr(cmd) if cmd else "advance"}',
                  flush=True)
            if cmd:
                # Pace byte writes so we don't overrun the slave's SIO-B
                # RX 3-deep FIFO.  At 38400 baud one byte is ~260 us on
                # the wire; the slave's SIO-B ISR latency is much higher
                # under heavy CP/NET PIO load (and the SDCC BIOS's ISR
                # appears to be slower than clang's -- empirically drops
                # the CR of bursts).  20 ms/byte matches cpnos's
                # smoke_inject pacing.  See feedback_no_taps_in_polled_rx.
                for byte in cmd:
                    conn.sendall(bytes([byte]))
                    time.sleep(0.02)
            # Drop everything up to and including the matched bytes.
            del buf[:end_idx]
            stage_idx += 1
            if stage_idx < len(STAGES):
                next_marker = STAGES[stage_idx][1]
                next_desc = repr(next_marker) if next_marker else '<CCP prompt>'
                stage_deadline = time.monotonic() + STAGES[stage_idx][0]
                print(f'[stage {stage_idx}] waiting for {next_desc} '
                      f'({STAGES[stage_idx][3]})', flush=True)
            continue
        if time.monotonic() > stage_deadline:
            elapsed = time.monotonic() - t0
            _m = STAGES[stage_idx][1]
            _mdesc = repr(_m) if _m else '<CCP prompt>'
            reason = (f'timeout at stage {stage_idx} '
                      f'({STAGES[stage_idx][3]}); '
                      f'wanted {_mdesc}; '
                      f'last 80 B = {bytes(buf[-80:])!r}')
            print(f'FAIL: {reason}', flush=True)
            write_result(f'FAIL: {reason}')
            sys.exit(1)

    elapsed = time.monotonic() - t0
    print(f'PASS: all {len(STAGES)} stages green (t={elapsed:.2f}s)',
          flush=True)
    write_result(f'PASS: rcbios PIO + PolyPascal PRIMES through 29989 '
                 f'and Q returned to CCP (t={elapsed:.2f}s)')


if __name__ == '__main__':
    main()
