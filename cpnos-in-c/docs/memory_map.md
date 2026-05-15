# cpnos slave runtime memory map

Snapshot taken from a `MIRROR_SIOB=1 BOOT_MARK_ENABLED=1` build at
commit `c3e0c2d`.  All numbers will shift slightly with future
shrinkage but the *structure* is stable.

> **2026-04-30 — Phase A + B + init/resident split + Option β:**
>
> | Region          | Pre-A         | Post-B        | Post-β (current) |
> |-----------------|---------------|---------------|------------------|
> | NDOSRL (DATA)   | 0xCC00        | 0xDAA0        | 0xDC80           |
> | NDOS  (CODE)    | 0xD000        | 0xDEA0        | 0xE080           |
> | cpnos.com end   | 0xDC80        | 0xEB20        | 0xED00           |
> | scratch_bss     | 0xEA20..0xEC00| split LO + HI | 0xF524..0xF6FF   |
> | IVT             | 0xEC00        | 0xEC00        | 0xF500           |
> | Stack (SP top)  | 0xED00        | 0xED00        | 0xF500           |
> | NIOS jump table | 0xEA00 (copy) | 0xED33 (pin)  | 0xED33 (pin)     |
> | Init code       | in resident @ 0xED00 | same  | PROM 0 0x0100, in place |
> | Resident size   | 2438 B        | 2438 B        | 1808 B           |
> | TPA reported    | 52 K          | 55 K          | 56 K             |
>
> Init/resident split (commits c6c00a4, 03a4248): init-only code
> (init_hardware, cfgtbl_init, print_banner, netboot_mpm) tagged
> `((section(".init.text/.init.rodata")))` and runs in place from
> PROM 0 0x0100..0x0375.  Resident shrank by 630 B.
>
> Option β (commit e131c16): freed RAM consolidated above resident;
> stack moved from 0xED00 to 0xF500 to clear cpnos.com's lifted top;
> scratch_bss + IVT moved up; cpnos.com CODE_BASE bumped to 0xE080.
> Layout asserts in `payload.ld` catch stack/cpnos/scratch overlaps
> at link time (`__cpnos_load_end`, `__stack_top`, `__stack_low`).
>
> Run `make cpnos && llvm-nm --numeric-sort clang/payload.elf` for
> live addresses.  See `tasks/timeline.md` Phase 30 + `tasks/todo.md`
> "Init/resident split" for path-α vs β reasoning.

Authoritative sources:

- `cpnos-rom/clang/payload.elf` (via `llvm-nm --numeric-sort`)
- `cpnos-rom/cpnos-build/d/cpnos.sym`
- `cpnos-rom/payload.ld`
- `cpnos-rom/cpnos_main.c` (zero-page seed in `nos_handoff()`)

```
+----------------------------------------------------------------------+
| addr     |  size  |  region                                          |
+----------+--------+--------------------------------------------------+
|  0x0000  |    8 B |  CP/M zero page seed (cpnos_main.c ZP_INIT)      |
|          |        |    0x0000..0x0002  JP 0xCF03  (NDOS BIOS-JT walk)|
|          |        |    0x0003          IOBYTE = 0                    |
|          |        |    0x0004          CDISK   = 4 (boot at E:)      |
|          |        |    0x0005..0x0007  JP NDOSE = 0xD122 after COLDST|
|  0x0008  |   58 B |  Z80 RST vectors / unused (Z80 0x08..0x40)       |
|  0x0040  |  192 B |  more low-RAM scratch (CP/M reserved 0x040..0x0FF|
|          |        |    contains FCB2 @ 0x6c, command tail @ 0x80,    |
|          |        |    default DMA buffer @ 0x80..0xFF)              |
+----------+--------+--------------------------------------------------+
|  0x0100  | 51.7K  |  TPA  (52 K reported by STAT-style tools)        |
|          |        |    upper bound = NDOSE (0xD122 - 0x100 = 0xD022) |
|          |        |    strict safe top = NDOSRL (0xCC00 - 1 = 0xCBFF)|
+----------+--------+--------------------------------------------------+
|  0xCC00  | 0x400  |  NDOSRL  -- NDOS relocatable data segment        |
|  0xCDEA  |        |    BDOSDS (BDOS data) inside NDOSRL block        |
|  0xD000  |        |  NDOS    -- NDOS code start (= cpnos.com IMG_BASE|
|  0xD003  |        |    NDOS+3 = COLDST entry (enter_coldst() target) |
|  0xD006  |        |    NDOSA  = BDOS dispatch entry analogue         |
|  0xD122  |        |    NDOSE  = the entry hidden behind ZP[0x0006]   |
|  0xD996  |        |    BDOS                                          |
|  0xDC80  |        |  cpnos.com end (file is 3200 B from 0xD000)      |
+----------+--------+--------------------------------------------------+
|  0xDC80  | 3.4 K  |  ** GAP ** (3456 B unused -- biggest single hole)|
+----------+--------+--------------------------------------------------+
|  0xEA00  |  24 B  |  NIOS  (SNIOS jump table -- DRI ABI fixed addr)  |
|          |        |    nos_handoff() memcpy 24 B from snios_jt(0xED33)|
|  0xEA18  |   8 B  |  gap                                             |
+----------+--------+--------------------------------------------------+
|  0xEA20  |  416 B |  .scratch_bss (zero-init, runtime-populated)     |
|  0xEA20  |        |    _pio_par_byte, _pio_par_count                 |
|  0xEA22  |        |    static frames for cpnos_cold_entry            |
|  0xEA24  |        |    _kbd_head, _kbd_tail                          |
|  0xEA26  |        |    _curx, _cury, _xflg, _xy_first                |
|  0xEA2A  |  16 B  |    _kbd_ring                                     |
|  0xEA3A  |        |    _cur_dirty                                    |
|  0xEA3B  |        |    static frames for resident.c CRT helpers      |
|  0xEA44  | 173 B  |    _cfgtbl  (DRI CFGTBL: NETST, SLAVEID, drives  |
|          |        |               16x2 B, console, list, FMT, DID,   |
|          |        |               SID, FNC, SIZ, MSG[1+128] = MSGBUF)|
|  0xEAF1  |        |    _pio_b_dir                                    |
|  0xEAF2  |        |    _pio_rx_tail, _pio_rx_head                    |
|  0xEAF4  |        |    static frame for transport_pio_recv_byte      |
|  0xEAF6  | 200 B  |    _msg  (cpnet message scratch buffer)          |
|  0xEBBE  |        |    static frame for netboot_mpm                  |
|  0xEBC0  |  64 B  |  scratch tail (unused, room to grow)             |
+----------+--------+--------------------------------------------------+
|  0xEC00  |  36 B  |  IVT (Z80 IM2 vector page; 18 vectors x 2 B)     |
|  0xEC24  | 220 B  |  ** GAP ** (free RAM below resident BIOS)        |
+----------+--------+--------------------------------------------------+
|  0xED00  |  ~2.4K |  RAM-RESIDENT PAYLOAD (relocator copy target)    |
|  0xED00  |  51 B  |    bios_jt   (17 entries x 3 B JP, BIOS ABI)     |
|  0xED33  |  24 B  |    snios_jt (SNIOS ABI, copied to 0xEA00 at boot)|
|  0xED4B  |        |    snios_sndmsg_c, snios_rcvmsg_c, SNDMSG body,  |
|          |        |    RCVMSG body, ENQ/ACK/SOH/EOT envelope         |
|  0xEEFE  |        |    init helpers (set_i_reg, enable_im2, EI/DI)   |
|  0xEF09  |        |    isr_noop, isr_crt, isr_pio_kbd, isr_pio_par   |
|  0xEFB9  |        |    impl_const, impl_conin, impl_conout, specc,   |
|          |        |    cursor_*, scroll_up, clear_screen, etc.       |
|  0xF2E9  |        |    transport_pio_send_byte / _recv_byte (byte    |
|          |        |    transport, --defsym aliased to _xport_*)      |
|  0xF33B  |        |    cpnos_cold_entry (init code -- runs once)     |
|  0xF3B1  |        |    bios_*_shim (sdcccall(1) <-> CP/M ABI shims)  |
|  0xF3CA  |        |    cfgtbl_init                                   |
|  0xF3FE  |        |    init_hardware                                 |
|  0xF46C  |        |    netboot_mpm + cpnet_xact (init code)          |
|  0xF5A7  |        |    static rodata (banner, ZP_INIT, FCB_HEAD)     |
|  0xF668  |   2 B  |    payload_checksum (recomputed by relocator)    |
|  0xF66A  | 150 B  |    gap before pio_rx_buf                         |
+----------+--------+--------------------------------------------------+
|  0xF700  | 256 B  |  pio_rx_buf  (page-aligned PIO-B IRQ ring)       |
+----------+--------+--------------------------------------------------+
|  0xF800  | 2000 B |  DISPLAY MEMORY (HARDWARE FIXED -- 80 x 25)      |
|  0xFFCF  |        |    last displayed cell (row 24, col 79)          |
|  0xFFD0  |  44 B  |  unused tail (DMA word-count is 2000)            |
|  0xFFFC  |   4 B  |  CRT 32-bit frame counter (incremented by isr_crt|
|          |        |  every VRTC; wraps at ~993 days; mirrors rcbios's|
|          |        |  RTC location)                                   |
+----------+--------+--------------------------------------------------+
```

## ROM image layout

The two physical 2 KB EPROMs hold the bytes that the relocator
reconstructs at `0xED00`.  Until `OUT (0x18)` runs, **both** PROMs
are mapped at `0x0000..0x07FF` and `0x2000..0x27FF` respectively;
after PROM-disable, the underlying RAM is exposed.

```
+----------+--------+----------------------------------------------+
| LMA      | size   | content                                       |
+----------+--------+----------------------------------------------+
|  0x0000  | 0x88   | relocator entry (`reset.s` -> `relocator.c`) |
|  0x0088  |        | -- gap padded 0xFF up to 0x80 --              |
|  0x00C0  | 1856 B | payload_a (first chunk of .payload)          |
|  0x07FF  |        | end of PROM 0 (2 KB)                          |
|  0x2000  |  554 B | payload_b (rest of .payload)                  |
|  0x2226  |        | -- 0xFF padding to 0x27FF --                  |
|  0x27FF  |        | end of PROM 1 (2 KB)                          |
+----------+--------+----------------------------------------------+
```

Combined: 0x80 reloc + 0x96A payload = 2538 B used out of 4096 B
(default build with `MIRROR_SIOB=1`).  Headroom: 1558 B unused.

## Where the gaps are (TPA-grow targets, lowest first)

| Gap                | Size   | Notes                                   |
|--------------------|--------|-----------------------------------------|
| 0xDC80..0xE9FF     | 3.4 KB | between cpnos.com end and NIOS at 0xEA00 |
| 0xEC24..0xECFF     | 220 B  | between IVT and resident BIOS at 0xED00 |
| 0xF66A..0xF6FF     | 150 B  | between resident BIOS end and PIO ring  |
| 0xEBC0..0xEBFF     |  64 B  | tail of scratch BSS                     |
| 0xFFD0..0xFFFB     |  44 B  | between display end and frame counter   |
| 0xEA18..0xEA1F     |   8 B  | between NIOS and scratch BSS            |

All RAM gaps total: **~3.85 KB**.  PROM gap: **~1.55 KB**.

## Where to look in source

| File                                | What it places                                |
|-------------------------------------|-----------------------------------------------|
| `cpnos-rom/payload.ld`              | resident payload section, scratch BSS, IVT, PIO ring |
| `cpnos-rom/relocator.ld`            | (similar) relocator linker script              |
| `cpnos-rom/cpnos_main.c`            | ZP_INIT, snios_jt copy, JP NDOSE seed         |
| `cpnos-rom/cpnos-build/`            | cpnos.com (DRI RMAC+LINK build of NDOS+CCP+BDOS) |
| `cpnos-rom/init.c`                  | merged cold-init TU: cfgtbl struct (210 B), msg buffer (aliased over cfgtbl.fmt+0..170), IVT setup, port_init, netboot_mpm |
| `cpnos-rom/transport_pio.c`         | _pio_rx_buf (256 B page-aligned)              |
| `cpnos-rom/resident.c`              | _kbd_ring (16 B), _curx/_cury, ISR-touched BSS |
| `cpnos-rom/hal.h`                   | DISPLAY_ADDR (0xF800), 8275/DMA port consts   |

## Things worth knowing

- **Symbols in cpnos.sym are partially absolute**: `NDOSRL`, `NDOS`,
  `BDOSDS`, `NIOS` are all linked to fixed addresses by the DRI
  RMAC/LINK build, NOT by our payload.ld.  Moving any of them
  requires rebuilding cpnos-build (and updating init.c's
  `IMG_BASE`, cpnos_main.c's `NDOS_SNIOS_ADDR`, and the JP target
  in ZP[0x0006..0x0007]).

- **The biggest single hole (3.4 KB at 0xDC80..0xE9FF)** is from
  cpnos.com originally being ~6 KB; modern shrinking left a gap.
  Closing it would let `NDOSRL` move from 0xCC00 up to ~0xD980,
  growing TPA by ~3.4 KB (51 KB -> 54 KB strict, ~55 KB reported).

- **Display memory is the hard ceiling** at 0xF800.  Anything above
  0xF800 except the 4 B counter at 0xFFFC is video RAM seen by the
  i8275 on every refresh -- writes there flicker on screen.

- **`_msg[200]` is the largest oversize buffer.** Worst-case CP/NET
  payload is the READ-SEQ response: 5 hdr + 1 rc + 36 FCB + 128 data
  + 1 cks = 171 B.  Could shrink to 175.

- **`_pio_rx_buf[256]` page-alignment** is what makes the PIO IRQ
  hot path use `LD H, _pio_rx_buf_page; LD L, head` instead of
  `LD HL,addr; ADD HL,head` -- shrinking would force back to the
  add-then-store form.  Trade-off if buffer size matters more than
  the few bytes saved per ISR call.
