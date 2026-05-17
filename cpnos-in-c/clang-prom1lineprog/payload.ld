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
  SCRATCH (rwx) : ORIGIN = 0xEB00, LENGTH = 0x200
  PIO_RX (rwx) : ORIGIN = 0xF700, LENGTH = 0x100
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
  __stack_top = 0xF700;
  __stack_low = 0xF621;
  __payload_size = __payload_end - __payload_start;
  ASSERT(__payload_size <= 0x1000, "payload exceeds 4 KB budget")
  ASSERT(__payload_end <= 0xF800, "payload overflows into display memory")
  .scratch_bss (NOLOAD) : {
    __scratch_bss_start = .;
    KEEP(*(.bss._pio_par_byte))
    KEEP(*(.bss._pio_par_count))
    *(.bss*)
    *(COMMON)
    __scratch_bss_end = .;
  } > SCRATCH
  ASSERT(__scratch_bss_end <= 0xED00, "scratch_bss overflowed")
  .pio_rx_bss 0xF700 (NOLOAD) : {
    __pio_rx_bss_start = .;
    *(.pio_rx_bss)
    __pio_rx_bss_end = .;
  } > PIO_RX
  _pio_rx_buf_page = (__pio_rx_bss_start >> 8) & 0xFF;
  ASSERT((__pio_rx_bss_start & 0xFF) == 0, "pio_rx_buf must be page-aligned")
  ASSERT(__payload_end <= 0xF700, "payload grew into pio_rx_bss region")
  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
