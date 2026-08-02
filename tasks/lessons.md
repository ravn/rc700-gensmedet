# Lessons Learned

## 2026-04-12: Use `-print-after-all` to trace codegen bugs to the responsible pass

**Context**: The switch discriminant was correctly allocated to register D
after the register allocator, but missing in the final assembly. Tracing
with `llc -print-after-all` showed that `Z80 Late Optimizations` was the
pass that erased the `LD D,A` instruction.

**Lesson**: When a register value is "lost" between regalloc and final
output, dump intermediate MIR with `-print-after-all` and diff consecutive
passes. The pass name in the header tells you exactly where to look in the
source. Much faster than guessing which pass is responsible.

## 2026-04-12: MAME persists ioport overrides across runs

**Context**: A baud rate experiment set `field.user_value = 23` (76800 baud)
on rs232b via Lua. Subsequent runs (using a different Lua script that did NOT
set baud) still had `user_value = 23` even after deleting all cfg files.

**Lesson**: MAME ioport `user_value` changes from Lua persist in ways that
are hard to clear. Always force-set critical ioport values in Lua scripts
rather than relying on defaults. The siob_test Lua now explicitly sets
rs232b baud to 38400.

## 2026-04-12: BIOS calls clobber registers — save/restore in test programs

**Context**: SIO-B test program used DJNZ (register B) as loop counter, but
BIOS READER (compiled C function with sdcccall(1)) clobbers B, C, D, E.
Test reported 80-169 bytes received from a 22-byte payload.

**Lesson**: Z80 CP/M BIOS calls preserve only the return value (A) and HL
(if the shim saves it). All other registers are caller-saved. Test programs
calling BIOS entry points must PUSH/POP any registers they need across calls.

## 2026-04-12: CP/M BDOS modifies IOBYTE during console I/O

**Context**: Test program set IOBYTE RDR:=UR1 (SIO-B), then called BDOS
C_PRINT. Lua snapshot showed IOBYTE=0x97 instead of expected 0x9B — bits 3:2
changed from 10 to 01, routing READER to SIO-A instead of SIO-B.

**Lesson**: Don't rely on IOBYTE being stable across BDOS calls. If you need
IOBYTE-routed BIOS calls, either re-assert IOBYTE before each call, or bypass
BIOS and access the hardware/ring buffer directly.

## 2026-04-12: SIO ×1 clock mode doesn't work for async receive

**Context**: Attempted 76800 baud on SIO-B using ×1 clock mode (CTC count=8)
instead of ×16 (CTC count=1). Test timed out — no data received.

**Lesson**: ×1 mode has no oversampling. Even in MAME's digital simulation,
the receiver clock edges don't align with transmitter bit centers. The SIO
samples at transitions, getting garbage. ×16 is the minimum for reliable
async receive. This means 38400 is the hardware ceiling for the 614.4 kHz
baud rate generator.

## 2026-02-28: Verify datasheet quotes against primary source

**Context**: MAME PR #15031 (Read Track ST1_ND fix) cited "the sector number is
not compared" as a µPD765A datasheet quote. The MAME maintainer (cracyc) asked
which datasheet says this and pointed to the actual NEC datasheet which says the
opposite — the FDC *does* compare IDs during Read Track.

**What happened**: The quote came from a secondary FDC programming reference
(isdaman.com), not from the NEC µPD765A datasheet. The NEC datasheet's command
description says the FDC compares IDs and sets ND "if there is no comparison."
However, the ST1 ND *bit definition* (a different page of the same datasheet)
says ND for Read Track means "if the starting sector cannot be found" — a
narrower condition.

**Lesson**: When citing hardware datasheets in upstream PRs:
1. Always verify exact wording against the primary source document
2. Don't conflate secondary reference material with official datasheets
3. Note when the datasheet is internally inconsistent (command description vs
   status register definition)
4. The correction was posted promptly and transparently, which is the right
   approach — acknowledge the error, present the correct evidence

**Files**: `rcbios/MAME_UPD765_READ_TRACK_ANALYSIS.md` has the full analysis.

## 2026-02-28: Always clearly identify AI authorship in PR comments

**Context**: When posting review replies on MAME PRs #15031 and #15032, the
comments must clearly state they were written by Claude Code on behalf of the
user, not claim to be the user. Use a closing line like
"(Analysis by Claude Code on behalf of Thorbjørn Ravn Andersen)".

**Lesson**: Never claim to be the user. Always state clearly what was written
and by whom. This is both honest and required by the user.

## 2026-03-07: zmac ORG inside .PHASE block causes Phase/Dephase error

**Context**: Adding an `ORG 0FFD0H` DS work-area block at the end of `src/BIOS.MAC`
triggered "Phase/Dephase error" on the ORG line.

**Root cause**: `INIPARMS.MAC` opens `.PHASE START` with no matching `.DEPHASE`.
The entire BIOS assembly after that include runs inside a phase block. zmac
rejects `ORG` inside a phase block.

**Fix**: Insert `.DEPHASE` immediately before the `ORG`. Since the DS block is at
the very end (after all code), re-entering `.PHASE` is not needed.

**Lesson**: Any time you add an `ORG` after the INIPARMS include in `src/BIOS.MAC`,
you must precede it with `.DEPHASE`. The existing alignment `DS (BIOS-$)` works
because DS does not trigger the phase check — only ORG does.

## 2026-03-07: Check for code labels before adding DS-layout labels with same name

**Context**: Adding a DS layout block in `src-rc702e/BIOS.MAC` with `MOTORTIMER:`
as a position label caused a "Mult. def. error" because `MOTORTIMER:` is also a
code function label in `FLOPPY.MAC` (REL201 FLOPPY ISR routine at ~0xE608).

**Lesson**: Before stacking a new label in a DS/work-area layout block, grep all
module files for that name to confirm it is not already a code label. When a symbol
has different roles across variants (code label in REL201, RAM variable in REL220),
use a conditional EQU alias in the variant-specific section rather than an
unconditional DS label.

## 2026-03-08: Always read AGENT.md and MEMORY.md at session start

**Context**: Started a session without reading the mandatory files. Used relative
paths for zmac which failed, then had to retry with absolute paths — a mistake
already documented in MEMORY.md line 38.

**Lesson**: The first action in every session must be reading `AGENT.md` and the
memory files. The auto-loaded MEMORY.md snippet in system context is truncated
(200 lines) and easy to skim past. Explicitly reading the files ensures full
coverage and primes the correct workflows.

## 2026-04-03: MAME Lua os.exit() does not flush MFI disk images

**Context**: SYSGEN wrote to disk in MAME, but the MFI file was unchanged
because the Lua script called `os.exit(0)` which kills MAME immediately.

**Fix**: Use `manager.machine:exit()` for clean shutdown. MAME flushes the
MFI file to disk during normal exit.

**Lesson**: Never use `os.exit()` in MAME Lua scripts when disk writes must
persist. Use `manager.machine:exit()` instead.

## 2026-04-03: CP/M LOAD.COM expects type 00 EOF, not Intel HEX type 01

**Context**: Generated Intel HEX with standard `:00000001FF` EOF record.
LOAD.COM reported "INVALID HEX DIGIT" because it doesn't recognize type 01.

**Fix**: Use `:0000000000` (zero-length type 00 data record) as EOF.
CP/M's ASM.COM also produces this format.

## 2026-04-03: MAME null_modem RS232 defaults override Lua settings

**Context**: Tried to change null_modem baud rate from Lua via
`field.user_value`. The setting appeared to change but the null_modem
didn't reconfigure — `DEVICE_INPUT_DEFAULTS` from the driver takes
precedence and is applied at device creation, before Lua runs.

**Fix**: Change the defaults in `rc702.cpp` and rebuild MAME.

## 2026-04-03: Original RC702 BIOS (rel 2.3) serial is 1200 7E1 with 1-char buffer

**Context**: Serial transfer via PIP dropped characters even at 1200 baud.
The original BIOS only buffers a single character in the SIO (no ring buffer,
no effective RTS flow control). The clang BIOS has a 256-byte ring buffer.

**Lesson**: Serial file transfer to the RC702 requires either the clang BIOS
(ring buffer + RTS), or an external pacing mechanism. The distribution disk
serial settings are 1200 baud, 7 data bits, even parity, 1 stop bit.

## 2026-04-03: SYSGEN CPM56.COM workflow from RC702 Users Guide

**Context**: Spent significant time trying to work around the fact that
LOAD.COM creates a .COM spanning 0x0100-0x6BFF which overlaps the SYSGEN
buffer. The official RC702 documentation (CPM_FOR_RC702_USERS_GUIDE.pdf
appendix C) describes the correct workflow: SYSGEN reads/writes a file
(CPM56.COM) directly, using a filename argument.

**Lesson**: Always check vendor documentation before inventing workarounds.
The SYSGEN file-based workflow is simple: `SYSGEN CPM56.COM` reads the
file and writes to system tracks in one step.

## 2026-04-11: `install_write_tap` does not see DMA writes

**Context**: Tried to find the CPU instruction that installs a `HALT`
opcode at RAM `0x0341` in the RC702 test disk using MAME Lua:

```lua
mem:install_write_tap(0x0341, 0x0341, "watch", function(off, data, mask)
    table.insert(hits, {pc=cpu.state["PC"].value, ...})
    return data
end)
```

The tap was installed correctly but **never fired**, even though the
bytes `76 18 FD` definitively appeared at `0x0341` during the run.

**Root cause**: the bytes arrive as **DMA payload**, not CPU stores.
MAME's Lua memory-tap API hooks the CPU bus side only; DMA
controllers write directly into the physical memory backing store
without going through that hook. Confirmed by static fingerprint
search: the 88-byte runtime dispatcher at RAM `0x0330-0x0388` is a
byte-exact copy of disk bytes `0x1D30-0x1D87`, so the phase-2 loader
reads T1S0 sector 3 with DMA destination `0x0200` and the overlay
lands the HALT byte at `0x0341` without any CPU store being involved.

**Lesson**: For "who wrote this memory location" in MAME, decide
first whether the source is a CPU store or a DMA payload:
- **CPU store**: `install_write_tap` works, catches the PC directly.
- **DMA payload**: put a watchpoint on the **DMA controller address
  register** (e.g. `wpset 0xF2` for Am9517 CH1 on RC702), not on the
  destination memory address. The DMA setup instruction is what you
  want to find, not the DMA cycles themselves.

Also a corollary: if `install_write_tap` reports zero hits on a
location you KNOW is being written, don't assume the tap is broken —
assume the writer is DMA and pivot to fingerprint-search the disk
image for the expected bytes.

**Files**: `rc702-test-v1.2/` full analysis.

## 2026-04-11: MAME Lua autoboot gotchas

Collected from debugging the RC702 test disk:

1. **`-debug` starts paused**. The MAME debugger interpreter freezes
   emulation at machine start when `-debug` is passed, waiting for
   a `g` from the user. An autoboot Lua script must issue
   `manager.machine.debugger:command("go")` as its first action if
   it wants the emulation to start without human intervention.

2. **`snap` filename is relative to `-snapshot_directory`**, not
   absolute. The debugger command `snap /tmp/foo.png` does NOT write
   to `/tmp/foo.png` — it treats the whole string as a relative
   filename inside the configured snapshot directory. The right
   recipe is `-snapshot_directory /tmp -snapname foo ; snap foo.png`.
   Discovered after my first snap attempts wrote nothing to `/tmp`.

3. **`-snap_directory` is NOT a valid option**. The correct name is
   `-snapshot_directory`. MAME logs "Error: unknown option" and
   quits on startup if you pick the wrong one.

4. **`manager.machine:schedule_exit()` does not exist** in modern
   MAME Lua. Correct methods: `manager.machine:exit()` or the
   debugger command `quit` via
   `manager.machine.debugger:command("quit")`.

5. **Deferred tools require `ToolSearch`** from inside Claude Code.
   Deferred doesn't mean disabled — it means the schema isn't loaded
   upfront to save context, and you pull it with
   `ToolSearch select:ToolName`. `WebFetch` was deferred in this
   session and had to be loaded this way.

**Lesson**: keep a file of known-working MAME Lua autoboot patterns
next to the MAME runs that need them. `rc702-test-v1.2/mame_dump_on_halt.lua`
is the canonical reference for "wait for a condition in memory,
snapshot, dump RAM, exit".

## 2026-04-11: Test program's port-0x50 is a diagnostic output channel

**Context**: MAME reported `io: unhandled I/O, output 00 to port 50`
during every run of the RC702 test disk. Initial assumption was that
the test program was writing to some unmapped port by mistake. Manual
§16 clarified.

**Fact**: port `0x50` is the testsystem's **diagnostic error-code
output channel**, designed for headless MIC-board test rigs that have
no CRT. The testrouter writes a 1-byte status code to it after each
sub-test completes: `00` OK, `01` PROM chksum error, `02` RAM error,
`03-04` DMA errors, `17` refresh test data error, `18-1A` FDC issues,
`1B-2D` FDD/FDC, `2E-3B` WDC. A headless rig wires a 7-segment
display or LED bargraph to this port via the MIC bus.

**Lesson**: when investigating "unhandled I/O" warnings on historical
hardware, check the hardware's service manual for diagnostic /
service-engineer ports before assuming it's a bug. A port that looks
spurious to MAME might be a documented but minor-use channel that
just isn't mapped in the driver.

**Actionable follow-up**: MAME `rc702mini` driver could usefully
gain a `-diag_port50 FILE` option that writes each byte to a log
file, enabling headless CI of the testsystem. ~20 lines of C++.

## 2026-04-11: Historical test programs require letter+Return

**Context**: The RC702 test disk's on-screen prompt says
`"type (H,R,L,G,S,P,<esc> or (0-F)) : "` but does NOT mention that
a second keystroke (`Return`) is required to commit a command. The
ISR at `0x0347` has an inner read loop that stays put until it sees
`0x0D`.

**Lesson**: when a historical interactive program seems "not to
react" to key presses, check whether it's waiting for a line
terminator. CRT-era test programs frequently batch keystrokes and
act only on `CR` or `LF`, modelled after the teletype they were
originally driven from. Read manual §3.2 (or equivalent) before
assuming the input path is broken.

## 2026-04-11: `ocrmypdf` with Danish tessdata via custom image

**Context**: `jbarlow83/ocrmypdf:latest` ships only English tessdata.
Running `ocrmypdf --language eng+dan ...` fails with "OCR engine
does not have language data for the following requested languages:
dan". The Debian package `tesseract-ocr-dan` adds it cheaply.

**Solution**: two-line Dockerfile on top of `jbarlow83/ocrmypdf`:

```dockerfile
FROM jbarlow83/ocrmypdf:latest
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends tesseract-ocr-dan \
 && rm -rf /var/lib/apt/lists/*
```

Build: `docker build -f Dockerfile.ocrmypdf-dan -t ocrmypdf-dan .`.
Adds ~4 MB to the base image, builds in ~4 seconds.

**Also**: `--force-ocr --deskew` transcodes images losslessly and
can bloat a scanned PDF 6×. For the 5.5 MB RCSL manual the sequence
`ocrmypdf --optimize 3 --jbig2-lossy` followed by
`gs -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook` brought it down to
2.4 MB — smaller than the original — while keeping a full
searchable text layer.

**Files**: `rc702-test-v1.2/Dockerfile.ocrmypdf-dan`.

## 2026-04-12: MAME cfg stale overrides corrupt serial data

**Context**: SIO-A data transfer produced garbled hex. TYPE showed control
characters instead of hex digits. Root cause: `rcbios-in-c/cfg/rc702.cfg`
had `RS232_STOPBITS value="0"` (zero stop bits!) left over from a previous
MAME session. The null_modem transmitted with 0 stop bits while the SIO
expected 1 — framing mismatch garbled every byte.

**Lesson**: Before debugging serial data corruption, check and delete stale
MAME cfg files in the working directory's `cfg/` folder. MAME auto-generates
these and any manual ioport changes persist. The `cfg/` directory should be
in `.gitignore` and deleted before automated tests.

## 2026-04-12: MAME null_modem RTS flow control must be explicitly enabled

**Context**: HEX transfer via SIO-A was truncated (430/468 records). The
BIOS correctly deasserts RTS when the ring buffer is nearly full, but the
MAME null_modem has `FLOW_CONTROL=0x00` (off) by default — it ignores RTS
and keeps sending, causing buffer overflow.

**Fix**: Set `FLOW_CONTROL` to `0x01` (RTS) in the MAME driver's
`rs232a_defaults`. The null_modem then pauses when `m_rts` is deasserted.

**Lesson**: MAME null_modem flow control is off by default. For any
interrupt-driven receive with ring buffer + RTS, enable RTS flow control in
the driver's DEVICE_INPUT_DEFAULTS.

## 2026-04-12: MAME IMD images are read-only — use MFI for writable disks

**Context**: SYSGEN wrote the new BIOS to disk, but after hard_reset the
old BIOS banner appeared. MAME loads IMD files read-only — writes go to an
in-memory copy that's discarded on reset.

**Fix**: Convert IMD to MFI using `floptool flopconvert auto mfi`. MFI is
MAME's native writable format. SYSGEN writes persist across hard_reset.

**Lesson**: Any MAME test that writes to the floppy (SYSGEN, PIP, SAVE)
must use MFI, not IMD. Pattern: `cp image.imd /tmp/test.imd && floptool
flopconvert auto mfi /tmp/test.imd /tmp/test.mfi && rm /tmp/test.imd`.

## 2026-04-12: Use MLOAD instead of LOAD for multi-file hex overlay

**Context**: CP/M's standard LOAD.COM can't merge a base .COM file with a
hex overlay. MLOAD can: `MLOAD CPM56.COM=BDOSCCP.COM,CPM56.HEX` loads
BDOSCCP.COM as the base image and overlays the hex records on top.

**Lesson**: For BIOS deploy, transfer only the BIOS hex (390 records, 17KB)
instead of the full CCP+BDOS+BIOS (779 records, 60KB). MLOAD merges it with
the CCP+BDOS base already on disk. Half the transfer time.

## 2026-04-12: Lua pcall protects against transient MAME state during hard_reset

**Context**: After `manager.machine:hard_reset()`, the Lua frame_done callback
still fires but `manager.machine.devices[":maincpu"].spaces["program"]` is
temporarily nil. This caused "attempt to index a nil value" errors and an
infinite reset loop.

**Fix**: Wrap `mem_read` in `pcall`: `local ok, val = pcall(function() ... end)`.
Return 0 on failure. The next frame after reset completes will succeed normally.

## 2026-07-16 — Never kill ninja mid-run

Interrupting `ninja` (via SIGTERM, SIGKILL, or `stop_bash`) corrupts the build-system
housekeeping state. The next invocation triggers a full cmake re-scan which touches
timestamps on generated files, cascading into a rebuild of unrelated libraries
(LLVMScalarOpts, LLVMipo, …). Even with sccache this costs 10+ minutes. Always let
ninja finish; if a build is taking too long, investigate while it runs rather than
killing it.

## 2026-07-16 — IsSM83 scope in getInstSizeInBytes

`getInstSizeInBytes` in Z80InstrInfo.cpp has an early scoped block `{ ... }` that
queries `STI.hasSM83()` and sets `bool IsSM83`. Cases that need SM83-aware sizes
must be added inside that switch, not in the outer switch that follows — `IsSM83`
is out of scope there and the compiler will catch it, but only at build time.

## 2026-08-02 — Control variables before debugging the emulator

Chasing a SEM702 "glyph compression" symptom, I bisected into MAME's i8275
rendering internals instead of first building the minimal, decoupled test.
The failing program (flip_test.c) mixed three uncontrolled variables at once:
font baked into the binary (font296.h), an upright path, and a "content-box"
flip -- so I could not isolate which part misbehaved. Compounding it, the
MARKER-gated snapshots were unreliable because clang optimises away empty
hold()/tick() busy-loops, so some "compressed" screenshots were likely caught
mid-flip (unconfirmed).

What actually resolved it was the user's prescription: DECOUPLE DATA FROM PATH.
A new chk_test.c ran one clean variable per phase -- (A) a constant 1px
checkerboard (no font data at all -> proves the sem702_loadglyph write path and
the 11-line 8275 cell), then (B) the real ROA296 read FROM A FILE at runtime and
loaded per glyph. Both rendered perfectly; the compression did not reproduce.

Lesson: when a symptom looks weird, STOP and build the smallest test that varies
ONE thing, rather than debugging deeper into the most complex layer (the
emulator). Reset the experiment; don't follow the symptom. And never trust a
snapshot gated on a marker whose preceding delay is an empty loop -- use a
volatile sink or a fixed late frame. Root cause of the original compression
remains UNVERIFIED (user said leave it); do not claim a mechanism I did not
confirm.
