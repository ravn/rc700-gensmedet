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

# Parallel build by default -- the SDCC compile pass is per-source
# (9 .c files + audit pass) so it parallelises cleanly.  `make -j N`
# on the command line overrides; `make -j1` forces serial.  uname -based
# detection so this is portable to Linux containers as well as macOS.
NCPU := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
MAKEFLAGS += -j$(NCPU)

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
# Off by default since session 33 — the byte-level transport_pio.c
# driver supersedes the bring-up scaffolding.  Set to 1 only to re-run
# the historical harness mode `loopback`.
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

# Slave talks CP/NET 1.2 (DRI MP/M protocol) to the master via
# netboot_mpm.c -- LOGIN / OPEN / READ / CLOSE against z80pack
# mpm-net2.  The legacy `SERVER=proxy` / netboot.c / NETBOOT_LEGACY
# dispatch was retired in Phase 51A (closes #19): netboot_server.py
# was already deleted in Phase 48b, so SERVER=proxy had no working
# server to talk to.  Single netboot path = no dispatch.
NETBOOT_OBJ = $(BUILDDIR)/netboot_mpm.o
SERVER_CFLAGS =

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
else
$(error TRANSPORT must be 'pio-irq' or 'sio')
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
               $(BUILDDIR)/cpnos_main.o $(BUILDDIR)/cpnos_cold.o \
               $(BUILDDIR)/resident.o $(BUILDDIR)/cfgtbl.o $(BUILDDIR)/init.o \
               $(BUILDDIR)/transport_sio.o $(BUILDDIR)/transport_pio.o \
               $(NETBOOT_OBJ) \
               $(BUILDDIR)/snios.o $(BUILDDIR)/snios_c.o $(BUILDDIR)/isr.o \
               $(BUILDDIR)/payload_checksum.o
PAYLOAD_LD = $(BUILDDIR)/payload.ld

# Preprocess payload.ld through cpp so source-level comments and any
# future build-time conditionals are flattened into a clean linker
# script.  ld.lld doesn't run cpp on linker scripts itself.
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

ALL_OBJS = $(PAYLOAD_OBJS) $(RELOC_OBJS) $(SDCC_C_OBJS) $(SDCC_AUDIT_S)

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

# `make cpnos` builds AND auto-installs the MAME PROMs (cpnos-mame-install).
# This closes the stale-ROM-in-MAME bug class: `make cpnos` followed by
# any MAME launch (Make-driven or direct via `regnecentralend`) is
# guaranteed to load the just-built code.  Use `cpnos-install` for the
# full install including cpmsim disk-side cpnos.com.
cpnos: $(BUILDDIR)/cpnos.bin cpnos-mame-install cpnos-size cpnos-lis

# Flag changes (e.g. -DRC702_SLAVEID=) must invalidate all objects.
$(ALL_OBJS): Makefile $(BUILDDIR)/transport_stamp

# Re-stamp whenever TRANSPORT changes so a `make cpnos TRANSPORT=sio`
# after a `TRANSPORT=pio-irq` build (or vice versa) actually picks up
# the new -DTRANSPORT_NAME / --defsym aliases instead of relinking
# stale .o files.  The stamp's content is the current TRANSPORT value.
#
# Run via $(shell) at parse time so the file's mtime only updates
# when TRANSPORT actually changes -- a recipe with `.PHONY` would mark
# the target "always out of date" and propagate that to every .o
# file (since `$(ALL_OBJS): $(BUILDDIR)/transport_stamp`), forcing a
# full re-compile on every `make` invocation.
ifeq ($(filter clean cpnos-clean,$(MAKECMDGOALS)),)
_DUMMY_TRANSPORT_STAMP := $(shell mkdir -p $(BUILDDIR); \
    if [ ! -f $(BUILDDIR)/transport_stamp ] || \
       [ "`cat $(BUILDDIR)/transport_stamp 2>/dev/null`" != "$(TRANSPORT)" ]; then \
        echo "$(TRANSPORT)" > $(BUILDDIR)/transport_stamp; \
        echo "transport stamp: $(TRANSPORT)" >&2; \
    fi)
endif

# No-op rule -- the file is created/updated by $(shell) at parse time.
$(BUILDDIR)/transport_stamp: ;

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
	@# NDOSRL: cpnos.com's DATA region base.  The slave's stack must
	@# stay BELOW this address or pushes during init/netboot stomp
	@# NDOS's variable storage and break NDOS COLDST (Path 6.1, see
	@# tasks/probe-results-2026-05-08.md).  HARD RULE: never literal
	@# the SP in reset.asm -- derive from this symbol.
	@perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOSRL\b/g) { print "#define CPNOS_NDOSRL_ADDR 0x$$1\n"; last }' \
	    cpnos-build/d/cpnos.sym >> $@.tmp
	@grep -q '^#define CPNOS_NDOSRL_ADDR' $@.tmp || \
	    { echo "ERROR: NDOSRL symbol missing from cpnos.sym"; rm -f $@.tmp; exit 1; }
	@# IVT-clobber guard: cpnos.com loads at NDOS and the slave's IVT
	@# starts at 0xEA00 (head of SCRATCH_BSS).  If cpnos.com grows past
	@# (0xEA00 - NDOS) bytes, its tail clobbers the IVT during netboot's
	@# LDIR -- silent until an IRQ fires after handoff and jumps to
	@# garbage.  Adjacent today (3200 B at 0xDE80 ends at 0xEAFF, exactly
	@# one byte before IVT).  Fail the build before we lose hours to
	@# random ISR crashes.
	@N=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 NV=$$((0x$$N)); \
	 SZ=$$(wc -c < cpnos-build/d/cpnos.com); \
	 MAX=$$(( 0xEA00 - NV )); \
	 if [ "$$SZ" -gt "$$MAX" ]; then \
	     echo "ERROR: cpnos.com is $$SZ B at NDOS=0x$$N -> tail at $$(printf '0x%04X' $$((NV + SZ - 1)))" \
	          " would clobber IVT at 0xEA00 (max $$MAX B)"; \
	     rm -f $@.tmp; exit 1; \
	 fi; \
	 echo "cpnos.com fits below IVT: $$SZ B at 0x$$N (tail $$(printf '0x%04X' $$((NV + SZ - 1))), $$(($$MAX - SZ)) B clearance)"
	@mv $@.tmp $@
	@echo "cpnos_addrs.h: $$(grep -E 'BDOS_ADDR|NDOS_ADDR|NDOSE_ADDR|TPA_KB' $@ | tr '\n' ' ')"

# Build info — UTC date + short git hash, regenerated every build so
# the signon banner reflects the moment this PROM was burnt.  The
# `cmp` dance avoids pointlessly retouching the file (and rebuilding
# cpnos_main.o) when neither field changed since last build.
#
# Run via $(shell) at parse time, NOT a make recipe, for the same
# reason as transport_stamp above -- a `.PHONY` target propagates
# "always rebuild" to dependents (cpnos_main.o + audit/cpnos_main.s),
# forcing a slow audit pass on every `make`.  $(shell) lets the
# .h file's mtime stay stable when content didn't change, so
# dependents correctly skip rebuild.
ifeq ($(filter clean cpnos-clean,$(MAKECMDGOALS)),)
_DUMMY_BUILDINFO := $(shell tasks/scripts/regen_buildinfo.sh \
    $(BUILDDIR)/cpnos_buildinfo.h)
endif

# No-op rule -- the file is created/updated by $(shell) at parse time.
$(BUILDDIR)/cpnos_buildinfo.h: ;

$(BUILDDIR)/cpnos_cold.o: cpnos_cold.c hal.h $(BUILDDIR)/cpnos_addrs.h $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/cpnos_main.o: cpnos_main.c hal.h $(BUILDDIR)/cpnos_addrs.h $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/resident.o: resident.c hal.h $(BUILDDIR)/cpnos_addrs.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/payload_checksum.o: payload_checksum.c
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/cfgtbl.o: cfgtbl.c
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/snios_c.o: snios_c.c cfgtbl.h compiler/compat.h
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

$(BUILDDIR)/netboot_mpm.o: netboot_mpm.c hal.h $(BUILDDIR)/cpnos_addrs.h
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
	@# CPNOS_HAS_P1_HEADER: tells the relocator that
	@# gen_payload_header emits a duplicate PROM1-byte-0 header (.payload_header_p1),
	@# so the cross-PROM mismatch memcmp gate is enabled.  SDCC build doesn't
	@# define this flag (yet -- see dual-header-plan-2026-05-08.md), so
	@# its relocator skips the memcmp and continues the same as before.
	$(CC) $(CFLAGS_RELOC) -DCPNOS_HAS_P1_HEADER -c $< -o $@

# Generate payload_header_data.s from the linked payload.elf.  Carries
# the metadata the relocator reads at boot (chunk sizes, BSS extents,
# cold entry, etc.) in lieu of --defsym injection.  Re-emit whenever
# payload.elf or the generator script changes.
$(BUILDDIR)/payload_header_data.s: $(BUILDDIR)/payload.elf $(BUILDDIR)/payload.bin \
                                   $(BUILDDIR)/cpnos_buildinfo.h \
                                   tasks/scripts/gen_payload_header.py
	@# Extract BUILD_DATE_STR from cpnos_buildinfo.h so the header's
	@# build_date_str field carries the same string the resident
	@# banner prints later.  Single source of truth, no drift.
	@BUILD_DATE_STR=$$(awk -F'"' '/BUILD_DATE_STR/{print $$2; exit}' \
	    $(BUILDDIR)/cpnos_buildinfo.h); \
	 python3 tasks/scripts/gen_payload_header.py \
	    --syntax=clang \
	    --payload-elf=$(BUILDDIR)/payload.elf \
	    --payload-bin=$(BUILDDIR)/payload.bin \
	    --chunk-a-size=$(PROM0_TAIL_SIZE) \
	    --llvm-nm=$(NM) \
	    --include-ivt \
	    --build-date-str="$$BUILD_DATE_STR" \
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
#   0x02A0 init.bin (.init runs in place, up to 0x520)
#   0x0520 .prom0_tail = first PROM0_TAIL_SIZE bytes of resident
#   0x2032 .prom1     = remaining resident bytes (after dup-header)
# PROM0_TAIL_SIZE = 0x800 - 0x520 = 0x2E0 = 736 bytes.  History:
#   1024 (initial) -> 768 (2026-05-07 .init bump 0x100->0x200 for
#                           data-driven relocator code budget)
#                  -> 736 (2026-05-08 .prom0_init bump 0x280->0x2A0 +
#                           .prom0_tail bump 0x500->0x520 to fit the
#                           relocator's display-init port sequence).
# PROM1 absorbs the difference each time, well within capacity (1998 B
# after dup-header at PROM1 byte 0).
PROM0_TAIL_SIZE = 736
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
	@# Pad prom0.bin to 4 KB as MAME's roa375.ic66 socket image.
	@# Mirrors the SDCC recipe so the prom0_padded.ic66 -> roa375.ic66
	@# install dependency fires for clang too — without this the
	@# install rule sees a stale prom0_padded.ic66 (older than the
	@# MAME ROM in place) and skips, leaving MAME with a PROM0 from
	@# whichever build last touched it.  Mismatched PROM0 + PROM1 ->
	@# relocator's word-additive checksum fails -> "BAD CHECKSUM" on
	@# the display.  Symptom seen 2026-05-08 when running clang trace
	@# after a fresh SDCC build.
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 { cat $(BUILDDIR)/prom0.bin; perl -e "print \"\\xff\" x (4096 - $$P0)"; } \
	   > $(BUILDDIR)/prom0_padded.ic66

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
#
# 2026-05-08: split into mame-side and disk-side halves so `make cpnos`
# can auto-refresh the MAME PROMs without the cpmsim disk-write
# overhead (which requires cpmtools + the cpmsim disk image).  The
# stale-PROM-in-MAME bug class -- builds fresh PROM in $(BUILDDIR)
# but MAME loads the previous-install ROM until cpnos-install runs --
# wasted hours of debugging on 2026-05-08 (slave-side instrumentation
# never appeared to fire because the new instrumentation wasn't
# loaded).  HARD RULE feedback_check_banner_timestamp.md captures the
# pre-flight check; this Makefile change closes the loop on the most
# common path (anyone running `make cpnos` gets fresh MAME PROMs).

# prom0_padded.ic66 / prom1.bin are MAME's loaded ROM files.  Both
# are side-effects of cpnos.bin's recipe (which generates prom0.bin,
# prom1.bin, and pads prom0.bin to 4 KB as prom0_padded.ic66 in one
# pass).  Declared here as targets of cpnos.bin's recipe so make's
# dep chain can propagate cpnos.bin updates → MAME ROM updates.
# Empty rule (no recipe) — the actual generation lives in the
# cpnos.bin recipe further down.
$(BUILDDIR)/prom0_padded.ic66 $(BUILDDIR)/prom1.bin: $(BUILDDIR)/cpnos.bin
	@:

# MAME ROM file targets: copy from build artifacts whenever they're
# newer.  Make tracks timestamps so subsequent builds auto-refresh.
# Also mirror to MAME_IRQ tree if it exists -- pio-irq targets and
# cpnos-bios-jt-trace launch from there, and an ad-hoc
# `regnecentralend` against MAME_IRQ would otherwise see whatever
# was in $(MAME_IRQ)/roms/rc702 from the previous polypascal-test
# (sync-on-launch in those targets) and silently boot a stale build.
# Same bug class as the asymmetric-recipe fix at 4e7f1de but on the
# MAME-tree axis.  Conditional `-d` check so the rule passes when
# MAME_IRQ doesn't exist on a given checkout.
$(MAME_PROM0): $(BUILDDIR)/prom0_padded.ic66
	cp $< $@
	@if [ -d $(MAME_IRQ)/roms/rc702 ]; then \
	    cp $@ $(MAME_IRQ)/roms/rc702/$(notdir $@); \
	    echo "installed cpnos prom0 -> $@ (+ MAME_IRQ)"; \
	else \
	    echo "installed cpnos prom0 -> $@"; \
	fi

$(MAME_PROM1): $(BUILDDIR)/prom1.bin
	cp $< $@
	@if [ -d $(MAME_IRQ)/roms/rc702 ]; then \
	    cp $@ $(MAME_IRQ)/roms/rc702/$(notdir $@); \
	    echo "installed cpnos prom1 -> $@ (+ MAME_IRQ)"; \
	else \
	    echo "installed cpnos prom1 -> $@"; \
	fi

# Just the MAME-side install (no cpmsim disk write).  Pulled in by the
# default `cpnos` target so a plain `make cpnos` is safe to follow with
# any MAME launch -- direct or via Make.
cpnos-mame-install: $(MAME_PROM0) $(MAME_PROM1)

# Full install: MAME PROMs + cpmsim disk-side cpnos.com.
cpnos-install: cpnos-mame-install cpnos-disk-install

# Verify the installed MAME PROMs match the latest build.  Use as a
# pre-flight check before any direct MAME launch (`regnecentralend`
# outside Make).  Fails with a clear error message + remediation if
# the install is stale.  HARD RULE feedback_check_banner_timestamp.md.
.PHONY: verify-mame-roms-current
verify-mame-roms-current:
	@if [ ! -f $(MAME_PROM0) ] || [ $(BUILDDIR)/prom0_padded.ic66 -nt $(MAME_PROM0) ]; then \
	    echo "STALE ROM: $(MAME_PROM0) older than $(BUILDDIR)/prom0_padded.ic66"; \
	    echo "  remediation: make COMPILER=$(COMPILER) cpnos-mame-install"; \
	    exit 1; \
	fi
	@if [ ! -f $(MAME_PROM1) ] || [ $(BUILDDIR)/prom1.bin -nt $(MAME_PROM1) ]; then \
	    echo "STALE ROM: $(MAME_PROM1) older than $(BUILDDIR)/prom1.bin"; \
	    echo "  remediation: make COMPILER=$(COMPILER) cpnos-mame-install"; \
	    exit 1; \
	fi
	@echo "MAME ROMs current ($(MAME_PROM0), $(MAME_PROM1))"

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
	@# Guard: make sure nothing else is squatting on :4002 (orphan
	@# cpmsim from a previous run, etc.) — any phantom listener will
	@# intercept MAME's netboot and produce misleading results.
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

# PolyPascal regression: drive cpnos through "PPAS PRIMES" / "R" / "Q"
# (PPAS is the PolyPascal interpreter command), verify primes are
# printed (looks for the last prime, 29989), and verify Q returns to
# the CCP E> prompt.  Forces MIRROR_SIOB=1 so the Lua script can
# scrape /tmp/cpnos_siob.raw for completion markers.  MP/M is
# restarted from scratch so the run is hermetic.
cpnos-polypascal-test:
	@# Build + install cpnos.com onto the mpm-net2 library disk BEFORE
	@# starting cpmsim.  cpmsim opens the disk image at startup and
	@# caches sector reads internally; if we update the disk file via
	@# `cpmcp` AFTER cpmsim has it open, mpm-net2 happily serves the
	@# pre-update bytes -- the slave then netboots a stale cpnos.com
	@# whose NDOS / BDOS addresses don't match the freshly-built
	@# cpnos_addrs.h, the post-handoff JP lands in the wrong place,
	@# and the slave warm-boots back to its own banner without ever
	@# reaching E>.  Symptom in /tmp/cpnos_siob.raw: slave banner with
	@# the current build's timestamp + 25 netboot dots + a SECOND,
	@# OLDER banner from the previous build.  Fixed 2026-05-08 by
	@# moving the install BEFORE the cpmsim restart so mpm-net2 reads
	@# fresh disk content.
	@echo "=== 1/4 building cpnos-rom with MIRROR_SIOB=1 + installing ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-install
	@echo "=== 2/4 (re)starting MP/M with fresh disks ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound -- kill the squatter first:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@echo "=== 3/4 waiting for MP/M CP/NET server on :4002 ==="
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.3; done
	@sleep 2
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
ifeq ($(TRANSPORT),sio)
	@# SIO route: SIO-A carries CP/NET frames to mpm-net2; SIO-B is the
	@# user-console mirror; PIO-B is unused.  mpm-net2's :4002 is a
	@# raw TCP console socket (z80pack cpmsim net_server.conf), which
	@# accepts byte pass-through identically to the PIO cpnet_bridge.
	-COMPILER=$(COMPILER) $(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 240 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -autoboot_script mame_polypascal_test.lua
else
	-COMPILER=$(COMPILER) $(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 240 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script mame_polypascal_test.lua
endif
	@echo "--- polypascal-test log tail ---"
	@tail -30 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

# BIOS-JT register-state trace (issue #60, task #36).  Hooks every JP
# entry in the resident BIOS jump table (0xED00..0xED32), the resident
# SNIOS jump table (0xED33..0xED4A), and the NDOS-patched BIOS-JT
# copy at 0xCF00..0xCF32 via memory read taps; logs full Z80 register
# state on entry and on the matching ret.  Output:
#   /tmp/cpnos_bios_jt_trace_$(COMPILER).log
#
# Topology mirrors polypascal-test (MAME_IRQ + MP/M + PIO-B bridge)
# so the trace exercises the same path bug #36 manifests on.  Trace
# Lua self-exits after 25s so the run is bounded.
#
# Usage:
#   make COMPILER=clang cpnos-bios-jt-trace
#   make COMPILER=sdcc  cpnos-bios-jt-trace
#   diff -u /tmp/cpnos_bios_jt_trace_clang.log \
#           /tmp/cpnos_bios_jt_trace_sdcc.log | less
cpnos-bios-jt-trace:
	@echo "=== 1/4 building cpnos-rom + installing ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-install
	@echo "=== 2/4 (re)starting MP/M with fresh disks ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound -- kill the squatter first:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@echo "=== 3/4 waiting for MP/M CP/NET server on :4002 ==="
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.3; done
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_bios_jt_trace.log
	@echo "=== syncing ROMs to IRQ-fix MAME tree ==="
	cp $(MAME)/roms/rc702/roa375.ic66 $(MAME_IRQ)/roms/rc702/roa375.ic66
	cp $(MAME)/roms/rc702/prom1.ic65  $(MAME_IRQ)/roms/rc702/prom1.ic65
	@echo "=== 4/4 launching MAME with BIOS-JT trace lua (~30s) ==="
	-$(MAME_IRQ)/regnecentralend rc702 -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 30 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script mame_bios_jt_trace.lua
	@if [ ! -s /tmp/cpnos_bios_jt_trace.log ]; then \
	    echo "FAIL: trace log empty or missing -- did the autoboot_script run?"; \
	    exit 1; \
	fi
	@mv /tmp/cpnos_bios_jt_trace.log /tmp/cpnos_bios_jt_trace_$(COMPILER).log
	@echo "--- banner timestamp (verify build is current) ---"
	@head -1 /tmp/cpnos_siob.raw 2>/dev/null | tr -d '\0' | head -c 200; echo
	@echo "--- trace summary ---"
	@wc -l /tmp/cpnos_bios_jt_trace_$(COMPILER).log
	@awk '/ ENTRY /{print $$3, $$4}' /tmp/cpnos_bios_jt_trace_$(COMPILER).log \
	    | sort | uniq -c | sort -rn
	@echo "--- first 10 events ---"
	@head -10 /tmp/cpnos_bios_jt_trace_$(COMPILER).log
	@echo "--- last 10 events ---"
	@tail -10 /tmp/cpnos_bios_jt_trace_$(COMPILER).log
	@echo "--- trace saved to /tmp/cpnos_bios_jt_trace_$(COMPILER).log ---"

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
# init.c, netboot_mpm.c, cfgtbl.c are PROM-only cold-init: their code
# runs once before resident_handoff's `OUT (0x18),A` disables the PROMs,
# and is never reached again.  Routing them to INIT_CODE/INIT_RODATA
# (PROM0 anchor group) instead of RESIDENT_PRE_CODE (RAM) frees the
# RAM bytes, mirroring clang's `.init` section.  Net resident saving
# at HEAD: ~374 B (init.c ~110 B + netboot_mpm.c ~229 B + cfgtbl_init
# ~35 B).  cfgtbl's BSS variable stays in bss_compiler regardless --
# only the cold-init code/rodata moves to PROM-only.
$(BUILDDIR)/init.o:           CFLAGS := $(SDCC_INIT_CFLAGS)
$(BUILDDIR)/netboot_mpm.o:    CFLAGS := $(SDCC_INIT_CFLAGS)
$(BUILDDIR)/cfgtbl.o:         CFLAGS := $(SDCC_INIT_CFLAGS)
$(BUILDDIR)/cpnos_cold.o:     CFLAGS := $(SDCC_INIT_CFLAGS)
$(BUILDDIR)/transport_sio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/transport_pio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/isr.o:            CFLAGS := $(SDCC_PRE_CFLAGS)
$(BUILDDIR)/relocator.o:      CFLAGS := $(SDCC_INIT_CFLAGS) -DCPNOS_HAS_P1_HEADER

# Standard SDCC C-object compile rule for relocator.c.  No .inc deps
# (those are clang-only embeds; the SDCC build is single-link and the
# resident bytes already live in their RESIDENT_* sections).
# -DCPNOS_HAS_P1_HEADER turns on the cross-PROM mismatch memcmp gate
# in relocator.c, parallel to the clang-side definition in the
# clang relocator.o recipe (#62).
$(BUILDDIR)/relocator.o: relocator.c payload_header.h compiler/compat.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Generate payload_header_data.s in symbolic mode -- emits `defw _sym`
# references for everything resolvable by the linker (resident_dest,
# cold_entry, scratch/pio_rx BSS extents, chunk_b_size).  Chunk LMAs
# (0x0400 / 0x2000) are build-script constants matching build_prom_image.py.
$(BUILDDIR)/payload_header_data.s: tasks/scripts/gen_payload_header.py \
                                   payload_header.h Makefile \
                                   $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(BUILDDIR)
	@# Dual-header at PROM1 byte 0 (#62): sdcc/sections.asm anchors
	@# PAYLOAD_HEADER_P1 at LMA 0x2000, gen_payload_header.py emits
	@# the duplicate section.  Chunk B starts at PROM1 + sizeof(header)
	@# = 0x2000 + 0x32 = 0x2032; the dd-split in the cpnos.bin recipe
	@# places resident chunk B at PROM1 byte 0x32, after the header.
	@# (Header size 0x32 is the link-time __PAYLOAD_HEADER_size; if
	@# the BSS-pair list grows the header expands, chunk_b_src must
	@# follow -- check_sdcc_layout.py's PROM1 audit catches drift.)
	@BUILD_DATE_STR=$$(awk -F'"' '/BUILD_DATE_STR/{print $$2; exit}' \
	    $(BUILDDIR)/cpnos_buildinfo.h); \
	 python3 tasks/scripts/gen_payload_header.py \
	    --syntax=sdcc --symbolic \
	    --chunk-a-src=0x0520 --chunk-b-src=0x2032 \
	    --include-ivt \
	    --build-date-str="$$BUILD_DATE_STR" \
	    --out=$@

# .c objects (single-link: relocator.c + payload_header_data.s + the
# resident sources all link in one z88dk pass).  No runtime.s / no
# payload.elf / no payload_checksum.c -- those are clang-only artifacts
# from the two-stage clang pipeline.
SDCC_C_OBJS = $(BUILDDIR)/cpnos_main.o $(BUILDDIR)/cpnos_cold.o \
              $(BUILDDIR)/resident.o \
              $(BUILDDIR)/cfgtbl.o $(BUILDDIR)/init.o \
              $(BUILDDIR)/snios_c.o \
              $(BUILDDIR)/transport_sio.o $(BUILDDIR)/transport_pio.o \
              $(NETBOOT_OBJ) $(BUILDDIR)/isr.o \
              $(BUILDDIR)/relocator.o

# Hand-written z88dk asm files (live in sdcc/ as tracked source).
# prom_loader.asm dropped 2026-05-07 -- replaced by relocator.c
# compiled under SDCC into INIT_CODE.  The unified relocator reads
# its metadata from the payload header instead of from hardcoded
# literals in prom_loader.asm.
SDCC_ASM_SRCS = sdcc/sections.asm sdcc/reset.asm \
                sdcc/bios_jt.asm sdcc/snios.asm sdcc/hal.asm \
                sdcc/runtime.asm

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

# Per HARD RULE feedback_no_literal_addresses.md: every memory address
# must be linker-derived.  This file extracts cpnos.com's NDOSRL base
# from cpnos.sym at build time and exports __stack_top as a symbol the
# SDCC linker resolves.  reset.asm references __stack_top via EXTERN;
# if cpnos-build's DATA_BASE shifts, this file regenerates and SP
# follows automatically.  No hand-typed literal in reset.asm.
$(BUILDDIR)/cpnos_layout.asm: cpnos-build/d/cpnos.sym
	@mkdir -p $(BUILDDIR)
	@NDOSRL=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOSRL\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 [ -n "$$NDOSRL" ] || { echo "ERROR: NDOSRL missing from cpnos.sym"; exit 1; }; \
	 NDOS=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 [ -n "$$NDOS" ] || { echo "ERROR: NDOS missing from cpnos.sym"; exit 1; }; \
	 BDOS=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+BDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 { \
	   echo "; Generated by Makefile from cpnos-build/d/cpnos.sym."; \
	   echo "; cpnos.com layout symbols for SDCC asm / linker.  Do not edit;"; \
	   echo "; HARD RULE feedback_no_literal_addresses.md: derive, don't hardcode."; \
	   echo ""; \
	   echo "    PUBLIC CPNOS_NDOSRL"; \
	   echo "    PUBLIC CPNOS_NDOS"; \
	   echo "    PUBLIC CPNOS_BDOS"; \
	   echo "    PUBLIC __stack_top"; \
	   echo ""; \
	   echo "defc CPNOS_NDOSRL = 0x$$NDOSRL    ; cpnos.com DATA region base"; \
	   echo "defc CPNOS_NDOS   = 0x$$NDOS    ; cpnos.com CODE region base (loaded by netboot)"; \
	   echo "defc CPNOS_BDOS   = 0x$$BDOS    ; BDOS dispatch (programs CALL ZP[5..7] -> jp here)"; \
	   echo ""; \
	   echo "; Stack top = NDOSRL.  First push lands at NDOSRL-1, in TPA proper"; \
	   echo "; (0x0100..NDOSRL-1) which is genuinely unused at boot.  Stack at"; \
	   echo "; or above NDOSRL would stomp NDOS's variable storage -- bug fixed"; \
	   echo "; by Path 6.1.  Symbol is referenced via EXTERN __stack_top in"; \
	   echo "; sdcc/reset.asm; if cpnos-build's DATA_BASE shifts, SP follows."; \
	   echo "defc __stack_top = CPNOS_NDOSRL"; \
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

# Audit %.s depends on the .c source + cpnos_addrs.h (stable; only
# regenerates when cpnos.com gets new addresses).  Does NOT depend on
# cpnos_buildinfo.h -- only cpnos_main.c uses BUILD_DATE_STR /
# GIT_HASH_STR / BUILD_INFO_STR (banner string), so only the cpnos_main
# audit .s needs the rebuild trigger.  Without this split, every
# `make` regenerated cpnos_buildinfo.h's timestamp and re-ran the
# audit pass on all 9 sources -- 5-9 minutes of wasted work.
$(SDCC_AUDIT_DIR)/%.s: %.c $(BUILDDIR)/cpnos_addrs.h
	@mkdir -p $(SDCC_AUDIT_DIR)
	$(CC) $(if $(SDCC_AUDIT_CFLAGS),$(SDCC_AUDIT_CFLAGS),$(SDCC_RESIDENT_CFLAGS)) -S $< -o $@

# Per-target extra dep: cpnos_main.s also re-runs when the banner
# changes.  Same logic as cpnos_main.o's dep on cpnos_buildinfo.h.
$(SDCC_AUDIT_DIR)/cpnos_main.s: $(BUILDDIR)/cpnos_buildinfo.h

$(BUILDDIR)/cpnos.cim: $(SDCC_C_OBJS) $(SDCC_ASM_SRCS) $(BUILDDIR)/xport_aliases.asm \
                       $(BUILDDIR)/cpnos_layout.asm \
                       $(BUILDDIR)/payload_header_data.s \
                       $(SDCC_AUDIT_S) \
                       tasks/scripts/check_sdcc_layout.py \
                       tasks/scripts/check_no_frame_ptr.py \
                       tasks/check_no_frame_ptr_baseline.txt \
                       tasks/scripts/check_unreferenced_publics.py \
                       tasks/check_unreferenced_publics_allowlist.txt
	@mkdir -p $(BUILDDIR)
	@# Audit BEFORE the link so a regression fails fast.
	python3 tasks/scripts/check_no_frame_ptr.py \
	    tasks/check_no_frame_ptr_baseline.txt $(SDCC_AUDIT_S)
	@# zcc wants to write outputs alongside the named -o file.  Run
	@# from $(BUILDDIR) so per-section .bin files land there.
	cd $(BUILDDIR) && $(CC) $(ZFLAGS_BASE) $(SDCC_ZLFLAGS) \
	    $(addprefix ../,$(SDCC_ASM_SRCS)) \
	    xport_aliases.asm \
	    cpnos_layout.asm \
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
	@# HARD GATE: any user-tracked PUBLIC in sdcc/*.asm with zero
	@# textual references in .s/.asm sources is dead and gets linked
	@# in for free under z88dk (no function-level DCE).  Caught a 33 B
	@# silent regression during #77 — see #79.
	python3 tasks/scripts/check_unreferenced_publics.py \
	    tasks/check_unreferenced_publics_allowlist.txt \
	    $(BUILDDIR)/cpnos.map \
	    $(SDCC_AUDIT_S) $(BUILDDIR)/payload_header_data.s $(SDCC_ASM_SRCS)
	@touch $@

# Override $(BUILDDIR)/cpnos.bin for SDCC: assemble PROM0 + PROM1 from
# z88dk's per-section .bin outputs.  Single `org 0xED00` for resident
# (matches clang's _bios_boot=0xED00 placement so cpnos.com's hardcoded
# NIOS=0xED33 lands on _snios_jt).  z88dk emits one binary file
# (cpnos_RESIDENT_JUMPTABLE.bin) that we dd-split: bytes 0..0x3FF →
# PROM0 tail (RAM 0xED00..0xF0FF), bytes 0x400..0xAFF → PROM1
# (RAM 0xF100..0xF7FF, capped at 1792 B to clear display memory).
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
	@# patch_payload_checksum.py requires an even-sized image (word-
	@# additive arithmetic).  Even-alignment is enforced at link time
	@# by `align 2` in sdcc/sections.asm's RESIDENT_CHECKSUM section
	@# (#59); the linker emits 0 or 1 fill bytes between RESIDENT_DATA
	@# and RESIDENT_CHECKSUM as needed, and __payload_chunk_b_size is
	@# computed from the post-align section tail.  No post-link pad
	@# fixup needed.
	python3 cpnos-build/patch_payload_checksum.py $(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin
	@# Phase 51A.2: chunk A starts at PROM0 0x0520 (was 0x0400) to mirror
	@# clang's layout — extra 288 B of INIT_CODE budget absorbs the
	@# cpnos_cold.c content moved out of cpnos_main.c (see Phase 51A.2
	@# split).  PROM0 init region 0x0000..0x051F = 1312 B; chunk A
	@# 0x0520..0x07FF = 736 B.
	@RES_TOTAL=$$(wc -c < $(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin | tr -d ' '); \
	 RES_A=736; \
	 if [ $$RES_TOTAL -lt 736 ]; then RES_A=$$RES_TOTAL; fi; \
	 RES_B=$$((RES_TOTAL - RES_A)); \
	 dd if=$(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin of=$(BUILDDIR)/resident_a.bin \
	    bs=1 count=$$RES_A status=none; \
	 if [ $$RES_B -gt 0 ]; then \
	    dd if=$(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin of=$(BUILDDIR)/resident_b.bin \
	        bs=1 skip=$$RES_A count=$$RES_B status=none; \
	 else : > $(BUILDDIR)/resident_b.bin; fi
	python3 tasks/scripts/build_prom_image.py $(BUILDDIR)/prom0.bin 2048 \
	    0x000:$(BUILDDIR)/cpnos_RESET.bin \
	    0x520:$(BUILDDIR)/resident_a.bin
	@# PROM1: PAYLOAD_HEADER_P1 (50 B) at byte 0, resident chunk B at
	@# byte 0x32.  Header offset must match --chunk-b-src=0x2032 in
	@# the gen_payload_header.py invocation (#62).
	python3 tasks/scripts/build_prom_image.py $(BUILDDIR)/prom1.bin 2048 \
	    0x000:$(BUILDDIR)/cpnos_PAYLOAD_HEADER_P1.bin \
	    0x032:$(BUILDDIR)/resident_b.bin
	cat $(BUILDDIR)/prom0.bin $(BUILDDIR)/prom1.bin > $@
	@# Generate prom0_padded.ic66 (4 KB image MAME loads) here so all
	@# PROM file outputs come from one recipe.  prom0.bin is 2 KB; pad
	@# with 0xFF to 4 KB.  Earlier this was inside cpnos-install's
	@# recipe; moved here so cpnos.bin's dep chain can propagate to
	@# MAME ROM files automatically (no stale-ROM-in-MAME bug class).
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 { cat $(BUILDDIR)/prom0.bin; perl -e "print \"\\xff\" x (4096 - $$P0)"; } \
	   > $(BUILDDIR)/prom0_padded.ic66
	@P0_RESET=$$(wc -c < $(BUILDDIR)/cpnos_RESET.bin | tr -d ' '); \
	 RES_TOTAL=$$(wc -c < $(BUILDDIR)/cpnos_RESIDENT_JUMPTABLE.bin | tr -d ' '); \
	 RES_A=$$(wc -c < $(BUILDDIR)/resident_a.bin | tr -d ' '); \
	 RES_B=$$(wc -c < $(BUILDDIR)/resident_b.bin | tr -d ' '); \
	 echo "PROM0:    reset+loader $$P0_RESET B + resident chunk A $$RES_A B / 1024"; \
	 echo "PROM1:    resident chunk B $$RES_B B / 1792"; \
	 echo "Resident: $$RES_TOTAL B total in RAM 0xED00..0xF7FF"; \
	 test $$RES_B -le 1792 || { echo "ERROR: resident overflows 1.75 KB (would clobber display memory at 0xF800)"; exit 1; }

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
