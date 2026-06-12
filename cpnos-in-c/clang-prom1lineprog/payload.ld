/* PROM1-only line-program linker script.
 *
 * Resident is at 0xEE00 (was 0xED00 until the 2026-06-04 TPA-grow move).
 * The slave's bottom edge — IVT at 0xEB00 (was 0xEA00) — shifts up by
 * 0x100 too, giving cpnos.com 256 B more clearance below IVT and 256 B
 * more TPA for user programs.  cpnos-build/Makefile's CODE_BASE/DATA_BASE
 * are bumped in lockstep so cpnos.com lands at the new NDOS=0xDE80;
 * cpnios-shim.asm's NIOS=0xEE33 matches _snios_jt below.
 *
 * Net layout post-move:
 *   IVT     0xEB00..0xEBFF  (36 B vectors + 210 B CFGTBL in tail + 10 B slack)
 *   SCRATCH 0xEC00..0xEDFF  (512 B; grew from 256 B post-#115 ring removal)
 *   PAYLOAD 0xEE00..        (resident BIOS + SNIOS; ceiling at 0xF60D)
 *   stack   0xF60E..0xF67F  (~114 B, SP top 0xF680)
 *   locale  0xF680..0xF7FF  (384 B = outcon[128] + inconv[256])
 *
 * Init code at 0xC000 is below NDOS (now 0xDE80) and the resident
 * (0xEE00); after handoff this RAM region returns to TPA for CP/M
 * programs.
 */
ENTRY(_cpnos_cold_entry)
MEMORY {
  INIT (rx) : ORIGIN = 0xC000, LENGTH = 0x0280
  PAYLOAD (rwx) : ORIGIN = 0xEE00, LENGTH = 0x1000
  IVT (rw) : ORIGIN = 0xEB00, LENGTH = 0x100
  /* PROM1-only-specific layout (post-#115 ring removal, 2026-06-12):
   *   IVT vectors 0xEB00..0xEB23 (36 B)
   *   CFGTBL      0xEB24..0xEBF5 (210 B; packed into IVT tail)
   *   IVT slack   0xEBF6..0xEBFF (10 B)
   *   SCRATCH     0xEC00..0xEDFF (512 B; absorbed PIO_RX region after ring removal)
   *   .payload    0xEE00..__payload_end
   *   stack       __payload_end..0xF67F (SP top 0xF680)
   *   locale      0xF680..0xF7FF (384 B for outcon[128]+inconv[256])
   */
  SCRATCH (rwx) : ORIGIN = 0xEC00, LENGTH = 0x200
}
SECTIONS {
  .ivt 0xEB00 (NOLOAD) : {
    __ivt_start = .;
    . = . + 18 * 2;
    __ivt_end = .;
  } > IVT
  /* CFGTBL now lives in the IVT page tail.  The IVT vectors occupy
   * 36 B at 0xEB00..0xEB23; CFGTBL fills the next 210 B; the last
   * 10 B of the page are slack.  Placed inside IVT region (not its
   * own MEMORY region) — see ASSERT below for the size guard. */
  .cfgtbl_bss 0xEB24 (NOLOAD) : {
    __cfgtbl_bss_start = .;
    KEEP(*(.bss.cfgtbl))
    KEEP(*(.bss._cfgtbl))
    __cfgtbl_bss_end = .;
  } > IVT
  ASSERT(__cfgtbl_bss_end <= 0xEC00,
         "cfgtbl overflowed IVT page (0xEB00..0xEBFF); CFGTBL+vectors must fit 256 B")
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
  .payload 0xEE00 : {
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
  ASSERT(_bios_boot == 0xEE00, "BIOS jump table must start at 0xEE00")
  ASSERT(_bios_conout - _bios_boot == 12, "BIOS CONOUT offset must be +12")
  ASSERT(_bios_sectran - _bios_boot == 48, "BIOS SECTRAN offset must be +48")
  ASSERT(_snios_jt == 0xEE33,
         "_snios_jt drifted; update cpnos-build/src/cpnios-shim.asm NIOS EQU")
  __stack_top = 0xF680;            /* locale region starts here */
  __stack_low = 0xF60E;            /* grows down to ~115 B max */
  __payload_size = __payload_end - __payload_start;
  ASSERT(__payload_size <= 0x1000, "payload exceeds 4 KB budget")
  ASSERT(__payload_end <= 0xF800, "payload overflows into display memory")
  ASSERT(__payload_end <= 0xF60E,
         "payload grew into stack workspace at 0xF60E (post-TPA-grow ceiling)")

  .scratch_bss (NOLOAD) : {
    __scratch_bss_start = .;
    KEEP(*(.bss._pio_par_byte))
    KEEP(*(.bss._pio_par_count))
    *(.bss*)
    *(.pio_rx_bss)              /* legacy section; expected empty post-#115 */
    *(COMMON)
    __scratch_bss_end = .;
  } > SCRATCH
  ASSERT(__scratch_bss_end <= 0xEE00, "scratch_bss overflowed into payload at 0xEE00")
  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
