# cpnos PROM1-only: consolidate init+payload into one ZX0 chunk

**Status:** DEFERRED with measurement (session 73j-late).

## User's idea

"Can the init code be placed just before the payload so there is just
one chunk to move? ... and overwritten when done?"

Architecturally yes -- init code is one-shot (NORETURN cpnos_cold_entry,
runs once at cold boot then JPs into NDOS).  Putting init at the BSS
addresses (0xEA00..0xECFF) lets BSS overwrite init bytes after init
completes, with no actual conflict at runtime.

## Blocker: PIO ring vs live init code

`pio_rx_buf` (256 B at 0xEC00, page-aligned for `ld h,page; ld l,head`
ISR trick) becomes IRQ-written from `enable_interrupts()` onward.
That call lives INSIDE init (cpnos_cold_entry runs it before
print_banner + netboot_mpm); subsequent IRQs scribble bytes into
0xEC00..0xECFF while init code is still executing there.

Three resolution paths (asked the user, deferred):

  A. **Move pio_rx_buf into resident (drop page alignment).**  Park
     at e.g. 0xF200..0xF2FF inside the 2190 B resident chain.  ISR
     drops `ld h,page; ld l,head` for `ld hl,base; ld a,head; ld l,a`
     -- ~5 B more, ~10 T-states/byte slower in the PIO RX hot path.
  B. **Park pio_rx_buf in low TPA, reused after handoff.**  Put
     ring at 0x0100..0x01FF during netboot; once netboot completes
     and CCP starts, relocate ring to a permanent address.  Two
     lifetimes; complex.
  C. **Defer enable_interrupts() until resident_handoff.**  Netboot
     uses POLLED `transport_pio_recv_byte` (loops on PIO ready
     flag) instead of IRQ-driven.  ~5x slower per byte but netboot
     is short.  Init code at 0xEC00 stays safe.  Cleanest
     architecturally.

## Concrete byte saving

Measured by concatenating the existing SDCC PROM1-only build's
INIT_CODE.bin + RESIDENT_JUMPTABLE.bin and ZX0-compressing as one
stream:

  | Layout       | Compressed |
  |--------------|------------|
  | Two streams  | 562 + 1552 = 2114 B |
  | One stream   | 2084 B (-30 B from dictionary sharing) |
  | Bootstrap delta | -9 B (one fewer `ld hl/ld de/call dzx0` triple) |
  | **Total saving** | **~39 B** |

Impact on the two PROM1-only builds:

  * **clang PROM1-only:** 2027 -> 1988 B / 2048 B (21 -> 60 B free).
    Triples headroom; nice but not load-bearing.
  * **SDCC PROM1-only:** 2216 -> 2177 B (still 129 B over 2 KB).
    Closes 23% of the gap; doesn't cross the line.

## Cost vs benefit

The ~39 B saving is ~2% of image size.  Doesn't on its own get SDCC
under 2 KB, doesn't break a hard constraint for clang.  Implementation
cost: one of the three pio_rx_buf relocations above + linker-script
surgery + retesting both builds.  Estimate: ~half a day to a day.

User direction this session: "leave it in two chunks for now".

## Cross-references

  * `clang-prom1lineprog/payload.ld` -- current INIT MEMORY at 0xC000.
  * `sdcc-prom1lineprog/sections.asm` -- INIT_CODE at 0xC000, BSS
    pages 0xEA00 / 0xEB00 / 0xEC00.
  * `sdcc-prom1lineprog/bootstrap.asm` -- two `call _dzx0_standard`
    invocations; would collapse to one.
  * `src/transport_pio.c` -- ISR uses `ld h, _pio_rx_buf_page` which
    becomes `ld hl, _pio_rx_buf` if page alignment is dropped.
