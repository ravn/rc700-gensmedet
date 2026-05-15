#!/usr/bin/env python3
"""Prompt-aware SIO-B injector for the cpnet-smoke test.

Listens as the server end of MAME's `-bitb2 socket.127.0.0.1:<PORT>`.
When the expected prompt pattern appears at the tail of the slave's
SIO-B TX stream, the next command in the sequence is pushed back on
the socket.  Required because sending all commands at once overruns
the Z80 SIO-B RX buffer while CCP is busy executing the current one
(network round-trips to MP/M take seconds).

Every received byte is appended to the log file so the make target
can grep the final result.

Usage:
    smoke_inject.py <port> [--log PATH] [--timeout SEC]
"""
import argparse
import os
import socket
import sys
import time

WORKLOADS = {
    # Each workload is (commands, finish_marker).  All steps wait for the
    # same CCP prompt — any drive letter followed by `>` at the buffer
    # tail (matched by _is_ccp_prompt below).  Used to be hardcoded `A>`,
    # but the cpnos-rom default drive moved to E: in Phase 27 (timeline.md
    # line 3927).  See ravn/rc700-gensmedet#98.
    # 'sumtest': m80 + l80 assembles+links+runs sumtest.asm; output is
    #   "CPNET OK A314" (deterministic 16-bit sum of 1..1000 mod 65536).
    # 'filecopy': pre-assembled FILECOPY.COM reads SUMTEST.ASM and
    #   writes SUMTEST.CPY via BDOS F_READ/F_WRITE.  Pure I/O — no
    #   m80/l80 in the timed window.  Marker "FILECOPY OK".
    #
    # First step on every workload is `A:` to switch from the slave's
    # default drive (E:, the local netboot drive carrying cpnos.com +
    # PolyPascal stuff) to the MP/M-served network drive A: where
    # M80.COM / L80.COM / sumtest.asm actually live.  Pre-Phase-27 the
    # default drive was A: so this step was implicit; after PROM 1
    # rework the default moved to E: and the smoke tools weren't
    # there to find.  See init.c:147 cfgtbl_init_template +
    # mksmokedisk.sh's drivea-only assumption.  ravn/rc700-gensmedet#98.
    'sumtest': (
        [b'A:\r',
         b'm80 sumtest,=sumtest.asm\r',
         b'l80 sumtest,sumtest/n/e\r',
         b'sumtest\r'],
        b'CPNET OK ',
    ),
    'filecopy': (
        [b'A:\r',
         b'filecopy\r'],
        b'FILECOPY OK ',
    ),
}


def _is_ccp_prompt(buf):
    """Buffer tail looks like a CCP prompt: ASCII drive letter + '>'."""
    if len(buf) < 2 or buf[-1:] != b'>':
        return False
    c = buf[-2]
    return 0x41 <= c <= 0x50  # 'A'..'P' (CP/M supports up to 16 drives)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('port', type=int)
    ap.add_argument('--log', default='/tmp/cpnos_siob.raw')
    ap.add_argument('--timeout', type=float, default=300.0)
    ap.add_argument('--workload', choices=sorted(WORKLOADS), default='sumtest')
    args = ap.parse_args()
    STEPS, FINISH_MARKER = WORKLOADS[args.workload]
    print(f'workload: {args.workload} ({len(STEPS)} step(s), '
          f'marker={FINISH_MARKER!r})', flush=True)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', args.port))
    srv.listen(1)
    print(f'smoke_inject listening on :{args.port}', flush=True)

    srv.settimeout(args.timeout)
    conn, peer = srv.accept()
    print(f'connected from {peer}', flush=True)
    conn.settimeout(0.5)

    log = open(args.log, 'wb', buffering=0)
    buf = bytearray()
    step_idx = 0
    # After sending a command, we briefly wait for its echo to start
    # before looking for the NEXT prompt — otherwise we'd match the
    # A> that triggered the first send again.
    cooldown_until = 0.0
    deadline = time.monotonic() + args.timeout
    saw_marker = False
    last_data_at = time.monotonic()
    next_nudge_at = time.monotonic() + 10.0

    bench_start = [None]   # set when first step fires
    bench_end = [None]     # set when CPNET OK detected

    def maybe_fire_step():
        nonlocal step_idx, cooldown_until
        if step_idx >= len(STEPS): return False
        if time.monotonic() < cooldown_until: return False
        if not _is_ccp_prompt(buf): return False
        cmd = STEPS[step_idx]
        if bench_start[0] is None:
            bench_start[0] = time.monotonic()
            print(f'[bench_start] t={bench_start[0]:.3f}s', flush=True)
        print(f'[step {step_idx}] CCP prompt {bytes(buf[-2:])!r} matched; '
              f'sending {cmd!r} (t+{time.monotonic()-bench_start[0]:.3f}s)',
              flush=True)
        for b in cmd:
            conn.sendall(bytes([b]))
            time.sleep(0.02)
        step_idx += 1
        cooldown_until = time.monotonic() + 0.5
        buf.clear()
        return True

    while time.monotonic() < deadline:
        # No nudge mechanism: with maybe_fire_step() now also called on
        # recv-timeout, the harness reliably sees a quiet A> within
        # ~0.5 s of CCP printing it.  Nudging on idle was injecting
        # phantom CRs DURING m80/l80 work (when CCP is busy and silent
        # by design), causing extra A> echoes after the program ends —
        # which is exactly the "I had to type enter" behavior we're
        # eliminating.  If a real byte got lost mid-command, the
        # harness will time out at the deadline; that's a clean fail
        # signal for the benchmark.

        try:
            data = conn.recv(256)
        except socket.timeout:
            # No new bytes — but check the buffer anyway in case the
            # slave just printed a quiet A> and is waiting for input.
            maybe_fire_step()
            continue
        if not data:
            print('peer closed', flush=True)
            break
        last_data_at = time.monotonic()
        log.write(data)
        buf.extend(data)
        if len(buf) > 4096:
            del buf[:-4096]

        if step_idx >= len(STEPS) and FINISH_MARKER in buf and not saw_marker:
            saw_marker = True
            bench_end[0] = time.monotonic()
            elapsed = bench_end[0] - bench_start[0] if bench_start[0] else -1
            print(f'[marker] CPNET OK found (bench={elapsed:.3f}s)', flush=True)
            deadline = min(deadline, time.monotonic() + 3.0)
            continue

        # Bytes arrived: check if the buf tail now ends with the
        # expected prompt and fire the next step if so.
        maybe_fire_step()

    conn.close()
    log.close()
    print(f'done (steps sent: {step_idx}/{len(STEPS)}, '
          f'marker seen: {saw_marker})', flush=True)
    return 0 if saw_marker else 2


if __name__ == '__main__':
    sys.exit(main())
