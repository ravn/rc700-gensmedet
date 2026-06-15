# rcbios: apply `__sfr __at` port-IO idiom (SDCC BIOS)

Date: 2026-05-19
Status: **CLOSED 2026-05-19** — already implemented.  Task was filed
without first reading `rcbios-in-c/hal.h`, which has been using
`__sfr __at` for SDCC since long before session 73k.  See lines
117-124 of that file:

```c
#elif defined(__SDCC) || defined(__SCCZ80)
#define DEFPORT(name, addr) __sfr __at (addr) _sfr_##name;
#define port_in(name)       (_sfr_##name)
#define port_out(name, val) (_sfr_##name = (val))
```

`check_no_helper_calls.py` confirms zero `__port_in` / `__port_out`
helper calls in the SDCC BIOS link output.  The 166 B SDCC-vs-clang
size gap on rcbios BIOS is therefore NOT from port-IO indirection;
it lives somewhere else (regalloc, jumptable, IX-frame -- the same
class of gaps cpnos has, tracked in cpnos-in-c/tasks/
sdcc-codegen-gap-2026-05-18.md and ravn/z88dk#8, #10).

The original ravn/z88dk#9 close ("just use __sfr") was the right
call for cpnos because cpnos was the outlier -- rcbios was already
following the pattern.

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
