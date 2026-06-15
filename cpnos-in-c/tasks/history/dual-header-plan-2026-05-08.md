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

## Follow-ups added 2026-05-08

### Move screen init before PROM check (operator visibility)

Today's relocator stamps "PROM MISMATCH" / "BAD CHECKSUM" /
build_date_str into display memory at 0xF800 and relies on the 8275
CRT controller being in its hardware-reset state with a default
refresh program that drives display memory visibly.  Empirically
that works on MAME and on the bench, but it's not guaranteed by the
datasheet -- if a future hardware variant needs explicit init or
the 8275 latches into a non-display state on power-on, the
relocator's status messages would be invisible and the operator
would see a black screen for both the success and failure paths.

Action: move the 8275 control-port + DMA-channel + clock-gate
sequence (currently inside init_hardware in the resident, runs
post-handoff) up into the relocator, BEFORE the dual-header
memcmp.  The whole point of the dual-header check is operator
visibility into a stale-PROM mismatch BEFORE the relocator does
anything destructive; the check is only useful if the message
reaches the operator -- relying on CRT default state is the weak
link.

Cost: ~30-50 bytes in PROM0 (currently 640 B reservation with
~50 B headroom after step 2+3).  May require bumping `.prom0_init`
from 0x280 again if headroom runs out -- shrinks init slot
correspondingly.  Init.bin is currently 630 B in the 640 B slot
(10 B headroom), so the next bump probably requires a parallel
init-code shrink.

Recorded by user 2026-05-08 evening.

**Status: DONE 2026-05-08 18:11.**  Implemented as a 30 B port-init
table (`reloc_display_init[]`) + ~10 B inline-asm OUT-loop in
relocator.c, runs as the very first thing in `relocate()` after
the magic check.  Sequence: 8237 DMA ch2 setup (master clear, ch2
mode mem->IO autoinit, base/wc pointing at 0xF800 for 2000 bytes,
unmask), then 8275 CRT (reset, 4 geometry params for 80x25/7-scan,
enable interrupts, start command 0x23).  No CTC -- relocator runs
DI and never refreshes via ISR; the 8275 is self-clocked and
maintains a static-content display through DMA autoinit.

Slot bumps required to fit:
  .prom0_init  0x280 -> 0x2A0  (+32 B for relocator code)
  .prom0_tail  0x500 -> 0x520  (+32 B in lockstep, init slot stays 640 B)
  PROM0_TAIL_SIZE  768  -> 736 (clang only; PROM1 absorbs the 32 B)

The C-side for-loop with `_port_out(uint16_t, uint8_t)` lowered to
~90 B on clang Z80 (relocator builds without +static-stack, so
locals spill to stack via `push hl; ld hl,N; add hl,sp; ...`
pattern -- same root cause as task #27).  Inline asm is ~10 B.
Updated check_no_frame_ptr.py baseline to reflect.
