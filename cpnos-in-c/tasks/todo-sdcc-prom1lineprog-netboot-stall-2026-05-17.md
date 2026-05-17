# SDCC PROM1-only line program: slave stalls after netboot dots

**Status:** TODO -- diagnosis needed for next session.

## What works (session 73j-late landed)

End-to-end build pipeline for SDCC PROM1-only via ZX0 compression:

  * `make sdcc-prom1lineprog COMPILER=sdcc` produces
    `sdcc-prom1lineprog/prom1-lineprog.bin` (2216 B raw, 4 KB padded).
  * MAME boots with the 4 KB image at 0x2000 (companion change in
    ravn/mame@d0a7dcd81f2: ROM_LOAD_OPTIONAL prom1.ic65 size 0x800
    -> 0x1000, PROMCFG default PROM1 = 2732 / 4 KB so bank2h
    exposes upper half of PROM1).
  * Autoload jumps to bootstrap_entry (0x2008) ✓.
  * Bootstrap pre-init: DI + SP + dzx0 payload to 0xED00 + dzx0 init
    to 0xC000 + jp _cpnos_cold_entry (symbolic; SDCC link places
    the symbol at ~0xC1A1, not 0xC000) ✓.
  * cpnos_cold_entry runs: outcon pre-fill at 0xF680, sentinel arm,
    SW1 reads, init_hardware, print_banner ✓.
  * SIO-B raw shows:
        RC702 CP/NOS 55K PIO sdcc 2026-05-17 21:07 00791ce+
        ............................   (28 netboot loading dots)

## Where it stalls

The 28 dots correspond to 28 * 128 = 3584 B = the full cpnos.img
(including 384 B locale prefix), so netboot's READ-SEQ loop COMPLETES.
But the next expected output (stamp from last 32 bytes of cpnos.com,
e.g. "2026-05-17 21:15 00791ce da_US") never appears.  Slave is stuck
somewhere between netboot_mpm()'s EOF break and resident_handoff().

Clang's identical path produces the stamp line + E> within ~2 s of
the dots line; SDCC's wedge persists past the MAME `-seconds_to_run`
window (tested 60 s).

## Hypotheses to investigate (most likely first)

1. **CLOSE FCB call (BDOS fn 16)** fails in SDCC build.  The
   `reuse_fcb()` + `cpnet_xact(16, 36)` after EOF is the last
   netboot step before printing the stamp.  Could be SDCC's
   snios_c.c `snios_sndmsg_c` / `snios_rcvmsg_c` state-machine
   differs subtly from clang's.

2. **dma pointer corruption in netboot_mpm READ-SEQ loop.**  The
   loop does `dma += 128` per record.  If SDCC compiled the
   `uint8_t *` arithmetic differently (e.g., a missed 16-bit add),
   dma could be off-by-256 by EOF, and the stamp read at `dma - 32`
   lands on garbage.

3. **install_locale_tables() in resident_handoff() crashes under
   SDCC.**  Now that SDCC builds with the locale machinery active
   (the #ifdef __clang__ gates were removed), install_locale_tables
   LDIRs 384 B from 0xDC00 to 0xF680 -- but the destination overlaps
   the stack workspace (stack top = 0xF680).  Should be fine since
   the LDIR copies AHEAD of where the stack grows, but worth
   re-verifying.

4. **resident_handoff after PROM disable** could fault on a missing
   helper that SDCC's link doesn't include from sdcc-prom1lineprog/
   sections.asm.  Compare sdcc-prom1lineprog/sections.asm against
   sdcc/sections.asm for any PUBLIC declarations that are still
   missing.

5. **The patch_payload_checksum step** writes 2 bytes to the LAST
   word of cpnos_lp_RESIDENT_JUMPTABLE.bin = the RESIDENT_CHECKSUM
   section.  Position matters -- if that section isn't the last
   in the resident chain, the patch lands in the middle of
   meaningful code/data.  Verify via sdcc/cpnos_lp.map that
   RESIDENT_CHECKSUM is at the end.

## Diagnostic findings (session 73j-late close)

  * **Slave dzx0_standard verified correct.**  Dumped slave RAM
    0xED00..0xF58D after decompression; cmp'd against host-side
    z88dk-dzx0 of payload.zx0; byte-identical (2190 / 2190).
    Slave init at 0xC000..0xC28C also matches host dzx0 of
    init.zx0.  So the ZX0 decoder + the compressed bytes round-trip
    correctly on the Z80; the resident is intact post-unpack.

  * **PC stall location: `_transport_pio_recv_byte` (0xEDEF +).**
    Slave PC oscillates 0xEDF5..0xEE04 -- the PIO IRQ ring drain
    loop.  Ring stays empty -> spins forever.

  * **28 dots = full 3584 B cpnos.img received.**  The IRQ ring
    worked for 28 records (one ACK and one data frame each).  The
    29th READ-SEQ request (which expects an EOF response with
    rc=1) is where the slave wedges.

So: dzx0 is good, the resident is good.  The bug is in the live
state of the netboot conversation -- master probably never sent
the 29th response, OR slave's request was malformed.  Reading
/tmp/cpnos_sioa.raw from a netboot run would show the wire-level
exchange.

## Diagnostic tools available

  * `/tmp/probe_resident.lua` (gist: reads memory at fixed addresses
    + PC at multiple times).
  * `/tmp/probe_bank2h.lua` (verifies 4 KB PROM1 mode active).
  * SIO-B raw at /tmp/cpnos_siob.raw -- last bytes hint at the stall
    point.
  * sdcc/cpnos_lp.map -- linker map with every symbol's runtime
    address.

## When picking this up

Start by adding a trace BOOT_MARK at the entry of resident_handoff()
+ post-install_locale_tables + pre-enter_coldst() to nail down which
phase stalls.  Compare against clang's same instrumentation.  Then
fix whichever module is divergent.
