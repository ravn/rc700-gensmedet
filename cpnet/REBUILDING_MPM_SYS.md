# Rebuilding `mpm.sys` — incorporating SERVER.RSP / NETWRKIF.RSP changes

## TL;DR

Editing `server.rsp` (or any other `.RSP`/`.SPR`) on the master disks
and rebooting **does not** propagate the change. MP/M II's boot image
`mpm.sys` is a pre-built snapshot that bakes the dispatch modules in at
GENSYS time. Until `mpm.sys` itself is regenerated, MP/M keeps using
the old SERVER.

**Use the automation:**

```bash
cd cpnet/mpm-server
./rebuild-mpm-sys.sh --install
```

That script (see `cpnet/mpm-server/rebuild-mpm-sys.sh`) does the whole
loop: rebuild `server.rsp` from `cpnet/mpm-server/server.asm` (the
project-side patched copy) via vcpm, stage all the
`.RSP`/`.SPR`/`.BRS`/`.DAT` files GENSYS needs, drive `GENSYS.COM`
under vcpm with the answer-table below, and rewrite a fresh
`mpm-net2-1.dsk` with the new `MPM.SYS`. Total wall-clock ≈ 10 s.

**Project layout note.** The patched `server.asm` (and this script)
live at `rc700-gensmedet/cpnet/mpm-server/`, not in the
upstream-tracked `cpnet-z80` submodule. The cpnet-z80 distribution
stays byte-identical to `durgadas311/cpnet-z80`. The gettod handler
(FN 105) is RC700-emulator-specific — it reads cpmsim's host RTC at
I/O ports 25/26 — so it doesn't belong in the upstream distribution.

With `--install`, the rebuilt disk lands in
`z80pack/cpmsim/disks/local/mpm-net2-1.dsk`. The `mpm-net2` launcher
prefers `disks/local/` over `disks/library/` so the next launch boots
the patched image automatically. The pristine `disks/library/` copies
stay untouched (and tracked in the z80pack submodule); the `local/`
directory is gitignored (`*/disks/local/` in `z80pack/.gitignore`).

Without `--install`, the script writes to `/tmp/mpm-net2-1.dsk`; pass
`-o <path>` to write somewhere else.

The rest of this doc explains *what the script does and why* — useful
when something changes and the script needs updating.

## The trap, in detail

The first instinct — rebuild `cpnet/mpm-server/server.rsp`, `cpmcp` it
onto `disks/library/mpm-net2-2.dsk`, and reboot — looks reasonable
because the file actually does land on disk:

```bash
DISKDEFS=…/diskdefs cpmcp -f ibm-3740 \
    .../mpm-net2-2.dsk tmp_build/d/server.rsp 0:server.rsp
```

`cpmls` confirms the file is on the disk, with the new bytes. But MP/M
boots from drive A: (`mpm-net2-1.dsk`), and the boot path is:

```
BIOS  -> MPMLDR.COM (drive A:)  -> reads MPM.SYS (drive A:)  -> running MP/M
```

`MPM.SYS` is a single ~42 KB file containing the relocated load image
of:
- LDRBIOS + system data segments
- BNKBDOS.SPR, BNKXDOS.SPR, BNKXIOS.SPR
- The RSP set: ABORT.RSP, SCHED.RSP, SPOOL.RSP, MPMSTAT.RSP,
  **SERVR0PR.RSP** (the file the source tree calls `server.rsp`), and
  **NtwrkIP0.RSP** (`netwrkif.rsp`).

GENSYS reads those individual files at build time, relocates each to its
chosen load address, and writes the concatenated image as `MPM.SYS`.
Nothing at runtime ever reopens them. So the only thing that matters
for the running system is what was *baked into* `MPM.SYS`; the `.RSP`
files on disk D: are inert leftovers as soon as `MPM.SYS` exists.

### How this was diagnosed (session 2026-06-10)

`server.asm` was patched to dispatch a custom FN 105 (Get Time/Date)
handler. After rebuild + `cpmcp` to drive D:, every wire test still
returned the standard `FF 0C` "function not implemented" payload.

The decisive evidence was a side-channel trace via cpmsim's printer
port (I/O port 3 → `printer.txt` in cpmsim's cwd). Eight `out 3`
instructions were inserted into `server.asm` at each gate in the
dispatch chain (`valid`, `val0..val2`, `net0`, the valid-failed branch,
`neterr`, `gettod`). The freshly built `server.rsp` had eleven `D3 03`
bytes total — but after a boot, `printer.txt` was never created.
Scanning the on-disk `MPM.SYS` for `D3 03` returned a single hit, none
of them ours.

Conclusion: `MPM.SYS` was carrying an older `SERVR0PR`. The same scan
located the `'COPYRIGHT (C) 1982, DIGITAL RESEARCH '` string from
`server.asm` inside `MPM.SYS` at file offset 16460 — proving a copy of
the original SERVER.RSP was sitting baked inside, with its
`fnctab[55]` still at the default `0`. See
`tasks/memory/feedback_fingerprint_build_after_two_no_change_edits.md`
for the meta-lesson.

## The build path that works: GENSYS under vcpm

Running `GENSYS.COM` under MP/M itself doesn't work cleanly: by the
time you reach the `0A>` prompt, all the system RSPs are already
running and holding FCBs. GENSYS hits `Bdos Err On D: Open File Limit
Exceeded` halfway through opening MPMSTAT.BRS, aborts, and leaves an
incomplete MPM.SYS (~32 KB instead of 42 KB).

> **Aside on the FCB-limit chicken-and-egg.** The relevant limits *are*
> exposed in the GENSYS dialog — prompt 12 `Maximum open files/process`
> and prompt 13 `Total open files/system` (defaults `#16` / `#32`).
> But raising them only affects the *next* `MPM.SYS` being written, not
> the running MP/M doing the writing. So you can't escape the limit
> from inside MP/M on a first-cut bootstrap — you'd need a `MPM.SYS`
> with higher limits *already in flight*. vcpm has no such limit at
> all, which is why it's the clean answer.

**Use vcpm (VirtualCpm.jar) instead.** It runs CP/M, not MP/M, so
there are no resident processes and no per-process FCB limit — GENSYS
walks the dialog without errors and writes a complete, bootable
`MPM.SYS`. The output is byte-equivalent to what an MP/M-hosted run
would produce if the FCB limit were raised. The script
`rebuild-mpm-sys.sh` drives it automatically; the manual procedure
follows for the case where you need to change something.

### Manual procedure (one-off)

1. **Stage** every input GENSYS reads into a vcpm drive:

   ```bash
   mkdir -p stage/a stage/d
   # Files GENSYS picks up from drive A: (default search dir)
   for f in gensys.com abort.rsp sched.rsp spool.rsp mpmstat.rsp \
            netwrkif.rsp server.rsp \
            bnkbdos.spr bnkxdos.spr bnkxios.spr resbdos.spr resxios.spr \
            xdos.spr tmp.spr \
            mpmstat.brs sched.brs spool.brs \
            system.dat; do
       DISKDEFS=$RC700/rcbios/diskdefs cpmcp -f ibm-3740 \
           $LIBRARY/mpm-net2-2.dsk "0:$f" "stage/a/$(echo $f | tr a-z A-Z)"
   done
   # Replace SERVER.RSP with the freshly built one
   cp tmp_build/d/server.rsp stage/a/SERVER.RSP
   ```

2. **Drive GENSYS** with the answer table:

   ```bash
   export CPMDrive_A=$PWD/stage/a CPMDrive_D=$PWD/stage/d CPMDefault=a:
   printf '%s\n' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' \
                 '' Y Y Y Y Y Y '' '' '' '' '' '' '' '' '' \
       | java -jar $CPNET/tools/VirtualCpm.jar gensys
   ```

   `stage/a/MPM.SYS` is now ~42 KB and complete.

3. **Patch a fresh boot disk:**

   ```bash
   cp $LIBRARY/mpm-net2-1.dsk new-mpm-net2-1.dsk
   DISKDEFS=$RC700/rcbios/diskdefs cpmrm -f ibm-3740 \
       new-mpm-net2-1.dsk 0:mpm.sys
   DISKDEFS=$RC700/rcbios/diskdefs cpmcp -f ibm-3740 \
       new-mpm-net2-1.dsk stage/a/MPM.SYS 0:mpm.sys
   ```

4. **Use it** (drop into the launcher's library path, or feed it to
   `cpmsim` directly as `disks/drivea.dsk`).

## The full GENSYS answer table

Captured live from the working run on 2026-06-10. Each row is one
prompt; "answer" is what the script feeds. `(parens)` show the
default GENSYS prints — empty answer means "accept default".

| # | Prompt (substring)                       | Default | Answer | Why |
|---|-------------------------------------------|---------|--------|-----|
| 0 | `Use SYSTEM.DAT for defaults`             | Y       |        | yes — re-use last run's values |
| 1 | `Top page of operating system`            | FF      |        | top of memory |
| 2 | `Number of TMPs (system consoles)`        | #3      |        | matches XIOS NMBCNS; must NOT be 2 — see `MPMNET_ANALYSIS.md` |
| 3 | `Number of Printers`                      | #1      |        | |
| 4 | `Breakpoint RST`                          | 06      |        | |
| 5 | `Add system call user stacks`             | Y       |        | |
| 6 | `Z80 CPU`                                 | Y       |        | |
| 7 | `Number of ticks/second`                  | #100    |        | |
| 8 | `System Drive`                            | A:      |        | |
| 9 | `Temporary file drive`                    | A:      |        | |
| 10 | `Maximum locked records/process`         | #16     |        | |
| 11 | `Total locked records/system`            | #32     |        | |
| 12 | `Maximum open files/process`             | #16     |        | |
| 13 | `Total open files/system`                | #32     |        | |
| 14 | `Bank switched memory`                   | Y       |        | |
| 15 | `Number of user memory segments`         | #7      |        | |
| 16 | `Common memory base page`                | B0      |        | |
| 17 | `Dayfile logging at console`             | N       |        | |
| 18 | `Accept new system data page entries`    | Y       |        | |
| 19 | `SPOOL   RSP`                            | N       | **Y**  | must include — running system has SPOOL |
| 20 | `ABORT   RSP`                            | N       | **Y**  | must include |
| 21 | `SCHED   RSP`                            | N       | **Y**  | must include |
| 22 | `SERVER  RSP`                            | N       | **Y**  | **must include — this is the dispatcher** |
| 23 | `NETWRKIFRSP`                            | N       | **Y**  | must include — wire I/O |
| 24 | `MPMSTAT RSP`                            | N       | **Y**  | must include |
| 25 | `Base,size,attrib,bank (54,AC,80,00)`    | …       |        | bank 0 = MP/M kernel |
| 26-32 | `Base,size,attrib,bank (00,B0,00,0N)` | …       |        | banks 1..7 = user segments |
| 33 | `Accept new memory segment table entries`| Y       |        | |

GENSYS prints `** GENSYS DONE **` when finished. The output lands at
`A:MPM.SYS` (or whatever the default drive is).

## Verifying a rebuild took effect

Three layers of evidence, cheapest first:

```bash
# 1. Size: should match the running baseline (~42 KB for the current
#    RSP set; 32 KB means a phase was skipped or aborted)
wc -c stage/a/MPM.SYS

# 2. Code presence: scan for a fingerprint from your new SERVER.RSP.
#    The session-2026-06-10 trace used D3 03 (OUT 3); pick anything
#    distinctive to your changes.
python3 -c "d=open('stage/a/MPM.SYS','rb').read(); \
print('OUT 3 count:', sum(1 for i in range(len(d)-1) if d[i]==0xD3 and d[i+1]==0x03))"

# 3. Boot test + wire test: launch cpmsim with the new boot disk and
#    drive the actual CP/NET call your change targets.
```

If size is right but the code fingerprint isn't there, GENSYS picked
up a stale `SERVER.RSP` from somewhere — verify `stage/a/SERVER.RSP`
is byte-equivalent to your build.

## Stale-`MPM.SYS` symptoms to recognise next time

The next time you "change `server.asm`, install `server.rsp`, see no
behaviour change," look for any of:

- A custom FNC dispatches to `neterr` (`FF 0C` reply) even though
  `fnctab[N]` source clearly sets a non-zero opcode.
- New trace I/O (`out N, …`) doesn't show up on the host side device
  the port is bound to (e.g., `printer.txt` for port 3).
- `cpmls` shows the new `.RSP` on disk D: with the right byte count,
  but `MPM.SYS` on disk A: is byte-identical to before.

All three say the same thing: GENSYS hasn't been re-run. Run the
`rebuild-mpm-sys.sh` script.

## References

- `cpnet-z80/doc/dri-cpnet.pdf` — Digital Research CP/NET manual.
  §4.3.6 step 4 names the GENSYS step but doesn't reproduce the
  dialog.
- `cpnet-z80/dist/mpm/app_note_01.txt` — DRI App Note 01 explicitly
  reminds: *"The patched SERVER.RSP must now be GENSYSed into
  MP/M-II."* That one sentence is the rule the original trap
  violated.
- `cpnet/MPMNET_ANALYSIS.md` §"GENSYS: Number of TMPs must be 5" —
  source for the TMP=5 / NmbCns=5 answer.
- `cpnet/Z80PACK_MPMNET.md` — the broader cpmsim ↔ MAME integration
  layout (drive map, launcher script).
- `tasks/memory/feedback_fingerprint_build_after_two_no_change_edits.md`
  — the meta-rule forged from this trap.
- `tasks/memory/reference_mpm_sys_baked_via_gensys.md` — one-liner
  recall of the trap.
