# clang/Makefile — Build RC702 BIOS with LLVM-Z80 clang
#
# Produces bios.cim from shared sources in parent directory.
# Uses native build if available, falls back to Docker.
# Called from parent: make -C clang bios.cim MSIZE=56 KBLANG=DANISH

PARENT = ..

# Inherit from parent
MSIZE  ?= 56
BIOSAD ?= $(shell printf '0x%04X' $$(( 0x3400 + ($(MSIZE) - 20) * 1024 + 0x1600 )))
KBLANG ?= DANISH

# LLVM-Z80 toolchain — probe for native build, fall back to Docker
LLVM_Z80 = $(CURDIR)/../../../llvm-z80
B_NATIVE = $(firstword $(wildcard $(LLVM_Z80)/build-macos/bin $(LLVM_Z80)/build/bin))

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

CFLAGS = --target=z80 -Oz -g -nostdlib -ffreestanding \
	 -ffunction-sections -fdata-sections \
	 -Xclang -target-feature -Xclang +static-stack \
	 -mllvm -disable-lsr \
	 -Iclang -I. -Wno-gcc-compat -Wno-return-type \
	 -Wimplicit-int-conversion \
	 -DMSIZE=$(MSIZE)

OBJS = boot_block.o boot_confi.o boot_entry.o bios_hw_init.o \
       bios_jump_vector_table.o bios.o bios_shims.o runtime.o

.PHONY: clean

# Build rules — $(RUN) is empty for native, Docker prefix for container
bios.cim: $(PARENT)/builddate.h $(OBJS) rc700_bios.ld
	$(RUN) $(B)/ld.lld --gc-sections --defsym BIOSAD=$(BIOSAD) \
		-T clang/rc700_bios.ld $(addprefix clang/,$(OBJS)) -o clang/bios.elf
	$(RUN) $(B)/llvm-objcopy -O binary clang/bios.elf clang/bios.cim
	$(RUN) $(B)/llvm-objdump -d --triple=z80 clang/bios.elf > bios.lis
	@echo "clang BIOS: $$(wc -c < bios.cim | tr -d ' ') bytes"
	@SIG=$$(dd if=bios.cim bs=1 skip=8 count=6 2>/dev/null); \
	if [ "$$SIG" != " RC702" ]; then \
		echo "ERROR: RC702 signature not found!"; exit 1; \
	fi

boot_block.o: $(PARENT)/boot_block.c $(PARENT)/bios.h $(PARENT)/builddate.h $(CLANG_BIN)
	$(RUN) $(B)/clang $(CFLAGS) -c boot_block.c -o clang/$@

boot_confi.o: $(PARENT)/boot_confi.c $(PARENT)/bios.h $(CLANG_BIN)
	$(RUN) $(B)/clang $(CFLAGS) $(if $(filter-out DANISH,$(KBLANG)),-D$(KBLANG)) -c boot_confi.c -o clang/$@

boot_entry.o: $(PARENT)/boot_entry.c $(PARENT)/bios.h $(PARENT)/hal.h intrinsic.h $(CLANG_BIN)
	$(RUN) $(B)/clang $(CFLAGS) -c boot_entry.c -o clang/$@

bios_hw_init.o: $(PARENT)/bios_hw_init.c $(PARENT)/bios.h $(PARENT)/hal.h intrinsic.h $(CLANG_BIN)
	$(RUN) $(B)/clang $(CFLAGS) -c bios_hw_init.c -o clang/$@

bios_jump_vector_table.o: bios_jump_vector_table.c $(PARENT)/bios.h $(CLANG_BIN)
	$(RUN) $(B)/clang $(CFLAGS) -c clang/bios_jump_vector_table.c -o clang/$@

bios.o: $(PARENT)/bios.c $(PARENT)/bios.h $(PARENT)/hal.h intrinsic.h string.h $(PARENT)/builddate.h $(CLANG_BIN)
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
	rm -f *.o bios.elf bios.cim bios.bin bios.lis bios_src.S bios_src.lis
