/* cpnos-rom linker script for LLVM-Z80 (ld.lld)
 *
 * Physical ROM (two EPROMs on the RC702):
 *   PROM0 at 0x0000, 2KB
 *   PROM1 at 0x2000, 2KB
 * Both are disabled by a single OUT (0x18,A) executed from runtime code
 * that has already been copied into high RAM at 0xF200+ (was 0xF580
 * before session #24; moved down to fit SNIOS within the resident chunk).
 *
 * Runtime RAM layout (after PROM disable):
 *   0xF200  BIOS jump table
 *   0xF233  SNIOS jump table + body
 *   0xF40E  BIOS resident code (stubs into SNIOS, console I/O)
 *   0xF4B3  CFGTBL
 *   ... display, workarea (0xF800+) untouched
 *
 * Phase 0 skeleton: everything fits in PROM0, PROM1 is 0xFF-padded by
 * the Makefile.  Subsequent phases will place runtime-resident code in
 * a separate section whose LMA is in PROM and VMA is at 0xF580+;
 * coldboot code memcpys it into place.
 */

ENTRY(_reset)

MEMORY {
  PROM0 (rx) : ORIGIN = 0x0000, LENGTH = 2048
  PROM1 (rx) : ORIGIN = 0x2000, LENGTH = 2048
  /* Runtime-resident BIOS lands here after cold boot copies it out of ROM. */
  /* Resident grows up to just below conv_tables (0xF780 in the planned
     memory map — see rcbios-in-c/tasks/cpnos-rom-plan.md). Phase 1 has
     no IVT or 8275 DMA chain yet, so the region that eventually hosts
     those (0xF680..0xF7FF) is temporarily available. Tighten this once
     the IVT lands. */
  /* BIOS_BASE moved from 0xF580 to 0xF200 in session #24 to fit SNIOS
     (~460B) alongside BIOS jump table + stubs.  Costs ~0x380 of TPA
     headroom relative to the original plan; acceptable given Phase 1 is
     still well under the 56KB TPA target.  Update cpnos-rom-plan.md
     concrete memory map when revisiting TPA numbers. */
  /* Session 33: RESIDENT grown down from 0xF200 to 0xEE00 (+0x400 =
   * 1 KB extra) to fit the rc700_console.c state machine (~790 B) in
   * the new .resident_pre section (0xEE00..0xF1FF).  Runtime stack
   * moves to 0xEE00 in reset.s — still ~0x11D B above BSS top ~0xECE3
   * (cold-boot only; CP/M sets its own SP at 0x0100 post-handoff). */
  RESIDENT (rwx) : ORIGIN = 0xEE00, LENGTH = 0xA00
  /* Scratch RAM for BSS (netboot msgbuf, diag breadcrumbs).
   * Session #27 shifted CCP+NDOS one more page down after observing
   * SP=0xE199 with CCP at 0xD400 (stack_symbol resolves to ~base +
   * 0xD99, not the ~0xB99 we guessed last revision — CCP's BSS/stack
   * extends ~3.5 KB past code_len).  Layout, generously sized so the
   * memory map can absorb more BSS discoveries without another move:
   *   CCP   0xD000..0xDDFF   (2.5 KB code; BSS up to ~0xDD99)
   *   NDOS  0xDE00..0xE9FF   (3 KB code; est. BSS up to ~0xEB99)
   *   BSS   0xEC00..0xED1F   (0x400 gap to stack bottom)
   *   STACK 0xF200 down      (~0x4EB = 1.2 KB)
   * TPA 0x0100..0xCFFF = ~51.75 KB.  Move CCP back up later once we
   * have a precise number for CCP+NDOS true extents. */
  SCRATCH (rwx) : ORIGIN = 0xEC00, LENGTH = 0x600
}

SECTIONS {
  .reset 0x0000 : {
    KEEP(*(.reset))
    KEEP(*(.reset.*))
  } > PROM0

  .init : {
    *(.text.init)
    *(.text.init.*)
    *(.text*)
    *(.rodata*)
  } > PROM0

  __prom0_end = .;
  ASSERT(__prom0_end <= 0x0800, "PROM0 code overflowed 2KB!")

  .prom1 0x2000 : {
    *(.prom1)
    *(.prom1.*)
  } > PROM1

  __prom1_end = .;
  ASSERT(__prom1_end <= 0x2800, "PROM1 code overflowed 2KB!")

  /* .resident_pre covers the 0xF000..0xF1FF range reserved by growing
   * RESIDENT down 512 B in session 33.  Non-ABI helper code (e.g. the
   * rc700_console state machine) lives here so the BIOS jump table can
   * stay anchored at its fixed ABI address of 0xF200. */
  .resident_pre 0xEE00 : AT(__prom0_end) {
    __resident_pre_start = .;
    *(.resident_pre)
    *(.resident_pre.*)
    __resident_pre_end = .;
  } > RESIDENT

  ASSERT(__resident_pre_end <= 0xF200,
         ".resident_pre overflowed into the BIOS jump table at 0xF200")

  /* Session 33: .resident LMA relocated to PROM1 (after netboot_mpm) so
   * the combined .init + .resident_pre + .resident image doesn't overflow
   * PROM0's 2 KB limit.  The --pad-to / dd extraction in the Makefile
   * writes prom1.bin from binary offset 0x2000..0x27FF, which is exactly
   * where PROM1 LMA content lives. */
  .resident 0xF200 : AT(__prom1_end) {
    __resident_start = .;
    /* BIOS jump table MUST come first — its entries are the BIOS's
     * public ABI (BOOT at +0, WBOOT at +3, CONST at +6, ...). */
    KEEP(*(.resident.jumptable))
    KEEP(*(.resident.snios_jt))
    KEEP(*(.resident.snios))
    KEEP(*(.resident.isr))
    *(.resident)
    *(.resident.*)
    KEEP(*(.resident.data))
    __resident_end = .;
  } > RESIDENT

  ASSERT(_bios_boot == 0xF200, "BIOS jump table must start at 0xF200")
  ASSERT(_bios_conout - _bios_boot == 12, "BIOS CONOUT offset must be +12")
  ASSERT(_bios_sectran - _bios_boot == 48, "BIOS SECTRAN offset must be +48")

  __resident_pre_lma = LOADADDR(.resident_pre);
  __resident_lma = LOADADDR(.resident);
  __resident_size = __resident_end - __resident_start;

  /* Guard: resident code must not overflow the RESIDENT region (below
     display RAM at 0xF800; really below conv_tables at 0xF680). */
  ASSERT(__resident_end <= 0xF800, "Resident chunk overflowed into display RAM!")

  .scratch_bss (NOLOAD) : {
    __scratch_bss_start = .;
    *(.bss*)
    *(COMMON)
    __scratch_bss_end = .;
  } > SCRATCH

  ASSERT(__scratch_bss_end <= 0xEE00,
         "scratch_bss overflowed into BIOS resident region!")

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
