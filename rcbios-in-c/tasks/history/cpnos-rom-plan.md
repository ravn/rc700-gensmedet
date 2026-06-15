# CP/NOS Combined Autoloader+BIOS PROM Plan

## Goal

Single 4KB ROM image (two 2KB PROMs: PROM0 @ 0x0000, PROM1 @ 0x2000, both
disabled by one OUT (0x18)) that boots the RC700 as a CP/NOS client against
MP/M, with optional 8" DSDD diskette fallback. Written in C/clang where
practical, SNIOS kept in assembly.

## Non-goals / Parked

- Parallel-port transport (J3/J4 PIO) — parked, user will return later.
  Reserve clean abstraction (transport vtable) so it drops in without
  restructuring.
- SDLC / synchronous transport — unproven HW, parked.
- Relocatable display memory / > 56KB TPA — requires HW changes, out of scope.

## Targets

- TPA (NOS-only build):  ~55KB
- TPA (NOS+diskette):    ~52KB
- Display + work area at 0xF800–0xFFFF **unchanged** (Comal80 compat).
- Total ROM image: ≤ 4096B, split `dd` into `prom0.bin` (0x0000–0x07FF)
  and `prom1.bin` (0x2000–0x27FF) for burning.

## Memory map at runtime (NOS+diskette build)

| Region | Addr | Notes |
|---|---|---|
| Page zero | 0x0000–0x00FF | CP/M vectors (JP WBOOT, IOBYTE, CDISK, JP BDOS) |
| TPA | 0x0100–CCP-1 | ~52KB with diskette, ~55KB without |
| CCP | variable | 2KB, loaded from server |
| BDOS | CCP+0x806 | 3.5KB, loaded from server |
| BIOS resident | below 0xF600 | jump table + console + SNIOS + (optional) FDC |
| IVT | 0xF600–0xF6FF | slim, only vectors we use |
| conv_tables | 0xF680–0xF7FF | keep layout — Comal80/existing apps |
| Display | 0xF800–0xFFCF | locked |
| Work area | 0xFFD0–0xFFFF | locked |

BIOS base address becomes a build-time constant, chosen by the linker to be
the lowest multiple of 0x100 that fits the resident size + stack. Two values:
one for NOS-only, one for NOS+FDC.

## Deliverables

1. New directory `rc700-gensmedet/cpnos-rom/` (combined PROM project), or
   reuse `autoload-in-c/` with a new target. Decision in Phase 0.
2. Two build configurations via `-DENABLE_FDC=0|1`.
3. Linker script `cpnos_rom.ld` enforcing 4KB limit and split layout.
4. `make cpnos` produces `prom0.bin` + `prom1.bin` + `cpnos.elf` + `.map`.
5. `make cpnos-mame` boots MP/M (z80pack) and brings up RC702 as CP/NOS node.
6. Lit tests for any llvm-z80 codegen issues found along the way.
7. Updated `tasks/cpnos-rom-plan.md` (this file) + session summary on completion.

## Phase 0 — Scaffolding & decisions (1 session)

- [ ] Decide project layout: new `cpnos-rom/` dir vs extending `autoload-in-c/`.
      Default: new dir to keep ROA375 SDCC build intact as reference.
- [ ] Copy over build harness from `autoload-in-c/` (Makefile, docker helper).
- [ ] Stub linker script `cpnos_rom.ld` with 4KB ROM region, 2KB split assertion.
- [ ] Decide MP/M server setup: existing `cpmsim` z80pack config, or the
      `cpnet-z80/` reference MP/M image. Document in `docs/cpnos-server.md`.
- [ ] Confirm MAME RC702 driver can boot a custom PROM pair and talk to
      z80pack MP/M over the configured SIO-A null-modem bridge.

## Phase 1 — Netboot MVP, no diskette (2 sessions)

Goal: `ENABLE_FDC=0` image boots an MP/M client over SIO-A async 38400.

- [ ] Reset vector + minimum hardware init (SIO-A/B, CTC, PIO, IVT setup).
      Existing `bios_hw_init` is the reference; strip FDC/DMA bring-up.
- [ ] Console I/O (CONIN/CONOUT/CONST on SIO-B) — lift from current BIOS.
- [ ] SNIOS in assembly — lift `cpnet/snios.asm` verbatim, adapt entry points
      to new BIOS base address (build-time symbol).
- [ ] Netboot loader: new function (`FNC=0xFF` or similar) that requests
      CCP+BDOS image from server, receives into RAM at correct addresses.
      Add matching handler to `cpnet/server.py`.
- [ ] Cold boot sequence:
      1. copy resident BIOS chunk to high RAM
      2. OUT (0x18) disables both PROMs
      3. init IVT, stack, console
      4. netboot request → load CCP+BDOS
      5. jump to CCP
- [ ] BIOS jump-table stubs: console entries real, all disk entries return
      "no disk" (CP/NOS funnels disk I/O through BDOS → SNIOS, not BIOS disk ops).
      Verify this matches DRI CP/NOS semantics — **open question, confirm from
      `cpnet-z80/` reference before coding.**
- [ ] CFGTBL + single network DPH for drive A:.
- [ ] MAME boot test: reach CP/NOS prompt `A>`, run `DIR`, read a file.
- [ ] Measure actual ROM size vs budget; record in this file.

## Phase 2 — Diskette support (1–2 sessions)

Goal: `ENABLE_FDC=1` image has both NOS and local 8" DSDD support.

- [ ] Add FDC driver: init, ISR, seek, recalibrate, read, write (lift and trim
      from current BIOS). Reference: `bios.c` FDC routines + `fdf[1]` at `:151`.
- [ ] Deblocking driver (512B physical ↔ 128B logical), 512B sector buffer in BSS.
- [ ] 8" DSDD DPB + SECTRAN: lift `dpb_maxi_512` (`bios.c:141`) and
      `xlt_maxi_512` (`bios.c:79–81`).
- [ ] Second DPH for drive B: on the same format (trivial, shares DPB).
- [ ] Boot-time drive detection: attempt FDC recalibrate; if no drive, mark
      A: and B: as network-only.
- [ ] Decide A:/B: policy:
      - Option X: A: = network, B: = local floppy (simplest, distinct)
      - Option Y: A: = local if present else network; B: = the other
      - **Default: Option X**, document in `docs/cpnos-drives.md`.
- [ ] MAME test: boot NOS, then `B:DIR` reads a local floppy image.
- [ ] Record ROM size with FDC enabled; verify ≤ 4096B.

## Phase 3 — Benchmark & decide local-cache policy (1 session)

User asked to measure whether local floppy can serve CP/NOS resident files
faster than the server. This is a **decision point, not immediate code**.

- [ ] Measure: time to transfer a 4KB file
      1. over SIO-A 38400 async from MP/M (baseline)
      2. read from local 8" DSDD (FDC + deblock)
- [ ] Decide policy based on numbers. Likely outcome: diskette wins by
      ~5–10× for bulk reads. If so, phase 3.5:
- [ ] (conditional) Add a boot-time option: if B: contains a valid
      `CPNOS.SYS` (or named file list), read CCP+BDOS from B: instead of
      server. Falls back to server if read fails.
- [ ] Record numbers in `tasks/cpnos-benchmarks.md`.

## Phase 4 — Real-hardware bring-up (1 session, depends on EPROM access)

- [ ] Burn `prom0.bin` and `prom1.bin` to 2716 (or compatible) EPROMs.
- [ ] Plug into RC702, connect SIO-A null-modem to host running MP/M server.
- [ ] Verify banner, boot, `DIR`, simple BDOS calls.
- [ ] Verify Comal80 still loads (confirms 0xF800+ layout preserved).
- [ ] Verify local floppy in B: if diskette build.

## Resolved questions (investigation round 1)

1. **BIOS disk semantics (RESOLVED).** NDOS checks CFGTBL bit-7 per drive
   and routes remote drives through SNIOS directly; BIOS READ/WRITE/SELDSK
   are never called for network drives. Evidence:
   `cpnet-z80/dist/src/ndos.asm:540-558, 1188-1195`. Disk stubs in NOS-only
   build are ~30B (error return + null DPH).

2. **Netboot protocol (RESOLVED).** Standard DRI protocol in
   `cpnet-z80/src/netboot.asm`: client sends FMT=0xB0/FNC=0; server replies
   FMT=0xB1 with FNC=1 (load text), FNC=2 (set DMA), FNC=3 (128B data),
   FNC=4 (execute). Port reference asm rather than inventing. Extend
   `cpnet/server.py` with matching handler.

3. **SLAVEID (RESOLVED).** Hard-coded at build time, stored at CFGTBL+1,
   copied to every outgoing SID field. Reference:
   `cpnet-z80/dist/src/cpnios.asm:55-63`. Use `-DRC702_SLAVEID=0x70`
   build flag.

## Remaining open questions

4. **IOBYTE defaults** — map to SIO-A for NOS traffic, SIO-B for console.
   Confirm matches current `rcbios-in-c` convention.
5. **Budget update from Q1/Q2 findings**: Phase 1 netboot asm is tighter
   (~250B vs 350B) and disk stubs are smaller (~30B vs 150B). Total saving
   ~200B — puts NOS-only TPA potentially at 56KB. Remeasure after Phase 1.

## Runtime vs init code split

**Only the runtime-resident portion gets copied to high RAM.** Init code
stays in ROM and runs in place, since it only executes before PROM disable.

Runtime-resident (copied to high RAM, survives PROM disable):
- BIOS jump table
- Console I/O (CONIN/CONOUT/CONST on SIO-B)
- SNIOS message layer (send/recv/checksum/retry)
- `ENABLE_FDC`: FDC driver + deblocking + 512B sector buffer + DPH/DPB
- Network DPH/CFGTBL tables

Init-only (stays in ROM, discarded at PROM disable):
- Reset vector + hardware init (SIO/CTC/PIO, IVT stub)
- Cold-boot driver (orchestrates netboot into RAM)
- Netboot receive loop — runs once, from ROM
- One-time banner/status messages

Cold boot order:
1. Reset → hardware init (runs from ROM)
2. Netboot handshake, load CCP+BDOS into RAM (ROM-resident init code)
3. Copy resident BIOS chunk from ROM to high RAM
4. OUT (0x18) — both PROMs disabled, init code vanishes (done with it)
5. Finalize IVT / stack in high RAM, jump to CCP

### Single-pass relocation (vs current autoloader)

The current ROA375 autoloader does a **two-pass** relocation: PROM0 code
first copies itself to 0x7000 in RAM, then that stage-two code reads
Track 0 into 0x0000 under the PROM, then disables the PROM. We do a
**single pass**: init code runs in place from PROM0; netboot writes
CCP+BDOS directly to their final RAM addresses (0xDF80+); resident BIOS
chunk copies once from ROM LMA to RAM VMA 0xF580. No intermediate hop.
This is feasible because we don't need to write RAM at 0x0000-0x07FF
(PROM-shadowed) during boot — we netboot to high RAM only.

**Size impact:** Init code (~500–800B estimated) lives in the 4KB ROM
budget but not in the runtime RAM footprint. Slight TPA uplift vs the
earlier assumption that everything had to be copied up. Measure in Phase 1.

## Session 24 update — SNIOS ported

SNIOS lifted from `cpnet/snios.asm` into `cpnos-rom/snios.s` (GNU-as
syntax, clang integrated asm).  Character I/O goes direct to the C
transport layer (`_transport_send_byte` / `_transport_recv_byte`)
instead of the old BIOS READER/PUNCH/READS vectors — simpler than a
shim layer, and the ring-buffered BIOS reader doesn't exist in
cpnos-rom anyway.

SNIOS size after port: 24B jump table + 436B body + 3B scratch = 463B
(DRI original was ~900B; ours is leaner because the transport
abstraction handles what READER/READS did, and the original's
verbatim CFGTBL inline bytes now live in `cfgtbl.c` only).

**Layout shift**: BIOS_BASE moved from 0xF580 → 0xF200, RESIDENT
region 0x200 → 0x600.  SNIOS + BIOS jump table + stubs + CFGTBL =
867B, doesn't fit in the original 512B window.  Init stack moved from
0xF580 → 0xF200 in step.  Files touched: `cpnos_rom.ld`, `reset.s`,
`bios_jt.s` (comment), `mame_boot_test.lua` (cfgtbl probe address),
plus comments in `cpnos_main.c` / `resident.c`.

**Known follow-up**: real NDOS load address (0xE786..0xF585 per the
original plan) now collides with the new BIOS region starting at
0xF200.  Harmless for Phase 1 because `netboot_server.py` currently
only streams a single RET byte, not a real NDOS.  Before the server
starts sending real NDOS, either drop NDOS lower (costs ~900B of TPA)
or trim SNIOS further.  Current TPA remains ~55KB in theory; exact
number depends on how much NDOS headroom we reserve.

**Tested**: `make cpnos-netboot` PASSes — RC702 boots in MAME,
PROM-disable sentinel intact at 0x0000, FNC=3 lands RET at 0xDF80,
CFGTBL at 0xF4B3 shows SLAVEID=0x70 / SID=0xFF / FNC=5, SNIOS jump
table at 0xF233 visible (8 JP entries).

## Decisions locked in (end of planning session)

- **Project layout**: new directory `rc700-gensmedet/cpnos-rom/` (created,
  README.md in place).
- **PROM disable port**: 0x18 (RAMEN), disables both PROMs. Port 0x14 is
  likely the DIP-switch read, not ROM disable. Project-root CLAUDE.md
  corrected.
- **Boot sequence order**: ROM is disabled *before* track 0 is read
  (safe because boot code runs from 0x7000 by then). Project-root CLAUDE.md
  corrected.
- **MP/M server**: z80pack `cpmsim` at `/Users/ravn/z80/rc700-gensmedet/z80pack/cpmsim` (submodule).
- **SLAVEID**: build-time constant, `-DRC702_SLAVEID=0x70` (can change).
- **Transport**: SIO-A async 38400, RTS/CTS flow control (session #23 fix).
- **Target TPA**: 55–56KB NOS-only, ~52KB with diskette.

## Next-session starting point

Pick up at Phase 0 code artifacts:
1. Write `cpnos-rom/Makefile` (adapt from `autoload-in-c/Makefile`, add
   `ENABLE_FDC` switch, add 4KB size check, add prom0/prom1 split step).
2. Write `cpnos-rom/cpnos_rom.ld` linker script (ROM @ 0x0000 length 0x1000,
   RESIDENT region for runtime-copied BIOS, display/IVT layout preserved).
3. Write `cpnos-rom/reset.s` stub (reset vector + relocate to 0x7000 +
   jump to C entry).
4. Write `cpnos-rom/cpnos_main.c` stub (empty main, just OUT 0x18 and
   infinite loop) to verify the build pipeline.
5. Verify `make cpnos ENABLE_FDC=0` produces a 4KB image that splits cleanly.
6. Set up z80pack cpmsim MP/M config reachable over stdio/pty for MAME
   null-modem bridging. Document in `docs/cpnos-server.md`.

No code has been written yet. The repo has: plan doc, cpnos-rom/README.md,
CLAUDE.md corrections.

## Risks & mitigations

- **Size overrun**: +10–15% clang codegen slippage is typical. Mitigation:
  early size measurement after Phase 1, willing to push small hot paths
  to assembly (SNIOS is already asm).
- **SNIOS entry-point drift**: applications may hard-code 0xDA12/0xDA15/0xDA4D.
  Mitigation: keep these three addresses stable as exported linker symbols;
  verify in size check.
- **MP/M server-side protocol gaps**: custom netboot function may need
  MP/M-side work. Mitigation: use `cpnet/server.py` (Python) for early
  bring-up, move to real MP/M only once protocol is frozen.
- **MAME ↔ real HW divergence**: known MAME SIO bugs (ravn/mame#2).
  Mitigation: async 38400 is proven on real HW per session #23; stick
  with that rate until real-HW test passes.

## Success criteria

- 4KB image builds, both configurations under budget.
- MAME: RC702 boots to `A>` talking to MP/M, `DIR` works, `TYPE FOO.TXT` works.
- NOS+FDC build: `B:DIR` reads local floppy.
- Real HW (when available): same as MAME.
- Comal80 still loads on the NOS-booted machine.

## Session log pointer

Session summaries go in `rc700-gensmedet/tasks/` as
`sessionNN-cpnos-*.md`. This plan lives here and is updated per session.

---

# Detailed design notes

## Concrete runtime memory map

### NOS-only build (ENABLE_FDC=0), target ~55.5 KB TPA

| Region | Addr | Size | Notes |
|---|---|---|---|
| Z80 vectors / CP/M zero page | 0x0000–0x00FF | 256B | WBOOT, IOBYTE, CDISK, BDOS entry |
| TPA | 0x0100–0xDF7F | 56,960B / **55.6 KB** | user programs |
| CCP | 0xDF80–0xE77F | 2KB | loaded from server at cold boot |
| BDOS (NDOS) | 0xE786–0xF57F | 3.5KB | NDOS from `cpnet-z80/dist/src/ndos.asm` |
| BIOS jump table | 0xF580 | ~60B | 20 × `jp nn` entries |
| BIOS resident code | 0xF5C0–0xF5FF | 64B | thin stubs → SNIOS |
| Stack (grows down from here) | 0xF600 | 128B | shared with post-boot BIOS stack |
| IVT (slim) | 0xF600–0xF6FF | 256B | only active vectors; rest → spurious_isr |
| conv_tables | 0xF680–0xF7FF | 384B | kept, Comal80 compat + CRT |
| Display | 0xF800–0xFFCF | 2000B | **locked** |
| Work area | 0xFFD0–0xFFFF | 48B | **locked** |

Runtime-resident BIOS footprint: ~60 + 64 + 128 + 256 + 384 = **~900B below display**.
With SNIOS (900B) also resident, total ~1.8KB → BIOS base at ~0xF580.

### NOS + 8" DSDD build (ENABLE_FDC=1), target ~52 KB TPA

Adds to runtime-resident:
- FDC driver: ~450B
- Deblocking logic: ~170B
- 512B deblock sector buffer (BSS)
- DPH/DPB/SECTRAN for 8" DSDD: ~90B
- ALV/CSV for 2 drives: ~120B (BSS, one block vector per drive)

Extra resident: ~1.3KB → BIOS base shifts down to ~0xD000, CCP at ~0xC400,
TPA = 0x0100–0xC3FF = **49.75 KB** (same as current BIOS!).

**Revision:** diskette build's "extra ~3KB cost vs NOS-only" means it matches
the current BIOS TPA — not a regression. NOS-only is the one that gains.

## Netboot wire protocol (from `cpnet-z80/src/netboot.asm`)

### Message framing (DRI)

All messages use the standard 5-byte header + payload + checksum:

```
Offset  Byte     Meaning
------  ----     --------------------------------------
 0      FMT      Format: 0xB0 = request, 0xB1 = response
 1      DID      Destination ID (master = 0x00)
 2      SID      Source ID (client SLAVEID, e.g. 0x70)
 3      FNC      Function code
 4      SIZ      Data size (0–255)
 5..    DAT      Payload (SIZ bytes)
 N      CKS      8-bit checksum of header+data
```

### Client state machine

```
START:  send FMT=0xB0, FNC=0 (boot request)
        DID=0x00, SID=SLAVEID, SIZ=0, DAT=empty
        → wait for response

LOOP:   receive FMT=0xB1, dispatch on FNC:
          FNC=1 (load text): echo DAT to console (banner)
                             → send ACK, loop
          FNC=2 (set DMA):   next 2 bytes of DAT = target address
                             → store as current DMA, send ACK, loop
          FNC=3 (load data): copy SIZ bytes from DAT to DMA address
                             → advance DMA, send ACK, loop
          FNC=4 (execute):   JP to entry point (first byte of CCP, 0xDF80)

ERROR:  timeout/checksum → send NAK, server re-transmits last block
        10 NAKs → abort, display error, halt
```

### Server-side handler (z80pack cpmsim or cpnet-z80 MP/M)

Must respond to FNC=0 boot request with:
1. FNC=1: signon banner ("CP/NOS loading...")
2. FNC=2: DMA=0xDF80 (CCP base) — build-time constant, client tells server
3. FNC=3 × N: stream CCP+BDOS (NDOS) image, 128B blocks
4. FNC=4: entry=0xDF80 (CCP cold start)

Z80pack cpmsim MP/M extension required: add a netboot slave responder that
reads a file (e.g., `CPNOS.IMG`) and streams it via the above sequence.
Python prototype first (`cpnet/server.py` extension), then port to Z80 on
the MP/M master.

## BIOS jump table entries (17 standard + 3 extended)

Offsets relative to BIOS base (0xF580 in NOS-only build):

| Off | Entry | NOS-only | NOS+FDC (for local B:) |
|---|---|---|---|
| +0 | BOOT | reset vector (unused after cold boot) | same |
| +3 | WBOOT | re-enter CCP from server (re-netboot) | same, local fallback |
| +6 | CONST | SIO-B rx-ready check | same |
| +9 | CONIN | SIO-B rx byte | same |
| +12 | CONOUT | SIO-B tx byte | same |
| +15 | LIST | → SNIOS LST: function | same |
| +18 | PUNCH | → SNIOS PUN: function | same |
| +21 | READER | → SNIOS RDR: function | same |
| +24 | HOME | stub (return NOS routes via NDOS) | set track=0 for B: |
| +27 | SELDSK | return DPH pointer from table | real selection |
| +30 | SETTRK | store in SCB | store in FCB |
| +33 | SETSEC | store in SCB | store in FCB |
| +36 | SETDMA | store in SCB | store in FCB |
| +39 | READ | stub: error (NDOS bypasses us) | real FDC read |
| +42 | WRITE | stub: error | real FDC write |
| +45 | LISTST | → SNIOS LST status | same |
| +48 | SECTRAN | identity map | 8" DSDD xlt table |
| +51 | (extended, may map to SNIOS entry points 0xDA12/15/4D equivalents for app compat) | | |

## Transport vtable (parallel-port drop-in prep)

```c
struct transport {
    void (*init)(void);
    uint8_t (*send_byte)(uint8_t b);   // returns status
    uint8_t (*recv_byte)(uint16_t timeout_ms);  // 0xFF = timeout
    // Optional block-mode hooks (parallel can bulk-handshake):
    void (*send_block)(const uint8_t *p, uint8_t n);
    void (*recv_block)(uint8_t *p, uint8_t n);
};

extern const struct transport t_sio_a;      // SIO-A async 38400
// extern const struct transport t_parallel;  // reserved, parked

#define TRANSPORT (&t_sio_a)  // compile-time, no indirection cost if only one
```

If only one transport is linked in, the compiler can fold indirect calls to
direct calls. Parallel port adds a build-time switch
`-DTRANSPORT=t_parallel` without code restructuring.

## File layout (`cpnos-rom/`)

| File | Purpose | Est. size | Notes |
|---|---|---|---|
| `Makefile` | build, size check, prom0/prom1 split | — | adapt from `autoload-in-c/Makefile` |
| `cpnos_rom.ld` | linker script | — | 4KB ROM @ 0x0000, RESIDENT VMA @ BIOS_BASE |
| `reset.s` | reset vector (0x0000 → init entry), NMI stub | 16B | |
| `init.c` | hardware init (SIO/CTC/PIO, IVT stub) | 260B | ROM-only, discarded |
| `coldboot.c` | orchestrates: netboot → copy resident → OUT 0x18 → CCP | 180B | ROM-only |
| `netboot.asm` | DRI netboot client (FNC 0→4 state machine) | 250B | ROM-only, port from cpnet-z80 |
| `transport_sio.c` | SIO-A driver: init, send_byte, recv_byte, RTS/CTS | 280B | resident |
| `transport.h` | vtable struct | — | header only |
| `snios.asm` | DRI SNIOS message layer | 900B | resident, port from cpnet/ |
| `console.c` | CONIN/CONOUT/CONST on SIO-B | 200B | resident |
| `bios_jt.s` | 20-entry `jp nn` jump table | 60B | resident |
| `bios_stubs.c` | disk-entry stubs (NOS) | 40B | resident (both configs) |
| `cfgtbl.c` | CFGTBL, DPH list, network DPH | 90B | resident |
| `fdc.c` | #if ENABLE_FDC: driver + ISR | 450B | resident when enabled |
| `deblock.c` | #if ENABLE_FDC: 512B↔128B deblocking | 170B | resident when enabled |
| `dpb_maxi.c` | #if ENABLE_FDC: 8" DSDD DPB + SECTRAN | 90B | resident when enabled |
| `banner.c` | one-time boot messages | 80B | ROM-only |
| `build_id.h` | generated: timestamp, SLAVEID, config flags | — | depends on `builddate.h` pattern |

## Build targets (Makefile)

```
make cpnos                          # default: ENABLE_FDC=0, clang
make cpnos ENABLE_FDC=1             # with diskette support
make cpnos-mame                     # build + boot in MAME against cpmsim
make cpnos-mame ENABLE_FDC=1        # NOS+FDC variant
make cpnos-burn                     # produce prom0.bin + prom1.bin ready for burner
make cpnos-size                     # size breakdown by section, check ≤ 4096
make cpnos-disasm                   # llvm-objdump -d for review
make cpnos-map                      # show linker map with addresses
make cpnos-clean                    # clean build artifacts
```

## Test strategy per phase

### Phase 0 (scaffolding)
- `make cpnos-size` passes: empty image ≤ 4096B
- `make cpnos-burn` produces two files of exactly 2048B each
- Linker placement test: resident section lands at expected BIOS_BASE

### Phase 1 (netboot MVP)
- Lit tests for any clang codegen bugs hit during port
- Unit test: netboot state machine, synthetic server responses
  (Python-side: `test_netboot_server.py` replays canned FNC=1/2/3/4)
- MAME integration: boot to `A>`, run `DIR`, `TYPE readme.txt`
- Measure actual ROM size, update budget in this file
- Record in `tasks/cpnos-phase1-results.md`

### Phase 2 (diskette)
- MAME with both NOS + 8" DSDD floppy image
- `A:DIR` (network), `B:DIR` (local) both work
- Read a known file from B:, verify byte-exact
- Write a file to B:, re-read, verify (tests deblocking write path)

### Phase 3 (benchmark)
- Time `A:COPY FOO.COM RAM` vs `B:COPY FOO.COM RAM` for identical 4KB file
- Record in `tasks/cpnos-benchmarks.md`

### Phase 4 (real HW)
- Burn EPROMs, plug in
- Verify banner matches build_id.h timestamp
- Boot, `DIR`, Comal80 load test

## z80pack MP/M server setup

Working directory: `/Users/ravn/z80/rc700-gensmedet/z80pack/cpmsim/` (submodule).

Two integration options:

**A. Python bridge (Phase 1 default, faster iteration):**
- `cpnet/server.py` (existing) extended with netboot handler
- MAME SIO-A null-modem → named pipe → Python script
- Python pretends to be the MP/M master for the boot protocol
- Good for rapid protocol debug; not representative of real MP/M

**B. Real MP/M on z80pack (Phase 1 end-state):**
- Add netboot slave handler to MP/M running on z80pack cpmsim
- Configure cpmsim to expose a serial port to MAME via PTY
- Full round-trip through actual MP/M BDOS / CP/NET master
- Document cpmsim config in `docs/cpnos-server.md`

Suggested sequence: start with A, switch to B once FNC=0/1/2/3/4 protocol
is wire-compatible.

## Debug & iteration workflow

- **Build + boot cycle:** `make cpnos-mame ENABLE_FDC=0` — full rebuild + MAME
  boot test with banner check (like existing `autoload-in-c/` workflow).
- **Symbol view in MAME:** generate `.sym` from ELF (existing pattern),
  inject as `comadd` commands into MAME debugger for source-level breakpoints.
- **Protocol trace:** Python server logs every FMT/FNC/SIZ for each message;
  saves transcript to `/tmp/cpnos-trace.log`.
- **Size regression check:** `make cpnos-size` fails build if > 4096B or
  if any resident symbol drifts from expected address (SNIOS entry points).
- **Lit tests:** any clang codegen issues hit go into `llvm-z80/llvm/test/
  CodeGen/Z80/` as XFAIL then FIX (per project policy).

## Error handling strategy

| Condition | Response |
|---|---|
| Server no-response at cold boot | retry 5× with 2s timeout, then show "NO SRV" + halt |
| Bad checksum during netboot | NAK, server re-sends last block (up to 10 retries) |
| Checksum retry exhausted | show "BOOT FAIL" + halt (cold reset required) |
| SIO-A RX overrun during runtime | log via SCB, SNIOS layer retries |
| SELDSK on unconfigured drive | return 0 (no DPH), CCP prints `BDOS err` |
| FDC failure (NOS+FDC build) | return error to BDOS, drive B: marked offline |

All error messages are 8 chars max (display line space) and stored in
init-only ROM — discarded after boot, so they don't cost runtime RAM.

## Compiler-bug test strategy (extensive)

A 4KB ROM leaves no margin for clang codegen bloat or subtle miscompiles.
Every clang bug that could affect this ROM must be caught **before** it
lands in a build, ideally as a lit test and as a size/codegen regression
check.

### Layers of testing

1. **Lit tests (`llvm/test/CodeGen/Z80/`)** — per-feature, per-bug.
   - For every clang Z80 bug encountered during Phase 1/2, add an XFAIL
     lit test first (documents the bug), then fix the compiler, then
     flip XFAIL → PASS (per project memory: `feedback_test_before_fix`,
     `feedback_compiler_bug_test`).
   - Categories to pre-cover:
     - Port I/O (inline asm `in`/`out` patterns used in `init.c`)
     - IM2 interrupt vector code (must not use IX/IY spills in ISR)
     - ROM-resident `const` data (must NOT be rewritten via peepholes
       that assume RAM)
     - Function-pointer calls (transport vtable)
     - Packed struct access (message framing)
     - 8-bit loop counters (SNIOS retry / receive loops → DJNZ)
     - 16-bit multiply/divide (SECTRAN arithmetic)
     - memcpy/memset to fixed addresses (→ LDIR)
     - volatile BSS access (ring buffers, ISR-shared state)
     - asm-called-from-C with sdcccall(0) and sdcccall(1) ABIs

2. **Byte-exact codegen snapshots.**
   - `tests/cpnos_codegen_snapshots/` — per-function `.golden.s` files
     capturing expected asm output for hot paths (SIO send, SIO recv,
     netboot loop, deblocking inner loop, disk-entry stubs).
   - `make cpnos-snapshot-check`: regenerates asm, diffs against golden.
     Any diff = investigate (either clang regression or intentional
     improvement that needs a golden refresh).
   - Covers: "same code, same bytes" across compiler rebuilds.

3. **Size regression gates.**
   - `make cpnos-size` fails if total image > 4096B.
   - `tests/cpnos_size_budget.json` — per-section expected sizes with
     tolerance (e.g., `netboot.asm: 250±10B`). Build fails if a section
     grows beyond tolerance, forcing explicit acknowledgement.
   - Aggregates published in `tasks/cpnos-size-history.md` after each
     session.

4. **Differential testing vs SDCC.**
   - Where feasible, compile the same C source with both clang and SDCC
     (via existing `autoload-in-c/` dual-build infrastructure).
   - Compare behavior — not byte output (ABIs differ) — via integration:
     both builds run the netboot + SNIOS path, both must produce identical
     protocol traces.
   - `tests/cpnos_dual_compiler.sh` — runs MAME+Python-server for each
     build, diffs protocol logs.

5. **Runtime invariants checked in code.**
   - `_Static_assert` at every opportunity:
     - Jump-table offsets match expected (CONIN at +9 etc.)
     - Struct sizes (netboot msg header = 5B)
     - DPB packing (15 bytes exact)
     - Resident code base ≤ display_start − resident_size
   - Build fails if codegen changes break these.

6. **Protocol replay tests (compiler-agnostic, catches bugs that
   bypass static checks).**
   - `tests/cpnos_netboot_replay.py` — canned server that replays known
     good FNC=1/2/3/4 sequences including edge cases:
     - 0-byte payloads
     - Maximum 255B payloads
     - Deliberately-corrupted checksums (expect NAK)
     - Out-of-order retransmissions
     - Timeout in the middle of a block
   - Run under MAME against the built ROM. Any hang/crash/wrong response
     = test fails. Catches bugs that only manifest at runtime (e.g.,
     wrong register save in ISR).

7. **Undocumented-instruction grep.**
   - Per existing memory (`feedback_undoc_check`): grep final `.s` for
     `IXH|IXL|IYH|IYL|SLL|OUT (C),0` — must be empty unless
     `+undocumented` is explicitly set. Part of `make cpnos-size`.

8. **Static-stack / no-recursion audit.**
   - `clang -Xclang -analyze` or a small Python pass over the map file:
     no function may use more stack than declared budget (128B total).
     Catches clang deciding to spill something unexpected.

9. **Fuzzer on the wire (long-game).**
   - Python-side fuzzer sends random-but-well-formed DRI packets.
     Build must never hang or overwrite its own code. Detects whole
     classes of range/overflow bugs in the SNIOS layer.

### Test matrix summary

| Test | Catches | Runs when |
|---|---|---|
| Lit tests | compiler regressions | every LLVM build |
| Codegen snapshots | silent clang diffs | every ROM build |
| Size gates | bloat | every ROM build |
| Dual-compiler diff | logic-level clang bugs | Phase 1+, weekly |
| `_Static_assert` | layout drift | every ROM build |
| Netboot replay | runtime/ISR bugs | Phase 1+, every build |
| Undoc grep | toolchain surprises | every ROM build |
| Stack audit | spill surprises | every ROM build |
| Wire fuzzer | edge cases | Phase 2+, nightly |

### Git commit discipline

Every commit that touches llvm-z80 and every commit to cpnos-rom runs the
full check. CI script (local, no GitHub Actions needed):

```bash
make -C cpnos-rom cpnos-check  # size + snapshots + asserts + undoc + stack
make -C cpnos-rom cpnos-mame   # MAME boot + netboot replay
cd llvm-z80 && build/bin/llvm-lit llvm/test/CodeGen/Z80/
```

Any red light = revert or fix before continuing. The 4KB budget makes
this discipline non-negotiable.
