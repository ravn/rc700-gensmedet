# RC702 CP/M Memory Map — rcbios (MSIZE=56)

Two states: plain CP/M boot, and after `CPNETLDR` loads CP/NET 1.2.

## Without CP/NET (plain CP/M boot)

```
Address   Size          Contents
--------  ------------  -------------------------------------------------
0x0000       3 B        JP WBOOT (warm-boot vector, set by BIOS at boot)
0x0003       1 B        IOBYTE
0x0004       1 B        CDISK (current drive)
0x0005       3 B        JP BDOS (BDOS entry vector)
0x0006–7F  122 B        (CP/M zero-page scratch, unused)
0x0080     128 B        DMA buffer (BDOS default transfer area, TBUFF)
0x0100–      –          TPA start (Transient Program Area)

                  ... TPA: 0x0100..0xC3FF = 49920 B = 48.75 KB ...

0xC400    2816 B  2.75 KB  CCP  (Console Command Processor)
0xCC00    3584 B  3.50 KB  BDOS (entry at 0xCC06)
0xDA00     113 B           BIOS JP table (17 × JP) + JTVARS (22 B) + ext JT
0xDA71    4234 B  4.13 KB  BIOS .text (code)
0xEAFB     447 B           BIOS .rodata (constants, strings, tables)
0xECBA       2 B           BIOS .data
0xECBC       2 B           BIOS .sentinel (check word 0x1842)
0xECBE    1783 B  1.74 KB  BIOS .bss (zeroed by coldboot, not in binary)
              ↕            (BSS ends at 0xF3B4)
0xF500       –             BIOS private stack top (grows down)
0xF600      36 B           IVT (18 × 2-byte IM2 vectors, page-aligned)
0xF600       –             Interrupt stack top (grows down into gap below IVT)
0xF680     384 B           Runtime conversion tables (OUTCON 128 B + INCONV 256 B)
0xF800    2000 B  1.95 KB  Display buffer (80 × 25 chars, DMA ch2 → 8275 CRT)
              ↕            (display ends at 0xFFCF)
0xFFD0      48 B           CRT work area (cursor, scroll state, timer)
0xFFFF       –             top of address space
```

TPA available: **0x0100–0xC3FF = 49920 B = 48.75 KB**

## With CP/NET 1.2 (after `CPNETLDR`)

CPNETLDR loads NDOS.SPR + SNIOS.SPR below the CCP and patches the BDOS
entry vector to point to NDOS. TPA shrinks by 2.25 KB.

```
Address   Size          Contents
--------  ------------  -------------------------------------------------
0x0000–FF  256 B        Zero page (same as above)
0x0100–      –          TPA start

                  ... TPA: 0x0100..0xBAFF = 47360 B = 46.25 KB ...

0xBB00    3072 B  3.00 KB  NDOS.SPR  (CP/NET network BDOS)
0xC700    1280 B  1.25 KB  SNIOS.SPR (network SIO/PIO transport)
0xCC00    3584 B  3.50 KB  BDOS (original, overlaid at same address)
0xDA00       –             BIOS (unchanged — JP table, code, BSS, etc.)
0xF800       –             Display, CRT work area (unchanged)
```

CP/NET intercept chain: program → `JP 0x0005` → NDOS at 0xBB00 →
(if local) original BDOS at 0xCC06 → BIOS at 0xDA00;
(if network) SNIOS PIO/SIO transport → master NDOS3 → master BIOS.

TPA available with CP/NET: **0x0100–0xBAFF = 47360 B = 46.25 KB**
TPA lost to CP/NET: 0xC400 − 0xBB00 = **0x900 = 2304 B = 2.25 KB**

## BIOS section detail (from ELF, LTO build fd4a197)

```
Section      VMA      LMA      Size
-----------  -------  -------  -------------------------
.boot        0x0000   0x0000    128 B        boot header (Track 0 ROM)
.boot_data   0x0080   0x0080    512 B        CONFI defaults + conv tables (ROM)
.boot_code   0x0280   0x0280    468 B        coldboot + relocate + bios_hw_init (ROM)
.bios_jt     0xDA00   0x0454    113 B        CP/M JP table + JTVARS + ext JT
.text        0xDA71   0x04C5   4234 B  4.1 KB  BIOS code
.rodata      0xEAFB   0x154F    447 B        constants, strings, tables
.data        0xECBA   0x170E      2 B        sentinel
.sentinel    0xECBC   0x1710      2 B        sentinel check word (0x1842)
.bss         0xECBE   —        1783 B  1.7 KB  zeroed at boot (not in binary)
```

Binary (Track 0 image): **5906 B = 5.77 KB** (LTO, 2026-07-03).
BSS zeroed by `coldboot()` before relocation; range 0xECBE–0xF3B4.

## Key addresses

| Symbol         | Address | Notes                              |
|----------------|---------|------------------------------------|
| `BIOS_BASE`    | 0xDA00  | BIOS JP table (set by linker)      |
| `BDOS_BASE`    | 0xCC06  | native BDOS entry                  |
| `CPMB`         | 0xC400  | CCP base                           |
| `IVT_ADDR`     | 0xF600  | IM2 vector table (page-aligned)    |
| `BIOS_STACK`   | 0xF500  | BIOS private stack top             |
| `CONV_ADDR`    | 0xF680  | runtime conversion tables          |
| `DSPSTR`       | 0xF800  | display buffer (80×25)             |
| CRT work area  | 0xFFD0  | cursor/scroll state (48 B)         |
| NDOS (CP/NET)  | 0xBB00  | loaded by CPNETLDR                 |
| SNIOS (CP/NET) | 0xC700  | PIO or SIO transport               |
