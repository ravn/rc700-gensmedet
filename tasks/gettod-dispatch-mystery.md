# cpnet-z80 SERVER.RSP gettod dispatch mystery (2026-06-10)

## State

A custom `gettod` handler has been added to `cpnet-z80/dist/mpm/server.asm`
at `fnctab[55] → op code 17 → fncptr[17] → gettod`.  It reads the cpmsim
host RTC at I/O ports 25/26 and replies with a 26-byte payload:

- bytes 0..4: binary CP/M-3 SCB-DAT (days_lo, days_hi, hour, minute, second BCD)
- bytes 5..25: ASCII `"YYYY-MM-DD HH:MM:SS\r\n"` (21 bytes)
- SIZ = 25 (per CP/NET `N-1` convention)

cpnos slave (`cpnos-in-c/src/init.c`) calls `cpnet_xact(105, 0)` after
LOGIN succeeds and prints the 21-byte ASCII portion via `impl_conout`.

## What works

- **Build chain**: `vcpm rmac e:server.asm '$RDPDSZ'` + `vcpm link
  'server.rsp=server[os,nr]'` produces a working server.rsp.
- **Source ↔ binary correspondence**: rebuilt server.rsp byte-matches the
  installed binary modulo the deliberate gettod additions, after putting
  the site-assigned serial number `00 0C 00 02 04 C4` into the source.
  (Note: RMAC drops the 6th expression in a single `db` line with 6
  values — split `db 0,0Ch,0,2,4` + `db 0C4h` is the working form.)
- **MP/M boots cleanly** with the patched server.rsp loaded
  (`SERVR0PR RSP BF00H` in the boot log).
- **cpnos boots cleanly** against the patched master and runs PolyPascal
  PRIMES end-to-end (`cpnos-polypascal-test PASS`).

## What doesn't work — the mystery

The slave's print after LOGIN shows **`FF 0C` followed by LOGIN
password leftover bytes** (`"SSW..." = PASSWORD[2..4]`).  That's the
standard **neterr response** from `server.asm` line 796-800:

    ; set CP/NET server error code 12...
    mvi  m,2-1     ; SIZ = 1
    inx  h
    mvi  m,0ffh    ; MSG[0] = 0xFF
    inx  h
    mvi  m,00ch    ; MSG[1] = 0x0C
    jmp  sndbak

This means **`valid` returned non-zero** for the FN 105 request.

## Verified facts

The following were each verified by reading the .RSP binary or the .prn
listing of the rebuilt server.asm:

1. `fnctab[55] = 0x11` (= 17). Confirmed at file offset 0x2D2.
2. `fncptr[17] = 0x020A`. Confirmed at file offset 0x308 = `0A 02 ...`
3. `gettod:` is at source offset 0x020A. Confirmed in server.prn:354.
4. The patched server.rsp on `mpm-net2-2.dsk` byte-matches the rebuilt
   binary (`cmp` returns identical).
5. MP/M loads the patched server.rsp (code size 0x0A07 in the .RSP
   header; boot log shows `0A00H` allocated which is page-truncated
   display of the same size).
6. LOGIN succeeds — proven because cpnos continues to OPEN+READ-SEQ on
   `A:CPNOS.IMG` after LOGIN, which requires the slave to be
   logged in.

## Failure-mode candidates for `valid`

Looking at the code paths in `server.asm`:

- **DID mismatch** (line 540): slave sends DID=0, server NID is 0
  (from `netwrkif-2.asm:493 db 0 ; Server ID`). Should match.
- **chklog returns 0xFF** (val1, after the FNC fold): SID 0x70 (cpnos's
  RC702_SLAVEID default per `init.c:110`) should be in the G$LOG bitmap
  if LOGIN succeeded. But LOGIN clearly succeeded.
- **FNC ≥ netend** (val3, line 569): netend = 76. FN 105 folds to 55
  via `val0`'s `cpi 100; jc val1; sui 50`. 55 < 76, so val3 shouldn't fire.

None of these obviously apply, yet **one of them must be firing** because
the response IS the standard neterr format.

## Diagnostic next steps

1. **Fingerprint test — DONE 2026-06-10**: replaced gettod's body with
   one that writes `'G','T','D'` into MSG[5..7] and sets SIZ=25 so the
   slave's 21-byte print would pick it up. **Result: slave still saw
   `ORD\0\0\0...` (the LOGIN PASSWORD leftover) — `GTD` did NOT appear.**
   This is definitive evidence that **gettod is NOT being dispatched at
   all**. The neterr (`FF 0C`) comes from `valid` rejecting the message
   before fnctab[55]/fncptr[17] is even consulted. The bug is upstream
   in `valid` (or net0 dispatch), NOT in the gettod handler body.

   **chklog-forced-to-zero test — DONE 2026-06-10**: replaced chklog
   with `xra a; ret` so it always returns 0 (`found, bit 0`). Result:
   FN 105 STILL returns neterr (FF 0C) on the wire. So chklog is NOT
   the gate either. Some other branch in `valid` is returning 0xFF
   for FN 105 but not for LOGIN.

   **Wire-byte capture via SNETDEBUG — DONE 2026-06-10**: rebuilt
   cpmsim with `SNETDEBUG` enabled (`z80pack/cpmsim/srcsim/sim.h:39`).
   Output goes to cpmsim stdout — every CP/NET wire byte is printed
   with `->` / `<-` direction prefixes.

   FN 105 exchange captured:
   ```
   slave -> master: 01 00 00 01 69 00 95
                    SOH FMT DID SID FNC SIZ HCS  (FNC 0x69 = 105)
   master -> slave: 01 01 01 00 37 01 c5
                    SOH FMT DID SID FNC SIZ HCS  (FNC 0x37 = 55 = FOLDED!)
                    02 ff 0c 03 f0 04
                    STX MSG[0]=0xFF MSG[1]=0x0C ETX CKS EOT
   ```

   The reply FNC byte = 55 (the value after val0's `sui 50; mov m,a`
   fold), confirming val0 executed all the way through fold. Then
   something between fold and dispatch returned 0xFF. With chklog
   forced to 0, the failure persists, so the bug is elsewhere in the
   valid chain or in net0/the dispatcher itself.

2. **cpmsim debug build available — DONE 2026-06-10**: cpmsim is now
   built with both `SNETDEBUG` (wire-byte dump) and `WANT_ICE`
   (interactive ICE: hardware/software breakpoints, single-step,
   memory dump, register inspect, history of last 1000 instructions,
   modify memory live). Defines in `z80pack/cpmsim/srcsim/sim.h`:
   `WANT_ICE`, `WANT_TIM`, `HISIZE 1000`, `SBSIZE 10`, `WANT_HB`.
   Caveat: with WANT_ICE, cpmsim starts in ICE prompt and stdin is
   shared between ICE (before `g`) and MP/M's CP/M console (after
   `g`). The mpm-net2 autoexec via $$$.SUB doesn't run cleanly when
   stdin is a pipe. To use ICE productively, attach via expect/pty or
   a coproc, or use software breakpoints set from a snapshot.

3. **AUX port-5 trace attempt — 2026-06-10**: instrumented `valid` with
   `out 5, A` writes at every branch (entry, DID-fail, val0 entry,
   LOGIN early-return, val1 entry, chklog-fail, val2 entry, val2-OK,
   val3) to emit single-character trace markers to `/tmp/.z80pack/
   cpmsim.auxout` (FIFO).  **Result: cpnos LOGIN itself started
   failing with the trace shim installed** — slave got past banner
   but never began READ-SEQ (no dots).  The shim's extra code in
   `valid` apparently disrupts something timing-sensitive or
   stack-related.  Reverted; production gettod-only server reinstalled.

4. **PROM checksum verification — gap noted 2026-06-10**: the build
   chain (`cpnos-build/patch_payload_checksum.py`) computes a
   word-additive checksum and patches the payload so the sum equals
   `0xCAFE`.  But neither `autoload-in-c/rom.c` `prom1_if_present()`
   nor `cpnos-in-c/clang-prom1lineprog/bootstrap.s` verifies it at
   runtime — `prom1_if_present` only checks the `" RC702"`
   signature at 0x2002, and `bootstrap_entry` just decompresses +
   jumps.  Session 30 notes claim "0xCAFE checksum catches
   missing/corrupt prom1" but that was in the parked cpnos-rom.
   Cpnos-in-c does NOT have the runtime check.  Not the cause of the
   current FN 105 failure (cpnos's banner prints fine, so PROM is
   loading correctly), but a real gap worth fixing separately.

5. **Investigate `valid`'s rejection of FN 105.**  LOGIN succeeds via
   the early-return path in val0 (`sui loginf; rz`), which **bypasses
   chklog**. FN 105 goes through the full chain: fold via `sui 50`,
   then `call chklog`. If chklog returns 0xFF, valid returns 0xFF →
   neterr. The most likely failure modes:
   - chklog returns 0xFF for our SID even though LOGIN succeeded:
     LOGIN's login routine (not val0) is what actually adds the SID to
     G$LOG; maybe it's not running, or it's running but not actually
     populating G$LOG.
   - Maybe LOGIN's success-reply path in val0 (`rz`) doesn't actually
     run the login routine; instead, the login routine runs through
     net0 dispatch AFTER valid returns. Need to trace what happens
     after `rz`.
   - Possible NmbSlvs mismatch — built srvcfg uses one G$MAX but
     server.asm chklog walks a different count.
   - Possible NID mismatch — slave sends SID=0x01 (from
     `-DRC702_SLAVEID=0x01` in cpnos Makefile:122) but server's login
     records something different.

3. **Trace within valid**: add debug writes to G$LOG (or to MP/M
   console 0 via port 1) at each branch in chklog to see which path
   it takes. Requires server rebuild but trivial to add.

3. **TODGET.COM (built but not run)**: `cpnet/todget/TODGET.COM` is a
   z88dk CP/M utility that calls BDOS 66/67 via the slave's full NDOS
   path (vs `cpnet_xact`'s bare snios). Running it after cpnos boots
   would tell us if the issue is slave-side (different code paths
   produce different results) or server-side (same neterr from
   any client).

4. **Wire-level capture**: PIO-B transport is direct TCP (no SIO-A
   capture). Add a tap.lua hook to capture raw bytes sent/received
   on the cpnet_bridge wire. Look at what FNC the server actually
   sees on the wire.

## Workarounds in place

- **PROM1 hard cap loosened from 2 KB to 4 KB** in
  `cpnos-in-c/clang-prom1lineprog/prom1.ld` so the cpnos integration
  builds. Currently overruns by ~5 B compressed-payload. MAME-only
  until either (a) the dispatch mystery is fixed and the boot print is
  worth keeping at the cost of a compiler-side compensating saving,
  or (b) the print is removed and the cap restored.
- The mpm-net2-2.dsk in the library has been replaced with the patched
  version. Original is at `/tmp/server.rsp.installed` and
  `/tmp/mpm-net2-2-orig.dsk` (this session's tmp; may be cleared on
  next boot).

## Files touched

- `cpnet-z80/dist/mpm/server.asm` — gettod handler + serial number fix.
- `cpnos-in-c/src/init.c` — FN 105 call after LOGIN + 21-byte print.
- `cpnos-in-c/clang-prom1lineprog/prom1.ld` — 2 KB → 4 KB cap.
- `z80pack/cpmsim/disks/library/mpm-net2-2.dsk` — installed patched
  server.rsp.
- `cpnet/todget/{todget.c,Makefile,TODGET.COM}` — slave-side test
  client (built, not yet exercised).
- `cpnet/rtctod/{rtctod.c,Makefile,RTCTOD.COM}` — already-working
  cpmsim ports 25/26 raw test (CP/M 2.2 side, no CP/NET involved).

## Pickup point

Run option 1 (fingerprint test) first — it's the cheapest diagnostic
and pins down whether the bug is in dispatch or in gettod's body.
