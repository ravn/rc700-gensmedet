# Makefile for RC702 autoload PROM rewrite
#
# Usage:
#   make prom                    Build + install PROM (default: clang)
#   make prom COMPILER=sdcc      Build + install PROM with SDCC
#   make mame                   Build + boot in MAME
#   make clean                  Clean both compiler outputs

# ================================================================
# Compiler selection
# ================================================================
#
# Each compiler produces its own distinguishable PROM artifact from the
# shared sources:
#   clang -> clang/prom.clang.bin  (annotated listing: clang/prom.clang.lis,
#                                    tracked in git so historical diffs work
#                                    without rebuilding clang)
#   sdcc  -> sdcc/prom.bin
# Distinct filenames let both compilers build in parallel without colliding.

COMPILER ?= clang

# Compiler-distinct artifact names.
ifeq ($(COMPILER),clang)
  PROM_BIN     = clang/prom.clang.bin
  PROM_ELF     = clang/prom.clang.elf
  PROM_LIS     = clang/prom.clang.lis
  PROM_TARGET  = clang/prom.clang.bin
else
  PROM_BIN     = sdcc/prom.bin
  PROM_ELF     = sdcc/prom.elf
  PROM_LIS     = sdcc/prom.lis
  PROM_TARGET  = sdcc/prom.bin
endif

# ================================================================
# Shared configuration
# ================================================================

MAME ?= $(CURDIR)/../../mame
MAME_ROM = $(MAME)/roms/rc702/roa375.ic66
MAME_RUN = $(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	-nothrottle -window -skip_gameinfo \
	-seconds_to_run 60 \
	-autoboot_script mame_boot_test.lua \
	-flop1 "$(FLOPPY)"
RC700 = ../../rc700
FLOPPY = $(HOME)/Downloads/SW1711-I8.imd

.PHONY: all prom mame mamesym rc700 clean \
        clang_asm clang_disasm clang_src_lis clang_symbols clang_mamesym

all: prom

# ================================================================
# PROM dispatch: make prom → build + pad + install
# ================================================================

prom:
	$(MAKE) $(PROM_TARGET)
	@PROM=$$(wc -c < $(PROM_BIN) | tr -d ' '); \
	 echo "$(COMPILER) PROM: $$PROM / 2048 bytes (PROM0 socket)"; \
	 if [ $$PROM -gt 4096 ]; then \
	   echo "ERROR: exceeds 4096-byte file-format limit by $$((PROM - 4096)) bytes"; \
	   exit 1; \
	 elif [ $$PROM -gt 2048 ]; then \
	   echo "WARNING: exceeds 2048-byte PROM0 socket by $$((PROM - 2048)) bytes"; \
	   echo "  -- OK for development per user policy; must shrink before burning EPROM."; \
	 else \
	   echo "OK: $$((2048 - PROM)) bytes free in PROM0"; \
	 fi
	@# Pad to 4096 for MAME's roa375.ic66 slot (the file format is
	@# 4 KB; high 2 KB is unused / 0xFF in autoload mode, holds the
	@# cpnos-in-asm slave when that's installed).  Hard-limit failure
	@# above stops anything exceeding the actual PROM0 EPROM size.
	@{ cat $(PROM_BIN); \
	   perl -e "print \"\\xff\" x (4096 - $$(wc -c < $(PROM_BIN) | tr -d ' '))"; \
	 } > $(COMPILER)/prom0.ic66
	cp $(COMPILER)/prom0.ic66 $(MAME_ROM)

# ================================================================
# MAME targets
# ================================================================

# SW1 status display test.  Boots autoload with a stock 0xFF PROM1
# (no signature -> autoload reaches its NO-LINEPROG halt, leaving the
# banner + SW1 line on display); dumps display rows 0..2 from RAM at
# 0x7A00 and greps for "SW1: " on row 1.  Use to verify the
# display_sw1_status() output after editing the formatting.
SW1_DUMP    = /tmp/autoload_sw1_dump.txt
SW1_PROM1   = $(MAME)/roms/rc702/prom1.ic65
SW1_PROM1_BACKUP = /tmp/autoload_prom1_backup.bin

.PHONY: sw1-test
sw1-test: prom
	@echo "=== preparing empty PROM1 (no signature) ==="
	@if [ -f "$(SW1_PROM1)" ]; then cp "$(SW1_PROM1)" "$(SW1_PROM1_BACKUP)"; fi
	@perl -e 'print "\xFF" x 2048' > "$(SW1_PROM1)"
	@rm -f $(SW1_DUMP)
	@echo "=== launching MAME for SW1 status check (~4 s) ==="
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 6 \
	    -autoboot_script mame_sw1_test.lua \
	    -snapname autoload_sw1 \
	    >/tmp/autoload_sw1_mame.log 2>&1
	@echo "=== restoring PROM1 ==="
	@if [ -f "$(SW1_PROM1_BACKUP)" ]; then cp "$(SW1_PROM1_BACKUP)" "$(SW1_PROM1)"; rm -f "$(SW1_PROM1_BACKUP)"; fi
	@echo "--- display memory rows 0..2 (read from RAM at 0x7A00) ---"
	@cat $(SW1_DUMP) 2>/dev/null || { echo "no dump produced"; exit 1; }
	@grep -qE "^row00: .*SW1 12345678: [01]{8}" $(SW1_DUMP) \
	    && echo "PASS: SW1 status present on row 0 (right side)" \
	    || { echo "FAIL: SW1 status not found on row 0"; exit 1; }

mame: prom mamesym
	@awk '{printf "comadd %s,%s\n", $$1, $$2}' $(COMPILER)/prom0_mame.sym > $(COMPILER)/prom0_debug.cmd
	$(eval EXPECT := $(if $(filter sdcc,$(COMPILER)),RC700 ROA375,RC700 CL))
	EXPECT_BANNER="$(EXPECT)" $(MAME_RUN)
	@cat /tmp/boot_test_result.txt
	@grep -q '^PASS' /tmp/boot_test_result.txt

mamesym:
ifeq ($(COMPILER),clang)
	@$(RUN) $(CLANG_NM) --numeric-sort clang/prom.clang.elf | \
		awk '/ [TtBbDd] / { sub(/^_/, "", $$3); printf "%s %s\n", $$1, $$3 }' \
		> clang/prom0_mame.sym
else
	@awk '/= \$$[0-9A-Fa-f]+ ; addr,/ { \
		name = $$1; addr = $$3; \
		if (name ~ /^l_/) next; \
		sub(/^\$$/, "0x", addr); \
		sub(/^_/, "", name); \
		printf "%s %s\n", addr, name; \
	}' sdcc/prom0.map | sort > sdcc/prom0_mame.sym
endif
	@echo "wrote $(COMPILER)/prom0_mame.sym ($$(wc -l < $(COMPILER)/prom0_mame.sym) symbols)"

# ================================================================
# LLVM-Z80 clang build
# ================================================================

LLVM_Z80 = $(CURDIR)/../../llvm-z80
NATIVE ?= 1

ifneq ($(NATIVE),0)
  # Native build — run tools directly (probe Linux first, then macOS, then plain build/)
  CLANG_BUILD = $(firstword $(wildcard $(LLVM_Z80)/build-linux/bin $(LLVM_Z80)/build-macos/bin $(LLVM_Z80)/build/bin))
  RUN =
  CLANG_COMPILER = $(CLANG_BUILD)/clang
else
  # Docker build
  CLANG_BUILD = /src/build/bin
  RUN = docker run --rm -m 8g \
	-v $(LLVM_Z80):/src \
	-v $(CURDIR):/rom \
	-w /rom \
	ubuntu:24.04
  CLANG_COMPILER = $(LLVM_Z80)/build/bin/clang
endif

CLANG_CC      = $(CLANG_BUILD)/clang
CLANG_LD      = $(CLANG_BUILD)/ld.lld
CLANG_OBJCOPY = $(CLANG_BUILD)/llvm-objcopy
CLANG_OBJDUMP = $(CLANG_BUILD)/llvm-objdump
CLANG_NM      = $(CLANG_BUILD)/llvm-nm

CLANG_CFLAGS = --target=z80 -Oz -g -nostdlib \
	       -ffunction-sections -fdata-sections \
	       -Xclang -target-feature -Xclang +static-stack \
	       -Xclang -target-feature -Xclang +shadow-regs \
	       -mllvm -disable-lsr \
	       -Iclang -I. \
	       -Weverything \
	       -Wno-unsafe-buffer-usage \
	       -Wno-c23-extensions \
	       -Wno-reserved-macro-identifier \
	       -Wno-reserved-identifier \
	       -Wno-gcc-compat \
	       -Wno-declaration-after-statement \
	       -Wno-pre-c11-compat
# -g enables DWARF debug info; binary unchanged because objcopy -O binary
# only emits ALLOC sections and .debug_* are non-ALLOC.  The DWARF info
# is what makes the source-annotated listing (clang/prom.clang.lis)
# possible.

CLANG_OBJS = clang/boot.o clang/intvec.o clang/rom.o clang/runtime.o

clang/prom.clang.bin: $(CLANG_OBJS) clang/rc700_prom.ld
	$(RUN) $(CLANG_LD) --gc-sections -T clang/rc700_prom.ld $(CLANG_OBJS) -o clang/prom.clang.elf
	$(RUN) $(CLANG_OBJCOPY) -O binary clang/prom.clang.elf clang/prom.clang.bin
	# Source-annotated listing (committed to git for historical diffs
	# without needing to rebuild clang).
	$(RUN) $(CLANG_OBJDUMP) -d -S --triple=z80 clang/prom.clang.elf > clang/prom.clang.lis

clang/banner.h:
	@BANNER=" RC700 CL $$(date '+%Y-%m-%d %H.%M')/$$(whoami)"; \
	 echo "#define BUILD_BANNER \"$$BANNER\"" > $@; \
	 echo "#define BUILD_BANNER_LENGTH $${#BANNER}" >> $@

clang/boot.o: boot_rom.c rom.h clang/banner.h $(CLANG_COMPILER)
	$(RUN) $(CLANG_CC) $(CLANG_CFLAGS) -c $< -o $@

clang/runtime.o: clang/runtime.s $(CLANG_COMPILER)
	$(RUN) $(CLANG_CC) --target=z80 -c $< -o $@

clang/intvec.o: intvec.c rom.h $(CLANG_COMPILER)
	$(RUN) $(CLANG_CC) $(CLANG_CFLAGS) -c intvec.c -o $@

clang/rom.o: rom.c rom.h $(CLANG_COMPILER)
	$(RUN) $(CLANG_CC) $(CLANG_CFLAGS) -c rom.c -o $@

clang_asm: rom.c rom.h
	$(RUN) $(CLANG_CC) $(CLANG_CFLAGS) -S rom.c -o /dev/stdout

clang_disasm: clang/prom.clang.bin
	$(RUN) $(CLANG_OBJDUMP) -d --triple=z80 clang/prom.clang.elf

# Source-annotated listing is now produced by the default build at
# clang/prom.clang.lis (since CLANG_CFLAGS already includes -g).  This
# alias rebuilds it explicitly for convenience.
clang_src_lis: clang/prom.clang.bin
	@echo "wrote clang/prom.clang.lis (built by default rule)"

clang_symbols: clang/prom.clang.bin
	$(RUN) $(CLANG_NM) --numeric-sort clang/prom.clang.elf

clang_mamesym: clang/prom.clang.bin
	@$(RUN) $(CLANG_NM) --numeric-sort clang/prom.clang.elf | \
		awk '/ [TtBbDd] / { sub(/^_/, "", $$3); printf "%s %s\n", $$1, $$3 }' \
		> clang/prom0_mame.sym
	@echo "wrote clang/prom0_mame.sym ($$(wc -l < clang/prom0_mame.sym) symbols)"

# ================================================================
# SDCC build (via z88dk Docker)
# ================================================================

Z88DK_DOCKER = docker run --rm \
	-v $(CURDIR):/src \
	-w /src \
	z88dk:2.4

ZFLAGS = +z80 -clib=sdcc_iy --no-crt --opt-code-size -SO3 \
         -Cs"--max-allocs-per-node 1000000" \
         -Cs"--fomit-frame-pointer" \
         -Cs"--allow-unsafe-read" \
         -Cs"--sdcccall 1" -Cs"--disable-warning 296" \
         -custom-copt-rules=sdcc/peephole.def \
         -pragma-define:CRT_ORG_CODE=0x0000 \
         -pragma-define:CRT_ORG_BSS=0x8200 \
         -pragma-define:CRT_CPU_CLOCK_HZ=4000000

ZLIB = -lz80
ZLFLAGS = -m --list -create-app -Cz"--org 0" $(ZLIB)

sdcc/prom.bin: sdcc/sections.asm rom.c rom.h boot_rom.c intvec.c sdcc/peephole.def
	@mkdir -p sdcc
	$(Z88DK_DOCKER) sh -c '\
	BANNER=" RC700 ROA375 $$(date "+%Y-%m-%d %H.%M")/$$(whoami)" && \
	printf '"'"'#define BUILD_BANNER "%s"\n#define BUILD_BANNER_LENGTH %d\n'"'"' "$$BANNER" $${#BANNER} > sdcc/build_stamp.h && \
	zcc $(ZFLAGS) -Cs"--codeseg BOOT" -c boot_rom.c -o sdcc/boot_rom.o && \
	zcc $(ZFLAGS) -c intvec.c -o sdcc/intvec.o && \
	cd sdcc && zcc $(ZFLAGS) $(ZLFLAGS) -o prom0 sections.asm intvec.o ../rom.c boot_rom.o'
	@cd sdcc && cat prom0_BOOT.bin prom0_CODE.bin > prom.bin
	@PROM=$$(wc -c < sdcc/prom.bin | tr -d ' '); \
	 echo "sdcc PROM: $$PROM bytes"

# ================================================================
# RC700 emulator
# ================================================================

CC = cc
RC700_SRC = cpu0.c cpu1.c cpu2.c cpu3.c cpu4.c cpu5.c cpu6.c cpu7.c \
            rom.c charrom.c charram.c pio.c sio.c ctc.c dma.c crt.c \
            fdc.c wdc.c ftp.c disk.c fifo.c monitor.c disasm.c

rc700: prom
	cd $(RC700) && ./rom2struct roa375.rom roa375 > roa375.c && \
	$(CC) -DSDL_main=main -DSDL_MAIN_HANDLED -DPROM0=roa375 \
		-o rc700-sdl2 -O3 -Wno-unused-result \
		$(RC700_SRC) roa375.c rc700.c rcterm-sdl2.c screen.c \
		-F/Library/Frameworks -framework SDL2 \
		-Wl,-rpath,/Library/Frameworks
	$(RC700)/rc700-sdl2 "$(FLOPPY)"

# ================================================================
# Clean
# ================================================================

clean:
	$(MAKE) -C clang clean
	$(MAKE) -C sdcc clean
	rm -f build_stamp.h prom0.ic66 prom0_mame.sym prom0_debug.cmd
