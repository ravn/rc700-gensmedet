/* cpnos-rom relocator linker script.
 *
 * Links reset.s + relocator.c into two 2 KB ROM images matching the
 * RC702's physical EPROM layout: PROM0 at 0x0000, PROM1 at 0x2000.
 *
 * Sections:
 *   .reset       0x0000     reset vector (3 instructions of stack setup)
 *   .text/.rodata            C relocator code + compiler-emitted
 *                            constants.  Lands in PROM0 above .reset.
 *   .prom0_init  0x0100     init.bin — init code+rodata that runs in
 *                            place from PROM 0 (cfgtbl_init,
 *                            init_hardware, print_banner, netboot_mpm).
 *                            See tasks/todo.md "Init/resident split".
 *   .prom0_tail  0x0400     payload_a[] — first chunk of the resident
 *                            payload, copied to RAM 0xED00 by relocate().
 *   .prom1       0x2000     payload_b[] — rest of resident payload in
 *                            PROM1, copied to RAM right after payload_a.
 *
 * Separate from payload.ld by design: this script knows about PROMs,
 * the payload's linker only knows about VMA addresses (0x0100 for
 * init, 0xED00 for resident).
 */

ENTRY(_reset)

MEMORY {
  PROM0 (rx) : ORIGIN = 0x0000, LENGTH = 0x0800
  PROM1 (rx) : ORIGIN = 0x2000, LENGTH = 0x0800
}

SECTIONS {
  .reset 0x0000 : {
    KEEP(*(.reset))
    KEEP(*(.reset.*))
  } > PROM0

  /* C relocator body + compiler-emitted rodata.  Kept below 0x100 by
   * the ASSERT; .prom0_init starts at 0x100. */
  .text : {
    *(.text*)
    *(.rodata*)
  } > PROM0

  /* Payload header — emitted by tasks/scripts/gen_payload_header.py
   * from the payload ELF's symbols.  Placed right after the relocator
   * code so the bytes are at a known runtime address that the relocator
   * reads via the `_payload_header` extern.  Contents: magic/version,
   * resident_dest, chunk-A/B src/size, cold_entry, checksum_magic, and
   * a list of (start, end) BSS-pairs to zero before checksum.  Replaces
   * the previous --defsym injection mechanism — see plan
   * /Users/ravn/.claude/plans/harmonic-sleeping-spring.md. */
  .payload_header : {
    KEEP(*(.payload_header))
  } > PROM0

  __reloc_code_end = .;
  ASSERT(__reloc_code_end <= 0x280,
         "relocator code + header exceeds 640 B reservation (shrink relocator or raise .prom0_init base)")

  /* Init image -- 0x280..0x4FF.  Bytes are extracted from the payload
   * ELF's .init output section by `objcopy --only-section=.init`,
   * then #embed'd into relocator.c's `init_image[]` and placed here.
   * VMA == LMA so init code's absolute references resolve when it
   * executes in place from PROM.  Base history:
   *   0x100 → 0x200 (2026-05-07) to give the data-driven relocator
   *                  + header more code budget
   *   0x200 → 0x280 (2026-05-08) to give the relocator the dual-
   *                  header memcmp + PROM_MISMATCH_MSG + the
   *                  build_date_str field's 16 bytes more room.
   *                  Init slot shrinks to 640 B; init.bin = 630 B
   *                  with 10 B headroom.  payload.ld matches. */
  .prom0_init 0x280 : {
    KEEP(*(.prom0_init))
  } > PROM0

  __init_end = .;
  ASSERT(__init_end <= 0x500,
         "init image exceeds 640 B PROM 0 reservation (raise .prom0_tail base)")

  /* Resident payload chunk A — PROM0 tail at 0x0500.  First
   * PROM0_TAIL_SIZE bytes of resident payload.  Makefile's
   * PROM0_TAIL_SIZE must match (0x800 - 0x500 = 768 bytes available
   * between 0x500 and 0x800).  __chunk_a_start emitted here so
   * gen_payload_header.py / the header can resolve `chunk_a_src`
   * to the actual placement (no hardcoded 0x500 outside this file). */
  .prom0_tail 0x500 : {
    __chunk_a_start = .;
    KEEP(*(.prom0_tail))
  } > PROM0

  /* Duplicate payload header at PROM1 byte 0 — emitted by
   * gen_payload_header.py into .payload_header_p1.  Same bytes as
   * .payload_header in PROM0; the relocator memcmp's them at boot so
   * a stale-PROM mismatch (PROM0 build N-1 + PROM1 build N) surfaces
   * BEFORE the word-additive checksum stage.  See
   * tasks/dual-header-plan-2026-05-08.md.  chunk_b's LMA shifts to
   * 0x2000 + sizeof(payload_header); chunk_b_size derivation in
   * payload.ld is unaffected (still payload_size - chunk_a_size). */
  .payload_header_p1 0x2000 : {
    KEEP(*(.payload_header_p1))
  } > PROM1

  /* Resident payload chunk B — rest of PROM1 after the duplicate
   * header.  Integrity checksum is the last 2 bytes of the linked
   * payload.bin (placed there by payload.ld's .payload_checksum
   * section).  After splitting it ends up as the last 2 bytes of
   * payload_b.bin.  __chunk_b_start emitted here for the same reason
   * as __chunk_a_start above; the linker resolves it to 0x2000 +
   * sizeof(payload_header) automatically. */
  .prom1 : {
    __chunk_b_start = .;
    KEEP(*(.prom1))
  } > PROM1

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame*)
    *(.note*)
    *(.addrsig)
    *(.bss*)    /* relocator is stateless — no BSS */
    *(.data*)   /* no mutable globals here */
  }
}
