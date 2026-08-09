# CP/M on-disk file checksum verification (ravn/z88dk#36)

Proof that a real C program placed on an RC702/RC703 CP/M diskette by
`z88dk-appmake +cpmdisk -f <format>` is read back by CP/M **byte-for-byte** as
laid out — including a file large enough to span multiple 16 KB CP/M extents
(the case the `byte_size_extents=0` word-pointer fix addresses).

The same checksum program (**PROG**) is reused to validate every non-jbox
RC700/RC703 format; only the host geometry (`cpmref.py`) and the appmake `-f`
name change. This is the payload to reuse when validating the other formats.

## What was verified

`PROG` computes two structurally unrelated checksums — **CRC-32** (poly
0xEDB88320) and **FNV-1a-32** — over two things, so a coincidental match is
astronomically unlikely:

1. an in-memory deterministic payload `big[i] = (i*31+7) & 0xFF` (proves the
   loaded program image is intact in RAM), and
2. its own file `PROG.COM`, read via CP/M BDOS `fopen`/`fread` to EOF (proves
   CP/M reads the on-disk file exactly as appmake laid it out).

**MAME-verified, source-independent (2026-08-09, rc702 boot on A:):** the
in-memory array checksum. This value does not depend on the compiled `.COM`
bytes, so it is the stable regression oracle:

| Payload                     | BYTES  | CRC-32     | FNV-1a-32  |
|-----------------------------|--------|------------|------------|
| in-memory `big[]` (40000 B) | 40000  | `3D6FF5B0` | `DC824845` |

The prior segment additionally booted the **rc700-8dd** disk in MAME and
confirmed the on-disk `PROG.COM` read matched the host reference bit-for-bit
(that build's file value was `9ABF27DD`/`A22B5087`; file checksums depend on
the exact `.COM` bytes and change with the program source).

**Host-verified cross-format identity (all four non-jbox formats):** the SAME
`PROG.COM`, laid out by appmake on four different geometries — word vs byte
block pointers, single vs double sided, different skews — is recovered
**byte-identically** by `cpmref.py`. With the current `gen_prog.py` source:

| Variant                     | BYTES  | CRC-32     | FNV-1a-32  |
|-----------------------------|--------|------------|------------|
| tiny (1 extent)             | 7808   | `12D74CE1` | (see run)  |
| 40000-array (48000 B, multi-extent) | 48000 | `6EB11AC7` | `DBBF3189` |

Identical output across `rc700-8dd`, `rc700-5dd`, `rc700-8sd`, `rc703-qd`
exercises both the word-pointer (8dd/5dd) and byte-pointer (8sd/703-qd)
directory layouts, and the two-logical-extents-per-entry folding that byte
pointers with 2 KB blocks produce (a 32 KB directory entry).

The 8dd >32 KB file lays out as EX=0/1/2 (Rc=128/128/116) with **16-bit (word)
block pointers** — matching the reference SW1711 system disk and confirming the
`byte_size_extents=0` fix (z88dk commits `b0e6e7183c` / `f8ee569914`).

The on-disk file checksum intentionally differs between ntvcm (host-file
padding) and MAME/IMD (0xE5 record padding) — expected, since CP/M reads whole
128-byte records and pads the tail with the disk filler 0xE5. The in-memory
array checksum is identical everywhere.

## How to reproduce

```sh
./build_and_verify.sh 40000          # host-only: build disk + print references
./build_and_verify.sh 40000 --mame   # also boot in MAME and run PROG on A: (slow)
./build_and_verify.sh 0              # tiny single-extent variant

FORMAT=rc700-5dd ./build_and_verify.sh 40000   # validate another format host-side
FORMAT=rc700-8sd ./build_and_verify.sh 40000
FORMAT=rc703-qd  ./build_and_verify.sh 40000
```

The disk format is selected with the `FORMAT` env var (default `rc700-8dd`).
Only `rc700-8dd` gets the licensed boot region spliced (bootable, so `--mame`
works); the other formats are built as non-bootable **data disks** (tracks 0/1
zero-filled) and validated host-side by `cpmref.py`, since no licensed boot
reference exists for them. Tool paths default to the macbook layout and are
overridable via env (`WS`, `Z88DK`, `REF_IMD`, `MAME_BIN`, `FORMAT`, ...).

### Supported formats (geometry in `cpmref.py` FORMATS, mirrored from cpm2.c)

| appmake `-f` | media          | SPT×size | sides | pointers | skew |
|--------------|----------------|----------|-------|----------|------|
| `rc700-8dd`  | 8" DS/DD       | 15×512   | 2     | word     | 4:1  |
| `rc700-5dd`  | 5.25" DS/DD    | 9×512    | 2     | word     | 2:1  |
| `rc700-8sd`  | 8" SS/SD (3740)| 26×128   | 1     | byte     | 6:1  |
| `rc703-qd`   | 5.25" DS/QD    | 10×512   | 2     | byte     | 2:1  |

`rc700-jbox` is intentionally excluded (0-based emulator sector IDs; not real
HW). Skew is applied only on the data area (track 2 and forward); tracks 0/1
(the boot region) carry no skew.

## The build pipeline

`zcc` drives `appmake` directly via its `-create-app` stage, so compile +
disk-image build is a **single command** (verified for rc700-8dd: the IMD
payload is byte-identical to a standalone `z88dk-appmake` call; only the IMD
header timestamp differs):

```sh
zcc +cpm -subtype=rc700 -O2 prog.c -o prog -create-app \
    -Cz"+cpmdisk -f rc700-8dd --container=imd -s bootregion.bin"
# -> prog.imd (bootable) + PROG.COM (in the directory)
```

`-Cz...` forwards arguments to the appmake stage. All appmake args can go in a
single quoted `-Cz"..."` (space-separated) instead of one `-Cz` per token; note
appmake's `-f` wants its value as the next token (`-f rc700-8dd`), the `-f=...`
form does not parse. The `+cpm` target defines ~150 subtypes that already do
`+cpmdisk -f <format> --container imd`; the `rc700` subtype links `-lrc700` but
has no disk line, so the format is given explicitly. Boot region is spliced with
appmake's sector-level `-s` (#61).

Without `-s` the disk is a non-bootable **data diskette** (tracks 0/1
zero-filled) — the intended default so a payload disk is not mistaken for a
bootable one.

## Files

| File                 | Role |
|----------------------|------|
| `prog.c`             | the saved PROG source (dual-checksum tool, no array). Reused to validate every format; inflate for multi-extent via `gen_prog.py 40000` |
| `gen_prog.py`        | emits `prog.c` (the dual-checksum tool); arg = `big[]` size (0 = tiny, 40000 = ~48 KB multi-extent) |
| `cpmref.py`          | host reference: extract a file from any supported RC700/RC703 IMD (`--format`, skew-inverted linear rebuild, word or byte block pointers) and print size + CRC-32 + FNV-1a-32 |
| `mame_run.lua`       | MAME autoboot: type `PROG`<CR> on A:, dump the 0xF800 text screen, exit |
| `build_and_verify.sh`| one-shot pipeline: generate -> zcc(+appmake) -> host refs -> optional MAME |

## Caveats / findings

- **Auto-run is via MAME keystrokes, not an on-disk auto-start.** The SW1711
  `AUTOEXEC.COM` byte-patch model (patch Track 1/Sector 0 CCP command buffer at
  `+7`) does **not** apply to this system's running CCP: it loads at `D5F8`
  (not the documented 56K `CPMB=CC00`) and byte `+7` is executable init code
  (`LD A,01`), not a command-length slot. Patching `+7` corrupts CCP code
  rather than injecting a command, so `mame_run.lua` drives PROG with simulated
  keystrokes instead. (A correct on-disk auto-start would need reverse
  engineering of this specific CCP's command-buffer location.)
- **MAME floppy timing:** reading the ~48 KB multi-extent file record-by-record
  through the emulated uPD765 with accurate rotational timing takes ~180 s of
  *simulated* time; run with `-seconds_to_run 220` (or more). The program is not
  hung — ntvcm computes the same result instantly.
- The licensed `SW1711-I8.imd` is **not** redistributable; only its boot region
  is spliced locally at build time. This is the payload mechanism from #36/#61.
