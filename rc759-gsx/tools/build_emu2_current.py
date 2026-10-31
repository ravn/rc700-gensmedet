#!/usr/bin/env python3
"""Assemble and link dd759h1 with current emu2 through a controlling PTY."""

from datetime import datetime
from pathlib import Path
import errno
import os
import pty
import re
import select
import signal
import time


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent.parent
EMU2 = WORKSPACE / "emu2-cpm86" / "emu2"


def run_guest(work, program, arguments, log_name, complete, timeout):
    pid, terminal = pty.fork()
    if pid == 0:
        os.chdir(work)
        os.execv(str(EMU2), [str(EMU2), str(work / program), arguments])

    output = bytearray()
    deadline = time.monotonic() + timeout
    completed_at = None
    status = None
    terminated = False

    while True:
        if time.monotonic() >= deadline:
            os.kill(pid, signal.SIGTERM)
            status = os.waitpid(pid, 0)[1]
            (work / log_name).write_bytes(output)
            os.close(terminal)
            raise TimeoutError(f"{program} did not finish within {timeout}s")

        ready, _, _ = select.select([terminal], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(terminal, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                chunk = b""
            if not chunk:
                status = os.waitpid(pid, 0)[1]
                break
            output.extend(chunk)

        if complete(output):
            if completed_at is None:
                completed_at = time.monotonic()
            elif time.monotonic() - completed_at >= 1.0:
                os.kill(pid, signal.SIGTERM)
                status = os.waitpid(pid, 0)[1]
                terminated = True
                break
        else:
            completed_at = None

        ended, child_status = os.waitpid(pid, os.WNOHANG)
        if ended:
            status = child_status
            break

    (work / log_name).write_bytes(output)
    os.close(terminal)
    if not terminated and status != 0:
        raise RuntimeError(f"{program} exited with wait status {status}")
    print(f"{program}: captured {len(output)} terminal bytes")
    return bytes(output)


def main():
    if not EMU2.is_file():
        raise FileNotFoundError(f"current emu2 executable not found: {EMU2}")

    work = ROOT / "scratch" / f"emu2-current-{datetime.now():%Y%m%d-%H%M%S}"
    work.mkdir(parents=True, exist_ok=False)
    print(f"Run directory: {work}", flush=True)

    for name in ("rasm86.cmd", "link86.cmd"):
        (work / name).write_bytes((ROOT / "tools" / name).read_bytes())
    source = (ROOT / "src" / "dd759h1.a86").read_bytes()
    source = source.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n") + b"\x1a"
    (work / "dd759h1.a86").write_bytes(source)

    rasm_output = run_guest(
        work,
        "rasm86.cmd",
        "dd759h1 $pz sz",
        "rasm86.log",
        lambda output: (
            b"END OF ASSEMBLY." in output
            or b"** ERROR" in output
        ),
        300,
    )
    if (
        not re.search(rb"NUMBER OF ERRORS:\s*0\b", rasm_output)
        or b"** ERROR" in rasm_output
    ):
        raise RuntimeError(f"RASM-86 failed; inspect {work / 'rasm86.log'}")
    obj = work / "dd759h1.obj"
    if not obj.is_file() or not obj.stat().st_size:
        raise RuntimeError("RASM-86 produced no non-empty OBJ")
    print(f"RASM-86: zero errors, OBJ {obj.stat().st_size} bytes", flush=True)

    cmd = work / "dd759h1.cmd"
    link_state = {"size": None, "since": None}

    def link_complete(output):
        if any(
            marker in output
            for marker in (b"OBJECT FILE ERROR", b"LINK-86 ERROR", b"ERROR NO:")
        ):
            return True
        if not cmd.is_file() or not cmd.stat().st_size:
            return False
        size = cmd.stat().st_size
        now = time.monotonic()
        if link_state["size"] != size:
            link_state.update(size=size, since=now)
            return False
        return now - link_state["since"] >= 1.5

    link_output = run_guest(
        work,
        "link86.cmd",
        "dd759h1[DATA[ORIGIN[0],MAXIMUM[1000]],EXTRA[ADDITIONAL[200]]]",
        "link86.log",
        link_complete,
        120,
    )
    if any(
        marker in link_output
        for marker in (b"OBJECT FILE ERROR", b"LINK-86 ERROR", b"ERROR NO:")
    ):
        raise RuntimeError(f"LINK-86 failed; inspect {work / 'link86.log'}")
    if not cmd.is_file() or not cmd.stat().st_size:
        raise RuntimeError("LINK-86 produced no non-empty CMD")
    print(f"LINK-86: CMD {cmd.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
