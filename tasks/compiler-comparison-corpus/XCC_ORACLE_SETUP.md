# xcc as a 5th corpus oracle — setup & build recipe

`xcc` (the XYZ Suite Z80 C compiler, [retro-vault/xyz](https://github.com/retro-vault/xyz))
is an **independent** SDCC-ABI Z80 C toolchain (compiler `xcc`, assembler `xas`,
linker `xld`, plus `xar`/`xopt`/`xgdb`/`xemu`). It emits real **CP/M `.COM`**
programs, which makes it a natural competing-backend baseline alongside
llvm-z80, zsdcc, dcc, and the llvmz80 z88dk-bridge.

Status: **evaluation**. Not yet a git submodule (deliberately, per user
2026-07-06 — "vent med submodul"). This doc + `setup_xcc.sh` are the
reproducible "get it in the air" steps until we decide to vendor it.

## 1. Install (prebuilt release, no from-source build)

```sh
./setup_xcc.sh                 # latest release, L model, auto OS (macos/linux)
XCC_MODEL=m ./setup_xcc.sh     # smaller libc (s|m|l; l = full stdio, the default)
XCC_TAG=v1.9.4 ./setup_xcc.sh  # pin a release tag
XCC_DIR=/path ./setup_xcc.sh   # choose the install parent (default /Users/ravn/z80/xyz-eval)
```

Requires an authenticated `gh` and `unzip`. It downloads `x-<model>-<os>.zip`
from the `retro-vault/xyz` releases and stages a stable symlink:

```
$XCC_DIR/xcc-current -> $XCC_DIR/x-<model>/x-<model>-<os>/
```

The prefix is self-contained and relocatable (tools find their headers/libs
relative to their own location). The **L (large)** model ships full `printf`/
`stdio`; S/M shrink the libc float/format surface (`X_MODEL` upstream).

Verify:

```sh
$XCC_DIR/xcc-current/bin/xcc --version   # -> xcc 1.9.4 (X Tools C Compiler for Z80)
```

## 2. Build a CP/M `.COM` from a corpus benchmark

Like the dcc lane, xcc uses a **single translation unit**: the bench source
concatenated with the CP/M harness `dcc_test_main.c` (which writes the 0xC000
sentinel and returns — xcc's `crt0-cpm3` routes `main`'s return through
`_exit` = `LD C,0; JP 5`, a BDOS warm boot, exactly like dcc).

```sh
P=/Users/ravn/z80/xyz-eval/xcc-current
cat bench_sieve.c dcc_test_main.c > /tmp/xs.c

# compile to a .rel object
"$P/bin/xcc" -c -Os /tmp/xs.c -o /tmp/xs.rel

# link a CP/M .COM (see "Beta workaround" below for why libs are explicit)
"$P/bin/xld" --mode=sdcc -nostartfiles -T "$P/z80/lib/linker-cpm3.lk" \
    "$P/z80/lib/crt0-cpm3.rel" /tmp/xs.rel \
    "$P/z80/lib/libc.a" "$P/z80/lib/libruntime.a" "$P/z80/lib/libcpm3.a" \
    --oformat=binary -o /tmp/xs.com
```

Optimization knobs: `-Os` (size baseline) and `-Of` (speed) map cleanly onto
the corpus size/speed columns. `linker-cpm3.lk` = `-f binary`, `_CODE=0x0100`,
`ENTRY _entry` (a true `.COM`).

### Beta workaround (important)

xcc is beta. Auto-linking of `libc.a` is **broken** in v1.9.4 via *both*
documented shortcuts:

- `xcc --platform=cpm3 foo.c -o foo.com`  → `xld: unresolved symbol '_printf'`
- `xcc foo.c -T linker-cpm3.lk --oformat=binary` → `xld: unresolved symbol '_puts'`

The driver's implicit library probe does not pull in `libc.a`. Workaround:
drive `xld` by hand and list the libraries explicitly, in this order:
`crt0-cpm3.rel`, your object(s), `libc.a`, `libruntime.a`, `libcpm3.a`
(startup → code → C library → compiler runtime → platform hooks). This is the
recipe verified above. File upstream when we wire the oracle in.

## 3. Measure cycles with ntvcm

The CP/M `.COM` runs directly in ntvcm; `-p` prints a Z80 cycle count — a
relative time cost comparable across compilers:

```sh
/Users/ravn/z80/ntvcm/ntvcm -p /tmp/xs.com
#   Z80  cycles:                 3,649,297
```

For a PASS/FAIL verdict use the same 0xC000 sentinel the dcc lane reads from a
z88dk-ticks RAM dump (`ticks -pc 100 -end 0 -output ram.bin img`; check
`ram[0xC004]==1 && ram[0xC006]==0xA5`). ntvcm has no RAM dump, so it gives the
cycle number; ticks gives the verifiable sentinel. Use ntvcm for quick relative
timing, ticks for the gated verify — mirror `build_dcc_corpus.sh`.

## 4. Wiring into sweep (TODO)

Add a `build_xcc_corpus.sh` (mirror `build_dcc_corpus.sh`: single-TU
compile → xld link → wrap in a 64 KB image → ticks sentinel verify + cycle
count) and an `ONLY=xcc` / `want xcc` lane in `sweep.sh`. Deferred until the
oracle is promoted from evaluation.

## Verified facts (2026-07-06, macOS, xcc 1.9.4, L model)

- `hello.c` (`puts`) → 862 B `.COM`, prints "Hello, CP/M world!" in ntvcm.
- `bench_sieve.c` + harness → 8760 B `.COM`, 3,649,297 Z80 cycles in ntvcm.
- xcc emits SDCC-dialect asm (`.optsdcc -mz80 sdcccall(1)`, `_main`, DE return)
  → SDCC-ABI compatible.
