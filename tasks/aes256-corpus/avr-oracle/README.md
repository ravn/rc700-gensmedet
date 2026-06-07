# AVR cross-target value oracle

Compiles the same `aes256.c` source the Z80 corpus uses, but under
`clang --target=avr -mmcu=atmega328p`, links with `avr-gcc + avr-libc`,
runs in `simavr`, and prints the verdict via the simavr `.mmcu` console
hook (writes to GPIOR0 @ 0x3E -> host stdout on '\n').

**Purpose.**  Third-party value oracle for the LLVM mid-end pipeline.  If
clang-built AES round-trips correctly on AVR (different ABI, regalloc,
scheduling, target ISA) it's strong evidence that no mid-end pass is
miscompiling the source.  Useful when triaging suspected mid-end bugs
(icmp-narrow soundness, TruncInstCombine, etc.) — Z80 is one target;
AVR is a second.

## Run

```
make run
```

Expected output:
```
AES-256: ENCRYPT PASS  CT=8ea2b7ca516745bfeafc49904b496089
AES-256: DECRYPT PASS
VERDICT: PASS
```

## Toolchain dependencies

- `clang` from llvm-z80 build-macos (already targets AVR + MSP430 since 2026-06-07).
- `avr-gcc`, `avr-ld`, `avr-objcopy`, `avr-size`, `simavr` — all provided by
  the `avr-tools` Docker image (see `Dockerfile.avr-tools`).  Wrappers live
  in `~/.local/bin/` on the macbook (Docker-shim pattern, same as
  `sdcc-tools`).
- The image embeds `simavr` master built from source with `libelf-dev`.
  Distro packages (ubuntu 24.04 / 25.04 / 26.04 / rolling, debian trixie)
  all ship 1.6+dfsg-3 which predates the `.mmcu` console-register tag;
  upstream simavr has not tagged a release since 2017 so apt is a dead end.

## Build the avr-tools image

```
docker build --platform linux/amd64 -t avr-tools -f Dockerfile.avr-tools .
```

## Why this lives next to the Z80 AES corpus

Same `aes256.c` source feeds both.  Cross-target consistency check is the
point.
