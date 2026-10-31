---
name: RC759 GSX-86 RASM86/LINK86 verification under emu2
description: Current emu2 matches MAME byte-for-byte for the reconstructed GSX-86 driver; use a controlling PTY for RASM86.
metadata:
  type: reference
---

# RC759 GSX-86 build verification with emu2

Verified 2026-10-31 against MAME using identical 16,710-byte `.A86` input
(CRLF line endings and CP/M-86 `^Z` EOF). The current
`/Users/ravn/z80/emu2-cpm86/emu2` was commit
`f1fe35cc6d18238311e6222c27cbe46bd7e43196` (`f1fe35c`, branch `local/cpm86`).

## Result

- RASM-86 1.2 reported zero errors.
- MAME and current emu2 produced byte-identical 1,792-byte OBJ files
  (81 OMF records plus 16 trailing bytes).
- LINK-86 1.4 succeeded in both and produced byte-identical 8,576-byte CMD
  files.
- Running the linked CMD directly in emu2 returned exit code 0; the DOS trace
  confirmed CP/M-86 loaded it and applied two load-time fixups. This verifies
  loading and return, not the driver's full hardware behavior.

The older pinned emulator at commit `55806f2` is not an equivalent control:
its OBJ stopped at 1,678 bytes / 72 records, and LINK-86 failed with
`OBJECT FILE ERROR 05`, record 0073. The current
`rc759-gsx/tools/build.sh` delegates to `tools/build_emu2_current.py`, which
uses the controlling-PTY procedure below.

## Terminal requirement

emu2 needs a controlling terminal. Redirecting stdin/stdout to files or an
ordinary pipe fails keyboard initialization (`open TTY`, `Device not
configured`). Use Python `pty.fork()` and `exec` emu2 in the child; merely
connecting `pty.openpty()` to the child is insufficient because it does not
give the child a controlling TTY.

Keep the PTY master open while RASM-86 runs, drain output, and wait for
`END OF ASSEMBLY` / `NUMBER OF ERRORS: 0` before stopping the emulator. Closing
the input side early sends Ctrl-D; RASM-86 then displays `STOP RASM-86 (Y/N)?`
and can consume the next command as its answer. RASM-86 may remain at the CP/M
prompt after finishing, so the harness must stop emu2 after capturing the
completion marker.

Run LINK-86 in the same kind of controlling PTY with:

```text
link86 dd759h1[DATA[ORIGIN[0],MAXIMUM[1000]],EXTRA[ADDITIONAL[200]]]
```

Check the log for `OBJECT FILE ERROR` / `LINK-86 ERROR`, require a non-empty
CMD, and compare both OBJ and CMD byte-for-byte against the MAME artifacts.

## H1 reconstruction progress

On 2026-10-31, the current-emu2 builder assembled `src/dd759h1.a86` with zero
RASM-86 errors and linked an 8,576-byte CMD. The independent oracle is
`tools/compare_sys_cmd.py` against `bin/dd759h1.sys`. The final artifact,
`scratch/emu2-current-20261031-222116/dd759h1.cmd`, matches the original in all
regions: header (128 B), CODE (4,160 B), DATA (3,136 B), EXTRA (992 B), and
relocation trailer (160 B). `cmp -s` independently confirms all 8,576 bytes
match.

The five P_LOAD records are:

- `CS:0005 -> DATA`
- `CS:0020 -> DATA`
- `CS:1016 -> EXTRA`
- `CS:101D -> DATA`
- `DATA:058D -> EXTRA`

The last three were important even though the linked operand bytes are zero:
the `SEG` expressions in the source preserve the corresponding LINK-86 fixups.
Running the final CMD directly in current emu2 exited with status 0. This only
checks load and return; full graphics behavior has not been verified.

DATA tables at `DATA:01C1..029E`, `DATA:0400..058B`, and
`DATA:0792..0C3F` were restored from the original image, along with
`DATA:02D2..02FB`; symbol meanings are only claimed where identified in source.

RASM-86 source syntax differs from common Intel notation: use forms such as
`les di,0Ah[bp]` and `mov ax,es:word ptr 2[di]`. Forms like `[bp+0Ah]` and
`word ptr es:[di+2]` produced operand errors in this build. For short
unconditional intra-segment branches, use `JMPS`.

Encoding also depends on operand order: `xchg ah,al` and `test dl,dh`
reproduce the original ModRM bytes where the symmetric forms do not. Preserve
the disassembly's exact branch targets; nearby loop labels are not interchangeable.

## Reproducing the byte check

From the workspace root, with emu2 built at the verified revision above:

```sh
cd rc700-gensmedet/rc759-gsx
sh tools/build.sh
# Substitute the new run directory printed by the builder:
python3 tools/compare_sys_cmd.py bin/dd759h1.sys scratch/RUN/dd759h1.cmd
cmp bin/dd759h1.sys scratch/RUN/dd759h1.cmd
```

The builder keeps normalized source, OBJ, CMD, and terminal logs in each fresh
run directory. These are evidence artifacts, not source files to commit.
The original and verified final CMD have SHA-256
`dcbe221f5efc105c9f983f63d31327a7a39df0739d9c050a110d917dbe8eddfe`.
