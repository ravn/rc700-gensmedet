# clang/Makefile — Build RC702 BIOS with LLVM-Z80 clang
#
# Produces bios.clang.cim from shared sources in parent directory.
# (Filename intentionally distinct from SDCC's sdcc/bios.cim so both
# compilers can build in parallel without stepping on each other.)
# Uses native build if available, falls back to Docker.
# Called from parent: make -C clang bios.clang.cim MSIZE=56 KBLANG=DANISH

PARENT = ..

# Inherit from parent
MSIZE  ?= 56
BIOSAD ?= $(shell printf '0x%04X' $$(( 0x3400 + ($(MSIZE) - 20) * 1024 + 0x1600 )))
KBLANG ?= DANISH
KBDPORT ?= A
SW1_CONSOLE_BIT ?= 0x01

# LLVM-Z80 toolchain — probe for native build, fall back to Docker
LLVM_Z80 = $(CURDIR)/../../../llvm-z80
B_NATIVE = $(firstword $(wildcard $(LLVM_Z80)/build-linux/bin $(LLVM_Z80)/build-macos/bin $(LLVM_Z80)/build/bin))

ifneq ($(B_NATIVE),)
  # Native — use whichever build directory exists
  B = $(B_NATIVE)
  RUN = cd $(PARENT) &&
  CLANG_BIN = $(B)/clang
else
  # Docker fallback
  B = /src/build/bin
  RUN = docker run --rm -m 8g \
	-v $(LLVM_Z80):/src \
	-v $(CURDIR)/..:/bios \
	-w /bios \
	ubuntu:24.04
  CLANG_BIN = $(LLVM_Z80)/build/bin/clang
endif

CFLAGS = --target=z80 -Oz -g -nostdlib -ffreestanding -std=c23 \
	 -flto -ffunction-sections -fdata-sections \
	 -DSW1_CONSOLE_BIT=$(SW1_CONSOLE_BIT) \
	 -Xclang -target-feature -Xclang +static-stack \
	 -Iclang -I. -Wno-gcc-compat -Wno-return-type \
	 -Wimplicit-int-conversion \
	 -DMSIZE=$(MSIZE) \
	 $(if $(filter B,$(KBDPORT)),-DKBD_PIO_B)
# -flto re-enabled 2026-07-03 (experiment): boot_entry.c + bios_hw_init.c
# functions annotated __attribute__((section(".boot_code"),used)) so LTO
# retains them in BOOT, not in .text.  Linker script gains KEEP(*(.boot_code))
# before the per-file matchers.  Previously disabled in a7a7293 (2026-06-28)
# because per-file matchers (*boot_entry.o, *bios_hw_init.o) don't fire under
# LTO — now covered by explicit section attributes (same fix boot_block.c uses
# for .boot).  Boot MUST be re-verified with make mame-test after this change.
# Investigation hook (ravn/llvm-z80#23): inject extra clang flags via
# `make CLANG_EXTRA="-mllvm -z80-enable-licm -mllvm -z80-enable-cse"`.
CFLAGS += $(CLANG_EXTRA)

OBJS = boot_block.o boot_confi.o boot_entry.o bios_hw_init.o \
       bios_jump_vector_table.o bios.o bios_shims.o runtime.o

# Flag fingerprint — the "fewest surprises when toggling a compiler flag" guard.
# Every C object depends on .cflags, whose contents ARE $(CFLAGS).  The recipe
# rewrites .cflags only when the flags actually change (cmp guard), so its mtime
# bumps exactly when you edit CFLAGS (e.g. toggle -flto).  That forces a rebuild
# of the affected objects instead of silently relinking stale ones built with
# the OLD flags — the exact trap that produced fd4a197's false "mame-test PASS"
# and hid the -flto boot hang for three days.  No more "remember to rm *.o".
.cflags: FORCE
	@printf '%s\n' '$(CFLAGS)' | cmp -s - $@ 2>/dev/null || printf '%s\n' '$(CFLAGS)' > $@

.PHONY: clean

# Build rules — $(RUN) is empty for native, Docker prefix for container
# z80_rt.a: llvm-z80's compiler-rt archive (memcpy/memset/memchr/memmove/
# __call_iy/___umodqi3 etc.).  Linked LAST as a last-resort archive so the
# linker pulls in only the members codegen references; unused members cost 0 B.
# Replaces the hand-rolled copies formerly in runtime.s (2026-07-08).
Z80_RT = $(B)/../lib/z80/z80_rt.a
bios.clang.cim: $(PARENT)/builddate.h $(OBJS) rc700_bios.ld
	$(RUN) $(B)/ld.lld --gc-sections --defsym BIOSAD=$(BIOSAD) \
		-T clang/rc700_bios.ld $(addprefix clang/,$(OBJS)) $(Z80_RT) -o clang/bios.clang.elf
	$(RUN) $(B)/llvm-objcopy -O binary clang/bios.clang.elf clang/bios.clang.cim
	# Source-annotated listing (committed to git for historical diffs).
	# Note: add -l for file:line references (clickable in terminal, not in editor)
	$(RUN) $(B)/llvm-objdump -d -S --triple=z80 clang/bios.clang.elf > clang/bios.clang.lis
	@# wc/dd run from the clang/ subdir cwd (no $(RUN) prefix), so use
	@# the bare filename without the clang/ prefix here.
	@echo "clang BIOS: $$(wc -c < bios.clang.cim | tr -d ' ') bytes"
	@SIG=$$(dd if=bios.clang.cim bs=1 skip=8 count=6 2>/dev/null); \
	if [ "$$SIG" != " RC702" ]; then \
		echo "ERROR: RC702 signature not found!"; exit 1; \
	fi

boot_block.o: $(PARENT)/boot_block.c $(PARENT)/bios.h $(PARENT)/builddate.h $(CLANG_BIN) .cflags
	$(RUN) $(B)/clang $(CFLAGS) -c boot_block.c -o clang/$@

boot_confi.o: $(PARENT)/boot_confi.c $(PARENT)/bios.h $(CLANG_BIN) .cflags
	$(RUN) $(B)/clang $(CFLAGS) $(if $(filter-out DANISH,$(KBLANG)),-D$(KBLANG)) -c boot_confi.c -o clang/$@

boot_entry.o: $(PARENT)/boot_entry.c $(PARENT)/bios.h $(PARENT)/hal.h intrinsic.h $(CLANG_BIN) .cflags
	$(RUN) $(B)/clang $(CFLAGS) -c boot_entry.c -o clang/$@

bios_hw_init.o: $(PARENT)/bios_hw_init.c $(PARENT)/bios.h $(PARENT)/hal.h intrinsic.h $(CLANG_BIN) .cflags
	$(RUN) $(B)/clang $(CFLAGS) -c bios_hw_init.c -o clang/$@

bios_jump_vector_table.o: bios_jump_vector_table.c $(PARENT)/bios.h $(CLANG_BIN) .cflags
	$(RUN) $(B)/clang $(CFLAGS) -c clang/bios_jump_vector_table.c -o clang/$@

bios.o: $(PARENT)/bios.c $(PARENT)/bios.h $(PARENT)/hal.h intrinsic.h string.h $(PARENT)/builddate.h $(CLANG_BIN) .cflags
	$(RUN) $(B)/clang $(CFLAGS) -c bios.c -o clang/$@

bios_shims.o: bios_shims.s $(CLANG_BIN)
	$(RUN) $(B)/clang --target=z80 -c clang/bios_shims.s -o clang/$@

runtime.o: runtime.s $(CLANG_BIN)
	$(RUN) $(B)/clang --target=z80 -c clang/runtime.s -o clang/$@

# Generate builddate.h in parent if needed
$(PARENT)/builddate.h: FORCE
	$(MAKE) -C $(PARENT) builddate.h

FORCE:

clean:
	rm -f *.o .cflags bios.clang.elf bios.clang.cim bios.bin bios_src.S bios_src.lis
	# Note: clang/bios.clang.lis is intentionally NOT removed by clean —
	# it is tracked in git so historical disassembly is available without
	# rebuilding clang.  Use `git restore clang/bios.clang.lis` if needed.
