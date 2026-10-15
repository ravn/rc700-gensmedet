# SW1 Status Display: Optimization and Feature Gate

Date: 2026-10-15
Branch: `work/zsdcc-sccz80-builds-20261012`
Component: `autoload-in-c`

---

## 1. Context

`display_sw1_status()` prints the 8-bit state of the motherboard SW1 DIP switch (`port 0x14`) to row 0, column 58 of the CRT framebuffer (`0x786A`) during power-on initialization:
```
row00:  RC700 ROA375 CL 2026-10-15 23.41 47cf9b2/ravn            SW1 12345678: 00000000
```
This is an informational / diagnostic feature added in the reconstructed firmware (the original ROA375 PROM did not display SW1).

The hardware boot logic (`diskette_size()`, `siob_debug_on()`, and `prom1_if_present()`) reads `port 0x14` directly via `read_sw1()` independent of `display_sw1_status()`.

---

## 2. Size Analysis of the C Implementation

The initial C implementation inside `rom.c`:
```c
#define display_sw1_status() do { \
    byte sw = read_sw1(); \
    char *p = (char *)dspstr + 80 - 22; \
    static const char prefix[] = "SW1 12345678: "; \
    byte i; \
    memcpy(p, prefix, sizeof prefix - 1); \
    p += sizeof prefix - 1; \
    for (i = 0; i < 8; i++) { \
        *p++ = (char)('0' + (sw & 1)); \
        sw >>= 1; \
    } \
} while (0)
```

Measured footprint:
- **Raw `.text`:** **110 bytes** (95 B code + 14 B string + spills)
- **Compressed ZX0:** **91 bytes**
- **PROM total (`prom.clang.bin`):** **2112 bytes** (+64 B over physical 2048 B socket limit)

### Root Cause of the C Code Bloat:
Because `display_sw1_status()` was inlined inside `_main_relocated` (a large function handling CRT, CTC, DMA, font-load, and QR), LLVM-Z80's register allocator faced severe register pressure:
1. Every loop variable (`p`, `sw`, loop counter `i`) was spilled into static frame slots in `.bss` (`$6db8`, `$6db9`, `$6dbb`, `$6dbd`).
2. Every iteration incurred 3- and 4-byte memory load/store instructions (`ld ($6db9), a`, `ld a, ($6db8)`, `ld bc, ($6dbd)`, `ld ($6dbd), hl`).
3. LLVM did not emit `DJNZ`, instead generating a 16-bit compare/jump sequence.

---

## 3. Compact Assembly Implementation (`clang/sw1_display.s`)

Implemented as a dedicated leaf assembly function:
```z80
_display_sw1_status:
	ld	hl, .Lsw1_prefix
	ld	de, 0x786a		; row 0, col 58 (0x7830 + 58)
	ld	bc, 14			; sizeof("SW1 12345678: ") - 1
	ldir
	in	a, (0x14)		; read SW1 port
	ld	b, 8
.Lsw1_loop:
	rrca
	ld	c, a
	ld	a, 0x30			; '0'
	adc	a, 0			; '0' + carry -> '0' or '1'
	ld	(de), a
	inc	de
	ld	a, c
	djnz	.Lsw1_loop
	ret

	.section .rodata._display_sw1_status,"a",@progbits
.Lsw1_prefix:
	.ascii "SW1 12345678: "
```

Footprint of assembly version:
- **Raw code:** 27 bytes
- **Prefix string:** 14 bytes
- **Total raw:** **41 bytes** (−69 B vs C version)
- **Static frame spills in `_main_relocated`:** 0 B (eliminated 7 B in BSS)
- **Compressed ZX0:** **1948 bytes** (−45 B vs C version)
- **PROM total (`prom.clang.bin`):** **2067 bytes** (−45 B vs C version)

---

## 4. Feature Gate (`DISPLAY_SW1_STATUS`)

A compile-time configuration flag was added:

### `Makefile`:
```makefile
# SW1 status line on row 0 (default OFF to meet 2048 B socket ceiling).
# Enable with make DISPLAY_SW1_STATUS=1 (+45 B compressed with asm implementation).
DISPLAY_SW1_STATUS ?= 0
CLANG_CFLAGS += -DDISPLAY_SW1_STATUS=$(DISPLAY_SW1_STATUS)
```
Propagated to `ZSDCC_FLAGS` and `LLVMZ80_CFLAGS`.

Recompilation of `clang/rom.o` on flag changes is tracked automatically via stamp file `clang/.display_sw1_status`.

### `rom.c`:
```c
#if !defined(DISPLAY_SW1_STATUS) || DISPLAY_SW1_STATUS
#if defined(__z80__) || defined(__LLVMZ80)
void display_sw1_status(void) __attribute__((leaf));
#else
#define display_sw1_status() do { ... } while (0)
#endif
#else
#define display_sw1_status() ((void)0)
#endif
```

---

## 5. Summary Comparison

| Configuration | Raw `.text` | ZX0 Payload | Total PROM | 2048 B Socket Headroom |
|---|---|---|---|---|
| **Original C version** | 3466 B | 1993 B | 2112 B | −64 B (exceeds 2 KB) |
| **Asm version (`DISPLAY_SW1_STATUS=1`)** | 3400 B | 1948 B | 2067 B | −19 B |
| **Default OFF (`DISPLAY_SW1_STATUS=0`)** | **3356 B** | **1902 B** | **2021 B** | **+27 B (fits in 2 KB 2716 EPROM!)** |

- `make prom` defaults to `DISPLAY_SW1_STATUS=0`, producing **2021 bytes** and fitting into physical 2716 EPROM with 27 bytes free.
- `make sw1-test` automatically invokes `$(MAKE) prom DISPLAY_SW1_STATUS=1` to test the status renderer, and PASSes.
- `make mame` and `make qr-test` both PASS on the default build.
