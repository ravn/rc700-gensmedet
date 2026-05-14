# Session state — 2026-05-14 (pre-reboot)

Saving where we left off before the user reboots.

## What landed this session

All committed; see `git log` in submodule:

1. `2572e5f` — corpus + harness, behavioural verification, ABI-mismatch bug caught
2. `b6d3ef0` — smallest-code flag audit (clang `-Oz`, zsdcc `--opt-code-size`)
3. `af5a0be` — swap `mul_8x8` → `mod_10/mod_7` + "why is clang better" writeup
4. `2213e5b` — sdcccall-1 shim helper PoC (later reverted in favour of zcc-native config)
5. `6d4677d` — align with cpnos-rom production zcc flags + dual volatile/non-volatile builds
6. `34749d2` — research note: four documented paths to `--sdcccall 1`
7. `3d41da9` — comparison of `__z88dk_fastcall` / `__z88dk_callee` / `__sdcccall(1)`
8. `650a27f` — production cpnos-rom build-time helper-call guard
9. `30b4562` — extend guard to rcbios-in-c/sdcc build
10. `3905f06` — survey correction: vbcc has NO Z80 backend (was AI hallucination)

Parent-repo bump commits mirror each.

## What's pending uncommitted (will be in next commit)

`tasks/sccz80-oracle-corpus/Makefile`:
- ACK Docker macro + `.PHONY` ack/ack_vol entries.
- **Scaffold only — no `ack:` / `ack_vol:` targets defined yet.** Safe
  to commit; doesn't break existing targets.

## Why ACK never got verified this session

User asked to add ACK as a 4th oracle compiler. Discovered en route:

- ACK has NO Z80 backend. Its `mach/` includes `i80` (Intel 8080) but
  no `z80`. The `cpm` platform compiles to i8080. Z80 executes i8080
  instructions natively (strict superset), so ACK output would run —
  but cannot use any Z80-specific instructions (DJNZ, JR, EX, EXX,
  IX/IY, BIT/SET/RES, LDIR, undocumented). Structurally provably
  worse than any Z80-aware compiler on patterns that use those.

- Tried `docker pull bensuperpc/ack`. Pull hung for 19 minutes,
  failed (`error during connect: ... EOF`). User restarted Docker.
  Retry pull also failed (`Cannot connect to the Docker daemon`).
  User now reboots.

## Where to resume

If continuing the ACK measurement is still wanted:

1. After reboot, verify Docker daemon is up: `docker info` should
   return cleanly without "Cannot connect".
2. Retry: `docker pull bensuperpc/ack:latest`. If it hangs, try
   pulling a specific version tag: `bensuperpc/ack:20211012-c71c689`
   (older but should be smaller; full tag list at
   hub.docker.com/v2/repositories/bensuperpc/ack/tags).
3. Smoke test: `docker run --rm -v $PWD:/work -w /work
   bensuperpc/ack ack -mcpm -c /work/corpus.c -o /work/corpus.o`
   (exact invocation TBD; check the image's documentation /
   entrypoint first via `docker run --rm bensuperpc/ack`).
4. Add `ack:` and `ack_vol:` targets to the Makefile mirroring the
   sccz80 / clang pattern. Compile output is `.com` (CP/M binary at
   ORG 0x0100). Run in `z88dk-ticks` with `-pc 0x100 -l 0x100`.
5. Document the i8080-vs-Z80 caveat in `findings-2026-05-13.md`'s
   next "update" section.

If skipping (recommended in last conversation turn — i8080 floor
measurement is structurally predetermined to be worst, low marginal
oracle value): revert the Makefile diff, no further action needed.

## Other open items from this session

- The SDCC volatile-store-merging finding (zsdcc and sccz80 both
  merge 4 adjacent byte writes into 2 × `ld (addr), hl` for
  `volatile uint8_t bss_buf[]` under `seq_bss`) is potentially a
  real C-abstract-machine violation. Worth filing upstream if SDCC
  engagement deepens. Not actioned this session.

- ZX Spectrum community survey confirmed: z88dk (zsdcc primary,
  sccz80 for size-tight) is the standard. Nothing missed. Sccz80's
  whole-program advantage (per z88dk's own benchmark table) comes
  from hand-tuned asm library amortization, not from compiler
  codegen — orthogonal to cpnos-rom's PROM use case (no libc).

## Survey corrections logged

Two previously-confident claims retracted:

- vbcc has Z80 backend → FALSE, no Z80 backend exists (commit 3905f06).
- ACK has Z80 backend → FALSE, only i8080 backend (this doc).

Both were AI-hallucinations from WebSearch summaries that propagated
without source verification. Lesson logged in commit messages; in
future, verify CPU/target claims against the source tree
(machines/, mach/ directories) before listing them.

## Production state at session end

- cpnos-rom: clang + SDCC builds both pass new `check_no_helper_calls.py`
  gate. Production sizes unchanged (1928 B clang resident /
  ~2068 B SDCC).
- rcbios-in-c: SDCC build also passes the gate. BIOS = 6091 B at HEAD.
- All four cells of the cpnos-rom test matrix (compiler × transport)
  still PASS at HEAD (verified before the helper-guard work landed;
  guard does not modify behaviour).

Nothing in flight that requires a restart-recovery step beyond
"docker daemon back up".
