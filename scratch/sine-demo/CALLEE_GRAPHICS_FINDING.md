# RC700 graphics: does __STDC_ABI_ONLY / callee routing fix llvmz80? — NO (2026-08-07)

## Question
Now that ravn/llvm-z80 clang has the fixed z88dk calling conventions (cc133 =
z80_smallc + z80_callee, #282), is the `__STDC_ABI_ONLY` gate in
`z88dk/include/graphics.h` still needed for RC700 graphics — i.e. does routing
llvmz80 to the native `*_callee` graphics workers make the demo render
correctly?

## Change tried (uncommitted, working tree only)
`z88dk/include/graphics.h`: derive `__GFX_NO_CALLEE_ABI` =
`__STDC_ABI_ONLY && !__LLVMZ80`, and gate the 27 `_callee` redirects on it, so
llvmz80 (which otherwise self-defines `__STDC_ABI_ONLY` via any clang) is routed
to the `_callee` graphics variants like sccz80/sdcc. Regression-free by
construction: only llvmz80 flips; sccz80 and ez80-clang byte-identical.

## Empirical result — VERIFIED in MAME (rc702), same gfxtest.c
gfxtest.c draws: circle + 2 straight diagonals + dotted horizontal midline.

- **sccz80 (reference, routes to _callee):** CORRECT full picture.
  -> snap/gfxtest-sccz80.png
- **llvmz80 + callee routing (this change):** WRONG — two distorted CURVES,
  no circle, no dotted line. -> snap/gfxtest-llvmz80.png
- **llvmz80 without callee (prior/plain smallc):** WRONG — a single straight
  diagonal only. -> snap/gfxtest.png (older reference)

## Conclusion
Callee routing does NOT fix the demo. It changes one wrong render into a
different wrong render. **The graphics.h change is not validated as a fix.**

Crucially, sccz80 uses the SAME `_callee` clib workers and renders correctly, so
the callee ABI / clib workers are fine. The residual bug is llvmz80-specific:
either llvmz80's `z80_callee` call-site lowering does not match what the clib
`*_callee` worker expects, or llvmz80 miscompiles main()'s coordinate math.
A straight `draw()` rendering as a CURVE points at corrupted arguments /
coordinate arithmetic, not at the disk or the emulator. Root cause NOT yet
confirmed — file as a separate llvmz80 codegen investigation, do not claim fixed.

## ROOT CAUSE CONFIRMED (2026-08-07) — 16-bit return not read from HL
User hypothesis: "looks like a scaling error, e.g. screen resolution reported
wrong." VERIFIED with a probe (gfxdims.c: print getmaxx()/getmaxy()):

- **sccz80:  W=159 H=74**   (correct — RC700 graphics is 160x75)
- **llvmz80: W=-13372 H=-13372**  (garbage; -13372 = 0xCC64, IDENTICAL for both)

The identical value for two DIFFERENT functions is the smoking gun: llvmz80 does
not read the actual HL result of these classic-clib functions. getmaxx returns
159 in HL but leaves DE untouched; llvmz80 reads its return from DE (= stale
0xCC64); getmaxy then returns 74 in HL, still leaves DE = 0xCC64, so llvmz80
reads 0xCC64 again -> both print -13372.

This is the HL->DE 16-bit-return mismatch: clang's default sdcccall(1) expects a
16-bit int return in a register the classic clib doesn't use (clib returns in
HL), and the __ZPROTO/HL->DE return bridge (CLAUDE.md) is NOT applied to these
plain `extern int __LIB__ getmaxx(void)` declarations (graphics.h:343-344).
Under llvmz80 `__LIB__` expands to nothing (sys/compiler.h:34), so nothing
bridges the return register.

NOTE: this bug is INDEPENDENT of the callee routing — getmaxx/getmaxy are not
callee-gated at all. It is a general classic-clib return-value-register bug for
value-returning graphics (and likely other __LIB__ int-returning) functions
under llvmz80. Because w/h come back garbage, every downstream coordinate
(cx,cy,r, the draw endpoints, the plot midline) is garbage -> the distorted
render.

REGISTER DIRECTION NOW BYTE-VERIFIED: clang leaves AND reads a 16-bit int in
**DE** (`int f(){return 159;}` -> `ld de,159; ret`; `w=getmaxx()` ->
`call getmaxx; ex de,hl; ld (_w),hl`), while the clib worker returns in **HL**
(getmaxx @0x16F4: `ld a,(console_w); add a; dec a; ld l,a; ld h,0; ret`). Linked
call site in main @0x04A9: `call getmaxx; ld (0x1FBE),de` — stores DE (garbage).
So clang's z80 CC is self-consistent (int arg in HL, int return in DE); the
mismatch is purely at the clang -> classic-clib(HL) boundary. `__smallc` is NOT
the fix (verified: still -13372; z80_smallc only changes arg passing).

Fix belongs in the header/bridge layer (apply the HL->DE return bridge, as the
stdio/fcntl family does, to value-returning __LIB__ classic graphics
prototypes: getmaxx/getmaxy/getx/gety), NOT in the graphics.h callee gate.

FILED: ravn/z88dk#50 (recurring HL->DE return-register class; cf closed
#23/#26/#31/#41 — graphics library was missed by the #26 sweep).

## Build/run recipe (now in scratch/sine-demo/Makefile)
- Compile: `zcc +cpm -subtype=rc700 [-compiler=llvmz80]` (llvmz80 needs a
  `llvmz80-clang` symlink -> llvm-z80/build-macos/bin/clang on PATH).
- Package for MAME: cpmcp-inject the .com onto a COPY of a real RC702 system
  disk: `cp SW1711-I8.imd out.imd; cpmcp -f rc702-8dd out.imd app.com 0:GFXTEST.COM`.
  Do NOT use `appmake +cpmdisk -f rc700-8dd/-jbox --container imd` — those
  images give "Bdos Err On B: Bad Sector" in MAME's rc702 FDC.
- Run: `regnecentralend rc702 -rompath mame/roms -flop1 <sysdisk> -flop2 <out.imd>
  -autoboot_script gfxtest_run.lua -snapshot_directory snap -seconds_to_run 120`.

## RESOLUTION (verified end-to-end)

The fix is the **minimal 4-line return-register bridge** in `z88dk/include/graphics.h`,
using the EXISTING `__z88dk_fastcall` attribute (no new attribute):

    extern int __LIB__ getx(void)    __z88dk_fastcall;
    extern int __LIB__ gety(void)    __z88dk_fastcall;
    extern int __LIB__ getmaxx(void) __z88dk_fastcall;
    extern int __LIB__ getmaxy(void) __z88dk_fastcall;

`__z88dk_fastcall` → `__attribute__((z80_fastcall))` under clang: a 16-bit int
return lands in **HL**, matching the classic clib worker. Verified via clang `-S`
(`ld (_w),hl`, no `ex de,hl`) and MAME render (`W=159 H=74`).

### The earlier callee-routing change was REVERTED
The `__STDC_ABI_ONLY`→`__GFX_NO_CALLEE_ABI` gate rewrite (routing llvmz80 to the
`*_callee` graphics primitives) did NOT fix the bug and was dropped. It also
INTRODUCED a cosmetic regression: `circle_callee` rounds slightly differently from
the portable `circle`, so the llvmz80 circle was ~1 graphics-pixel larger in radius
(top row y=13 vs y=17 in the 590px snapshot). This was NOT a coordinate rounding
error — `getmaxx/getmaxy` returned identical 159/74 both ways; only the drawing
worker differed.

With callee routing reverted (minimal fastcall fix only), llvmz80 vs sccz80 renders
are **byte-identical**: 7231 == 7231 on-pixels, 0-pixel diff. Snapshot:
`snap/gfxtest-llvmz80-noncallee.png` vs `snap/gfxtest-sccz80.png`.
