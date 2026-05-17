/* Variant of clang/payload.ld for the PROM1-only line-program build.
 *
 * Only difference vs the parent: INIT MEMORY ORIGIN moves from 0x02A0
 * (PROM-resident in the existing PROM0+PROM1 split build) to 0xC000
 * (RAM, decompressed there by the PROM1 line program's ZX0 stage).
 *
 * All other layout, asserts, and section ordering match the parent
 * exactly so cpnos-in-c's resident interface and resident-side symbol
 * resolution remain unchanged.  The relinked .init bytes get extracted
 * by objcopy and fed into z88dk-zx0 separately from .payload.
 *
 * Init code at 0xC000 is below NDOS (0xDD80) and the resident
 * (0xED00); after handoff this RAM region returns to TPA for CP/M
 * programs.  See tasks/zx0-prom1-only-plan-2026-05-17.md for the
 * full rationale + budget analysis.
 */
ENTRY(_cpnos_cold_entry)
MEMORY {
  INIT (rx) : ORIGIN = 0xC000, LENGTH = 0x0280
  PAYLOAD (rwx) : ORIGIN = 0xED00, LENGTH = 0x1000
  IVT (rw) : ORIGIN = 0xEA00, LENGTH = 0x100
  /* PROM1-only-specific layout (2026-05-17, locale_tables_v3):
   *   SCRATCH 0xEB00..0xEC00 (256 B; shrunk from 0x200)
   *   PIO_RX  0xEC00..0xECFF (256 B; moved from 0xF700, page-aligned)
   *   CFGTBL  0xF53C..0xF60D (210 B; moved out of scratch_bss so the
   *                            shrunk SCRATCH region fits everything)
   *   stack workspace 0xF60E..0xF67F (~114 B; was 0xF53C..0xF6FF)
   *   FREE    0xF680..0xF7FF (384 B for outcon[128]+inconv[256])
   * Two-PROM's linker (cpnos-shared/ld/payload.ld) is UNCHANGED. */
  SCRATCH (rwx) : ORIGIN = 0xEB00, LENGTH = 0x100
  PIO_RX (rwx) : ORIGIN = 0xEC00, LENGTH = 0x100
  CFGTBL_RAM (rw) : ORIGIN = 0xF53C, LENGTH = 0xD2
}
SECTIONS {
  .ivt 0xEA00 (NOLOAD) : {
    __ivt_start = .;
    . = . + 18 * 2;
    __ivt_end = .;
  } > IVT
  .init 0xC000 : {
    __init_start = .;
    *(.init.text)
    *(.init.text.*)
    *(.init.rodata)
    *(.init.rodata.*)
    __init_end = .;
  } > INIT
  __init_size = __init_end - __init_start;
  ASSERT(__init_size <= 0x0280, ".init exceeds 640 B INIT region budget")
  .payload 0xED00 : {
    __payload_start = .;
    KEEP(*(.resident.jumptable))
    KEEP(*(.resident.snios_jt))
    KEEP(*(.resident.snios))
    KEEP(*(.resident.isr))
    *(.resident)
    *(.resident.*)
    KEEP(*(.resident.data))
    *(.text.init)
    *(.text.init.*)
    *(.text*)
    *(.rodata*)
    *(.data*)
    . = ALIGN(2);
    __payload_checksum_start = .;
    KEEP(*(.payload_checksum))
    __payload_end = .;
    ASSERT(__payload_end - __payload_checksum_start == 2,
           ".payload_checksum must be exactly 2 bytes")
  } > PAYLOAD
  ASSERT(_bios_boot == 0xED00, "BIOS jump table must start at 0xED00")
  ASSERT(_bios_conout - _bios_boot == 12, "BIOS CONOUT offset must be +12")
  ASSERT(_bios_sectran - _bios_boot == 48, "BIOS SECTRAN offset must be +48")
  ASSERT(_snios_jt == 0xED33,
         "_snios_jt drifted; update cpnos-build/src/cpnios-shim.asm NIOS EQU")
  __stack_top = 0xF680;            /* moved from 0xF700 for locale tables */
  __stack_low = 0xF53C;            /* grows down to resident end */
  __payload_size = __payload_end - __payload_start;
  ASSERT(__payload_size <= 0x1000, "payload exceeds 4 KB budget")
  ASSERT(__payload_end <= 0xF800, "payload overflows into display memory")
  /* cfgtbl moved OUT of scratch_bss to its own fixed-address region
   * (0xF53C, just above resident).  Saves 210 B in scratch_bss so the
   * shrunk 256 B SCRATCH region has room for the remaining items.
   * Placed BEFORE the .scratch_bss rule so .bss.cfgtbl doesn't get
   * matched by the `*(.bss*)` wildcard below. */
  .cfgtbl_bss 0xF53C (NOLOAD) : {
    KEEP(*(.bss.cfgtbl))
    KEEP(*(.bss._cfgtbl))
  } > CFGTBL_RAM

  .scratch_bss (NOLOAD) : {
    __scratch_bss_start = .;
    KEEP(*(.bss._pio_par_byte))
    KEEP(*(.bss._pio_par_count))
    *(.bss*)
    *(COMMON)
    __scratch_bss_end = .;
  } > SCRATCH
  ASSERT(__scratch_bss_end <= 0xEC00, "scratch_bss overflowed into pio_rx_bss at 0xEC00")
  .pio_rx_bss 0xEC00 (NOLOAD) : {
    __pio_rx_bss_start = .;
    *(.pio_rx_bss)
    __pio_rx_bss_end = .;
  } > PIO_RX
  _pio_rx_buf_page = (__pio_rx_bss_start >> 8) & 0xFF;
  ASSERT((__pio_rx_bss_start & 0xFF) == 0, "pio_rx_buf must be page-aligned")
  ASSERT(__payload_end <= 0xF53C, "payload grew into stack workspace at 0xF53C")
  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
