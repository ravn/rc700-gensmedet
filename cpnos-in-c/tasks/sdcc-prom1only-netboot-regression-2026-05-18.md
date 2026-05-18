# SDCC PROM1-only netboot regression — banner shows but no dots

Date: 2026-05-18
Status: open; pre-existing on `main` (predates 2026-05-18 work)

## Symptom

SDCC PROM1-only line program boots to banner display ("RC702 CP/NOS 55K PIO
sdcc <timestamp> <hash>+") with cursor on row 1, then hangs.  No netboot
"." dots ever appear.  SIO-B mirror is empty (siob.raw 0 B) — including
the banner that DID render to the CRT.

Same MP/M, same disk, same autoload PROM0.  clang PROM1-only with
identical setup runs to E> in 51.45 s (cpnos-polypascal-test PASS).

## Failure surface

```
cpnos-polypascal-test stage 1 timeout (E> never appears):
  [ 12.00s] === stage 1 (deadline 30s): wait for E> on SIO-B; type WS launch
  [ 42.01s] FAIL: timeout waiting for E> boot prompt
```

Screen capture at 30 s shows banner only, cursor at (col 0, row 1), no
netboot dots.  Slave appears alive (no spinning patterns / CRT mis-init)
but stalled in early netboot.

## Hypothesis (likely hang site)

Banner ran → `print_banner()` returned → `netboot_mpm()` entered.  First
thing `netboot_mpm()` does is `snios_ntwkin()`, which sends a CP/NET
INIT frame on PIO-B and waits for ACK.  No dots = stuck before the first
`impl_conout('.')` (= before first successful `cpnet_xact` READ).

Three candidate hang points (in increasing depth):
1. `snios_ntwkin()` — SNIOS arm + INIT frame send, wait for master ACK.
2. `cpnet_xact(64, 7)` — LOGIN frame send/recv.
3. `cpnet_xact(15, 36)` — OPEN A:CPNOS.IMG send/recv.

`BOOT_MARK` markers in init.c lines 430-445 would pinpoint which step
failed, but the build runs with `-DBOOT_MARK_ENABLED=0` (no visible
trace).  Re-enabling BOOT_MARK temporarily would localize the hang at
column 8 ('N' = entered netboot_mpm), 9 ('I' = NTWKIN ok), 10 ('L' =
LOGIN ok), 11 ('O' = OPEN ok), or 12 ('R' = first READ ok).

## Pre-existing on main (NOT introduced by 2026-05-18 work)

A/B stash test confirmed the regression predates today's IO_WRITE
(`__sfr`) rewrite:

```
git stash push -m io_write_changes src/*.c src/hal.h
rm -f sdcc/*.o sdcc/cpnos_lp*.bin sdcc-prom1lineprog/prom1-lineprog.bin
COMPILER=sdcc TRANSPORT=pio-irq make cpnos-polypascal-test
  -> FAIL: timeout waiting for E> boot prompt   (same symptom)
```

So the regression sits between session 73j-end (commit d674186, where
SDCC PROM1-only PASSed in 49.81 s) and the current HEAD (8226708, the
post-merge state).

## Bisect candidates

Commits between d674186..8226708 on main:

```
8226708 Merge branch 'locale_tables_v3': session 73j (locale tables + PROM1-only parity)
a6b8948 cpnos: drop misleading __stack_top emit from cpnos_layout.asm
d674186 session 73j-end wrap: SDCC PROM1-only at functional parity with clang  (LAST KNOWN PASS)
```

Only one intermediate commit (a6b8948) plus the merge.  a6b8948 dropped
the `__stack_top` symbol — supposedly only broke the parked two-PROM
SDCC build per its own commit message ("smoke-tested: clang and SDCC
PROM1-only both still boot to E>").  Worth verifying by checking out
a6b8948 and re-running.

If a6b8948 reproduces, regression came in with the merge (8226708) —
review what `locale_tables_v3` carried in that wasn't on main at d674186.

## Reproduction

```sh
cd cpnos-in-c
make _kill-mpm; sleep 6
rm -f sdcc/*.o sdcc/cpnos_lp*.bin sdcc-prom1lineprog/prom1-lineprog.bin
COMPILER=sdcc TRANSPORT=pio-irq make cpnos-polypascal-test
```

Failure is deterministic — every run times out at stage 1 after ~42 s
with the same screen state.

## Next steps

1. Enable `BOOT_MARK_ENABLED=1` for a single diagnostic build to pinpoint
   the stall column (one-line make-flag override).
2. `git bisect` between d674186 and 8226708 (3 commits — likely a single
   step).
3. If a6b8948 is the bisect culprit, restore `__stack_top` or move SP
   setup into reset.asm directly per the parked-two-PROM workaround
   note in that commit's message.
4. Once the regression is fixed, re-run `cpnos-polypascal-test` for both
   compilers and update the CLAUDE.md size table with the post-fix
   SDCC PROM1-only payload size.

## Not blocking

clang PROM1-only is the production target (per
[project_cpnos_clang_only.md]).  SDCC PROM1-only is a parity build kept
for compiler-comparison purposes.  Regression isn't a release blocker;
record-keeping + bisect when time permits.
