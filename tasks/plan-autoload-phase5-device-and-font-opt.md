# Plan: Autoload-in-C ZSDCC Phase 5 Optimizations

**Date:** 2026-11-17  
**Target:** `autoload-in-c` (ROA375 2 KB physical PROM0 cap)  
**Baseline:** ZSDCC 4.6.0 PROM0 = **1,914 B** (134 B free out of 2,048 B), Clang PROM0 = **1,963 B** (85 B free).  
**Goal:** Reduce ZSDCC PROM0 size below **1,885 B** (>160 B free headroom) while maintaining 100% dual-compiler parity and verified MAME boot.

---

## ⚠ ZX0 Compression Constraint (2026-11-17)

The ZSDCC build is ZX0-compressed: raw code (3230 B) → compressed (1810 B) → PROM (1914 B).
Small raw-code savings do NOT reliably reduce compressed PROM size:

- **Item 1 tested**: Table-driven `init_devices` saved −36 B raw but INCREASED PROM by +7 B.
  The init_seq table (varying port/value bytes) compresses *worse* than the original sequential
  `3E XX D3 YY` code (repeating D3 opcode enables ZX0 back-references). **Item 1 reverted.**
- **Item 3 tested**: Two new peephole rules added. Effect on PROM size: within timestamp noise
  (±1–2 B). Rules are kept as they don't regress and may help the uncompressed SDCC plain build.
- **Item 2 not tested**: 2 B raw savings → <1 B compressed savings. Below timestamp noise floor.

**Revised metric**: For ZSDCC ZX0, meaningful optimization requires removing *large* code blocks
(≥50 B raw) with low compressibility, or redesigning a major subsection. Small peephole fixes
are not reliably measurable against the timestamp noise in the banner string.

**Current state (2026-11-17)**: ZSDCC 1914 B (134 B free), clang 1964 B (84 B free).
The 160 B free headroom target requires a different approach for ZSDCC.

---

## 1. Concrete Optimization Items

### Item 1: Table-driven `init_devices()` (`rom.c:111-147`)
* **Current implementation:**
  26 sequential inlined port writes (`pio_write_*`, `ctc*_write`, `dma_*`, `crt_*`).
  Compiles to 26 consecutive `ld a, <val>; out (<port>), a` blocks = **106 bytes code**.
* **Target implementation:**
  A compact `const byte init_seq[]` table containing `(port, value)` pairs in `rodata_compiler`, dispatched by a 14-byte loop:
  ```z80
      ld   hl, _init_seq
      ld   b, 26
  init_loop:
      ld   c, (hl)
      inc  hl
      ld   a, (hl)
      inc  hl
      out  (c), a
      djnz init_loop
      ret
  ```
* **Cost / Savings:**
  - Code: 106 B -> ~14 B (-92 B)
  - Data table: +52 B (26 × 2)
  - Net raw savings: **~40 bytes raw**.
  - ZX0 compressibility: Repetitive `(port, val)` bytes compress significantly better than disparate `3E <val> D3 <port>` opcodes.
  - Dual-compiler safety: Works identically in both Clang and SDCC; Clang size will shrink as well.

---

### Item 2: Optimize `load_font_sem702()` font RAM upload (`rom.c:166-173`)
* **Current implementation:**
  ```c
  for (byte line = 0; line < 11; line++) {
      outp(0xD2, line);
      for (byte ch = 0; ch < 128; ch++) {
          outp(0xD1, ch);
          outp(0xD3, *src++);
      }
  }
  ```
  ZSDCC allocates `A` for `ch`. Because `out (0xD3), a` requires `A`, ZSDCC emits `push af / pop af` on *every single iteration* (1,408 times):
  ```z80
  out ($d1), a
  push af          ; spilt 1 B
  ld a, (de)
  out ($d3), a
  pop af           ; spilt 1 B
  ```
* **Target implementation:**
  Keep `ch` in an alternate register (e.g. `B`) or structure the inner loop so `A` is not spilled to the stack.
* **Cost / Savings:**
  - Net raw savings: **2 bytes code**.
  - Runtime savings: **29,568 T-states eliminated** (1,408 iterations × 21T) on every cold boot CRT initialization.

---

### Item 3: Add Missing Peephole Rules to `sdcc/peephole.def`
* **Target patterns identified in disassembly:**
  1. **Dead `ld a, r` before `xor a`:**
     ```text
     ld  a, %1
     xor a, a
     =
     xor a, a
     ```
     (Eliminates dead `ld a, h` at 0x6413).
  2. **4-byte `HL=0` replacement:**
     ```text
     xor a, a
     ld  l, a
     ld  h, a
     =
     ld  hl, 0x0000
     ```
     (Saves 1 byte per occurrence and preserves `A`).
  3. **Redundant memory reload:**
     ```text
     ld  hl, (%1)
     ld  (%1), hl
     =
     ld  hl, (%1)
     ```

---

## 2. Step-by-Step Execution Plan

1. **Step 1: Baseline Check**
   - Confirm clean baseline build on both compilers:
     `make -C rc700-gensmedet/autoload-in-c prom COMPILER=zsdcc` (expect 1914 B)
     `make -C rc700-gensmedet/autoload-in-c prom COMPILER=clang` (expect 1963 B)

2. **Step 2: Implement Item 1 (`init_devices` table)**
   - Define `device_init_entry` or packed byte array `device_init_seq[]` in `rom.c`.
   - Update `init_devices()` in `rom.c`.
   - Rebuild ZSDCC and Clang; record exact byte delta.

3. **Step 3: Implement Item 2 (`load_font_sem702` loop)**
   - Adjust `load_font_sem702()` loop to avoid `A`-spill.
   - Verify disassembly with `z88dk-dis` that `push af / pop af` is gone.

4. **Step 4: Implement Item 3 (`peephole.def` rules)**
   - Add the 3 verified peephole patterns to `autoload-in-c/sdcc/peephole.def`.
   - Rebuild and confirm `check_preserves_regs.py` passes cleanly.

5. **Step 5: Full Verification Gate**
   - Headless MAME tests:
     `make -C rc700-gensmedet/autoload-in-c qr-test COMPILER=zsdcc`
     `make -C rc700-gensmedet/autoload-in-c floppy-boot-test COMPILER=zsdcc`
     `make -C rc700-gensmedet/autoload-in-c qr-test COMPILER=clang`
     `make -C rc700-gensmedet/autoload-in-c floppy-boot-test COMPILER=clang`
   - Validate both PROM0 binaries remain `<= 2048 B`.

6. **Step 6: Document & Commit**
   - Record exact before/after measurements in `tasks/timeline.md` and `tasks/lessons.md`.
   - Commit changes.
