# PARKED: exploit -flto better for more rcbios size savings

**Requested by user 2026-07-06** ("senere kigge på om der kan spares mere hukommelse
ved at udnytte lto bedre").

## Context
`-flto` is now ON and SAFE (link-time ASSERTs + section attrs + .cflags fingerprint
guard against the placement class that caused the 3-day FDC boot hang).  Current size:
clang **5906 B** with -flto vs 5931 B without (only −25 B realised so far).

The 25 B is small because LTO's cross-module inlining is currently constrained by the
boot/BIOS section split (boot_code/boot_data/bios_jt must stay pinned) and by the
sdcccall(1) ABI shims.  There is likely more to gain.

## Candidate levers to investigate (NOT yet tried)
1. `-flto` + `-fwhole-program-vtables` style internalisation: many BIOS helpers are
   `static` already, but cross-TU ones (bios.c <-> bios_hw_init.c) may still not be
   internalised.  Check `llvm-nm` for externally-visible symbols that could be `static`.
2. LTO could merge the many tiny `bios_*_shim` wrappers (bios_shims.s) if they were C
   instead of asm — but they need exact register translation, so measure first.
3. `-Oz` is set; try per-function `optnone`/`minsize` audit on the largest functions
   (_specc, _rwoper, _bg_clear_from) to see if LTO+inlining changes their shape.
4. Identity/duplicate function folding (`--icf=all` on ld.lld) — safe for a ROM image?
   Measure; ICF can merge byte-identical functions.  Verify boot after.

## Guardrails when doing this work
- Every experiment MUST pass the link-time ASSERTs (they now exist) AND `make mame-test`
  on a CLEAN build (the .cflags fingerprint makes incremental safe, but verify).
- Follow `feedback_no_op_control_measurement` + `feedback_revalidate_historical_compiler_claims`.
- BIOS is disk-resident (NOT PROM-capped), so size here is lower-priority than autoload/
  cpnos PROM budgets — weigh effort accordingly.
