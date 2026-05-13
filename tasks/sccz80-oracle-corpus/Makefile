# Z80 codegen oracle micro-corpus — behavioural verification harness.
#
# Builds the corpus + test_main with each of three compilers, runs each
# in z88dk-ticks, dumps the 32-byte results vector at 0xC000, and
# compares all three vectors. Divergence = at least one compiler is
# miscompiling.

Z88DK ?= /Users/ravn/z80/z88dk
CLANG ?= /Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLDLD ?= /Users/ravn/z80/llvm-z80/build-macos/bin/ld.lld
LLVMOBJCOPY ?= /Users/ravn/z80/llvm-z80/build-macos/bin/llvm-objcopy
LLVMNM ?= /Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
TICKS ?= $(Z88DK)/bin/z88dk-ticks

ZCC_ENV = ZCCCFG=$(Z88DK)/lib/config PATH=$(Z88DK)/bin:$$PATH
ZCC = $(ZCC_ENV) $(Z88DK)/bin/zcc

SRCS = corpus.c test_main.c

.PHONY: all clean test verify zsdcc sccz80 clang

all: test

# ---------- zsdcc ----------
# zcc +z80 default: code at ORG=0, BSS at 0x8000+ (embedded clib).
# That fits ticks' default `load at PC=0, run from 0` model. We choose
# RESULTS_ADDR=0xC000 in test_main.c so the results land cleanly above
# BSS but well within 64K RAM.
# NOTE: --sdcccall 1 (cpnos-rom production flag) is incompatible with
# z88dk's stock __mulint runtime (built for sdcccall 0, expects args on
# stack). zcc's warning 296 flags it. Using sdcccall 0 here so the
# corpus compiles+links cleanly for behavioural verification.
# Real cpnos-rom production code needs to ensure --sdcccall 1 builds
# don't reach any 16-bit-mul helper path.
#
# Size optimization: --opt-code-size switches SDCC's peephole pass from
# the default (sdcc_peeph.3) to the size-focused variant
# (sdcc_peeph_cs.3) and biases other heuristics for code density.
# cpnos-rom disables it (NET LOSS due to ___sdcc_enter_ix helper
# amortization in that 2-function-IX-frame profile, see cpnos-rom
# Makefile). For this stand-alone 10-function corpus the flag is the
# correct choice — we want each compiler in its smallest-code mode.
zsdcc.bin: $(SRCS)
	$(ZCC) +z80 -compiler=sdcc -clib=sdcc_iy \
	    --opt-code-size \
	    -SO3 -Cs"--max-allocs-per-node 25000" \
	    -Cs"--fomit-frame-pointer" \
	    -create-app \
	    -o zsdcc $(SRCS) 2>&1 | tail -30
	@test -f zsdcc.bin || (echo "zsdcc.bin missing — see zcc output above"; false)

# ---------- sccz80 ----------
sccz80.bin: $(SRCS)
	$(ZCC) +z80 -compiler=sccz80 \
	    -O2 -SO2 \
	    -create-app \
	    -o sccz80 $(SRCS) 2>&1 | tail -30
	@test -f sccz80.bin || (echo "sccz80.bin missing"; false)

# ---------- clang ----------
# Minimal reset stub: set SP, call main, halt.
reset_clang.s:
	@printf '%s\n' \
	    '    .section .reset, "ax"' \
	    '    .global _start' \
	    '_start:' \
	    '    di' \
	    '    ld sp, 0xFFFE' \
	    '    call _main' \
	    '_done:' \
	    '    halt' \
	    '    jp _done' \
	    > $@

clang.ld:
	@printf '%s\n' \
	    'ENTRY(_start)' \
	    'MEMORY {' \
	    '  RAM (rwx) : ORIGIN = 0x0000, LENGTH = 0xC000' \
	    '}' \
	    'SECTIONS {' \
	    '  .text 0x0000 : { *(.reset) *(.text*) } > RAM' \
	    '  .rodata : { *(.rodata*) } > RAM' \
	    '  .data : { *(.data*) } > RAM' \
	    '  .bss : { *(.bss*) *(COMMON) } > RAM' \
	    '}' \
	    > $@

CLANG_RT = /Users/ravn/z80/llvm-z80/build-macos/lib/z80/elf-runtime/builtins/mulhi3.o

clang.elf: $(SRCS) reset_clang.s clang.ld
	$(CLANG) --target=z80 -Oz -nostdlib -ffreestanding -c reset_clang.s -o reset_clang.o
	$(CLANG) --target=z80 -Oz -nostdlib -ffreestanding -c corpus.c -o corpus_clang.o
	$(CLANG) --target=z80 -Oz -nostdlib -ffreestanding -c test_main.c -o test_main_clang.o
	$(LLDLD) -T clang.ld -o clang.elf reset_clang.o corpus_clang.o test_main_clang.o $(CLANG_RT)
	$(LLVMNM) --numeric-sort clang.elf | head -30

clang.bin: clang.elf
	$(LLVMOBJCOPY) -O binary clang.elf clang.bin

zsdcc: zsdcc.bin
sccz80: sccz80.bin
clang: clang.bin

# ---------- Test runner ----------
# Loads each .bin at 0x8000, runs to halt, dumps full 64K to *.ram.
%.ram: %.bin
	$(TICKS) -mz80 -counter 5000000 -output $@ $<
	@ls -la $@

test: zsdcc.ram sccz80.ram clang.ram
	@echo "=== Results at 0xC000 (33 bytes per compiler) ==="
	@printf "%-8s" "expected"; \
	    python3 expected.py
	@for c in zsdcc sccz80 clang; do \
	    printf "%-8s" $$c; \
	    python3 -c "import sys; d=open('$$c.ram','rb').read(); print(' '.join(f'{b:02x}' for b in d[0xC000:0xC021]))"; \
	done

verify: test
	@python3 verify.py

clean:
	rm -f *.o *.bin *.map *.elf *.ram reset_clang.s clang.ld
