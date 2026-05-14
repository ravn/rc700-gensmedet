# Z80 codegen oracle micro-corpus — behavioural verification harness.
#
# Builds the corpus + test_main with each of three compilers in BOTH
# non-volatile and volatile configurations (6 binaries total), runs
# each in z88dk-ticks, dumps the 33-byte results vector at 0xC000, and
# compares all six vectors. Both flavours are interesting:
# - Non-volatile shows each compiler's best-case codegen
#   (LoopIdiomRecognize, store merging, etc.)
# - Volatile shows the real production cost of hardware-state
#   constraints (clang's LDIR-overlap fill is blocked, byte loops
#   stay literal).
#
# Flag philosophy: z88dk's frontend (zcc) is configured via its
# documented native options (-clib, -compiler, --opt-code-size,
# +target, etc.), NOT by tunneling component flags via -Cs. The one
# exception is matching cpnos-rom production exactly:
#   -Cs"--sdcccall 1" -Cs"--disable-warning 296"
# This is workaround-by-avoidance, not a fix to the underlying ABI
# mismatch (z88dk's stock SDCC stdlib helpers are sdcccall-0 only).
# Production keeps it safe by writing source that never reaches a
# helper. The corpus does the same: no `x % N` for non-power-of-2 N,
# no 16-bit multiply, no division.

Z88DK ?= /Users/ravn/z80/z88dk
CLANG ?= /Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLDLD ?= /Users/ravn/z80/llvm-z80/build-macos/bin/ld.lld
LLVMOBJCOPY ?= /Users/ravn/z80/llvm-z80/build-macos/bin/llvm-objcopy
LLVMNM ?= /Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
TICKS ?= $(Z88DK)/bin/z88dk-ticks

# ACK (Amsterdam Compiler Kit) -- runs in Docker.
# IMPORTANT: ACK has no z80 backend; the `cpm` platform uses ACK's
# `i80` (Intel 8080) machine. Output runs on Z80 (since Z80 is a strict
# superset of 8080) but cannot use Z80-specific instructions: DJNZ, JR,
# EX, EXX, IX/IY, BIT, SET, RES, LDIR, etc. This is therefore a
# different kind of data point than the other three -- a "what does C
# look like when restricted to the 1976 i8080 ISA" baseline.
ACK_DOCKER ?= bensuperpc/ack
ACK = docker run --rm -v $(CURDIR):/work -w /work $(ACK_DOCKER)

ZCC_ENV = ZCCCFG=$(Z88DK)/lib/config PATH=$(Z88DK)/bin:$$PATH
ZCC = $(ZCC_ENV) $(Z88DK)/bin/zcc

SRCS = corpus.c test_main.c

.PHONY: all clean test verify zsdcc sccz80 clang ack \
        zsdcc_vol sccz80_vol clang_vol ack_vol

all: test

# ---------- zsdcc — matches cpnos-rom production flags ----------
ZSDCC_FLAGS = +z80 -compiler=sdcc -clib=sdcc_iy \
              --opt-code-size -SO3 \
              -Cs"--sdcccall 1" -Cs"--disable-warning 296" \
              -Cs"--max-allocs-per-node 25000" \
              -Cs"--fomit-frame-pointer" \
              -create-app

zsdcc.bin: $(SRCS)
	$(ZCC) $(ZSDCC_FLAGS) -o zsdcc $(SRCS) 2>&1 | tail -5
	@test -f zsdcc.bin || (echo "zsdcc.bin missing"; false)

zsdcc_vol.bin: $(SRCS)
	$(ZCC) $(ZSDCC_FLAGS) -DUSE_VOLATILE -o zsdcc_vol $(SRCS) 2>&1 | tail -5
	@test -f zsdcc_vol.bin || (echo "zsdcc_vol.bin missing"; false)

# ---------- sccz80 ----------
SCCZ80_FLAGS = +z80 -compiler=sccz80 -O2 -SO2 -create-app

sccz80.bin: $(SRCS)
	$(ZCC) $(SCCZ80_FLAGS) -o sccz80 $(SRCS) 2>&1 | tail -5
	@test -f sccz80.bin || (echo "sccz80.bin missing"; false)

sccz80_vol.bin: $(SRCS)
	$(ZCC) $(SCCZ80_FLAGS) -DUSE_VOLATILE -o sccz80_vol $(SRCS) 2>&1 | tail -5
	@test -f sccz80_vol.bin || (echo "sccz80_vol.bin missing"; false)

# ---------- clang ----------
CLANG_RT_DIR = /Users/ravn/z80/llvm-z80/build-macos/lib/z80/elf-runtime/builtins
CLANG_FLAGS = --target=z80 -Oz -nostdlib -ffreestanding

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

define BUILD_CLANG
$(1).elf: $$(SRCS) reset_clang.s clang.ld
	$$(CLANG) $$(CLANG_FLAGS) -c reset_clang.s -o reset_clang_$(1).o
	$$(CLANG) $$(CLANG_FLAGS) $(2) -c corpus.c -o corpus_$(1).o
	$$(CLANG) $$(CLANG_FLAGS) $(2) -c test_main.c -o test_main_$(1).o
	$$(LLDLD) -T clang.ld -o $(1).elf reset_clang_$(1).o corpus_$(1).o test_main_$(1).o

$(1).bin: $(1).elf
	$$(LLVMOBJCOPY) -O binary $(1).elf $(1).bin
endef

$(eval $(call BUILD_CLANG,clang,))
$(eval $(call BUILD_CLANG,clang_vol,-DUSE_VOLATILE))

zsdcc: zsdcc.bin
zsdcc_vol: zsdcc_vol.bin
sccz80: sccz80.bin
sccz80_vol: sccz80_vol.bin
clang: clang.bin
clang_vol: clang_vol.bin

# ---------- Test runner ----------
%.ram: %.bin
	$(TICKS) -mz80 -counter 5000000 -output $@ $<
	@ls -la $@

RAMS = zsdcc.ram zsdcc_vol.ram sccz80.ram sccz80_vol.ram clang.ram clang_vol.ram

test: $(RAMS)
	@echo "--- Results at 0xC000 (33 bytes per binary) ---"
	@printf "%-12s" "expected"; \
	    python3 expected.py
	@for c in zsdcc zsdcc_vol sccz80 sccz80_vol clang clang_vol; do \
	    printf "%-12s" $$c; \
	    python3 -c "import sys; d=open('$$c.ram','rb').read(); print(' '.join(f'{b:02x}' for b in d[0xC000:0xC021]))"; \
	done

verify: test
	@python3 verify.py

clean:
	rm -f *.o *.bin *.map *.elf *.ram reset_clang.s clang.ld \
	      zsdcc zsdcc_vol sccz80 sccz80_vol \
	      *_CODE.bin *_DATA.bin *_BSS.bin \
	      corpus.c.lis test_main.c.lis
