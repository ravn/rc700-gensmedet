/* PROM1-only line-program linker script.
 *
 * Builds a single 2 KB PROM1 image (0x2000..0x27FF) holding:
 *   0x2000  .lineprog_header   8 B   jump-target + " RC702" signature
 *   0x2008  .lineprog_entry    ~30 B bootstrap_entry (DI, set SP,
 *                                    2x call dzx0_standard, jp 0xC000)
 *   0x20XX  .zx0_decoder       68 B  dzx0_standard
 *   0x20XX  .init_zx0          ~546 B  ZX0-compressed init (decode -> 0xC000)
 *   0x2XXX  .payload_zx0       ~1275 B ZX0-compressed payload (decode -> 0xED00)
 *
 * Designed to be loadable into MAME's prom1.ic65 slot and detected by
 * autoload-in-c's prom1_if_present (compare " RC702" at 0x2002, jump
 * to *(word*)0x2000 = bootstrap_entry).
 */

ENTRY(bootstrap_entry)

MEMORY {
  PROM1 (rx) : ORIGIN = 0x2000, LENGTH = 0x0800
}

SECTIONS {
  .lineprog_header 0x2000 : {
    KEEP(*(.lineprog_header))
  } > PROM1

  .lineprog_entry : {
    KEEP(*(.lineprog_entry))
  } > PROM1

  .zx0_decoder : {
    KEEP(*(.zx0_decoder))
  } > PROM1

  .init_zx0 : {
    __init_zx0_start = .;
    KEEP(*(.init_zx0))
    __init_zx0_end = .;
  } > PROM1

  .payload_zx0 : {
    __payload_zx0_start = .;
    KEEP(*(.payload_zx0))
    __payload_zx0_end = .;
  } > PROM1

  __prom1_used = .;
  ASSERT(__prom1_used <= 0x2800,
         "PROM1 line program exceeds 2 KB socket")

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
  }
}
