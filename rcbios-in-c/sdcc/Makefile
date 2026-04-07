# sdcc/Makefile — Build RC702 BIOS with SDCC via z88dk
#
# Produces bios.cim from shared sources in parent directory.
# Uses native z88dk if available, falls back to Docker.
# Called from parent: make -C sdcc bios.cim MSIZE=56 KBLANG=DANISH

PARENT = ..

# Inherit from parent
MSIZE  ?= 56
BIOSAD ?= $(shell printf '0x%04X' $$(( 0x3400 + ($(MSIZE) - 20) * 1024 + 0x1600 )))
KBLANG ?= DANISH

# z88dk: use native install if available, otherwise Docker
Z88DK_HOME ?= $(firstword $(wildcard $(CURDIR)/../../../z88dk))
ifneq ($(wildcard $(Z88DK_HOME)/bin/zcc),)
  # Native z88dk
  export ZCCCFG = $(Z88DK_HOME)/lib/config
  export PATH := $(Z88DK_HOME)/bin:$(PATH)
  RUN =
else
  # Docker fallback
  RUN = docker run --rm \
	-v $(CURDIR)/..:/src \
	-w /src/sdcc \
	z88dk:2.4
endif

ZFLAGS = +z80 -clib=sdcc_iy --no-crt --opt-code-size -SO3 \
         -Cs"--max-allocs-per-node 1000000" \
         -Cs"--fomit-frame-pointer" \
         -Cs"--allow-unsafe-read" \
         -Cs"--sdcccall 1" \
         -Cs"--std-sdcc23" \
         -Cs"--disable-warning 296" \
         -custom-copt-rules=peephole.def \
         -pragma-define:CRT_ORG_CODE=0x0000 \
         -Cs"-DMSIZE=$(MSIZE)" \
         -Ca-DBIOSAD=$(BIOSAD) \
         $(if $(filter-out DANISH,$(KBLANG)),-Ca-D$(KBLANG))

ZLIB = -lz80
ZLFLAGS = -m --list -create-app -Cz"--org 0" $(ZLIB)

.PHONY: clean

bios.cim: z88dk_section_layout.asm $(PARENT)/boot_block.c $(PARENT)/boot_confi.c \
          $(PARENT)/boot_entry.c $(PARENT)/bios_hw_init.c \
          $(PARENT)/bios_jump_vector_table.c $(PARENT)/bios.c \
          $(PARENT)/hal.h $(PARENT)/bios.h \
          $(PARENT)/builddate.h $(PARENT)/builddate.inc peephole.def
	$(RUN) sh -c '\
	zcc $(ZFLAGS) -Cs"--codeseg BOOT" -Cs"--constseg BOOT" -c ../boot_block.c -o boot_block.o && \
	zcc $(ZFLAGS) -Cs"--codeseg BOOT_DATA" -Cs"--constseg BOOT_DATA" $(if $(filter-out DANISH,$(KBLANG)),-Cs"-D$(KBLANG)") -c ../boot_confi.c -o boot_confi.o && \
	zcc $(ZFLAGS) -Cs"--codeseg BOOT_CODE" -c ../boot_entry.c -o boot_entry.o && \
	zcc $(ZFLAGS) -Cs"--codeseg BOOT_CODE" -c ../bios_hw_init.c -o bios_hw_init.o && \
	zcc $(ZFLAGS) -Cs"--codeseg BIOS" -Cs"--constseg BIOS" -c ../bios_jump_vector_table.c -o bios_jump_vector_table.o && \
	zcc $(ZFLAGS) $(ZLFLAGS) -o bios z88dk_section_layout.asm ../bios.c \
		boot_block.o boot_confi.o boot_entry.o bios_hw_init.o bios_jump_vector_table.o'
	@BSS_HEAD=$$(grep '__bss_compiler_head' bios.map | head -1 | sed 's/.*= \$$\([0-9A-Fa-f]*\).*/\1/'); \
	CODESIZE=$$((0x$$BSS_HEAD - $(BIOSAD))); \
	cat bios_BOOT.bin > bios.cim; \
	dd if=bios_BIOS.bin bs=1 count=$$CODESIZE 2>/dev/null >> bios.cim
	@echo "sdcc BIOS: $$(wc -c < bios.cim | tr -d ' ') bytes"
	@SIG=$$(dd if=bios.cim bs=1 skip=8 count=6 2>/dev/null); \
	if [ "$$SIG" != " RC702" ]; then \
		echo "ERROR: RC702 signature not found!"; exit 1; \
	fi

# Generate builddate files in parent if needed
$(PARENT)/builddate.h $(PARENT)/builddate.inc: FORCE
	$(MAKE) -C $(PARENT) builddate.h builddate.inc

FORCE:

clean:
	rm -f *.o bios bios.cim bios.map bios.lis bios_BOOT.bin bios_BIOS.bin
	rm -f *.sym bios.def zcc_opt.def *.c.lis *.c.asm
