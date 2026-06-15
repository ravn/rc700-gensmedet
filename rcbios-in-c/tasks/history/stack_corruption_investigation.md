# Stack Corruption Investigation (2026-03-08)

## Symptoms
1. Screen memory (0xF800-0xFFC7) fills with repeating pattern
2. OUTCON table (0xF680-0xF6FF) overwritten
3. INCONV table (0xF700-0xF7FF) overwritten
4. Keyboard returns wrong characters (sequential ^A, ^B, ^C...) because INCONV is corrupted
5. No A> prompt visible (screen completely corrupted)

## Memory Layout
```
0xD480-0xEE1F  BIOS code + rodata (6559 bytes)
0xDC00-0xDF??  BSS (variables including kbbuf, kbhead, kbtail, sp_sav)
0xF400-0xF4FF  BIOS stack space (grows down from 0xF500)
0xF500         BIOS stack top
0xF500-0xF5F9  Unused (was BGSTAR)
0xF5FA-0xF61F  ISR stack space (grows down from 0xF620)
0xF620         ISR stack top (CRT, PIO, floppy ISRs)
0xF680-0xF6FF  OUTCON table (128 bytes, output conversion)
0xF700-0xF7FF  INCONV table (256 bytes, input conversion)
0xF800-0xFFC7  Screen memory (80x25 = 2000 bytes)
0xFFD0-0xFFFF  Work area (BDOS variables)
```

## Key Findings

### Bug fixes identified (from previous session, committed)
- bios_conin, bios_const, bios_listst: returned in L instead of A (CP/M reads A)
- bios_reader: same L-vs-A bug
- rwoper: IX frame pointer clobber fixed

### ISR entry pattern difference (CRITICAL)
The original assembly BIOS saves SP and switches stack FIRST, then pushes registers
on the ISR stack. The C BIOS pushes 12 bytes on the interrupted stack before switching.

**Original pattern (safe):**
```asm
LD (SP_SAV),SP    ; save interrupted SP (0 bytes on interrupted stack)
LD SP,ISTACK      ; switch to ISR stack
PUSH AF,BC,DE,HL  ; save registers on ISR stack
```

**C BIOS pattern (dangerous):**
```asm
PUSH AF,BC,DE,HL,IX,IY  ; 12 bytes on INTERRUPTED stack
LD (sp_sav),SP           ; save SP-12
LD SP,#0xF620            ; switch to ISR stack
```

If interrupted code has SP near 0x0000, the C pattern wraps pushes through 0xFFFF,
corrupting the work area (0xFFD0-0xFFFF). The original pattern only has the Z80
hardware push (2 bytes for return address) on the interrupted stack.

### Diagnostic results

**With original C pattern (pushes first):**
- sp_sav=0xFFF2 (0x0000 - 14 bytes: 2 hardware + 12 push)
- Cascade corruption: ISR pops garbage from 0xFFF2-0xFFFF into registers
- RETI jumps to garbage address, all memory gets trashed
- Pattern: `47 1A` repeating (BC=0x1A47 from work area values)

**With original-BIOS pattern (save SP first, tested but rolled back):**
- sp_sav=0xF141 (direct save of interrupted SP — in BIOS code area, invalid)
- Previous sp_sav=0x0040 (zero page — also invalid)
- ISR itself works correctly (saves/restores cleanly)
- But the interrupted code was already executing garbage (SP in wrong area)
- Pattern: `47 47 33 D5 48 00` repeating (different corruption source)
- Page zero at 0x0000: corrupted (should be `C3 03 DA` = JP WBOOT)
- CCP at 0xC400: shows `85 00 85 00` repeating — BUT user points out CCP
  loads correctly (A> prompt is shown with the assembly BIOS on same disk).

### What was verified correct
- BIOS binary code at CONIN address is correct
- INCONV table is correctly loaded at cold boot
- kbbuf receives correct keycodes from PIO (0x61 for 'a')
- DMA mode registers match original assembly BIOS exactly (DMODE2=0x4A, DMODE3=0x4B)
- PIO initialization matches original BIOS exactly
- sp_sav sharing is same as original BIOS (all ISRs share one SP save location)
- No IX/IY frame pointer violations in current build
- Cold boot signon message displays correctly

### Eliminated causes
- sp_track_display: removed, corruption persists
- INCONV table content: verified correct at cold boot
- DMA mode registers: identical to working assembly BIOS
- PIO keyboard initialization: identical to working assembly BIOS
- Stack overflow into OUTCON: BIOS stack at 0xF500 can't reach 0xF680 (288 bytes gap)
- CCP loading from disk: user confirms CCP loads correctly (A> prompt shown)

### BIOS entry points missing DI/EI (potential race)
bios_conout has DI/EI around stack switch (matches original). These do NOT:
- bios_home
- bios_seldsk
- bios_read
- bios_write

The original assembly BIOS uses DI/EI around stack switches in entry points.
Not proven to cause the bug, but a correctness issue to fix.

## Resolution (2026-03-08)

All three issues were fixed:

### Fix 1: BIOS stack address 0xF680→0xF500 (ROOT CAUSE)
All BIOS entry points (conout, home, seldsk, read, write) used `ld sp, #0xF680`
as the BIOS stack. But 0xF680 is the start of the OUTCON table! Stack grows DOWN,
so pushes went directly into the gap between ISR stack and OUTCON, and with deep
C call chains, into the ISR stack area itself. When a CRT ISR fired while BIOS
code was running on this stack, the overlapping stacks caused corruption.

Changed to `ld sp, #0xF500` — well below OUTCON with 256 bytes of stack space.

### Fix 2: ISR entry pattern (save SP first)
Changed from push-then-save to save-then-push (matching original assembly BIOS).
Only 2 bytes (hardware return address) touch the interrupted stack instead of 14.

### Fix 3: DI/EI on all stack-switching BIOS entry points
Added DI/EI around stack switch in bios_home, bios_seldsk, bios_read, bios_write
(bios_conout already had it).

### Fix 4: CONIN and other return register bugs (ld l → ld a)
CP/M reads return values in A register. Five __naked BIOS functions returned in L:
- bios_const: `ld l, #0xFF` → `ld a, #0xFF`
- bios_conin: `ld l, (hl)` → `ld a, (hl)` (INCONV lookup)
- bios_reader: `ld l, #0x1A` → `ld a, #0x1A`
- bios_listst: `ld l, #0xFF` → `ld a, #0xFF`
- bios_reads: `ld l, #0` → `xor a`

The CONIN bug caused A to contain kbtail (0-15), producing sequential control
characters (^A, ^B, ^C...) instead of the actual keystroke.

### Fix 5: Makefile FORCE target
Post-build steps (cp bios.rom, sdcccall check) were in the FORCE target instead
of the bios target. This caused `make clean && make` to fail (tried to cp bios.rom
before it existed). Moved post-build steps to the bios target recipe.

## Verified working
- CP/M boots to A> prompt
- DIR command shows correct directory listing (disk reads work)
- Keyboard input works correctly (DIR, ASM DUMP typed via injection)
- No memory corruption after 120 seconds of runtime
- Signon message displays with correct build timestamp

## Remaining issue
- **Disk writes hang**: ASM command (which writes .PRN and .HEX files) hangs
  after loading. DIR (read-only) works fine. The write path (secwr/wrthst) is
  likely stuck waiting for a floppy interrupt. Needs separate investigation.
