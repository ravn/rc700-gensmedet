; ravn/llvm-z80#160 refined repro — pure-IR missed-narrowing.
;
; Demonstrates the residual after #158 closed the 441 B caller-bloat in #160.
; Verified 2026-05-14 with HEAD opt: -O2 / instcombine / aggressive-instcombine
; leave ALL four `icmp samesign ult i16 X, 128` ops un-narrowed when zext'd
; operands are shared across multiple xor chains (the real mc_loop shape).
; Single-use isolated cases DO narrow correctly via icmp folding.
;
; Expected narrowing: every `icmp samesign ult i16 X, 128` is a high-bit
; test on a chain provably <= 255 (xors of zext'd i8s). Equivalent to
; `icmp slt i8 trunc(X), 0`. Narrowing one sink unblocks the whole chain.
;
; Suggested fix area: extend TruncInstCombine in
; llvm/lib/Transforms/AggressiveInstCombine/TruncInstCombine.cpp to treat
; `icmp <pred> iN %x, CONST` (CONST fits in iM, predicate preserved) as a
; narrowing sink alongside the existing `trunc to iM` sink. The pass
; already does multi-sink chain narrowing for trunc; icmp is the obvious
; missing sink class.
;
; Build:
;   opt -O2 -S repro_160_icmp_narrow_missed.ll
; Confirm 4 `samesign ult i16` icmps survive un-narrowed.
;
; If the fix lands, expect them to narrow to `icmp slt i8 ...` form.

define void @many_uses(i8 %a, i8 %b, i8 %c, i8 %d, ptr %out) {
  %za = zext i8 %a to i16
  %zb = zext i8 %b to i16
  %zc = zext i8 %c to i16
  %zd = zext i8 %d to i16

  ; Many i16 ops sharing the zexts (like mc_loop):
  %xor_ab = xor i16 %za, %zb
  %xor_cd = xor i16 %zc, %zd
  %xor_ac = xor i16 %za, %zc
  %xor_bd = xor i16 %zb, %zd

  ; Many trunc+icmp uses:
  %tr_ab = trunc nuw i16 %xor_ab to i8
  %cmp_ab = icmp samesign ult i16 %xor_ab, 128
  %tr_cd = trunc nuw i16 %xor_cd to i8
  %cmp_cd = icmp samesign ult i16 %xor_cd, 128
  %tr_ac = trunc nuw i16 %xor_ac to i8
  %cmp_ac = icmp samesign ult i16 %xor_ac, 128
  %tr_bd = trunc nuw i16 %xor_bd to i8
  %cmp_bd = icmp samesign ult i16 %xor_bd, 128

  ; Use everything
  %s1 = select i1 %cmp_ab, i8 %tr_ab, i8 %tr_cd
  %s2 = select i1 %cmp_cd, i8 %tr_ac, i8 %tr_bd
  %s3 = select i1 %cmp_ac, i8 %s1, i8 %s2
  %s4 = select i1 %cmp_bd, i8 %s3, i8 %tr_ab
  store i8 %s4, ptr %out
  ret void
}
