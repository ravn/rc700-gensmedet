# Makefile for cpnos-rom — combined CP/NOS autoloader+BIOS PROM
#
# Usage:
#   make cpnos                    Build NOS-only image (ENABLE_FDC=0)
#   make cpnos ENABLE_FDC=1       Build NOS + 8" DSDD image
#   make cpnos-size               Size breakdown, verify <= 4096 bytes
#   make cpnos-burn               Produce prom0.bin + prom1.bin for burner
#   make cpnos-disasm             Disassemble the ELF
#   make cpnos-clean              Remove build artifacts
#
# Phase 0: proof-of-life.  All code lands in PROM0, PROM1 is 0xFF-padded.

ENABLE_FDC ?= 0

# Mirror every impl_conout byte to SIO-B as well as the CRT.  Default 1
# matches existing smoke / netboot tests that grep /tmp/cpnos_siob.raw
# for the boot prompt.  Set MIRROR_SIOB=0 for CRT-only -- impl_conout
# becomes a single-target write, ~12 B smaller in resident code, and
# SIO-B stays silent so the channel is free for other uses.
MIRROR_SIOB ?= 1

# Boot-progress marker: 19 single-byte writes to the upper-right of
# row 0 ("INIT OKPNILOREC+PSJ" by the time CCP starts).  Default 1
# keeps the marker on for bring-up / debugging.  Set to 0 for the
# tightest production PROM -- saves ~30-50 B by collapsing every
# BOOT_MARK() call site to a no-op.  See hal.h for placement.
BOOT_MARK_ENABLED ?= 1

# Bring-up scaffolding: enables the PIO-B 10-byte CP/NET frame loopback
# test in cpnos_main (Z80 sends -> harness mirrors -> Z80 validates).
# Off by default since session 33 — the real driver (transport_pio.c
# pio_send_msg / pio_recv_msg, with the boot-time probe) supersedes
# the bring-up scaffolding.  Set to 1 only to re-run the historical
# harness mode `loopback`.
PIO_LOOPBACK_TEST ?= 0
# Speed test (overrides PIO_LOOPBACK_TEST when nonzero):
#   1 = C-loop TX     (transport_pio_send_byte per byte; function-call cost)
#   2 = inline OTIR TX (raw OUT (C),(HL); INC HL; DEC B; ~21 T/byte)
#   3 = RX (ISR-driven; back-to-back ISRs; ring overflow at high rates)
#   4 = RX (INIR busy-poll; IE disabled; ~21 T/byte, no IRQ overhead)
PIO_SPEED_TEST    ?= 0

# ================================================================
# Compiler selection — clang (default) | sdcc | hitech (TBD)
# ================================================================
#
# Each compiler builds into its own output dir so the two PROMs can
# coexist (deploy time picks one).  Default is clang (existing path,
# byte-stable).  SDCC is being brought up in Phase 2 of the dual-
# compile port; HiTech is scaffolded and errors with "not implemented".
#
# Usage:
#   make cpnos                    # COMPILER=clang
#   make cpnos COMPILER=sdcc      # SDCC build (in progress)
#   make cpnos COMPILER=hitech    # HiTech (not yet implemented)
COMPILER ?= clang
BUILDDIR  = $(COMPILER)

ifeq ($(COMPILER),clang)
  # ---- clang Z80 toolchain -----------------------------------------
  LLVM_Z80    = $(CURDIR)/../../llvm-z80
  CLANG_BUILD = $(firstword $(wildcard $(LLVM_Z80)/build-linux/bin \
                                       $(LLVM_Z80)/build-macos/bin \
                                       $(LLVM_Z80)/build/bin))

  CC      = $(CLANG_BUILD)/clang
  LD      = $(CLANG_BUILD)/ld.lld
  OBJCOPY = $(CLANG_BUILD)/llvm-objcopy
  OBJDUMP = $(CLANG_BUILD)/llvm-objdump
  NM      = $(CLANG_BUILD)/llvm-nm

  CFLAGS = --target=z80 -std=c23 -Oz -nostdlib -g \
           -ffunction-sections -fdata-sections \
           -Xclang -target-feature -Xclang +static-stack \
           -mllvm -disable-lsr \
           -DENABLE_FDC=$(ENABLE_FDC) \
           -DMIRROR_SIOB=$(MIRROR_SIOB) \
           -DBOOT_MARK_ENABLED=$(BOOT_MARK_ENABLED) \
           -DRC702_SLAVEID=0x01 \
           $(SERVER_CFLAGS) \
           -I$(BUILDDIR) -I. -Icompiler \
           -Weverything \
           -Wno-unsafe-buffer-usage \
           -Wno-reserved-macro-identifier \
           -Wno-reserved-identifier \
           -Wno-gcc-compat \
           -Wno-declaration-after-statement \
           -Wno-pre-c11-compat \
           -Wno-pre-c23-compat \
           -Wno-int-to-pointer-cast \
           -Wno-cast-qual \
           -Wno-padded \
           -Wno-missing-prototypes \
           -Wno-missing-variable-declarations \
           -Wno-missing-noreturn \
           -Wno-sign-conversion

  ASFLAGS = --target=z80 -g

else ifeq ($(COMPILER),sdcc)
  # ---- z88dk-zsdcc toolchain (Phase 2 in progress) -----------------
  Z88DK_HOME ?= $(firstword $(wildcard $(CURDIR)/../../z88dk))
  ifneq ($(wildcard $(Z88DK_HOME)/bin/zcc),)
    # Native z88dk on the host.  Set ZCCCFG via exported var; export
    # PATH with z88dk's bin so zcc's internal `z88dk-z80asm` /
    # `z88dk-appmake` lookup succeeds.
    export ZCCCFG = $(Z88DK_HOME)/lib/config
    export PATH := $(Z88DK_HOME)/bin:$(PATH)
    ZCC = $(Z88DK_HOME)/bin/zcc
    RUN =
  else
    RUN = docker run --rm -v $(CURDIR):/src -w /src z88dk:2.4
    ZCC = zcc
  endif

  CC = $(RUN) $(ZCC)
  # SDCC link/asm tools wrapped via zcc — single front-end.
  LD      = $(CC)
  OBJCOPY = $(RUN) $(Z88DK_HOME)/bin/z88dk-appmake
  OBJDUMP = echo "(no llvm-objdump under sdcc)"
  NM      = echo "(no llvm-nm under sdcc)"

  # `--opt-code-size` was tried at zcc level (it switches z88dk's
  # peephole file from sdcc_peeph.3 to sdcc_peeph_cs.3) but it's a
  # NET LOSS in cpnos-rom: peephole_cs saves ~17 B across the
  # resident, but it also factors an 11 B `___sdcc_enter_ix` helper
  # out into a shared symbol.  The shared helper amortises only
  # against IX-frame function prologues -- this build has just 2
  # such functions (relocator.c::relocate, resident.c::delete_line),
  # so we save 3 B per prologue (6 B total) and pay 11 B for the
  # helper.  Net: +5 B resident, which overflows display memory at
  # 0xF800.  Re-enable when the build accumulates enough IX-frame
  # functions to amortise (or after refactoring those two via
  # tasks #27/#28).  See sibling rcbios-in-c/sdcc/Makefile for the
  # correct zcc-level wrapping when re-enabling.
  #
  # `--max-allocs-per-node 1000000` is INTENTIONAL and LOAD-BEARING.
  # 2026-05-08 #30 investigation tried 100000 / 250000 / 500000 and
  # all three produced byte-identical resident sizes AND identical
  # IX+/IY+ audit counts (12), yet the SDCC slave hangs early in
  # cold-init (never reaches E>) under all of them.  SDCC's register
  # allocator picks different registers at lower alloc budgets even
  # when the visible structural metrics match, and the difference is
  # enough to break polypascal-test boot.  Cost: 5-9 minute builds.
  # Don't lower without re-running cpnos-polypascal-test under SDCC.
  ZFLAGS_BASE = +z80 -compiler=sdcc -clib=sdcc_iy --no-crt \
                -Cs"--std-sdcc23" \
                -Cs"--sdcccall 1" \
                -Cs"--max-allocs-per-node 1000000" \
                -Cs"--fomit-frame-pointer" \
                -Cs"--allow-unsafe-read" \
                -Cs"--disable-warning 296"
  CFLAGS = $(ZFLAGS_BASE) -SO3 \
           '-DENABLE_FDC=$(ENABLE_FDC)' \
           '-DMIRROR_SIOB=$(MIRROR_SIOB)' \
           '-DBOOT_MARK_ENABLED=$(BOOT_MARK_ENABLED)' \
           '-DRC702_SLAVEID=0x01' \
           $(SERVER_CFLAGS) \
           -I$(BUILDDIR) -I. -Icompiler

  ASFLAGS =

else ifeq ($(COMPILER),hitech)
  $(error HiTech (zc) toolchain not yet implemented; see tasks/sdcc-port.md)

else
  $(error COMPILER must be 'clang', 'sdcc', or 'hitech')
endif

ifneq ($(PIO_SPEED_TEST),0)
CFLAGS += -DPIO_SPEED_TEST=$(PIO_SPEED_TEST)
else ifeq ($(PIO_LOOPBACK_TEST),1)
CFLAGS += -DPIO_LOOPBACK_TEST
endif

# Server side: default is standard MP/M II (cpmsim mpm-net2).
# Override with SERVER=proxy to use the legacy Python netboot_server.py
# (FMT=0xB0 custom protocol).
SERVER ?= mpm

ifeq ($(SERVER),mpm)
NETBOOT_OBJ = $(BUILDDIR)/netboot_mpm.o
SERVER_CFLAGS =
else ifeq ($(SERVER),proxy)
NETBOOT_OBJ = $(BUILDDIR)/netboot.o
SERVER_CFLAGS = -DNETBOOT_LEGACY
else
$(error SERVER must be 'mpm' or 'proxy')
endif

# Transport selection — picks which chip drives the byte-level CP/NET
# wire.  SNIOS calls _xport_send_byte / _xport_recv_byte (snios.s);
# we ld --defsym those names to the chip-specific implementations.
#
#   pio-irq  : Z80-PIO Mode 1, IRQ-driven 256-byte SPSC ring buffer
#              (transport_pio.c).  Default for this branch.
#   sio      : SIO-A async polled (transport_sio.c).  Original wire,
#              ~38400 baud, ~3.8 KB/s.
#
# Used by `make pio-irq-smoke`, `make sio-smoke`, etc.
TRANSPORT ?= pio-irq
ifeq ($(TRANSPORT),pio-irq)
TRANSPORT_DEFSYMS = --defsym=_xport_send_byte=_transport_pio_send_byte \
                    --defsym=_xport_recv_byte=_transport_pio_recv_byte
# Banner name shortened from "PIO-IRQ" (8 B incl. NUL) to "PIO" (4 B)
# 2026-05-08: the 4 saved bytes are exactly the resident overflow we
# hit on the SDCC pio-irq build (RESIDENT_RODATA tail was 4 B past
# 0xF800 / display memory).  IRQ vs PROXY mode is still distinguishable
# at runtime (only one transport is built; the make target name is
# the source of truth) and the date+hash in the banner already
# disambiguates the build.
TRANSPORT_NAME = PIO
else ifeq ($(TRANSPORT),sio)
TRANSPORT_DEFSYMS = --defsym=_xport_send_byte=_transport_send_byte \
                    --defsym=_xport_recv_byte=_transport_recv_byte
TRANSPORT_NAME = SIO
else ifeq ($(TRANSPORT),pio-proxy)
# pio-proxy uses raw OTIR/INIR frames (transport_pio_vt) — no SNIOS
# envelope, so the byte-level _xport_* aliases aren't on the hot path.
# Still need to alias them or the linker complains; point at the PIO
# byte primitives (the bridge tolerates whatever bytes appear on the
# wire — only the frame-level matters for correctness).
TRANSPORT_DEFSYMS = --defsym=_xport_send_byte=_transport_pio_send_byte \
                    --defsym=_xport_recv_byte=_transport_pio_recv_byte
# Banner name shortened to 3 chars to keep both pio variants under the
# resident size limit (see pio-irq comment above).
TRANSPORT_NAME = PRX
SERVER_CFLAGS += -DTRANSPORT_PROXY
else
$(error TRANSPORT must be 'pio-irq', 'sio', or 'pio-proxy')
endif

# Banner tag baked into transport_sio_vt.name (cpnos prints it as the
# wire-mode at boot — "RC702 CP/NOS WWW-MMM ...").  Padded to 7 chars
# (DRI's wire-mode field) — the build aborts if shorter.
#
# Quoting differs per compiler: clang accepts -DX='"value"', SDCC's zcc
# strips the inner quotes — use backslash-escaped form for SDCC.
ifeq ($(COMPILER),sdcc)
# zcc -> sdcpp: needs backslash-escaped quotes inside single-quoted shell arg
# so the literal `\"` reaches sdcpp's -D parser.
SERVER_CFLAGS += -DTRANSPORT_NAME='\"$(TRANSPORT_NAME)\"'
else
SERVER_CFLAGS += -DTRANSPORT_NAME='"$(TRANSPORT_NAME)"'
endif

# ---- Payload (linked at 0xED00, no PROM knowledge) ----------------
# The payload is the single contiguous blob of everything that runs
# at runtime.  The payload linker doesn't know about the two EPROMs;
# a separate relocator stitches it back together at cold boot.
PAYLOAD_OBJS = $(BUILDDIR)/runtime.o $(BUILDDIR)/bios_jt.o \
               $(BUILDDIR)/cpnos_main.o \
               $(BUILDDIR)/resident.o $(BUILDDIR)/cfgtbl.o $(BUILDDIR)/init.o \
               $(BUILDDIR)/transport_sio.o $(BUILDDIR)/transport_pio.o \
               $(NETBOOT_OBJ) \
               $(BUILDDIR)/snios.o $(BUILDDIR)/isr.o \
               $(BUILDDIR)/payload_checksum.o
PAYLOAD_LD = $(BUILDDIR)/payload.ld

# Preprocess payload.ld so the linker sees TRANSPORT_PROXY-conditional
# ASSERTs (e.g., the upper bound for __payload_end depends on whether
# the IRQ ring buffer at 0xF700 is in the layout).  ld.lld doesn't run
# cpp on linker scripts itself.
$(BUILDDIR)/payload.ld: payload.ld $(BUILDDIR)/transport_stamp
	@mkdir -p $(BUILDDIR)
	$(CC) --target=z80 -E -P -x c $(SERVER_CFLAGS) -o $@ $<

# ---- Relocator (PROM0 reset + #embed'd payload halves) -----------
# Tiny: reset.s for stack setup, relocator.c with two #embed arrays,
# plus a generated payload_header_data.s that carries metadata the
# relocator reads at boot (chunk sizes, BSS extents, cold entry, etc.)
# in lieu of the previous --defsym injection.  See
# tasks/scripts/gen_payload_header.py and payload_header.h.
RELOC_OBJS = $(BUILDDIR)/reset.o $(BUILDDIR)/relocator.o $(BUILDDIR)/payload_header_data.o
RELOC_LD = relocator.ld

ALL_OBJS = $(PAYLOAD_OBJS) $(RELOC_OBJS)

.PHONY: all cpnos cpnos-size cpnos-burn cpnos-disasm cpnos-clean \
        integration-test test cpnos-polypascal-test

all: cpnos

# Integration test: full E2E with z80pack mpm-net2 + MAME running CP/NOS
# slave + PolyPascal compiling and running PRIMES.PAS.  Catches the
# whole stack (transport, NDOS, BDOS, console, keyboard, file load,
# code execution, output framing).  Not part of `all` -- a normal build
# shouldn't boot MAME.  `make test` is an alias.
integration-test test: cpnos-polypascal-test

# Backwards-compatible alias for the old `make cpnos-ppas-test` name.
.PHONY: cpnos-ppas-test
cpnos-ppas-test: cpnos-polypascal-test

cpnos: $(BUILDDIR)/cpnos.bin cpnos-size cpnos-lis

# Flag changes (e.g. -DRC702_SLAVEID=) must invalidate all objects.
$(ALL_OBJS): Makefile $(BUILDDIR)/transport_stamp

# Re-stamp whenever TRANSPORT changes so a `make cpnos TRANSPORT=sio`
# after a `TRANSPORT=pio-irq` build (or vice versa) actually picks up
# the new -DTRANSPORT_NAME / --defsym aliases instead of relinking
# stale .o files.  The stamp's content is the current TRANSPORT value.
.PHONY: $(BUILDDIR)/transport_stamp
$(BUILDDIR)/transport_stamp:
	@mkdir -p $(BUILDDIR)
	@if [ ! -f $@ ] || [ "$$(cat $@ 2>/dev/null)" != "$(TRANSPORT)" ]; then \
	    echo "$(TRANSPORT)" > $@; \
	    echo "transport stamp: $(TRANSPORT)"; \
	fi

# ---- Compile ------------------------------------------------------

$(BUILDDIR)/reset.o: reset.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILDDIR)/runtime.o: runtime.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILDDIR)/bios_jt.o: bios_jt.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILDDIR)/snios.o: snios.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

# Phase 2B: cpnos_main.c (nos_handoff) writes ZP[5..7] = JP BDOS
# itself, replacing cpnos-build's deleted cpnos.asm entry stub.
# BDOS's address is link-time-determined inside cpnos.com; extract it
# from cpnos.sym into a generated header.
$(BUILDDIR)/cpnos_addrs.h: cpnos-build/d/cpnos.com
	@mkdir -p $(BUILDDIR)
	@perl -ne 'while (/([0-9A-Fa-f]{4})\s+BDOS\b/g) { print "#define CPNOS_BDOS_ADDR 0x$$1\n"; last }' \
	    cpnos-build/d/cpnos.sym > $@.tmp
	@grep -q '^#define CPNOS_BDOS_ADDR' $@.tmp || \
	    { echo "ERROR: BDOS symbol missing from cpnos.sym"; rm -f $@.tmp; exit 1; }
	@# TPA top reported by CP/M utilities = NDOSE = NDOS + 0x0122 (the
	@# NDOS BDOS-replacement entry).  TPA size = TPA top - 0x0100.
	@N=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 [ -n "$$N" ] || { echo "ERROR: NDOS symbol missing from cpnos.sym"; rm -f $@.tmp; exit 1; }; \
	 NV=$$((0x$$N)); \
	 TPA_KB=$$(( (NV + 0x122 - 0x100) / 1024 )); \
	 NDOSE=$$(printf '0x%04X' $$(( NV + 3 )) ); \
	 echo "#define CPNOS_NDOS_ADDR 0x$$N" >> $@.tmp; \
	 echo "#define CPNOS_NDOSE_ADDR $$NDOSE   /* NDOS + 3, the BDOS dispatch entry */" >> $@.tmp; \
	 echo "#define CPNOS_TPA_KB $$TPA_KB" >> $@.tmp
	@mv $@.tmp $@
	@echo "cpnos_addrs.h: $$(grep -E 'BDOS_ADDR|NDOS_ADDR|NDOSE_ADDR|TPA_KB' $@ | tr '\n' ' ')"

# Build info — UTC date + short git hash, regenerated every build so
# the signon banner reflects the moment this PROM was burnt.  The
# `cmp` dance avoids pointlessly retouching the file (and rebuilding
# cpnos_main.o) when neither field changed since last build.
.PHONY: $(BUILDDIR)/cpnos_buildinfo.h
$(BUILDDIR)/cpnos_buildinfo.h:
	@mkdir -p $(BUILDDIR)
	@D=$$(date -u +"%Y-%m-%d %H:%M"); \
	 H=$$(git rev-parse --short HEAD 2>/dev/null || echo "????"); \
	 if ! git diff --quiet -- . 2>/dev/null; then H="$$H+"; fi; \
	 { \
	   echo '#ifndef CPNOS_BUILDINFO_H'; \
	   echo '#define CPNOS_BUILDINFO_H'; \
	   echo "#define BUILD_DATE_STR \"$$D\""; \
	   echo "#define GIT_HASH_STR   \"$$H\""; \
	   echo '#define BUILD_INFO_STR BUILD_DATE_STR " " GIT_HASH_STR'; \
	   echo '#endif'; \
	 } > $@.tmp; \
	 if cmp -s $@.tmp $@ 2>/dev/null; then rm -f $@.tmp; \
	 else mv $@.tmp $@; echo "buildinfo: $$D $$H"; fi

$(BUILDDIR)/cpnos_main.o: cpnos_main.c hal.h $(BUILDDIR)/cpnos_addrs.h $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/resident.o: resident.c hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/payload_checksum.o: payload_checksum.c
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/cfgtbl.o: cfgtbl.c
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/init.o: init.c hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/isr.o: isr.c hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/transport_sio.o: transport_sio.c transport.h hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/transport_pio.o: transport_pio.c transport.h hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/netboot.o: netboot.c transport.h hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/netboot_mpm.o: netboot_mpm.c hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Relocator: includes init/payload byte arrays via `#include "*.inc"`.
# Each .inc is a comma-separated byte stream generated from the
# matching .bin by tasks/scripts/bin2inc.py.  The mechanism is
# compiler-portable: clang and SDCC see the same C source, with the
# .inc resolved via per-compiler -I.  C23 `#embed` would be cleaner
# but SDCC doesn't implement it.  See tasks/sdcc-port.md.
#
# Relocator compile flags: same as CFLAGS but without the
# `-Xclang -target-feature -Xclang +static-stack` sequence.  The
# relocator stack is at SP=0xED00 (RAM) and stack-allocated C
# locals work fine; +static-stack would put them in .bss, which
# relocator.ld discards — link fails on .bss relocation.
CFLAGS_RELOC = $(subst -Xclang -target-feature -Xclang +static-stack,,$(CFLAGS))

# ---- clang-specific relocator chain ------------------------------
# Two-stage link: first payload.elf (resident), then relocator.elf
# (PROM-image with relocator code + payload header + chunk bytes
# embedded via #include ".inc").  The SDCC pipeline below uses a
# single-stage link instead and provides its own relocator-build
# rules.
ifeq ($(COMPILER),clang)

# Generated .inc files — re-emitted whenever the .bin or the
# converter script changes.
$(BUILDDIR)/%.inc: $(BUILDDIR)/%.bin tasks/scripts/bin2inc.py
	python3 tasks/scripts/bin2inc.py $< $@

$(BUILDDIR)/relocator.o: relocator.c payload_header.h \
                   $(BUILDDIR)/init.inc $(BUILDDIR)/payload_a.inc $(BUILDDIR)/payload_b.inc
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS_RELOC) -c $< -o $@

# Generate payload_header_data.s from the linked payload.elf.  Carries
# the metadata the relocator reads at boot (chunk sizes, BSS extents,
# cold entry, etc.) in lieu of --defsym injection.  Re-emit whenever
# payload.elf or the generator script changes.
$(BUILDDIR)/payload_header_data.s: $(BUILDDIR)/payload.elf $(BUILDDIR)/payload.bin \
                                   tasks/scripts/gen_payload_header.py
	python3 tasks/scripts/gen_payload_header.py \
	    --syntax=clang \
	    --payload-elf=$(BUILDDIR)/payload.elf \
	    --payload-bin=$(BUILDDIR)/payload.bin \
	    --chunk-a-size=$(PROM0_TAIL_SIZE) \
	    --llvm-nm=$(NM) \
	    --include-ivt \
	    --out=$@

$(BUILDDIR)/payload_header_data.o: $(BUILDDIR)/payload_header_data.s
	$(CC) --target=z80 -c $< -o $@

# ---- Link payload (no PROM awareness) ----------------------------

$(BUILDDIR)/payload.elf: $(PAYLOAD_OBJS) $(PAYLOAD_LD) cpnos-build/d/cpnos.sym
	@# Extract NDOS load address from cpnos.sym and pass cpnos.com end
	@# (NDOS + 0xC80) as a linker symbol so payload.ld's stack/cpnos
	@# overlap ASSERTs can fire.  Catches the Option β bring-up bug
	@# (stack at 0xED00 colliding with raised cpnos.com top) at link
	@# time instead of as silent boot-time RAM corruption.
	@N=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 [ -n "$$N" ] || { echo "ERROR: NDOS symbol missing from cpnos.sym"; exit 1; }; \
	 NEND=$$(printf '0x%X' $$(( 0x$$N + 0xC80 ))); \
	 echo "payload.elf: __cpnos_load_end = $$NEND (NDOS 0x$$N + 0xC80)"; \
	 $(LD) --gc-sections --emit-relocs -T $(PAYLOAD_LD) \
	    --defsym=__cpnos_load_end=$$NEND \
	    $(TRANSPORT_DEFSYMS) $(PAYLOAD_OBJS) -o $@

$(BUILDDIR)/payload.bin: $(BUILDDIR)/payload.elf cpnos-build/patch_payload_checksum.py
	$(OBJCOPY) -O binary --only-section=.payload $< $@
	# Patch the payload integrity checksum into the last 2 bytes
	# of the resident image.  See patch_payload_checksum.py /
	# payload.ld (.payload_checksum section).
	python3 cpnos-build/patch_payload_checksum.py $@

# Init image: .init output section -- runs in place from PROM 0
# at 0x0100, never copied to RAM.  Init/resident split, step 3.
$(BUILDDIR)/init.bin: $(BUILDDIR)/payload.elf
	$(OBJCOPY) -O binary --only-section=.init $< $@

# Split resident payload.bin into the two chunks the relocator
# #embed's.  Split point = relocator.ld's .prom0_tail base.  After
# the init/resident split (step 3) PROM 0 layout is:
#   0x0000 reset (0x0F)
#   0x0010 relocator code + payload header (~0x200 B, capped at 0x200)
#   0x0200 init.bin (.init runs in place, up to 0x300)
#   0x0500 .prom0_tail = first PROM0_TAIL_SIZE bytes of resident
#   0x2000 .prom1     = remaining resident bytes
# PROM0_TAIL_SIZE = 0x800 - 0x500 = 0x300 = 768 bytes (was 1024
# before 2026-05-07 .init bump from 0x100 to 0x200 to give the
# data-driven relocator more code budget; PROM1 absorbs the 256 B
# difference, still within its 1536 B clearance from display memory).
PROM0_TAIL_SIZE = 768
$(BUILDDIR)/payload_a.bin $(BUILDDIR)/payload_b.bin: $(BUILDDIR)/payload.bin
	dd if=$< of=$(BUILDDIR)/payload_a.bin bs=1 count=$(PROM0_TAIL_SIZE) status=none
	dd if=$< of=$(BUILDDIR)/payload_b.bin bs=1 skip=$(PROM0_TAIL_SIZE) status=none

# ---- Link relocator ----------------------------------------------
# The relocator reads its metadata from the payload header (emitted by
# tasks/scripts/gen_payload_header.py into payload_header_data.s and
# linked into RELOC_OBJS).  Only `__stack_top` still needs --defsym
# injection — that one is consumed by reset.s, not by relocator.c, and
# reset.s runs BEFORE the relocator could read the header.
#
# Six previous --defsym lines (`_cpnos_cold_entry`, `_bios_boot`,
# `__scratch_bss_*`, `__pio_rx_bss_*`) were dropped 2026-05-07 when
# the relocator became header-driven — see plan
# /Users/ravn/.claude/plans/harmonic-sleeping-spring.md and
# memory feedback_relink_dependencies_atomically.md for why this
# four-way coupling was a structural problem.

$(BUILDDIR)/relocator.elf: $(RELOC_OBJS) $(RELOC_LD) $(BUILDDIR)/payload.elf
	@stack=$$($(NM) $(BUILDDIR)/payload.elf | awk '/ __stack_top$$/ {print "0x"$$1}'); \
	 test -n "$$stack" || { echo "ERROR: __stack_top not found in payload"; exit 1; }; \
	 echo "relocator: __stack_top=$$stack (other metadata via payload_header)"; \
	 $(LD) --gc-sections -T $(RELOC_LD) \
	       --defsym=__stack_top=$$stack \
	       $(RELOC_OBJS) -o $@

# ---- Produce prom0.bin / prom1.bin (clang only) -------------------
# SDCC provides its own cpnos.bin recipe at the bottom of this file.

$(BUILDDIR)/cpnos.bin: $(BUILDDIR)/relocator.elf
	$(OBJCOPY) -O binary --gap-fill=0xFF --pad-to=0x2800 $< $(BUILDDIR)/cpnos.raw
	dd if=$(BUILDDIR)/cpnos.raw of=$(BUILDDIR)/prom0.bin bs=2048 count=1 status=none
	dd if=$(BUILDDIR)/cpnos.raw of=$(BUILDDIR)/prom1.bin bs=2048 skip=4 count=1 status=none
	cat $(BUILDDIR)/prom0.bin $(BUILDDIR)/prom1.bin > $@

endif  # ifeq ($(COMPILER),clang)

# ---- Size check ---------------------------------------------------

cpnos-size: $(BUILDDIR)/cpnos.bin
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 P1=$$(wc -c < $(BUILDDIR)/prom1.bin | tr -d ' '); \
	 PLD=$$(wc -c < $(BUILDDIR)/payload.bin | tr -d ' '); \
	 TOTAL=$$(wc -c < $(BUILDDIR)/cpnos.bin | tr -d ' '); \
	 echo "payload:  $$PLD bytes (linked at 0xED00)"; \
	 echo "PROM0:    $$P0 / 2048 bytes"; \
	 echo "PROM1:    $$P1 / 2048 bytes"; \
	 echo "TOTAL:    $$TOTAL / 4096 bytes"; \
	 test $$TOTAL -eq 4096 || { echo "ERROR: image not exactly 4096 bytes"; exit 1; }
	@echo "--- payload section sizes ---"
	@$(OBJDUMP) --headers $(BUILDDIR)/payload.elf | awk '/\.(payload|scratch)/ { printf "%-16s 0x%s VMA=0x%s\n", $$2, $$3, $$4 }'
	@echo "--- top payload symbols ---"
	@$(NM) --numeric-sort --size-sort --reverse-sort $(BUILDDIR)/payload.elf | head -10
	@echo "--- actual code bytes in PROM0 (non-0xFF) ---"
	@od -An -tx1 $(BUILDDIR)/prom0.bin | tr -s ' ' '\n' | grep -v '^$$' | grep -v '^ff$$' | wc -l | awk '{ printf "%d non-padding bytes\n", $$1 }'

# ---- CP/M .COM loader (test PROMs without burning) ---------------
#
# Produces a ~4 KB .COM that, when executed from the CP/M prompt,
# copies prom0.bin into 0x0000 and prom1.bin into 0x2000 then JPs
# to 0x0000 — mimicking a cold boot against new PROM payloads
# without touching physical EPROMs.  See build_loader.py for layout.

cpnos-loader: $(BUILDDIR)/cpnos.bin
	python3 build_loader.py $(BUILDDIR)/prom0.bin $(BUILDDIR)/prom1.bin $(BUILDDIR)/cpnos_loader.com
	cp $(BUILDDIR)/cpnos_loader.com testutil/cpnosldr.com
	@echo "staged testutil/cpnosldr.com (run 'cpnosldr' from CP/M A>)"

# ---- Split for burner --------------------------------------------

cpnos-burn: $(BUILDDIR)/cpnos.bin
	@echo "PROM0 (0x0000-0x07FF): $(BUILDDIR)/prom0.bin ($$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' ') B)"
	@echo "PROM1 (0x2000-0x27FF): $(BUILDDIR)/prom1.bin ($$(wc -c < $(BUILDDIR)/prom1.bin | tr -d ' ') B)"

# ---- Switch MAME into cpnos boot mode ----------------------------
#
# RC702 has two PROM slots and the MAME rc702 driver loads each from
# a separate file:
#     PROM 0 ($0000..$07FF) <- mame/roms/rc702/roa375.ic66
#     PROM 1 ($2000..$27FF) <- mame/roms/rc702/prom1.ic65
#
# This target SWITCHES MAME into the cpnos network-boot mode by
# overwriting BOTH files with today's cpnos build:
#     prom0.bin -> roa375.ic66
#     prom1.bin -> prom1.ic65
#
# Both MUST be refreshed in lockstep.  Refreshing only one
# mismatches the patcher's checksum correction (which lives in
# payload_b -> prom1.bin) against today's body sum, triggering the
# cpnos PROM's BAD CHECKSUM infinite loop -- visible as a black
# screen with "BAD CHECKSUM" at row 0 of the CRT.
#
# Mode swap: to go back to the rcbios standalone (autoload-PROM)
# boot mode, run `make prom` in ../autoload-in-c/, which writes
# autoload-in-c's prom.bin -> roa375.ic66 (overwriting cpnos's
# PROM 0).  prom1.ic65 is unused in autoload mode but stays as
# whatever was last installed.
#
# Note: cpnos requires a host-side z80pack mpm-net2 server to do
# anything beyond the banner (per project_cpnos_mame_prereqs).
# This target refreshes PROMs only -- spinning up mpm is the
# user's job.  For BIOS-only verification work (no cpnos network
# code), use rcbios standalone mode instead -- it boots end-to-end
# without mpm.

MAME_ROMS_DIR ?= $(CURDIR)/../../mame/roms/rc702

mame-roms-cpnos: $(BUILDDIR)/cpnos.bin
	@test -d "$(MAME_ROMS_DIR)" || \
	    { echo "ERROR: MAME_ROMS_DIR=$(MAME_ROMS_DIR) does not exist"; exit 1; }
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 P1=$$(wc -c < $(BUILDDIR)/prom1.bin | tr -d ' '); \
	 test "$$P0" = "2048" || { echo "ERROR: prom0.bin is $$P0 B, expected 2048"; exit 1; }; \
	 test "$$P1" = "2048" || { echo "ERROR: prom1.bin is $$P1 B, expected 2048"; exit 1; }
	cp $(BUILDDIR)/prom0.bin "$(MAME_ROMS_DIR)/roa375.ic66"
	cp $(BUILDDIR)/prom1.bin "$(MAME_ROMS_DIR)/prom1.ic65"
	@echo "Switched MAME into cpnos mode:"
	@echo "  $(MAME_ROMS_DIR)/roa375.ic66 (cpnos prom0)"
	@echo "  $(MAME_ROMS_DIR)/prom1.ic65 (cpnos prom1)"
	@echo "To switch back to rcbios standalone mode, run:"
	@echo "  cd ../autoload-in-c && make prom"

# ---- Inspection --------------------------------------------------

cpnos-disasm: $(BUILDDIR)/payload.elf $(BUILDDIR)/relocator.elf
	$(OBJDUMP) -d --triple=z80 $(BUILDDIR)/payload.elf
	@echo '=== relocator ==='
	$(OBJDUMP) -d --triple=z80 $(BUILDDIR)/relocator.elf

# ---- MAME boot test ----------------------------------------------

MAME = /Users/ravn/git/mame
MAME_PROM0 = $(MAME)/roms/rc702/roa375.ic66
MAME_PROM1 = $(MAME)/roms/rc702/prom1.ic65

# Disk-image install: rebuild cpnos.com from cpnos-build/ and inject the
# fresh blob into both MP/M library disks.  Prevents the "PROM updated
# but disk still has stale cpnos.com" trap (2026-04-25 incident — see
# memory: project_cpnos_address_coupling_brittle).  The launcher prefers
# cpnetsmk-1.dsk if present, so updating only mpm-net2-1.dsk silently
# fails to take effect — both must be refreshed.
MPM_DISK_LIB = ../z80pack/cpmsim/disks/library
cpnos-disk-install: cpnos-build/d/cpnos.com
	@echo "=== stamping cpnos.com with build timestamp ==="
	@python3 cpnos-build/stamp_cpnos.py cpnos-build/d/cpnos.com $(BUILDDIR)/cpnos_stamped.com
	@echo "=== installing stamped cpnos.com onto MP/M library disks ==="
	@cpmrm -f ibm-3740 $(MPM_DISK_LIB)/mpm-net2-1.dsk 0:cpnos.img 2>/dev/null || true
	cpmcp -f ibm-3740 $(MPM_DISK_LIB)/mpm-net2-1.dsk \
	    $(BUILDDIR)/cpnos_stamped.com 0:cpnos.img
	@if [ -f $(MPM_DISK_LIB)/cpnetsmk-1.dsk ]; then \
	    cpmrm -f ibm-3740 $(MPM_DISK_LIB)/cpnetsmk-1.dsk 0:cpnos.img 2>/dev/null || true; \
	    cpmcp -f ibm-3740 $(MPM_DISK_LIB)/cpnetsmk-1.dsk \
	        $(BUILDDIR)/cpnos_stamped.com 0:cpnos.img; \
	    echo "  refreshed cpnos.img on cpnetsmk-1.dsk"; \
	 fi
	@echo "  refreshed cpnos.img on mpm-net2-1.dsk"

# Force cpnos.com to rebuild whenever any of its sources change.
.PHONY: cpnos-disk-install
cpnos-build/d/cpnos.com: $(wildcard cpnos-build/src/*.asm cpnos-build/src/*.s) cpnos-build/Makefile
	$(MAKE) -C cpnos-build all

# Install prom0.bin into MAME (4KB slot, pad with 0xFF).  PROM1 at
# 0x2000 in MAME is 0xFF by default — fine for Phase 1 where our
# PROM1 is unused.
#
# Depends on cpnos-disk-install so a single `make cpnos-install` (and
# anything that pulls in cpnos-install — cpnet-smoke, cpnos-mame, etc.)
# guarantees the disk-side cpnos.com matches the freshly-built PROM.
cpnos-install: $(BUILDDIR)/cpnos.bin cpnos-disk-install
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 { cat $(BUILDDIR)/prom0.bin; perl -e "print \"\\xff\" x (4096 - $$P0)"; } \
	   > $(BUILDDIR)/prom0_padded.ic66
	cp $(BUILDDIR)/prom0_padded.ic66 $(MAME_PROM0)
	cp $(BUILDDIR)/prom1.bin         $(MAME_PROM1)
	@echo "installed cpnos prom0 -> $(MAME_PROM0)"
	@echo "installed cpnos prom1 -> $(MAME_PROM1)"

# ---- cpnet-smoke: end-to-end test against live MP/M ---------------
#
# Non-trivial test: slave drives CP/M ASM (from master B:) to assemble
# an unrolled sum-of-1..1000 program from master D:, LOADs the HEX to
# COM (also on D:), and runs it.  The program computes 0xA314 and
# prints "CPNET OK A314".  Any CP/NET or CCP/BDOS/BIOS regression
# corrupts the assembler's output → the running program prints the
# wrong string or crashes → grep fails → make target fails.
#
# Preconditions:
#   - MP/M is running in a screen session (see
#     z80pack/cpmsim/mpm-net2).  Target restarts it so the drive
#     staging is fresh.
#   - cpnos-rom is built and installed into MAME.
#
# Prints PASS or FAIL and exits accordingly.
MPM_DIR ?= $(CURDIR)/../z80pack/cpmsim
SMOKE_PORT ?= 9001

# WORKLOAD selects which CCP-driven program the bench harness runs.
# Each value here is a key in WORKLOADS (testutil/smoke_inject.py)
# plus a corresponding finish-marker string + 1-line description.
#   sumtest  : m80 sumtest,=sumtest.asm + l80 + sumtest (CPU-bound,
#              ~10:1 read:write CP/NET RTTs; deterministic CPNET OK
#              A314 verifies arithmetic).
#   filecopy : pre-staged FILECOPY.COM reads SUMTEST.ASM record-by-
#              record via BDOS F_READ and writes SUMTEST.CPY via
#              F_WRITE.  Pure file I/O, no compiler in the timed
#              window.  Verify step extracts both files via cpmcp and
#              byte-compares them.
WORKLOAD ?= sumtest
ifeq ($(WORKLOAD),sumtest)
WORKLOAD_MARKER = CPNET OK A314
WORKLOAD_DESC   = m80+l80+sumtest
else ifeq ($(WORKLOAD),filecopy)
WORKLOAD_MARKER = FILECOPY OK
WORKLOAD_DESC   = filecopy (R+W SUMTEST.ASM via CP/NET)
else
$(error WORKLOAD must be 'sumtest' or 'filecopy')
endif

# ---- preflight checks: setup must match target ---------------------
#
# The "wire-mode tag" baked into the cpnos banner (and visible at
# runtime as e.g. "RC702 CP/NOS PIO-IRQ ...") is set from
# active_transport->name in transport_sio.c.  The string lives at a
# fixed offset in cpnos.bin, so a literal grep on the binary tells us
# what the slave will report.  Targets assert the right tag is present
# (or absent) to avoid the topology-mismatch class of bug from
# 2026-04-28 (Phase 27c — see tasks/timeline.md).
#
# Likewise we check that MAME_IRQ exists with the cpnet_bridge gate
# fix before pio-irq-* targets launch — otherwise the slave's IRQ
# path silently drops bytes when poll_tick over-strobes.

# Slave was built with active_transport->name = "PIO-IRQ"
_check-tag-pio-irq:
	@if ! strings $(BUILDDIR)/cpnos.bin 2>/dev/null | grep -q '^PIO-IRQ '; then \
	    echo "FAIL: cpnos.bin does not contain wire-mode tag 'PIO-IRQ'."; \
	    echo "      This target requires a PIO-IRQ build; check"; \
	    echo "      transport_sio.c's transport_sio_vt.name."; \
	    exit 1; \
	fi

# Slave was NOT built for PIO-IRQ (cpnet-smoke wires SIO-A, not PIO-B)
_check-tag-not-pio-irq:
	@if strings $(BUILDDIR)/cpnos.bin 2>/dev/null | grep -q '^PIO-IRQ '; then \
	    echo "FAIL: cpnos.bin reports wire-mode 'PIO-IRQ' but this target"; \
	    echo "      wires SIO-A only.  Either rebuild cpnos for SIO mode"; \
	    echo "      or use 'make pio-irq-smoke' instead."; \
	    exit 1; \
	fi

# Slave was built with active_transport->name = "PIO-PRX" (pio-proxy mode).
_check-tag-pio-prx:
	@if ! strings $(BUILDDIR)/cpnos.bin 2>/dev/null | grep -q '^PIO-PRX '; then \
	    echo "FAIL: cpnos.bin does not contain wire-mode tag 'PIO-PRX'."; \
	    echo "      This target requires a TRANSPORT=pio-proxy build."; \
	    exit 1; \
	fi

# MAME_IRQ tree contains the cpnet_bridge gate fix (commit 60e2b9a032f
# on pio-mpm-irq-fix branch).  We check by source-grep, not by binary
# inspection — robust against the binary being rebuilt without the fix.
_check-mame-irq:
	@if [ ! -x $(MAME_IRQ)/regnecentralend ]; then \
	    echo "FAIL: $(MAME_IRQ)/regnecentralend not found or not executable"; \
	    exit 1; \
	fi
	@if [ ! -f $(MAME_IRQ)/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp ]; then \
	    echo "FAIL: $(MAME_IRQ) is not a MAME tree (no cpnet_bridge.cpp)"; \
	    exit 1; \
	fi
	@if ! grep -q 'm_brdy_high' $(MAME_IRQ)/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp; then \
	    echo "FAIL: $(MAME_IRQ) cpnet_bridge.cpp missing the gate fix."; \
	    echo "      Need branch with poll_tick gated on m_brdy_high"; \
	    echo "      (commit 60e2b9a032f on ravn/mame:pio-mpm-irq-fix)."; \
	    exit 1; \
	fi
	@if [ ! $(MAME_IRQ)/regnecentralend -nt $(MAME_IRQ)/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp ]; then \
	    echo "FAIL: $(MAME_IRQ)/regnecentralend is older than cpnet_bridge.cpp."; \
	    echo "      Rebuild MAME (cd $(MAME_IRQ) && make)."; \
	    exit 1; \
	fi

# ---- _verify-bench: shared bench verifier (post-MAME) -----------
# Asserts SIO-B contains the workload's finish marker, prints the
# smoke_inject "bench=X.XXXs" timing, and (for filecopy) extracts
# SUMTEST.ASM + SUMTEST.CPY from the master's drivea.dsk and byte-
# compares them.  WORKLOAD must already be set by the caller.
.PHONY: _verify-bench
_verify-bench:
	@echo "=== verify ($(WORKLOAD)): marker '$(WORKLOAD_MARKER)' ==="
	@echo "--- inject log ---"
	@cat /tmp/cpnos_smoke_inject.log
	@echo "--- SIO-B tail ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw 2>/dev/null | tail -c 400
	@echo
	@grep -q '$(WORKLOAD_MARKER)' /tmp/cpnos_siob.raw \
	    && echo "PASS: marker '$(WORKLOAD_MARKER)' present" \
	    || (echo "FAIL: marker '$(WORKLOAD_MARKER)' not in SIO-B"; exit 1)
	@bench=$$(grep -oE 'bench=[0-9.]+s' /tmp/cpnos_smoke_inject.log | tail -1); \
	 [ -n "$$bench" ] && echo "BENCH (-nothrottle, $(WORKLOAD_DESC)): $$bench" \
	   || echo "(bench timing not found)"
ifeq ($(WORKLOAD),filecopy)
	@echo "--- frames-to-completion / throughput (from FILECOPY OK) ---"
	@line=$$(grep 'FILECOPY OK' /tmp/cpnos_siob.raw | tail -1 | tr -d '\r'); \
	 echo "  $$line"; \
	 r=$$(echo "$$line" | sed -nE 's/.*FILECOPY OK ([0-9A-F]{4}) .*/\1/p'); \
	 s=$$(echo "$$line" | sed -nE 's/.*S=([0-9A-F]{8}).*/\1/p'); \
	 e=$$(echo "$$line" | sed -nE 's/.*E=([0-9A-F]{8}).*/\1/p'); \
	 if [ -n "$$r" ] && [ -n "$$s" ] && [ -n "$$e" ]; then \
	   recs=$$(printf '%d' $$((0x$$r))); \
	   d=$$(printf '%d' $$((0x$$e - 0x$$s))); \
	   bytes_dir=$$((recs * 128)); \
	   bytes_total=$$((bytes_dir * 2)); \
	   echo "  records = $$recs ($$bytes_dir B per direction, $$bytes_total B total R+W)"; \
	   echo "  frames  = E - S = $$d (= $$(echo "scale=2; $$d / 50" | bc) s emulated @ 50 Hz CRT)"; \
	   if [ "$$d" -gt 0 ]; then \
	     kbps_dir=$$(echo "scale=2; $$bytes_dir * 50 / $$d / 1024" | bc); \
	     kbps_tot=$$(echo "scale=2; $$bytes_total * 50 / $$d / 1024" | bc); \
	     echo "  THROUGHPUT (one direction) = $$kbps_dir KB/s emulated"; \
	     echo "  THROUGHPUT (R+W combined)  = $$kbps_tot KB/s emulated"; \
	   fi; \
	 fi
	@echo "--- byte-compare SUMTEST.ASM vs SUMTEST.CPY ---"
	@DRIVE_A=$(MPM_DIR)/disks/drivea.dsk; \
	 cpmcp -f ibm-3740 $$DRIVE_A 0:SUMTEST.ASM /tmp/_ref.asm 2>/dev/null || \
	     (echo "FAIL: cpmcp could not extract SUMTEST.ASM from $$DRIVE_A"; exit 1); \
	 cpmcp -f ibm-3740 $$DRIVE_A 0:SUMTEST.CPY /tmp/_cpy.asm 2>/dev/null || \
	     (echo "FAIL: cpmcp could not extract SUMTEST.CPY"; exit 1); \
	 ref_n=$$(wc -c < /tmp/_ref.asm | tr -d ' '); \
	 cpy_n=$$(wc -c < /tmp/_cpy.asm | tr -d ' '); \
	 echo "  SUMTEST.ASM: $$ref_n bytes"; \
	 echo "  SUMTEST.CPY: $$cpy_n bytes"; \
	 head -c $$ref_n /tmp/_cpy.asm > /tmp/_cpy_head.asm; \
	 if cmp -s /tmp/_ref.asm /tmp/_cpy_head.asm; then \
	     echo "PASS: first $$ref_n bytes identical (CPY tail is record-pad)"; \
	 else \
	     echo "FAIL: byte mismatch in CPY[0..$$ref_n]; first 5 offsets:"; \
	     cmp -l /tmp/_ref.asm /tmp/_cpy_head.asm 2>/dev/null | head -5; \
	     exit 1; \
	 fi
endif

cpnet-smoke: cpnos-install _check-tag-not-pio-irq

# ---- sio-smoke: pio-irq-smoke counterpart for SIO mode ------------
# Recursive make invocation so TRANSPORT=sio reaches all the rebuild
# rules (the stamp triggers the .o invalidation).  cpnet-smoke's own
# preflight (_check-tag-not-pio-irq) verifies the build came out right.
.PHONY: sio-smoke
sio-smoke:
	$(MAKE) cpnet-smoke TRANSPORT=sio WORKLOAD=$(WORKLOAD)
	@echo "=== 1/5 regenerating sumtest.asm + smoke disk ==="
	python3 testutil/mksmokeasm.py
	testutil/mksmokedisk.sh
	@echo "=== 2/5 restarting MP/M with fresh drive D: ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@# Guard: make sure nothing else is squatting on :4002 (stray
	@# netboot_server.py, orphan cpmsim, ...) — any phantom listener
	@# will intercept MAME's netboot and produce misleading results.
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound — kill the squatter first:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@echo "=== 3/5 waiting for MP/M CP/NET server on :4002 ==="
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.5; done
	@sleep 4
	@echo "=== 4/5 launching MAME + smoke injector (workload: $(WORKLOAD)) ==="
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_smoke_inject.log /tmp/cpnos_boot_marks.txt
	@python3 -u testutil/smoke_inject.py $(SMOKE_PORT) \
	    --workload $(WORKLOAD) \
	    --log /tmp/cpnos_siob.raw --timeout 240 \
	    > /tmp/cpnos_smoke_inject.log 2>&1 & \
	 echo $$! > /tmp/cpnos_smoke_inject.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 1200 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 socket.127.0.0.1:$(SMOKE_PORT) \
	    -autoboot_script mame_porttap.lua
	@kill $$(cat /tmp/cpnos_smoke_inject.pid) 2>/dev/null || true
	@$(MAKE) _verify-bench WORKLOAD=$(WORKLOAD)

cpnos-mame: cpnos-install
	$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 8 \
	    -rs232a null_modem \
	    -bitb1 /tmp/cpnos_sioa.raw \
	    -autoboot_script mame_boot_test.lua

# ---- pio-irq-netboot: PIO-IRQ-direct topology against mpm-net2 -----
#
# The irq-fix branch slave drives SNDMSG/RCVMSG over PIO byte primitives
# (transport_pio_send_byte / transport_pio_recv_byte in transport_pio.c)
# but keeps the SNIOS envelope (ENQ/ACK/SOH/STX/ETX/EOT framing).  Since
# mpm-net2 also speaks the SNIOS envelope on its TCP port, the slave
# byte stream and mpm-net2's wire stream are bit-identical — no host
# proxy required.  Just connect MAME's PIO-B bridge directly to :4002.
#
# This target uses the IRQ-fix MAME tree at ../../mame (branch
# pio-mpm-irq-fix), which has the cpnet_bridge gate fix that the
# stock master tree doesn't.
#
# Pass criterion: boot-strip column 18 = 'J' (NDOS COLDST reached) and
# clean A> on SIO-B.
MAME_IRQ ?= $(CURDIR)/../../mame
pio-irq-netboot: cpnos-install _check-tag-pio-irq _check-mame-irq
	@echo "=== 1/4 restarting MP/M with fresh disks ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound — kill the squatter first:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@echo "=== 2/4 waiting for MP/M CP/NET server on :4002 ==="
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.3; done
	@sleep 2
	@echo "=== 3/4 syncing ROMs to IRQ-fix MAME tree ==="
	cp $(MAME)/roms/rc702/roa375.ic66 $(MAME_IRQ)/roms/rc702/roa375.ic66
	cp $(MAME)/roms/rc702/prom1.ic65  $(MAME_IRQ)/roms/rc702/prom1.ic65
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_screen.txt /tmp/cpnos_boot_marks.txt
	@echo "=== 4/4 launching MAME (PIO-B -> mpm-net2 :4002) ==="
	-$(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 30 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script mame_porttap.lua
	@echo "--- boot-marker strip ---"
	@cat /tmp/cpnos_boot_marks.txt 2>/dev/null && echo
	@echo "--- SIO-B (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw 2>/dev/null && echo
	@strip=$$(cat /tmp/cpnos_boot_marks.txt 2>/dev/null); \
	 if [ "$${strip:18:1}" = "J" ] && grep -q 'E>' /tmp/cpnos_siob.raw 2>/dev/null; then \
	     echo "PASS: NDOS COLDST reached (J) and E> seen on SIO-B"; \
	 else \
	     echo "FAIL: strip='$$strip', expected J at col 18 + 'E>' in SIO-B"; \
	     exit 1; \
	 fi

# ---- pio-irq-smoke: pio-irq-netboot + SUMTEST workload ------------
#
# Same wiring as pio-irq-netboot (PIO-B -> mpm-net2 :4002), but adds
# smoke_inject on SIO-B to drive m80 / l80 / sumtest.  This is the
# end-to-end verification path for the warm-boot port-0x81 OUT
# (commit b06e6dd) AND the sumtest port-0x80 done signal: each program
# exit overwrites CCP which warm-boots itself, firing port 0x81; the
# running sumtest emits port 0x80 at end-of-run.
#
# Pass criterion: port-0x80 written once (sumtest done) AND port-0x81
# written >= 3 times (m80, l80, sumtest each warm-boot CCP).
pio-irq-smoke: cpnos-install _check-tag-pio-irq _check-mame-irq
	@echo "=== 1/5 regenerating sumtest.asm + smoke disk ==="
	python3 testutil/mksmokeasm.py
	testutil/mksmokedisk.sh
	@echo "=== 2/5 restarting MP/M with fresh disks ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.3; done
	@sleep 2
	@echo "=== 3/5 syncing ROMs to IRQ-fix MAME tree ==="
	cp $(MAME)/roms/rc702/roa375.ic66 $(MAME_IRQ)/roms/rc702/roa375.ic66
	cp $(MAME)/roms/rc702/prom1.ic65  $(MAME_IRQ)/roms/rc702/prom1.ic65
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_wboot.txt /tmp/cpnos_boot_result.txt \
	    /tmp/cpnos_smoke_inject.log /tmp/cpnos_boot_marks.txt
	@echo "=== 4/5 launching smoke_inject + MAME (workload: $(WORKLOAD)) ==="
	@python3 -u testutil/smoke_inject.py $(SMOKE_PORT) \
	    --workload $(WORKLOAD) \
	    --log /tmp/cpnos_siob.raw --timeout 240 \
	    > /tmp/cpnos_smoke_inject.log 2>&1 & \
	 echo $$! > /tmp/cpnos_smoke_inject.pid
	@sleep 0.4
	-$(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 1200 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 socket.127.0.0.1:$(SMOKE_PORT) \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script mame_porttap.lua
	@kill $$(cat /tmp/cpnos_smoke_inject.pid) 2>/dev/null || true
	@$(MAKE) _verify-bench WORKLOAD=$(WORKLOAD)

# ---- pio-proxy-smoke: PIO-B raw OTIR/INIR via cpnet_pio_server proxy
#
# Slave is built with TRANSPORT=pio-proxy (cpnet_dispatch.c sets
# active_transport = &transport_pio_vt; transport_pio.c's pio_send_msg
# / pio_recv_msg use raw OTIR/INIR — no SNIOS envelope).  Host runs
# cpnet_pio_server.py --upstream 127.0.0.1:4002 on :4003 to translate
# raw frames into SIO envelope and forward to mpm-net2.
#
# Topology:
#   slave PIO-B --bitb3-> cpnet_pio_server :4003 -> mpm-net2 :4002
#   slave SIO-B --bitb2-> smoke_inject :SMOKE_PORT
#
# Same pass criterion / bench timing as pio-irq-smoke.
.PHONY: pio-proxy-smoke
pio-proxy-smoke:
	$(MAKE) _pio-proxy-smoke-impl TRANSPORT=pio-proxy WORKLOAD=$(WORKLOAD)

PIO_BRIDGE_PORT ?= 4003
_pio-proxy-smoke-impl: cpnos-install _check-tag-pio-prx _check-mame-irq
	@echo "=== 1/6 regenerating sumtest.asm + smoke disk ==="
	python3 testutil/mksmokeasm.py
	testutil/mksmokedisk.sh
	@echo "=== 2/6 restarting MP/M with fresh disks ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; exit 1; \
	fi
	@if lsof -nP -iTCP:$(PIO_BRIDGE_PORT) -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port $(PIO_BRIDGE_PORT) already bound"; \
	    lsof -nP -iTCP:$(PIO_BRIDGE_PORT) -sTCP:LISTEN; exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.3; done
	@sleep 2
	@echo "=== 3/6 spawning cpnet_pio_server --upstream localhost:4002 ==="
	@rm -f /tmp/cpnos_pio_server.log
	@python3 -u cpnet_pio_server.py $(PIO_BRIDGE_PORT) \
	    --upstream 127.0.0.1:4002 \
	    > /tmp/cpnos_pio_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_pio_server.pid
	@# Don't `nc -z` to verify — that connect-and-close trips the
	@# server's single-shot accept loop, leaving MAME's bitb3 connect
	@# refused.  Just give the listener time to bind.
	@sleep 1.0
	@echo "=== 4/6 syncing ROMs to IRQ-fix MAME tree ==="
	cp $(MAME)/roms/rc702/roa375.ic66 $(MAME_IRQ)/roms/rc702/roa375.ic66
	cp $(MAME)/roms/rc702/prom1.ic65  $(MAME_IRQ)/roms/rc702/prom1.ic65
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_wboot.txt /tmp/cpnos_boot_result.txt \
	    /tmp/cpnos_smoke_inject.log /tmp/cpnos_boot_marks.txt
	@echo "=== 5/6 launching smoke_inject + MAME (workload: $(WORKLOAD)) ==="
	@python3 -u testutil/smoke_inject.py $(SMOKE_PORT) \
	    --workload $(WORKLOAD) \
	    --log /tmp/cpnos_siob.raw --timeout 240 \
	    > /tmp/cpnos_smoke_inject.log 2>&1 & \
	 echo $$! > /tmp/cpnos_smoke_inject.pid
	@sleep 0.4
	-$(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 1200 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 socket.127.0.0.1:$(SMOKE_PORT) \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:$(PIO_BRIDGE_PORT) \
	    -autoboot_script mame_porttap.lua
	@kill $$(cat /tmp/cpnos_smoke_inject.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_pio_server.pid)   2>/dev/null || true
	@$(MAKE) _verify-bench WORKLOAD=$(WORKLOAD)

# End-to-end netboot test: Python server on localhost, MAME bridged to
# it over SIO-A null_modem.
NETBOOT_PORT ?= 9000
SIOB_PORT    ?= 9001
SIOB_TRIGGER ?=
SIOB_INJECT  ?=
cpnos-netboot: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log
	@python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) \
	    $(if $(SIOB_TRIGGER),--trigger '$(SIOB_TRIGGER)') \
	    $(if $(SIOB_INJECT),--inject '$(SIOB_INJECT)') \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 70 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)" \
	    -autoboot_script mame_boot_test.lua
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- server log ---"
	@cat /tmp/cpnos_netboot_server.log
	@echo "--- SIO-B driver log ---"
	@cat /tmp/cpnos_siob_driver.log
	@echo "--- SIO-B capture (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw 2>/dev/null || true
	@echo
	@echo "--- boot test ---"
	@cat /tmp/cpnos_boot_result.txt
	@grep -q '^PASS' /tmp/cpnos_boot_result.txt

# Step 1 of the smoke plan: ^C warm boot via SIO-B injection.
# Runs long enough for cold boot + ^C + full CCP.SPR reload, then
# asserts the server observed two OPEN events for CCP.SPR.
cpnos-warmboot-test: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log
	@python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) \
	    --trigger 'E>' --inject '\x03' --timeout 30 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 25 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)"
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- server log (OPEN events) ---"
	@grep -E 'opened|FNC=0x0f' /tmp/cpnos_netboot_server.log || true
	@echo "--- SIO-B driver log ---"
	@cat /tmp/cpnos_siob_driver.log
	@echo "--- SIO-B capture (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw 2>/dev/null || true
	@echo
	@echo "--- assertion ---"
	@n=$$(grep -cE '    opened ' /tmp/cpnos_netboot_server.log); \
	 echo "CCP.SPR OPEN count: $$n"; \
	 [ "$$n" -ge 2 ] || { echo 'FAIL: expected >= 2 OPEN events'; exit 1; }; \
	 echo 'PASS: warm boot re-fetched CCP.SPR'

# Auto-run a canned CP/NOS session via $70.SUB (native CP/M batch
# mechanism — the server seeds the SUB file, CCP reads+executes it
# at the first prompt, then deletes it).  Pass commands pipe-separated:
#   make cpnos-sub-test CPNOS_SUB='dir'
#   make cpnos-sub-test CPNOS_SUB='dir|pip foo.txt=login.com|dir'
# Asserts that the SUB file is opened (proving execution) and that
# afterwards CCP is idle at the prompt (no SNIOS traffic for >2 s).
CPNOS_SUB ?= dir
cpnos-sub-test: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log /tmp/cpnos_boot_result.txt
	@CPNOS_SUB='$(CPNOS_SUB)|done' python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) --timeout 30 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 70 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)" \
	    -autoboot_script mame_sub_test.lua
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- SIO-B (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw | sed 's/$$/ /'
	@echo
	@echo "--- result ---"
	@cat /tmp/cpnos_boot_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_boot_result.txt

# ---- CONOUT acid test --------------------------------------------
#
# Builds testutil/acid.com with z88dk (+cpm), boots CP/NOS via
# netboot_server.py with CPNOS_SUB='acid' so CCP runs it at first
# prompt, then mame_acid_test.lua dumps the 8275 display RAM at
# 0xF800 and asserts the known pixel pattern the 15 RC700 control
# codes are supposed to produce.
#
# Finish marker: the .COM emits "DONE\r\n" through BIOS CONOUT,
# which mirrors to SIO-B -- same gate as mame_sub_test.lua.
Z88DK_ROOT = $(CURDIR)/../z88dk
Z88DK_ZCC  = $(Z88DK_ROOT)/bin/zcc
testutil/acid.com: testutil/acid.c
	cd testutil && \
	    PATH=$(Z88DK_ROOT)/bin:$$PATH \
	    ZCCCFG=$(Z88DK_ROOT)/lib/config \
	    zcc +cpm --opt-code-size \
	    -create-app -o acid acid.c
	@echo "built testutil/acid.com ($$(wc -c < testutil/acid.com | tr -d ' ') B)"

conout-acid: cpnos-install testutil/acid.com
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log /tmp/cpnos_boot_result.txt /tmp/cpnos_display.txt
	@CPNOS_SUB='acid|done' python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) --timeout 90 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 100 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)" \
	    -autoboot_script mame_acid_test.lua
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- display dump ---"
	@cat /tmp/cpnos_display.txt 2>/dev/null || echo '(no display dump)'
	@echo "--- result ---"
	@cat /tmp/cpnos_boot_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_boot_result.txt

# PolyPascal regression: drive cpnos through "PPAS PRIMES" / "R" / "Q"
# (PPAS is the PolyPascal interpreter command), verify primes are
# printed (looks for the last prime, 29989), and verify Q returns to
# the CCP E> prompt.  Forces MIRROR_SIOB=1 so the Lua script can
# scrape /tmp/cpnos_siob.raw for completion markers.  MP/M is
# restarted from scratch so the run is hermetic.
cpnos-polypascal-test:
	@echo "=== 1/4 (re)starting MP/M with fresh disks ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound -- kill the squatter first:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@echo "=== 2/4 waiting for MP/M CP/NET server on :4002 ==="
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.3; done
	@sleep 2
	@echo "=== 3/4 building cpnos-rom with MIRROR_SIOB=1 + installing ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-install
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_polypascal_log.txt /tmp/cpnos_polypascal_result.txt
	@echo "=== 4/4 syncing ROMs to IRQ-fix MAME tree ==="
	cp $(MAME)/roms/rc702/roa375.ic66 $(MAME_IRQ)/roms/rc702/roa375.ic66
	cp $(MAME)/roms/rc702/prom1.ic65  $(MAME_IRQ)/roms/rc702/prom1.ic65
	@echo "=== generating $(BUILDDIR)/cpnos_polypascal_addrs.lua ==="
ifeq ($(COMPILER),sdcc)
	@# z88dk's `cpnos.map` lines look like:
	@#   _kbd_head    = $ED10 ; addr, public, ...
	@KH=$$(awk '/^_kbd_head[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos.map | head -1); \
	 KR=$$(awk '/^_kbd_ring[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos.map | head -1); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	   echo "ERROR: kbd_head/kbd_ring missing from $(BUILDDIR)/cpnos.map"; exit 1; }; \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
else
	@KH=$$($(NM) $(BUILDDIR)/payload.elf | awk '/_kbd_head$$/{print $$1}'); \
	 KR=$$($(NM) $(BUILDDIR)/payload.elf | awk '/_kbd_ring$$/{print $$1}'); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	   echo "ERROR: kbd_head/kbd_ring missing from payload.elf"; exit 1; }; \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
endif
	@cat $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@echo "=== launching MAME with PolyPascal test driver (max ~4 min) ==="
	-$(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 240 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script mame_polypascal_test.lua
	@echo "--- polypascal-test log tail ---"
	@tail -30 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

# Interactive: boot CP/NOS, leave MAME running at the E> prompt so a
# human can type on the native keyboard (PIO-A path).  SIO-B output
# still streams to /tmp/cpnos_siob.raw so the other side can watch
# what got typed + echoed.  Exit by closing the MAME window (Esc).
cpnos-interactive: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log
	@python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) --timeout 3600 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	@echo "netboot server pid=$$(cat /tmp/cpnos_netboot_server.pid)"
	@echo "sio-b driver  pid=$$(cat /tmp/cpnos_siob_driver.pid)"
	@echo "Watch typed output:  tail -f /tmp/cpnos_siob.raw"
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -window -skip_gameinfo \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)"
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true

# CPU trace: captures every executed instruction to /tmp/cpnos_trace.log.
# Use for debugging control-flow issues.  Pipe through tail or head to
# avoid filling the disk (per project memory).
cpnos-trace: cpnos-install
	$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 2 \
	    -autoboot_script mame_boot_test.lua \
	    -debug -debugscript trace.dbg
	@echo "trace written to /tmp/cpnos_trace.log"

# Source-interleaved disassembly (requires -g, enabled in CFLAGS).
# The -S flag interleaves the original C lines with emitted Z80 asm.
# Clang-only (uses llvm-objdump on payload.elf).  SDCC has its own
# cpnos-lis override at the bottom of this file that points at the
# per-file .lst and the cpnos.map.
ifeq ($(COMPILER),clang)
cpnos-lis: $(BUILDDIR)/payload.elf
	$(OBJDUMP) -d -S -r --symbolize-operands --triple=z80 $< > $(BUILDDIR)/cpnos.lis
	@echo "wrote $(BUILDDIR)/cpnos.lis (with C source + symbol-resolved operands)"

cpnos-map: $(BUILDDIR)/payload.elf
	$(NM) --numeric-sort $<
endif

# Note: per-TU listings from .o files don't work reliably because
# unlinked object files have incomplete DWARF (relocations unresolved
# until link).  The linked-ELF listing from cpnos-lis gives the same
# C-source-interleaved output for the whole program; see it there.

# ---- CP/NET fast-link MAME bridge smoke test ---------------------
# Prerequisite: ravn/mame:cpnet-fast-link branch built; a CP/NET
# server (z80pack on :4002) running so cpnos-rom actually loads via
# netboot in MAME — without it the Z80 sits in the autoload PROM and
# isr_pio_par never gets a chance to fire.  See
# ../tests/cpnet_bridge/README.md for the full prereq list.
cpnet-mame-test: cpnos
	cd .. && python3 tests/cpnet_bridge/harness.py

# ---- Clean --------------------------------------------------------

cpnos-clean:
	rm -rf clang
	rm -f sdcc/*.o sdcc/cpnos*.bin sdcc/cpnos*.map sdcc/cpnos*.lis \
	      sdcc/cpnos*.sym sdcc/cpnos*.def sdcc/cpnos*.ihx \
	      sdcc/prom0*.bin sdcc/prom1*.bin sdcc/cpnos.cim sdcc/cpnos \
	      sdcc/zcc_opt.def sdcc/cpnos_addrs.h sdcc/cpnos_buildinfo.h \
	      sdcc/transport_stamp \
	      $(addprefix sdcc/,$(notdir $(wildcard *.c)))
	rm -f sdcc/*.bin sdcc/*.lst sdcc/*_BIN.bin

# ---- SDCC build pipeline (Option C) ------------------------------
#
# Single-stage z88dk link: resident image is built at its runtime
# VMA span (0xEE00..0xF7FF); PROM0 holds reset + tiny prom_loader;
# PROM1 holds 2 KB of resident bytes copied to RAM at boot.  PROM
# disable is in resident_handoff (cpnos_main.c), running from RAM.
#
# Source layout:
#   sdcc/sections.asm       z88dk section ordering / origins
#   sdcc/reset.asm          reset vector at 0x0000
#   sdcc/prom_loader.asm    LDIR PROM1 -> RAM (replaces relocator.c)
#   sdcc/bios_jt.asm        CP/M BIOS jump table at 0xF200
#   sdcc/snios.asm          SNIOS protocol code
#   $(BUILDDIR)/*.o         Compiled .c sources (RESIDENT_CODE)

ifeq ($(COMPILER),sdcc)

# Most .c files land in RESIDENT_CODE (org 0xF200, lives in PROM1).
# bios_jt.asm and snios.asm have their own SECTION declarations that
# override per-file --codeseg.  Cold-init files (init.c, netboot_mpm.c)
# get redirected to RESIDENT_PRE_CODE (org 0xEE00, lives in PROM0 tail)
# below — pushes ~1 KB of code into PROM0 to keep PROM1 usage under
# the 1.5 KB display-RAM-clearance limit.
CFLAGS += -Cs"--codeseg RESIDENT_CODE" -Cs"--constseg RESIDENT_RODATA"

# Per-target CFLAGS override — init.c and netboot_mpm.c go to PROM0 tail.
# Snapshot CFLAGS now (immediate `:=`) so the per-target assignment
# below doesn't recurse on itself.
SDCC_RESIDENT_CFLAGS := $(CFLAGS)
SDCC_PRE_CFLAGS := $(filter-out -Cs"--codeseg RESIDENT_CODE" -Cs"--constseg RESIDENT_RODATA",$(CFLAGS)) \
                   -Cs"--codeseg RESIDENT_PRE_CODE" -Cs"--constseg RESIDENT_PRE_RODATA"
# relocator.c lives in INIT_CODE/INIT_RODATA (PROM0 0x0000 anchor group,
# packed by z88dk after RESET).  This is the SDCC equivalent of the
# clang relocator.ld putting it in the relocator-side ELF.
SDCC_INIT_CFLAGS := $(filter-out -Cs"--codeseg RESIDENT_CODE" -Cs"--constseg RESIDENT_RODATA",$(CFLAGS)) \
                    -Cs"--codeseg INIT_CODE" -Cs"--constseg INIT_RODATA"
$(BUILDDIR)/init.o:           CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/netboot_mpm.o:    CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/transport_sio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/transport_pio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/isr.o:            CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/cfgtbl.o:         CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/relocator.o:      CFLAGS := $(SDCC_INIT_CFLAGS)

# Standard SDCC C-object compile rule for relocator.c.  No .inc deps
# (those are clang-only embeds; the SDCC build is single-link and the
# resident bytes already live in their RESIDENT_* sections).
$(BUILDDIR)/relocator.o: relocator.c payload_header.h compiler/compat.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Generate payload_header_data.s in symbolic mode -- emits `defw _sym`
# references for everything resolvable by the linker (resident_dest,
# cold_entry, scratch/pio_rx BSS extents, chunk_b_size).  Chunk LMAs
# (0x0400 / 0x2000) are build-script constants matching build_prom_image.py.
$(BUILDDIR)/payload_header_data.s: tasks/scripts/gen_payload_header.py \
                                   payload_header.h Makefile
	@mkdir -p $(BUILDDIR)
	python3 tasks/scripts/gen_payload_header.py \
	    --syntax=sdcc --symbolic \
	    --chunk-a-src=0x0400 --chunk-b-src=0x2000 \
	    --include-ivt \
	    --out=$@

# .c objects (single-link: relocator.c + payload_header_data.s + the
# resident sources all link in one z88dk pass).  No runtime.s / no
# payload.elf / no payload_checksum.c -- those are clang-only artifacts
# from the two-stage clang pipeline.
SDCC_C_OBJS = $(BUILDDIR)/cpnos_main.o $(BUILDDIR)/resident.o \
              $(BUILDDIR)/cfgtbl.o $(BUILDDIR)/init.o \
              $(BUILDDIR)/transport_sio.o $(BUILDDIR)/transport_pio.o \
              $(NETBOOT_OBJ) $(BUILDDIR)/isr.o \
              $(BUILDDIR)/relocator.o

# Hand-written z88dk asm files (live in sdcc/ as tracked source).
# prom_loader.asm dropped 2026-05-07 -- replaced by relocator.c
# compiled under SDCC into INIT_CODE.  The unified relocator reads
# its metadata from the payload header instead of from hardcoded
# literals in prom_loader.asm.
SDCC_ASM_SRCS = sdcc/sections.asm sdcc/reset.asm \
                sdcc/bios_jt.asm sdcc/snios.asm sdcc/hal.asm

# Linker invocation: -create-app makes z88dk-appmake emit one .bin
# file per `org`-anchored section (cpnos_RESET.bin, cpnos_RESIDENT_PRE_CODE.bin,
# cpnos_RESIDENT_JUMPTABLE.bin).  We ignore SCRATCH_BSS (NOLOAD).
SDCC_ZLFLAGS = -create-app -Cz"--org 0" -lz80 -m

# Transport aliasing — z88dk has no --defsym, so generate a small
# trampoline asm file (3 bytes per entry) that exports _xport_*
# pointing at the chosen TRANSPORT primitive.
ifeq ($(TRANSPORT),pio-irq)
SDCC_XPORT_SEND = _transport_pio_send_byte
SDCC_XPORT_RECV = _transport_pio_recv_byte
else ifeq ($(TRANSPORT),sio)
SDCC_XPORT_SEND = _transport_send_byte
SDCC_XPORT_RECV = _transport_recv_byte
else ifeq ($(TRANSPORT),pio-proxy)
SDCC_XPORT_SEND = _transport_pio_send_byte
SDCC_XPORT_RECV = _transport_pio_recv_byte
endif

$(BUILDDIR)/xport_aliases.asm: $(BUILDDIR)/transport_stamp
	@mkdir -p $(BUILDDIR)
	@{ \
	  echo "; Generated by Makefile from TRANSPORT=$(TRANSPORT)."; \
	  echo "    SECTION RESIDENT_CODE"; \
	  echo "    PUBLIC _xport_send_byte"; \
	  echo "    EXTERN $(SDCC_XPORT_SEND)"; \
	  echo "_xport_send_byte:"; \
	  echo "    jp $(SDCC_XPORT_SEND)"; \
	  echo "    PUBLIC _xport_recv_byte"; \
	  echo "    EXTERN $(SDCC_XPORT_RECV)"; \
	  echo "_xport_recv_byte:"; \
	  echo "    jp $(SDCC_XPORT_RECV)"; \
	} > $@

# Frame-pointer audit: produce a .s for every C source we compile so
# the audit script can grep for IX+/IY+ stack-frame addressing (which
# --fomit-frame-pointer is supposed to eliminate but in practice does
# not, because SDCC spills to the stack when register pressure is
# high).  See tasks/scripts/check_no_frame_ptr.py.
SDCC_AUDIT_DIR = $(BUILDDIR)/audit
SDCC_C_SRCS    = $(notdir $(SDCC_C_OBJS:.o=.c))
SDCC_AUDIT_S   = $(addprefix $(SDCC_AUDIT_DIR)/,$(SDCC_C_SRCS:.c=.s))

# `-S` produces only the .s (no .o), so this is a separate compile pass.
# Mirror the same per-target codeseg overrides as the .o build so the
# audit sees the same generated code.
$(SDCC_AUDIT_DIR)/relocator.s:    SDCC_AUDIT_CFLAGS = $(SDCC_INIT_CFLAGS)
$(SDCC_AUDIT_DIR)/init.o-codeseg-marker: ;
$(foreach f,init netboot_mpm transport_sio transport_pio isr cfgtbl, \
  $(eval $(SDCC_AUDIT_DIR)/$f.s: SDCC_AUDIT_CFLAGS = $(SDCC_PRE_CFLAGS)))

$(SDCC_AUDIT_DIR)/%.s: %.c $(BUILDDIR)/cpnos_addrs.h $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(SDCC_AUDIT_DIR)
	$(CC) $(if $(SDCC_AUDIT_CFLAGS),$(SDCC_AUDIT_CFLAGS),$(SDCC_RESIDENT_CFLAGS)) -S $< -o $@

$(BUILDDIR)/cpnos.cim: $(SDCC_C_OBJS) $(SDCC_ASM_SRCS) $(BUILDDIR)/xport_aliases.asm \
                       $(BUILDDIR)/payload_header_data.s \
                       $(SDCC_AUDIT_S) \
                       tasks/scripts/check_sdcc_layout.py \
                       tasks/scripts/check_no_frame_ptr.py \
                       tasks/check_no_frame_ptr_baseline.txt
	@mkdir -p $(BUILDDIR)
	@# Audit BEFORE the link so a regression fails fast.
	python3 tasks/scripts/check_no_frame_ptr.py \
	    tasks/check_no_frame_ptr_baseline.txt $(SDCC_AUDIT_S)
	@# zcc wants to write outputs alongside the named -o file.  Run
	@# from $(BUILDDIR) so per-section .bin files land there.
	cd $(BUILDDIR) && $(CC) $(ZFLAGS_BASE) $(SDCC_ZLFLAGS) \
	    $(addprefix ../,$(SDCC_ASM_SRCS)) \
	    xport_aliases.asm \
	    payload_header_data.s \
	    $(notdir $(SDCC_C_OBJS)) \
	    -o cpnos
	@# HARD GATE: every public symbol must resolve into a section
	@# whose VMA is inside a region the loader actually populates.
	@# z88dk silently auto-places library sections (`code_string`,
	@# `code_clib`, `code_l_sccz80`, ...) into address gaps, which
	@# can land them outside the resident PROM-loaded range.  This
	@# audit fires the moment any symbol is mis-placed (including
	@# section overlaps).  It is a build-failure gate, not advisory.
	python3 tasks/scripts/check_sdcc_layout.py $(BUILDDIR)/cpnos.map \
	    $(BUILDDIR)/cpnos_RESET.bin
	@touch $@

# Override $(BUILDDIR)/cpnos.bin for SDCC: assemble PROM0 + PROM1 from
# z88dk's per-section .bin outputs.  Single `org 0xEE00` for resident
# (matches clang's _bios_boot=0xEE00 placement so cpnos.com's hardcoded
# NIOS=0xEE33 lands on _snios_jt).  z88dk emits one binary file
# (cpnos_RESIDENT_JUMPTABLE.bin) that we dd-split: bytes 0..0x3FF →
# PROM0 tail (RAM 0xEE00..0xF1FF), bytes 0x400..0x9FF → PROM1
# (RAM 0xF200..0xF7FF, capped at 1536 B to clear display memory).
$(BUILDDIR)/cpnos.bin: $(BUILDDIR)/cpnos.cim tasks/scripts/build_prom_image.py \
                       cpnos-build/patch_payload_checksum.py
	@# Patch the resident image so its 16-bit word-additive sum
	@# equals PAYLOAD_CHECKSUM_MAGIC (0xCAFE).  The relocator
	@# verifies this AFTER copying both chunks to RAM and zeroing
	@# the BSS extents -- a runaway BSS-clear or a missing PROM1
	@# surfaces as "BAD CHECKSUM" rather than silent JP-0.
	@# Patches the last 2 bytes (RAM 0xF7FE..0xF7FF), which are
	@# snios.asm's MSGADR-high + RETCNT scratch -- both code paths
	@# (SNDMSG / RCVMSG) overwrite those before reading, so the
	@# link-time initial values don't matter.
	python3 cpnos-build/patch_payload_checksum.py $(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin
	@RES_TOTAL=$$(wc -c < $(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin | tr -d ' '); \
	 RES_A=1024; \
	 if [ $$RES_TOTAL -lt 1024 ]; then RES_A=$$RES_TOTAL; fi; \
	 RES_B=$$((RES_TOTAL - RES_A)); \
	 dd if=$(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin of=$(BUILDDIR)/resident_a.bin \
	    bs=1 count=$$RES_A status=none; \
	 if [ $$RES_B -gt 0 ]; then \
	    dd if=$(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin of=$(BUILDDIR)/resident_b.bin \
	        bs=1 skip=$$RES_A count=$$RES_B status=none; \
	 else : > $(BUILDDIR)/resident_b.bin; fi
	python3 tasks/scripts/build_prom_image.py $(BUILDDIR)/prom0.bin 2048 \
	    0x000:$(BUILDDIR)/cpnos_RESET.bin \
	    0x400:$(BUILDDIR)/resident_a.bin
	python3 tasks/scripts/build_prom_image.py $(BUILDDIR)/prom1.bin 2048 \
	    0x000:$(BUILDDIR)/resident_b.bin
	cat $(BUILDDIR)/prom0.bin $(BUILDDIR)/prom1.bin > $@
	@P0_RESET=$$(wc -c < $(BUILDDIR)/cpnos_RESET.bin | tr -d ' '); \
	 RES_TOTAL=$$(wc -c < $(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin | tr -d ' '); \
	 RES_A=$$(wc -c < $(BUILDDIR)/resident_a.bin | tr -d ' '); \
	 RES_B=$$(wc -c < $(BUILDDIR)/resident_b.bin | tr -d ' '); \
	 echo "PROM0:    reset+loader $$P0_RESET B + resident chunk A $$RES_A B / 1024"; \
	 echo "PROM1:    resident chunk B $$RES_B B / 1536"; \
	 echo "Resident: $$RES_TOTAL B total in RAM 0xEE00..0xF7FF"; \
	 test $$RES_B -le 1536 || { echo "ERROR: resident overflows 1.5 KB (would clobber display memory at 0xF800)"; exit 1; }

# Override cpnos-size for SDCC (no payload.bin / payload.elf).
cpnos-size: $(BUILDDIR)/cpnos.bin
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 P1=$$(wc -c < $(BUILDDIR)/prom1.bin | tr -d ' '); \
	 TOTAL=$$(wc -c < $(BUILDDIR)/cpnos.bin | tr -d ' '); \
	 echo "PROM0:    $$P0 / 2048 bytes"; \
	 echo "PROM1:    $$P1 / 2048 bytes"; \
	 echo "TOTAL:    $$TOTAL / 4096 bytes"; \
	 test $$TOTAL -eq 4096 || { echo "ERROR: image not exactly 4096 bytes"; exit 1; }

# cpnos-lis is a no-op for SDCC (no llvm-objdump; .lst is per-file from zcc).
cpnos-lis: $(BUILDDIR)/cpnos.bin
	@echo "(cpnos-lis: SDCC build emits per-file .lst; see $(BUILDDIR)/cpnos.map)"

endif
