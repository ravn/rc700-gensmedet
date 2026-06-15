# cpnos-rom: clang vs SDCC annotated-list comparison (post-NDOS handoff path)

Generated 2026-05-08 from `clang/cpnos.lis` (llvm-objdump -d -S, source-interleaved)
and `z80dasm` of SDCC's `cpnos.bin` chunks reassembled at VMA 0xEE00.  SDCC
does not produce a source-interleaved listing through z88dk-zsdcc, so the
SDCC side is the binary disassembly with addresses; clang side carries C
source as comments alongside.

Focus: the post-netboot handoff path that's failing the SDCC pio-irq
polypascal-test (slave reaches 25 dots, then warm-boots before E> prompt).

## Code-flow ordering — IDENTICAL in both

Both `_cpnos_cold_entry` implementations call, in order:

    cfgtbl_init -> init_hardware -> BOOT_MARK 7 'P' -> enable_interrupts
    -> print_banner -> netboot_mpm -> BOOT_MARK 15 '+' or '-'
    -> resident_handoff(entry)

`_resident_handoff` in both:

    PROM-disable (OUT 0x18,0) -> BOOT_MARK 16 'P' -> cfgtbl.fnc=5
    -> snios_ntwkin -> if(entry==0) busy-loop
    -> LDIR bios_boot -> BIOS_JT_COPY_ADDR (0xDD80, 51 B)
    -> LDIR zp_init_data -> 0x0000 (8 B)
    -> BOOT_MARK 18 'J' -> enter_coldst

`_enter_coldst` is byte-identical: `ld sp,0x100; jp 0xDE83`.

## Differences worth flagging

### 1. PROM disable: clang inline `out ($18),a` vs SDCC library `__port_out`

clang resident_handoff @ 0xF435:

    f435: e5            push hl
    f436: af            xor a
    f437: d3 18         out ($18),a       ; 5 bytes total

SDCC resident_handoff @ 0xF400:

    f400: e5            push hl
    f401: af            xor a
    f402: f5            push af
    f403: 33            inc sp
    f404: 21 18 00      ld hl,0x0018
    f407: cd e1 f3      call __port_out   ; 13 bytes + library body
    f40a: d1            pop de

SDCC's `__port_out` body @ 0xF3E1:

    f3e1: 4d            ld c,l            ; port -> C
    f3e2: 21 02 00      ld hl,2
    f3e5: 39            add hl,sp         ; hl = &v
    f3e6: 7e            ld a,(hl)         ; A = v
    f3e7: ed 79         out (c),a         ; **uses BC, B uninitialised**
    f3e9: e1            pop hl            ; retaddr
    f3ea: 33            inc sp
    f3eb: e9            jp (hl)

**Oddity**: SDCC's `out (c),a` (ED 79) places B on A8-A15 of the I/O cycle.
B is whatever the caller left in it — uninitialised.  Most Z80 systems
including the RC702 only decode A0-A7, so this is benign for port 0x18
(RAMEN).  But every other port write goes through this same helper
(`init_hardware` does roughly 40 of them), so any RC702 peripheral that
DOES decode A8-A15 — or that the host bridge in MAME models with full
16-bit I/O — would silently misroute.  Not an obvious smoking gun for the
post-handoff failure (PROM-disable itself doesn't depend on B), but worth
noting as a class of latent risk.

Action item to consider: switch `__port_out` to `ld b,h; out (c),a` so
the upper byte at least mirrors `port`, matching what clang's direct
`OUT (n),A` instruction does (which puts A on A8-A15).

### 2. zp_init_data location

- clang: `_zp_init_data` @ 0xF42A (right before `_resident_handoff` at 0xF435,
  in RESIDENT_DATA-equivalent)
- SDCC: `_zp_init_data` @ 0xF7F5 (very tail of resident, just before BSS)

Both copy the same 8 bytes:

    +0..2: c3 83 dd     JP BIOS_JT_COPY_ADDR+3   (BIOS WBOOT entry)
    +3..4: 00 04        IOBYTE/USER fillers (clang shows 00 04)
    +5..7: c3 16 e8     JP 0xE816                 (BDOS entry)

Both targets match `cpnos_addrs.h` (BDOS=0xE816, BIOS_JT_COPY_ADDR=0xDD80).
Functionally equivalent; just different placement.

### 3. cfgtbl placement

- clang: `_cfgtbl` @ 0xF544 (RESIDENT_DATA, in the relocated payload)
- SDCC: `_cfgtbl` @ 0xED19 (SCRATCH_BSS, NOLOAD; zeroed at boot then init'd)

Both `+0x2a` accesses go to `_cfgtbl.fnc` set to 5 before `snios_ntwkin`.
This is a deliberate design difference (SDCC's BSS is sized larger so
cfgtbl doesn't fit in resident); the SDCC layout puts cfgtbl in the
zeroed-then-initialised BSS scratch region 0xEC00..0xEDFF.

### 4. Memory layout: cpnos.com tail vs IVT

cpnos.com is 3200 B = 0x0C80, loaded at NDOS=0xDE80, so cpnos.com bytes
occupy 0xDE80..0xEAFF.  The slave's IVT lives at __ivt_start = 0xEB00
(start of SCRATCH_BSS).

cpnos.com's last byte (0xEAFF) is exactly one byte before the IVT
(0xEB00).  Adjacent but not overlapping — IVT survives netboot.

If cpnos.com ever grows past 3200 B (e.g., a CCP-included build), the tail
WILL clobber the IVT.  Currently safe; should be guarded by a build-time
assertion.

### 5. BIOS jump-table differences (informational)

Both compilers emit a 17-entry BIOS jt at 0xEE00 followed by SNIOS jt at
0xEE33.  Internal stub addresses differ but functionally:

- entries 0/1 (BOOT/WBOOT): both jump to enter_coldst-equivalents
- entries 2/3/4 (CONST/CONIN/CONOUT): both jump to per-entry shims
- entries 5..16 (LIST..SECTRAN): both consolidate to a single stub
  - clang: all -> 0xF0C1 (`ret`)
  - SDCC: all -> 0xF3DC (`ret`)

These are CP/NET stubs — NDOS handles the real work.  No semantic
difference.

## Suspect ranking for post-NDOS handoff failure

Nothing in the disassembly comparison is a clear "this is wrong" — both
post-handoff sequences look correct, both jump to NDOSE 0xDE83 with
SP=0x100, and the BIOS jt copy + zp_init_data values match.

The remaining divergence surface, in order of likelihood:

1. **Something inside cpnos.com that depends on slave state** — NDOS reads
   CFG block (cfgtbl) and may walk into a path that diverges based on a
   value the slave wrote.  Worth dumping `_cfgtbl` contents at handoff
   time (one BOOT_MARK byte at a time, or a hex dump via SIO) to see if
   clang and SDCC produce different cfgtbl payloads.
2. **Stack alignment or value at SP=0x100 entry to NDOSE** — both
   compilers set `ld sp,0x100; jp 0xDE83`, so SP value is identical.  But
   the bytes at 0x100..0x1FF are RAM, and both compilers' BSS-clear should
   have left them at 0x00 (low TPA).  If something else writes there
   between BSS-clear and handoff under SDCC only, NDOS might pop garbage.
3. **Interrupt state at handoff** — both cold-entry paths call
   `enable_interrupts` (EI) before netboot.  Neither calls DI before
   `enter_coldst`.  If an IRQ fires during `ld sp,0x100; jp 0xDE83` it'd
   push retaddr to the new stack at 0x100 — fine on its face, but NDOS
   may not expect to start with a non-zero IRQ-pending state.
4. **B register garbage during init_hardware port writes** — see #1
   above.  Easy to test: change `__port_out` to set B=H or B=port-high
   before `out (c),a` and re-run.

## Files

- clang annotated: `clang/cpnos.lis` (5821 lines, source-interleaved)
- SDCC compiler asm (per-TU, no source annotation): `sdcc/audit/*.s`
- SDCC binary disasm: `/tmp/sdcc_resident.dis` (z80dasm @ 0xEE00,
  reassembled from `sdcc/cpnos.bin` chunks A+B)
