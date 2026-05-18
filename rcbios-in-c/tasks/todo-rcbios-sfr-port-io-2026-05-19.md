# rcbios: apply `__sfr __at` port-IO idiom (SDCC BIOS)

Date: 2026-05-19
Status: open; concrete-win follow-up from session 73k.

## Opportunity

Today's session landed `__sfr __at N port_name` in `cpnos-in-c`
(commit `754b901`) and closed ravn/z88dk#9.  Result: every
compile-time-constant `OUT (n),a` / `IN A,(n)` site became a 2-byte
direct instruction instead of a 7-byte indirect call.  SDCC cpnos
PROM1-only resident dropped 76 B raw (-39 B post-ZX0).

rcbios-in-c uses the same z88dk-SDCC build path with the same
indirect-helper pattern via `port_in()` / `port_out()` macros in
`hal.h`.  Looking at the SDCC BIOS size:

  ```
  $ make -C rcbios-in-c bios COMPILER=sdcc
  sdcc BIOS: 6091 bytes
  ```

  vs clang:

  ```
  $ make -C rcbios-in-c bios COMPILER=clang
  clang BIOS: 5925 bytes
  ```

166 B gap.  Some unknown fraction is port-IO indirection.  Worth
auditing.

## Concrete steps

1. **Inventory port-IO sites.**  Grep `rcbios-in-c/{bios,bios_hw_init,boot_*}.c`
   for `port_in(` / `port_out(` calls; count by port name + arg
   type (compile-time-constant port vs runtime-variable).

2. **Define `__sfr __at` variables in `rcbios-in-c/hal.h`** for the
   ports actually used at compile-time-constant sites.  Pattern from
   `cpnos-in-c/src/hal.h` post-754b901.

3. **Migrate call sites** to the new `IO_WRITE(NAME, v)` /
   `IO_READ(NAME)` macros (or whichever naming rcbios prefers --
   the `port_in`/`port_out` macros can be redefined inline if
   easier).

4. **Verify codegen.**  Audit `sdcc/audit/*.s` (or whatever rcbios's
   equivalent is) for zero `call __port_in` / `call __port_out`
   sites post-migration.  Same check cpnos does.

5. **Re-measure SDCC BIOS size.**  Document the delta in
   `tasks/timeline.md` and update `CLAUDE.md`'s size table if the
   sdcc-vs-clang gap moves.

## Why this matters

rcbios's SDCC BIOS is currently 166 B larger than clang's.  Most of
that gap probably isn't port-IO -- but the port-IO is the easiest
low-risk shrink and the pattern is already proven in cpnos.

Also keeps the two slave-side codebases in stylistic sync: same
`hal.h` shape, same `__sfr` block, same `_Static_assert` matching
the literal port numbers to the `PORT_*` enum.

## Not blocking

rcbios + SNIOS PIO already works end-to-end (commit `86ab3b8`).
Size shrink is opportunistic.

## See also

- `cpnos-in-c/src/hal.h` (post-754b901): canonical `__sfr __at` pattern.
- `cpnos-in-c/tasks/sdcc-codegen-gap-2026-05-18.md`: the codegen-gap
  analysis that motivated cpnos's migration.
- ravn/z88dk#9 (closed): "Feature: inline port-IO intrinsic" --
  resolved via `__sfr`.
