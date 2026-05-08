# Dual-header structural fix for stale-PROM mismatch class

User request 2026-05-08:
> "can you put the copy header at the start of both proms, so there
> are _two_ data structures telling what to copy, including the build
> date and print when copying? Also check that they are the same?"
>
> "the checksum should still be on the final memory image"

## Goal

Detect cross-PROM mismatch (PROM0 from build N-1 + PROM1 from build N)
at the relocator stage, before "BAD CHECKSUM" surfaces.  Make the
build-date visible to the operator from boot, before the resident
banner runs.  Existing word-additive checksum on the final RAM image
stays as-is (per user clarification).

Today's symptom (closed at recipe level by `4e7f1de`): asymmetric
clang vs SDCC Makefile recipes left a stale `prom0_padded.ic66` on
disk; install rule didn't refresh; MAME loaded mixed-build PROMs;
relocator's word-sum failed -> "BAD CHECKSUM" with no operator hint
of which PROMs were involved.

## Design

1. **Add `char build_date_str[16]` field** to `payload_header.h`,
   between `checksum_magic` and `bss_pairs[][2]`.  ASCII format:
   `"YYYY-MM-DD HH:MM"` (16 chars exactly).  Source: existing
   `BUILD_DATE_STR` macro in `$(BUILDDIR)/cpnos_buildinfo.h`.

2. **Two header copies, identical bytes:**
   - PROM0: existing `_payload_header` slot (linker-decided, currently
     ~0x0185 in the relocator code area).  Stays where it is.  Honors
     "start of both proms" loosely -- it's the first non-code data
     block in PROM0 after the reset vector + relocator code.
   - PROM1: NEW slot at LMA `0x2000` (= byte 0 of PROM1).  Strict
     "start of PROM1".  chunk_b shifts from `0x2000` to
     `0x2000 + sizeof(header)`.
   - SDCC PROM1 budget: chunk_b max becomes 1792 - sizeof(header)
     bytes.  Today's SDCC chunk_b is 1734 B; sizeof(header) is ~38 B
     (24 fixed + 16 build_date + 16 BSS pairs).  Headroom: ~20 B.
     Tight but fits.

3. **Build-script changes** (`gen_payload_header.py`):
   - New `--build-date-str` CLI arg (required).
   - Emit two sections per generation:
     - clang: `.section .payload_header,"a",@progbits` (existing) +
       `.section .payload_header_p1,"a",@progbits` with same bytes.
     - sdcc: `SECTION PAYLOAD_HEADER` (existing) + `SECTION
       PAYLOAD_HEADER_P1` with same bytes.
   - Encode 16-byte build_date_str as 8 `.short` / `defw` words.

4. **Linker scripts:**
   - `relocator.ld` (clang): add a `.payload_header_p1` section in
     PROM1 region, BEFORE `.prom1`:
     ```
     .payload_header_p1 0x2000 : { KEEP(*(.payload_header_p1)) } > PROM1
     .prom1 : { __chunk_b_start = .; KEEP(*(.prom1)) } > PROM1
     ```
   - `sdcc/sections.asm`: add `SECTION PAYLOAD_HEADER_P1` before the
     existing PROM1 chunk-B region, ensuring it starts at the PROM1
     `org`.

5. **Relocator (`relocator.c`)** — at the very top of the entry path,
   BEFORE chunk copy:
   - `serial_putc_busy_loop` over `_payload_header.build_date_str`,
     bracketed by `[CPNOS ...]\r\n`.  Uses SIO-B busy-wait (no init
     dependencies; SIO-B was set up by reset.s before relocator runs
     in the existing build path).  Survives a stale-PROM mismatch
     because PROM0 always has SOMETHING readable at the build-date
     slot -- the operator will see EITHER `[CPNOS <p0_date>]` then
     "PROM MISMATCH" when the verify fails, OR `[CPNOS <date>]` then
     normal boot.
   - `memcmp(&_payload_header, (struct payload_header *)0x2000,
     sizeof(struct payload_header))`.
   - On mismatch: print `PROM MISMATCH P0=<p0_date> P1=<p1_date>` to
     SIO-B AND copy a 12-char "PROM MISMATCH" string to display
     memory (mirrors existing BAD_CHECKSUM_MSG path), halt.
   - On match: proceed with existing chunk-copy + BSS-clear +
     word-sum check.

6. **Makefile:**
   - Pass `--build-date-str "$(BUILD_DATE_STR)"` to gen_payload_header.
   - Verify build passes for both compilers at each step.

## Test plan

1. Build clang -> boot -> verify SIO-B shows `[CPNOS YYYY-MM-DD
   HH:MM]\r\n` then normal banner.
2. Build SDCC -> same.
3. Deliberately mismatch: build clang then `cp clang/prom1.bin
   $(BUILDDIR)/prom1.bin` over an SDCC build, run.  Expect "PROM
   MISMATCH" on display + SIO-B; no checksum message.
4. Run `cpnos-bios-jt-trace` for both compilers -- trace
   infrastructure should still work.
5. Run `cpnos-polypascal-test COMPILER=clang` -- regression check.

## File list

- `cpnos-rom/payload_header.h` (struct)
- `cpnos-rom/tasks/scripts/gen_payload_header.py` (emit twice)
- `cpnos-rom/relocator.ld` (chunk_b shift + new section)
- `cpnos-rom/sdcc/sections.asm` (chunk_b shift + new section)
- `cpnos-rom/relocator.c` (print + memcmp + halt-on-mismatch)
- `cpnos-rom/Makefile` (--build-date-str arg)

## Estimated size

~150-200 LOC across 6 files.  3 incremental commits:
1. build_date_str field + relocator print (no dup yet, no shift).
2. dup-header section + linker script changes.
3. memcmp + mismatch halt.

## Why three commits

Each step is independently testable and reversible.  If step 2 fails
(linker section ordering), step 1's print already provides operator
visibility into which build is running -- partial benefit if step 2
needs investigation.
