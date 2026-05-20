# ravn/z88dk#5 root cause analysis — session 73l

The original issue described the bug as "writes through a late-assigned
absolute-address pointer are dropped after a struct-arg call."  Deep
trace analysis (`z88dk-ticks -trace`) refutes that diagnosis.  The writes
happen correctly; a SUBSEQUENT call clobbers the memory.

## Trace evidence

K&R + `-Cs"--sdcccall 1" -Cs"--nogcse"` build of
`repro_nogcse_late_r.c + aes256.c`.  All PC addresses from the linked
binary disassembly.

1. **Main's encrypt-store loop runs correctly.**  PC=0x01EA
   (`ld (hl), a` opcode 0x77) executes 16 times with HL = $C000+i and
   A = AES cipher byte.  16 stores hit $C000..$C00F with the correct
   cipher (`8e a2 b7 ca 51 67 45 bf ea fc 49 90 4b 49 60 89`).
2. **r[16] = enc_ok succeeds.**  PC=0x021E writes 0x01 to $C010.
3. **Decrypt-store loop runs correctly.**  PC=0x0258 writes plaintext
   bytes to $C011..$C020.
4. **r[33] = dec_ok succeeds.**  PC=0x0283 writes 0x01 to $C021.
5. **Main then calls `aes_done(&ctx)` at PC=0x0289**:
   ```
   ld (hl), d       ; r[33] write
   push bc          ; save BC (which still holds 0xC000 = main's `r`)
   ld hl, $0002
   add hl, sp       ; HL = &ctx (the local struct)
   call $0ce0       ; aes_done
   ```
   Under `--sdcccall 1`, the single pointer arg should be in HL.  Main
   correctly sets HL = $FF6A (= address of main's local `ctx` struct).
6. **Inside `aes_done` body (entry at $0CE0), the function uses BC as
   the ctx base address, NOT HL.**  At entry, BC still holds $C000
   (the value of main's `r` variable, which the compiler kept in BC
   across the encrypt loop and never overwrote because none of main's
   subsequent code touched BC).
7. **`aes_done`'s zero-init loop at PC=0x0D2A fires 32 times** with
   HL = BC + i = $C000+i for i = 0..31, zeroing $C000..$C01F.  Trace
   shows all 32 executions of the `ld (hl), $00` opcode (0x36 with
   immediate 0x00).  This clobbers the cipher and decrypt plaintext
   main just wrote.

## Why `--sdcccall 0` masks the bug

Under stack-arg ABI, `aes_done`'s body reads ctx from `(ix+d)` via the
saved stack frame, not from a register.  BC's leftover value doesn't
matter; the function gets the right ctx pointer.  Cross-product
diagnostic (`diagnostic_sweep.sh` configs 03 vs 04) confirms: K&R +
`--nogcse + --sdcccall 0` PASSes.

## Why `--nogcse` is necessary to trigger

Under default GCSE, the address `0xC000` gets folded directly into
address-arithmetic expressions in main, and `r` does NOT survive as a
register-resident value.  Main's encrypt-store loop uses
`ld (bc), a` with C = loop counter and B = 0xC0 (constant), so BC
gets overwritten per iteration with `(0xC0, i)`.  When main calls
`aes_done`, BC holds something other than $C000 — but more importantly,
`aes_done`'s wrong-register read picks up a value that no longer
aliases the cipher region.

With `--nogcse`, the constant `0xC000` is kept as a 16-bit value in
BC across the loop body (using IX-relative spill of the recomputed
address for each store), and BC retains $C000 at the point of
`aes_done`'s call.  The callee miscompile then aliases its ctx onto
$C000.

## Why ANY structural change to main() fixes the symptom

Adding another store / call / variable use in main shifts the register
allocation of `r`.  If `r` doesn't live in BC at the moment of
`aes_done`'s call, the callee miscompile aliases its ctx onto a
different (harmless) address.  The cipher area is untouched.  This
explains why the bug was reported as "fragile to any change" — the
fragility is in WHERE BC happens to be at the call site, not in the
store loop itself.

## Root cause hypothesis

SDCC's `--sdcccall 1` parameter-passing handling under K&R + `--nogcse`
disagrees between caller and callee on which register holds the first
pointer argument.

- **Caller side** (main): correctly passes &ctx in HL.
- **Callee side** (aes_done's body): reads ctx from BC.

This is either:
- A miscompile of the callee's prologue (should move HL → BC, but
  doesn't emit the move).
- A code-gen mode mismatch where the callee is compiled as if `aes_done`
  used the stack-args ABI but with a register-args entry sequence.
- A peephole-pass-removed `ld c, l; ld b, h` move that should be at
  the function entry.

The bug fires in `aes_done` AND likely in the second `aes256_init`
call (also called after r is set) — that one zeros 96 bytes
(`ctx->key`, `ctx->enckey`, `ctx->deckey` ranges) at $C000+ if BC has
$C000.

## Reproducible repro

Source: this directory's `repro_nogcse_late_r.c` + `aes256.c`.
Build with K&R + `-Cs"--sdcccall 1" -Cs"--nogcse"`.  Output: $C000
reads all zeros at end of execution despite trace evidence that
correct cipher was written there mid-execution.

## Cluster reframe

#5 was filed as "drops writes through late-assigned pointer."  The
correct title is closer to "callee-side register-convention bug:
function reads its pointer arg from BC instead of HL."  Same trigger
class as #14 (K&R int-promotion penalty under --sdcccall 1) and same
root pass family (`--sdcccall 1` parameter-handling iCode allocation).
A single fix in the SDCC pass that handles `--sdcccall 1` parameter
receipt on K&R-prototyped functions likely closes both.
