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
  /* Init-only code+rodata.  Lives at PROM 0 addresses, runs in
   * place from PROM, never copied to RAM.  After PROM disable
   * the underlying RAM is exposed and reused as cpnos.com TPA.
   * The relocator embeds init.bin into PROM 0 at exactly this
   * VMA so absolute references resolve.  Init/resident split,
   * step 3 (tasks/todo.md). */
  INIT    (rx)  : ORIGIN = 0x0200, LENGTH = 0x0300

  /* Payload (resident): copied to RAM at 0xED00 by the relocator.
   * Limited by the combined size of the two 2 KB EPROMs minus the
   * relocator + init.bin.  Real cap tracked by the relocator's
   * ASSERTs once it consumes both artifacts. */
  PAYLOAD (rwx) : ORIGIN = 0xED00, LENGTH = 0x1000

  /* Zero-init RAM used by C code (static locals without initializer,
   * runtime-populated tables).  NOT carried in the ROM image — the
   * relocator doesn't touch this region.  Power-on RAM = 0x00 in MAME
   * and typically on real hardware too; real-HW warm boot relies on
   * the prior image having left it in a sensible state.
   *
   * Option β (2026-04-30, post init/resident split): scratch BSS moved
   * to a single region above IVT (0xF524..0xF6FF) so cpnos.com can
   * load up to 0xED00.  The 0xF410..0xF4FF range is RESERVED FOR THE
   * STACK -- reset.s sets SP=0xF500, stack grows down into that 240 B
   * region.  Anything in BSS that ends up below 0xF500 would be
   * silently corrupted by stack pushes -- the linker ASSERTs below
   * catch this.  cfgtbl, _msg, kbd_ring, and static-stack frames all
   * live here.  The two `.scratch_bss*` input sections are kept
   * distinct (legacy section attrs in source) but mapped to one
   * SCRATCH region. */
  SCRATCH (rwx) : ORIGIN = 0xF524, LENGTH = 0x1DC  /* above IVT, below PIO_RX */

  /* PIO-B receive ring buffer (.pio_rx_buf section).  Page-aligned
   * 256-byte buffer at 0xF700 — the head/tail are 8-bit so wrap is
   * free (uint8_t arithmetic).  Sits in the unused tail of the
   * payload memory region (0xED00..0xF800).  Hard-asserted to not
   * overlap actual payload code below. */
  PIO_RX (rwx) : ORIGIN = 0xF700, LENGTH = 0x100
}

/* IVT location shared with init.c (setup_ivt).  Defined here so the
 * ASSERTs can check overlap with .payload / .scratch_bss.  Issue #35. */
__ivt_start = 0xF500;
__ivt_end   = __ivt_start + 18 * 2;

/* PIO ring page address — derived from the actual placement of the
 * .pio_rx_bss section, not a hardcoded literal.  The previous design
 * spelled this as `_pio_rx_buf_page = 0xF7` and was mirrored as
 * `defc _pio_rx_buf_page = 0xF7` in sdcc/sections.asm; both could
 * silently disagree with where each linker actually placed the
 * buffer.  Now both pipelines say "HIGH byte of the symbol's actual
 * address" — the linker computes both, drift is impossible.  Defined
 * AFTER the .pio_rx_bss section below; until then the symbol is
 * unresolved.  isr.c uses `_pio_rx_buf_page` as a high-byte literal
 * in `ld h, _pio_rx_buf_page`. */

SECTIONS {
  /* Init-only output section -- runs in place from PROM 0 at 0x0100.
   * The Makefile extracts these bytes via `objcopy --only-section=.init`
   * into init.bin and the relocator embeds them at PROM 0 0x0100 so
   * VMA == LMA and absolute references inside init code resolve.
   * Symbols inside .init can call resident-RAM symbols at 0xED00+
   * because the relocator populates that range before any init code
   * runs (cpnos_cold_entry in resident orchestrates the calls). */
  .init 0x0200 : {
    __init_start = .;
    *(.init.text)
    *(.init.text.*)
    *(.init.rodata)
    *(.init.rodata.*)
    __init_end = .;
  } > INIT

  __init_size = __init_end - __init_start;
  ASSERT(__init_size <= 0x0300, ".init exceeds 768 B INIT region budget")

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

    /* Resident text + rodata + data.  .init.* was already harvested
     * into the .init output section above so resident is everything
     * that isn't init-tagged. */
    *(.text.init)
    *(.text.init.*)
    *(.text*)
    *(.rodata*)
    *(.data*)

    /* Pad to a 2-byte boundary so the word-additive sum the
     * relocator computes processes whole words.  Without this,
     * an odd-sized .payload would leave one byte uncovered and
     * the patcher rejects odd-length input. */
    . = ALIGN(2);

    /* Payload integrity checksum — last 2 bytes of the .payload
     * section.  Placeholder is 0xFFFF at link time;
     * cpnos-build/patch_payload_checksum.py overwrites it post-link
     * with the correction value that makes the word-additive sum
     * over the entire .payload equal PAYLOAD_CHECKSUM_MAGIC
     * (0xCAFE).  The relocator (relocator.c) recomputes this sum
     * after copying the payload to RAM and halts on mismatch with
     * "BAD CHECKSUM" displayed.  Catches missing prom1.ic65, bit
     * rot, and version mismatches.  KEEP because the placeholder
     * has no incoming references. */
    __payload_checksum_start = .;
    KEEP(*(.payload_checksum))
    __payload_end = .;
    ASSERT(__payload_end - __payload_checksum_start == 2,
           ".payload_checksum must be exactly 2 bytes")
  } > PAYLOAD

  ASSERT(_bios_boot == 0xED00, "BIOS jump table must start at 0xED00")
  ASSERT(_bios_conout - _bios_boot == 12, "BIOS CONOUT offset must be +12")
  ASSERT(_bios_sectran - _bios_boot == 48, "BIOS SECTRAN offset must be +48")

  /* cpnos-build/src/cpnios-shim.asm pins NDOS's NIOS extern symbol at
   * 0xED33 directly, so NDOS calls land in the resident SNIOS jump
   * table without a runtime memcpy.  If _snios_jt ever drifts, the
   * shim must be updated in lockstep -- this assert turns drift into
   * a build failure with a clear message.  Phase A (2026-04-30). */
  ASSERT(_snios_jt == 0xED33,
         "_snios_jt drifted; update cpnos-build/src/cpnios-shim.asm NIOS EQU")

  /* Stack & cpnos.com layout invariants.  Option β (2026-04-30) bumped
   * cpnos.com's CODE up to 0xED00 and moved the stack from 0xED00 to
   * 0xF500; if either drifts the system silently corrupts itself
   * (stack-vs-loaded-image collision -- exactly what bit us during
   * Option β bring-up).  __stack_top mirrors the SP value reset.s
   * loads.  Reset.s should reference these symbols to stay in sync. */
  /* Stack moved to top of free RAM (was 0xF500 pre-Path-3) so resident
   * can rise from 0xED00 to 0xED00 (+256 B TPA via raised CODE_BASE).
   * SP top = 0xF700 (just below PIO_RX); stack growth area =
   * 0xF621..0xF6FF (~223 B; max observed depth ~50 B during init). */
  __stack_top = 0xF700;
  __stack_low = 0xF621;

  __payload_size = __payload_end - __payload_start;

  /* Hard guard: payload must fit in the available ROM space.  Exact
   * budget is (2 * 2048) - relocator_size; relocator.bin tracks the
   * high-water mark and split_proms.py fails if the payload
   * doesn't fit.  Here we just guard the generous upper bound. */
  ASSERT(__payload_size <= 0x1000,
         "payload exceeds 4 KB combined PROM budget")

  /* CRITICAL: payload must NOT overlap display memory at 0xF800.
   * If it did, the relocator would write code/rodata into display RAM
   * at boot, then init_hardware's clear_screen() would wipe it back
   * to spaces — silently corrupting any string literals / const arrays
   * the compiler placed there.  Symptom: "INIT OK" boot marker shows
   * blank, RC702_LOGIN_PWD turns into spaces, signon string vanishes.
   * Catch at link time. */
  ASSERT(__payload_end <= 0xF800,
         "payload overflows into display memory at 0xF800 — shrink it")

  .scratch_bss (NOLOAD) : {
    __scratch_bss_start = .;
    /* Force-keep harness-observed symbols even though their writers
     * (legacy polled-PIO ISR) were removed in commit f10c99f.
     * tests/cpnet_bridge/harness.py treats them as required; without
     * KEEP, ld.lld --gc-sections drops them despite __attribute__((used))
     * on the C declarations. */
    KEEP(*(.bss._pio_par_byte))
    KEEP(*(.bss._pio_par_count))
    *(.bss*)
    *(COMMON)
    __scratch_bss_end = .;
  } > SCRATCH

  ASSERT(__scratch_bss_end <= 0xF700,
         "scratch_bss overflowed into PIO_RX region!")

  /* Stack-vs-cpnos.com / stack-vs-resident / stack-vs-scratch ASSERTs.
   * `__cpnos_load_end` comes via --defsym from the Makefile (=
   * CPNOS_NDOS_ADDR + 0xC80).  Together these turn the kind of silent
   * memory corruption that broke Option β bring-up into link-time
   * failures with clear messages. */
  ASSERT(__cpnos_load_end <= 0xED00,
         "cpnos.com CODE end overflows resident BIOS at 0xED00")
  ASSERT(__stack_top > __cpnos_load_end,
         "stack top <= cpnos.com load end -- pushes will corrupt loaded image")
  ASSERT(__payload_end <= __ivt_start,
         "resident payload extends into IVT region")
  ASSERT(__scratch_bss_end <= __stack_low,
         "scratch_bss extends into stack growth area")

  /* zp_init_data is the 8-byte CP/M zero-page seed copied to
   * 0x0000..0x0007 by resident_handoff AFTER PROM disable.  Reading
   * it from a .init.rodata address would silently fail because PROM
   * 0x???? becomes RAM (zero or TPA garbage) post-disable.  This
   * ASSERT catches a future move into init at link time instead of
   * as a silent boot regression (the trap that bit Option β cleanup
   * pass 1 -- "boot completes netboot, then dies on NDOS COLDST"). */
  ASSERT(_zp_init_data >= 0xED00 && _zp_init_data < 0xF800,
         "zp_init_data must be resident (read after PROM disable)")

  /* PIO-B receive ring (page-aligned at 0xF700). */
  .pio_rx_bss 0xF700 (NOLOAD) : {
    __pio_rx_bss_start = .;
    *(.pio_rx_bss)
    __pio_rx_bss_end = .;
  } > PIO_RX

  /* High byte of the buffer's actual placement.  Computed AFTER the
   * .pio_rx_bss output section so __pio_rx_bss_start is bound.  The
   * `& 0xFF` mask is paranoia — page-aligned by construction (PIO_RX
   * MEMORY region origin is a page boundary), so this resolves to a
   * single byte at link time. */
  _pio_rx_buf_page = (__pio_rx_bss_start >> 8) & 0xFF;
  ASSERT((__pio_rx_bss_start & 0xFF) == 0,
         "pio_rx_buf must be page-aligned for ISR's `ld h, page; ld l, head` trick")

#ifdef TRANSPORT_PROXY
  /* TRANSPORT_PROXY mode skips the IRQ ring buffer (transport_pio.c
   * #ifndef TRANSPORT_PROXY around pio_rx_buf etc), so .pio_rx_bss
   * is empty and payload may extend up to display memory at 0xF800. */
  ASSERT(__payload_end <= 0xF800,
         "payload overflows display memory at 0xF800 — shrink it")
#else
  ASSERT(__payload_end <= 0xF700,
         "payload grew into pio_rx_bss region — shrink payload or move buffer")
#endif

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
