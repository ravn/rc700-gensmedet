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
    # (deadline_sec, marker_bytes,  cmd_to_send_after, name)
    (90.0,           b'>>',          b'L PRIMES\r',     'initial PPAS prompt / L PRIMES'),
    (90.0,           b'>>',          b'R\r',            'post-load prompt / R'),
    (180.0,          b'29989',       None,              'PRIMES output complete'),
    (30.0,           b'>>',          b'Q\r',            'post-Run prompt / Q'),
    (30.0,           b'A>',          None,              'CCP return (A>)'),
]


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
    print(f'[stage {stage_idx}] waiting for {STAGES[stage_idx][1]!r} '
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
        marker = STAGES[stage_idx][1]
        if marker in buf:
            cmd = STAGES[stage_idx][2]
            elapsed = time.monotonic() - t0
            print(f'[stage {stage_idx}] matched {marker!r} '
                  f'(t={elapsed:.2f}s) -> '
                  f'{"send "+repr(cmd) if cmd else "advance"}',
                  flush=True)
            if cmd:
                conn.sendall(cmd)
            # Drop everything up to and including the marker so the
            # next stage doesn't re-match it.
            i = buf.find(marker) + len(marker)
            del buf[:i]
            stage_idx += 1
            if stage_idx < len(STAGES):
                stage_deadline = time.monotonic() + STAGES[stage_idx][0]
                print(f'[stage {stage_idx}] waiting for {STAGES[stage_idx][1]!r} '
                      f'({STAGES[stage_idx][3]})', flush=True)
            continue
        if time.monotonic() > stage_deadline:
            elapsed = time.monotonic() - t0
            reason = (f'timeout at stage {stage_idx} '
                      f'({STAGES[stage_idx][3]}); '
                      f'wanted {STAGES[stage_idx][1]!r}; '
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
