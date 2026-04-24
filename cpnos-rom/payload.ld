/* cpnos-rom payload linker script.
 *
 * Everything lives at VMA = LMA = 0xED00 — the final RAM destination
 * of the CP/NOS BIOS + SNIOS + init + netboot code, as a single
 * contiguous blob.  The linker has NO knowledge of the two physical
 * EPROMs (roa375.ic66 at 0x0000, prom1.ic65 at 0x2000).
 *
 * After this ELF is produced:
 *   1. objcopy strips to raw payload.bin (starting at 0xED00).
 *   2. split_proms.py carves it into prom0.bin + prom1.bin.
 *   3. A separate relocator (relocator.s, linked against 0x0000)
 *      sits at PROM0 start, reconstructs this payload in RAM from
 *      both PROMs, then JPs to _cpnos_cold_entry.
 *
 * Why this design:
 *   - Keeps the compiler/linker free of PROM geometry — no AT(),
 *     no LMA-vs-VMA gymnastics, no "which section lands in which
 *     EPROM" decisions leaking into link logic.
 *   - Eliminates a class of bug: switch jump tables (and any other
 *     compiler-emitted .rodata) are at the same address as the code
 *     that references them, because the whole payload relocates
 *     as one unit.  No more "jumptable landed in PROM0 then got
 *     overwritten when TPA came in" footguns.
 *
 * The relocator is expected to copy roughly 4 KB from the two
 * PROMs to 0xED00.  Keep payload size < ~3.9 KB to leave room
 * for the relocator itself.  Hard assert below.
 */

ENTRY(_cpnos_cold_entry)

MEMORY {
  /* Payload: up to 4 KB.  Limited by the combined size of the two
   * 2 KB EPROMs minus the relocator.  Real cap is tracked by the
   * ASSERT below once we have both artifacts. */
  PAYLOAD (rwx) : ORIGIN = 0xED00, LENGTH = 0x1000

  /* Zero-init RAM used by C code (static locals without initializer,
   * runtime-populated tables).  NOT carried in the ROM image — the
   * relocator doesn't touch this region.  Power-on RAM = 0x00 in MAME
   * and typically on real hardware too; real-HW warm boot relies on
   * the prior image having left it in a sensible state.
   *
   * SCRATCH stops at the IVT (0xEC00); anything larger than 0x1E0
   * (480 B) must live in DISKBSS below or be refactored.  */
  SCRATCH (rwx) : ORIGIN = 0xEA20, LENGTH = 0x1E0

  /* Secondary BSS for CP/M disk buffers (dirbuf, alv, csv) — placed
   * just below the 0xF800 display-RAM ceiling so it doesn't collide
   * with either the IVT (0xEC00..0xEC24) or the cold-boot stack
   * (grows down from 0xED00 into the 0xEC24..0xED00 gap).
   *
   * Lowers the effective payload ceiling from 0xF800 to 0xF700; the
   * ASSERT below enforces it.  Payload currently ~2054 B with ~434 B
   * of slack after this reservation — still ample room.  */
  DISKBSS (rwx) : ORIGIN = 0xF700, LENGTH = 0x100
}

/* IVT location shared with init.c (setup_ivt).  Defined here so the
 * ASSERTs can check overlap with .payload / .scratch_bss.  Issue #35. */
__ivt_start = 0xEC00;
__ivt_end   = __ivt_start + 18 * 2;

SECTIONS {
  .payload 0xED00 : {
    __payload_start = .;

    /* BIOS jump table MUST come first — its entries are the BIOS's
     * public ABI (BOOT at +0, WBOOT at +3, CONST at +6, ...).  The
     * `.resident.*` section names are historical — keep them so we
     * don't churn every source file; the linker just glues everything
     * into .payload here. */
    KEEP(*(.resident.jumptable))
    KEEP(*(.resident.snios_jt))
    KEEP(*(.resident.snios))
    KEEP(*(.resident.isr))
    *(.resident)
    *(.resident.*)
    KEEP(*(.resident.data))

    /* Everything else — init code, netboot, C helpers, runtime stubs,
     * compiler-emitted rodata (switch tables etc).  All lands at RAM
     * addresses so jumptables resolve correctly after relocation. */
    *(.text.init)
    *(.text.init.*)
    *(.text*)
    *(.rodata*)
    *(.data*)

    __payload_end = .;
  } > PAYLOAD

  ASSERT(_bios_boot == 0xED00, "BIOS jump table must start at 0xED00")
  ASSERT(_bios_conout - _bios_boot == 12, "BIOS CONOUT offset must be +12")
  ASSERT(_bios_sectran - _bios_boot == 48, "BIOS SECTRAN offset must be +48")

  __payload_size = __payload_end - __payload_start;

  /* Hard guard: payload must fit in the available ROM space.  Exact
   * budget is (2 * 2048) - relocator_size; relocator.bin tracks the
   * high-water mark and split_proms.py fails if the payload
   * doesn't fit.  Here we just guard the generous upper bound. */
  ASSERT(__payload_size <= 0x1000,
         "payload exceeds 4 KB combined PROM budget")
  ASSERT(__payload_end <= 0xF700,
         "payload crossed into DISKBSS region at 0xF700")

  .scratch_bss (NOLOAD) : {
    __scratch_bss_start = .;
    *(.bss*)
    *(COMMON)
    __scratch_bss_end = .;
  } > SCRATCH

  ASSERT(__scratch_bss_end <= 0xEC00,
         "scratch_bss overflowed into IVT!")

  /* Disk-specific BSS — CP/M dirbuf + alloc/check vectors for drive B:.
   * Directed here by __attribute__((section(".disk_bss"))) in disk.c.
   * Kept separate from .scratch_bss so the main region stays under
   * the IVT ceiling.  */
  .disk_bss (NOLOAD) : {
    __disk_bss_start = .;
    KEEP(*(.disk_bss))
    KEEP(*(.disk_bss.*))
    __disk_bss_end = .;
  } > DISKBSS

  /* Issue #35: IVT must not overlap payload or BSS (memcpy / BSS
   * clear would stomp the vector table). */
  ASSERT(__ivt_end <= __payload_start || __ivt_start >= __payload_end,
         "IVT overlaps .payload")
  ASSERT(__ivt_end <= __scratch_bss_start || __ivt_start >= __scratch_bss_end,
         "IVT overlaps .scratch_bss")

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
