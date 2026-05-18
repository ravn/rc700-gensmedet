# SDCC switch dead-code bug — minimal repro

Date: 2026-05-18
Toolchain: z88dk 2.4 docker image (`z88dk:2.4`), zsdcc bundled there.
Target: ravn/z88dk issue (sibling to #7 block-scope-extern).

## Source

```c
extern void a(void);
extern void b(void);
extern void c(void);
extern void d(void);

void f(unsigned char x) {
    switch (x) {
    case 0x01: a(); break;
    case 0x02: b(); break;
    case 0x03: c(); break;
    case 0x04: d(); break;
    }
}
```

## Build

```
docker run --rm -v $(pwd):/src -w /src z88dk:2.4 \
    zcc +z80 -SO3 -clib=sdcc_iy --list -compiler=sdcc \
    -Cs"--sdcccall 1" -Cs"--fomit-frame-pointer" \
    -c specc_repro.c
```

## Output (`specc_repro.c.lis`, function `_f`)

```
_f:
    0000  fe01        cp   a,0x01
    0002  ca0000      jp   Z,_a       ; live dispatch
    0005  fe02        cp   a,0x02
    0007  ca0000      jp   Z,_b
    000a  fe03        cp   a,0x03
    000c  ca0000      jp   Z,_c
    000f  d604        sub  a,0x04
    0011  ca0000      jp   Z,_d
    0014  c9          ret             ; default
    0015  c30000      jp   _a         ; <-- DEAD: 12 B unreachable
    0018  c30000      jp   _b
    001b  c30000      jp   _c
    001e  c30000      jp   _d
```

Function size 33 B, of which **12 B (36%) is dead code**.  The post-`ret`
block at offsets 0x15..0x21 is unreachable: every case-dispatch slot
already tail-calls via `jp Z,<handler>`, and the only fallthrough path
hits `ret` at 0x14.

The pattern scales linearly with the number of cases.  In a 16-case
switch (cpnos-in-c `_specc`) the dead block costs ~20 B by itself, plus
additional dead `jr <end>` bytes after each `jp` body for the cases that
needed an `l_f_NNNN:` body slot.

## Reproduction matrix

Confirmed reproduces under:
- `--sdcccall 1 --fomit-frame-pointer` (modern preferred config)
- All optimization levels tested (`-SO0`, `-SO3`)
- 4-case minimum to see the dead block (smaller switches optimize through)

Does NOT reproduce when:
- Frame pointer is enabled (function has `pop ix; ret` epilogue, so
  handlers cannot be tail-called — SDCC emits `call _x; jr <end>`)
- Cases have any local side effects beyond the tail-call

## Root cause hypothesis

SDCC's switch-lowering pass treats every case body as a basic block with
two outputs: the body code and a branch to the switch-exit label.  When
the body shrinks to a single `jp <handler>` (tail-call optimization), the
pass leaves the orphaned body block in place even though dispatch jumps
directly to the handler.  A trailing peephole could DCE these blocks
since they have no incoming edges.

## Project impact

In cpnos-in-c (current PROM1-only build):
- `_specc` (16-case switch): ~36 B dead code out of +48 B SDCC-vs-clang gap.
- Other smaller switches in `resident.c` likely contribute another 10-20 B.
- Total ravn/z88dk fix would close roughly 1/4 of the SDCC PROM1 size gap.
