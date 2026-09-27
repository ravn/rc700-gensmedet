# zcc -compiler=llvmz80 validation listings

Generated 2026-09-27 to validate the new `z80-unknown-none-z88dk` target
triple (z88dk#81/#82) against autoload-in-c's real production sources.

Not a production artifact — for comparison/review only. The production
build path (`autoload-in-c/Makefile`, `COMPILER=clang`) invokes llvm-z80's
clang directly and links via `ld.lld` + a custom linker script + ZX0
compression; it does not use zcc or z88dk's own z80asm/appmake toolchain.

## Files

- `rom_zcc.asm` / `boot_rom_zcc.asm` — z80asm-format assembly emitted by
  `zcc +embedded -compiler=llvmz80 --opt-code-size --no-crt -nostdlib -a`
  (matches production's `-Oz`; `boot_rom.c` compiled with `__z80__`/`__ELF__`
  forced so the real clang branch, not the IDE stub, is exercised).

## Status: compile-only, not linked

These are **pre-link textual assembly** (z80asm's `-l` listing-file output
only exists as a real, address-annotated `.lis` after an actual
assemble+link step). Attempting to actually link `rom_zcc.asm` +
`boot_rom_zcc.asm` with `z80asm` fails on undefined symbols:
`__call_iy`, `___z80_memset_builtin` (llvm-z80 runtime intrinsics, normally
supplied by `clang/runtime.o`/`clang/rt_memset.o` in the direct-clang
production build) and `_reloc_zx0`/`__bss_start`/`__bss_size` (normally
supplied by autoload-in-c's custom linker script, `rc700_prom.ld`).

None of these exist in a form z88dk's own toolchain can currently resolve —
producing a real linked `.lis` would require either porting llvm-z80's
runtime objects into z80asm-compatible form, or writing an equivalent
linker script for z88dk's toolchain. Neither has been done. An earlier
version of this validation used hand-written stub definitions to force a
fake link through — that was fabricated, not a real result, and has been
removed. Do not reuse the object-code size numbers derived from that fake
link.

## What IS confirmed (compile-only, real)

Both `rom.c` and `boot_rom.c` compile cleanly through
`zcc -compiler=llvmz80` with the new target triple, and the emitted z80asm
text has the same 32 named functions + 8 outlined stubs as the direct-clang
production build, with instruction sequences that visibly match (e.g. the
port-I/O `in`/`out` sequences from the `DEFPORT`/`port_in`/`port_out` fix).

## Known gotcha found during validation

The `z80-unknown-none-z88dk` target does not predefine the lowercase
`__z80__` macro (only `__Z80__`/`__Z80`), unlike direct clang's
`z80-unknown-elf` target which defines both `__z80__` and `__ELF__`.
Without forcing these macros, `boot_rom.c`'s `#if defined(__z80__)` branch
silently falls through to the no-op IDE-stub fallback. Worth flagging on
z88dk#81/#82 for any code using the lowercase GCC-compat macro.

## Non-freestanding (full crt0+clib) link also fails, independently

Dropping `--no-crt -nostdlib` and attempting `zcc +embedded -compiler=llvmz80
-create-app rom.c boot_rom.c` (z88dk's own `embedded_crt0` + classic clib)
fails for two separate, unrelated reasons, confirming this isn't just a
missing-runtime-object gap but a structural mismatch:

1. `embedded_crt0.asm` hardcodes its own entry point (`extern _main`, not our
   `start()`) and memory map (`Stack_Top = $ffff`, `RAM_Start = $8000`) —
   incompatible with `rc700_prom.ld`'s hand-placed sections.
2. The default classic clib (`-clib=default`) unconditionally requires a
   `fputc_cons`/`fputc_cons_native` console driver symbol even though this
   code never calls `printf`. The newlib alternative (`-clib=new`) fails
   separately: no `z80.lib` is actually built for any compiler variant in
   this local z88dk checkout (only the classic `sdcc_iy/z80.lib` exists, and
   only inside the `z88dk:2.4` Docker image).

## No source-level debug information in z80asm-format output

Tracked upstream as **ravn/llvm-z80#392**. `Z80MCAsmInfoZ80ASM` hardcodes
`SupportsDebugInformation = false` (`Z80MCAsmInfo.cpp:179`), unlike the
direct-ELF path (`:61`, `= true`, which is what gives production's
`prom.clang.lis` its interleaved `rom.c:NNN` source lines via real DWARF +
`llvm-objdump -S`). Confirmed neither `clang -g` nor z80asm's own
`-debug`/`-g` flags produce any source-line reference in `rom_zcc.asm` —
only LLVM's internal basic-block comments (`; %bb.0: ; %entry`) are present.
This means there is currently no way to produce a source-annotated listing
via the `zcc -compiler=llvmz80` path at all, independent of the linking
problems above.

## Size comparison recap (rom.c, matched -Oz, compile-only, real)

Direct clang production object (`clang/rom.o`, via `llvm-readelf -S`):
2411 B code + 1687 B rodata + 35 B bss = 4098 B.
zcc/llvmz80 object (`z88dk-z80nm` section sizes): 2343 B code + 1686 B
rodata + 35 B bss = 4029 B (−69 B vs. clang, at matched `--opt-code-size`).
Not a pure isolated triple comparison — see caveat above (missing
`+static-frame +shadow-regs`, different `-mllvm` flags).
`boot_rom.c`: clang 73 B vs. zcc 72 B — essentially identical.
