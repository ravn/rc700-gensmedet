# Makefile for cpnos-in-c — C-language CP/NOS slave (clang + SDCC dual-compile).
#
# Path layout (post-rename, session 73d):
#   cpnos-shared/    protocol headers, linker scripts, MAME harness, docs
#   cpnos-in-c/      this dir — C sources in src/, build outputs per compiler
#   cpnos-in-asm/    sibling pure-asm slave, PROM1-fit target
#
# Path variables — every reference to a moved file goes through these.
SHARED ?= ../cpnos-shared
SRC     = src

# vpath lets compile rules find sources in $(SRC) without rewriting every
# dependency line.  Order matters: more specific patterns first.
vpath %.c $(SRC)
vpath %.s $(SRC)
vpath %.h $(SRC) $(SHARED)/include

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
BOOT_MARK_ENABLED ?= 0    # disabled 2026-05-17 to fit the locale-table
                          # feature into PROM1 (cpnos-in-c PROM1-only at
                          # 2 KB cap).  Was default 1; cost was 67 B for
                          # cold-boot visual progress markers in row 0
                          # cols 60..78 ('I N I L O R E + P J' etc.).
                          # Re-enable explicitly for cold-init debugging.

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

# ----------------------------------------------------------------------
# CPNOS_PROM1_CAP: max size of the PROM1-only line program binary.
#
# Hard physical cap on the user's RC702 is 2048 B (no A11 bridge -- see
# memory rule `project_rc702_2kb_prom_hard_limit`).  Anything larger
# does not fit a real 2 KB PROM1 socket and is MAME-only.  Override via
# `make ... CPNOS_PROM1_CAP=4096` only for MAME PROMCFG=2 experiments.
# ----------------------------------------------------------------------
CPNOS_PROM1_CAP ?= 2048

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

  # ravn/llvm-z80#177: -disable-machine-licm / -disable-machine-cse were
  # dropped from CFLAGS -- they are redundant.  MachineLICM, EarlyMachineLICM
  # and MachineCSE are disablePass-ed globally in the Z80 backend (#128,
  # Z80TargetMachine.cpp), so the flags never changed codegen.  Removal
  # verified byte-identical on the uncompressed payload (2026-05-26).
  # -disable-lsr is kept: LSR is IR-level (still runs), and on cpnos the
  # flag is marginally beneficial via better ZX0 compressibility.
  CFLAGS = --target=z80 -std=c23 -Oz -nostdlib -g \
           -ffunction-sections -fdata-sections \
           -Xclang -target-feature -Xclang +static-stack \
           -mllvm -disable-lsr \
           -DENABLE_FDC=$(ENABLE_FDC) \
           -DMIRROR_SIOB=$(MIRROR_SIOB) \
           -DBOOT_MARK_ENABLED=$(BOOT_MARK_ENABLED) \
           -DRC702_SLAVEID=0x01 \
           $(SERVER_CFLAGS) \
           -I$(BUILDDIR) -I$(SRC) -I$(SHARED)/include -I. \
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
  # Investigation hook (ravn/llvm-z80#23): inject extra clang flags via
  # `make CLANG_EXTRA="-mllvm -z80-enable-licm -mllvm -z80-enable-cse"`.
  CFLAGS += $(CLANG_EXTRA)

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
           -I$(BUILDDIR) -I$(SRC) -I$(SHARED)/include -I.

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

# Cold-boot default drive/user (zero-page cdisk byte at 0x0004; low nibble =
# drive, high nibble = user).  Unset => cpnos_main.c default 0x00 (A:), the
# normal CP/M boot drive.  Tests that want the slave to come up on the tool
# drive set CPNOS_DEFAULT_DRIVE=0x04 (E: -> master I: hard disk).  E: is
# opt-in per build, never baked in unconditionally.
ifneq ($(CPNOS_DEFAULT_DRIVE),)
CFLAGS += -DCPNOS_DEFAULT_DRIVE=$(CPNOS_DEFAULT_DRIVE)
endif

# Default goal: pin BEFORE the common.mk include below, otherwise the
# first non-pattern target inside common.mk ($(MAME_PROM0) ...) wins
# as `make` (no args) → MAME-ROM install.  After the two-PROM removal
# 2026-06-03, that install path's prereqs are dead (prom0_padded.ic66
# is no longer generated), so the wrong default broke `make`.
.DEFAULT_GOAL := all

# Pull in shared MAME-install / burn / verify recipes.  See
# $(SHARED)/common.mk for the variables it defaults and the targets it
# provides.  Must come AFTER BUILDDIR / COMPILER are resolved.
# cpnos-in-asm/Makefile (parked) includes the same fragment.
include $(SHARED)/common.mk

# Slave talks CP/NET 1.2 (DRI MP/M protocol) to the master via the
# netboot_mpm() helper -- LOGIN / OPEN / READ / CLOSE against z80pack
# mpm-net2.  The legacy `SERVER=proxy` / netboot.c / NETBOOT_LEGACY
# dispatch was retired in Phase 51A (closes #19): netboot_server.py
# was already deleted in Phase 48b, so SERVER=proxy had no working
# server to talk to.  Single netboot path = no dispatch.
# 2026-05-10 (Phase 59): netboot_mpm.c merged into init.c, so the
# code lives in $(BUILDDIR)/init.o and there is no separate object.
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

# Default emulated-time cap for polypascal-test variants.  Baseline (LOG=0,
# no debugger trace) PASS lands at ~53 sim sec, so 240 is generous.  The
# -trace targets override to 1200 because LOG=1 + MAME debugger trace +
# the post-mame#10 invoke() coroutine overhead push wall-clock work per
# simulated second up by ~5x.
SECONDS_TO_RUN_POLYPASCAL ?= 240
# Export so polypascal_test.lua can read it (os.getenv) and set the MAME SW1
# S03 DIP to actually select the intended transport at runtime (ravn/llvm-z80
# #150 follow-up — the prom1-lineprog binary is transport-agnostic; SW1 chooses).
export TRANSPORT
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

# Banner tag inserted via TRANSPORT_NAME macro -- cpnos's
# print_banner builds the boot banner as
# "RC702 CP/NOS NNK <NAME> <compiler> <date> <hash>" where <NAME> is
# this string.  Visible at boot on the display + SIO-B mirror.
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

# Locale tag stamped into cpnos.img (NOT into PROM1).  Format:
# <kbd>_<charset>.
#   da_US  Danish keyboard inconv + US-ASCII outcon (current default)
#   da_DK  Danish keyboard + Danish-national outcon
# Passed to stamp_cpnos.py as --locale, ends up in the last 32 B of
# cpnos.com so the slave prints it on row 2 after netboot completes.
# Doesn't go through -D because print_banner runs BEFORE netboot
# (the slave PROM doesn't know which locale tables the master's
# cpnos.img carries until READ-SEQ finishes).  Must stay in sync
# with the inconv/outcon choice in cpnos-build/gen_locale_prefix.py.
CPNOS_LOCALE_TAG ?= da_US

# ---- Payload object list -----------------------------------------
# The same set of objects is linked by both clang and SDCC into the
# PROM1-only line program (see PROM1ONLY_* rules below; build dirs
# clang-prom1lineprog/ and sdcc-prom1lineprog/).  The two-PROM build
# was removed 2026-06-03 (TWO_PROM_PARKED → deleted).
PAYLOAD_OBJS = $(BUILDDIR)/runtime.o $(BUILDDIR)/bios_jt.o \
               $(BUILDDIR)/cpnos_main.o \
               $(BUILDDIR)/resident.o $(BUILDDIR)/init.o \
               $(BUILDDIR)/transport_sio.o $(BUILDDIR)/transport_pio.o \
               $(BUILDDIR)/snios.o $(BUILDDIR)/snios_c.o

ALL_OBJS = $(PAYLOAD_OBJS) $(SDCC_C_OBJS) $(SDCC_AUDIT_S)

.PHONY: all cpnos-size cpnos-burn cpnos-disasm cpnos-clean \
        integration-test test cpnos-polypascal-test

# Production target = autoload-in-c (PROM 0) + cpnos PROM1-only line program
# (PROM 1).  The two-PROM build was removed 2026-06-03; the only supported
# slave topology is `make prom1-lineprog`.  See finishing-checklist.md.
all: prom1-lineprog

# Integration test: full E2E with z80pack mpm-net2 + MAME running CP/NOS
# slave + PolyPascal compiling and running PRIMES.PAS.  Catches the
# whole stack (transport, NDOS, BDOS, console, keyboard, file load,
# code execution, output framing).  Not part of `all` -- a normal build
# shouldn't boot MAME.  `make test` is an alias.
integration-test test: cpnos-polypascal-test

# Backwards-compatible alias for the old `make cpnos-ppas-test` name.
.PHONY: cpnos-ppas-test
cpnos-ppas-test: cpnos-polypascal-test

# Flag changes (e.g. -DRC702_SLAVEID=) must invalidate all objects.
$(ALL_OBJS): Makefile $(BUILDDIR)/transport_stamp $(BUILDDIR)/toolchain_stamp

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
# Stamp key includes CPNOS_DEFAULT_DRIVE too: switching the cold-boot default
# drive (production A: vs E:-test 0x04) recompiles cpnos_main.o (zp_init_data)
# the same way a TRANSPORT switch does -- otherwise a `make CPNOS_DEFAULT_DRIVE=
# 0x04` after a plain `make` would relink stale A: objects.
_STAMP_KEY := $(TRANSPORT) drv=$(CPNOS_DEFAULT_DRIVE)
ifeq ($(filter clean cpnos-clean,$(MAKECMDGOALS)),)
_DUMMY_TRANSPORT_STAMP := $(shell mkdir -p $(BUILDDIR); \
    if [ ! -f $(BUILDDIR)/transport_stamp ] || \
       [ "`cat $(BUILDDIR)/transport_stamp 2>/dev/null`" != "$(_STAMP_KEY)" ]; then \
        echo "$(_STAMP_KEY)" > $(BUILDDIR)/transport_stamp; \
        echo "transport stamp: $(_STAMP_KEY)" >&2; \
    fi)
endif

# No-op rule -- the file is created/updated by $(shell) at parse time.
$(BUILDDIR)/transport_stamp: ;

# ---------------------------------------------------------------------
# Toolchain stamp -- track compiler binary content so a rebuild of
# clang (via ninja in llvm-z80/) forces our .o files to rebuild.
#
# Without this, the Makefile's $(CC) refers to a binary path but the
# binary isn't a prereq of any rule -- so updating clang and re-running
# make leaves stale .o files compiled by the OLD clang, producing
# misleading "no change" measurements.  This file is content-hashed:
# the md5 of $(CC) goes into BUILDDIR/toolchain_stamp; when the hash
# changes, the stamp's mtime updates, and ALL_OBJS depend on it.
# ---------------------------------------------------------------------
ifeq ($(filter clean cpnos-clean,$(MAKECMDGOALS)),)
_DUMMY_TOOLCHAIN_STAMP := $(shell mkdir -p $(BUILDDIR); \
    NEW=$$(md5 -q "$(CC)" 2>/dev/null || md5sum "$(CC)" 2>/dev/null | awk '{print $$1}'); \
    [ -n "$$NEW" ] || NEW=missing; \
    OLD=$$(cat $(BUILDDIR)/toolchain_stamp 2>/dev/null); \
    if [ "$$NEW" != "$$OLD" ]; then \
        echo "$$NEW" > $(BUILDDIR)/toolchain_stamp; \
        echo "toolchain stamp: $$NEW ($(COMPILER))" >&2; \
    fi)
endif

# No-op rule -- the file is created/updated by $(shell) at parse time.
$(BUILDDIR)/toolchain_stamp: ;

# ---- Compile ------------------------------------------------------

$(BUILDDIR)/runtime.o: runtime.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILDDIR)/bios_jt.o: bios_jt.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILDDIR)/xport_jt.o: xport_jt.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILDDIR)/snios.o: snios.s
	@mkdir -p $(BUILDDIR)
	$(CC) $(ASFLAGS) -c $< -o $@

# Phase 2B: cpnos_main.c (nos_handoff) writes ZP[5..7] = JP BDOS
# itself, replacing cpnos-build's deleted cpnos.asm entry stub.
# BDOS's address is link-time-determined inside cpnos.com; extract it
# from cpnos.sym into a generated header.
$(BUILDDIR)/cpnos_addrs.h: cpnos-build/d/cpnos.sys
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
	@# starts at IVT_BASE (head of the slave-resident envelope).  If
	@# cpnos.com grows past (IVT_BASE - NDOS) bytes, its tail clobbers
	@# the IVT during netboot's LDIR -- silent until an IRQ fires after
	@# handoff and jumps to garbage.  Adjacent today (3200 B at 0xDE80
	@# ends at 0xEA9F, with ~95 B clearance below the new IVT=0xEB00).
	@# Fail the build before we lose hours to random ISR crashes.
	@#
	@# IVT_BASE post-TPA-grow 2026-06-04: 0xEB00 (was 0xEA00).  Source
	@# of truth is the IVT ORIGIN in clang-prom1lineprog/payload.ld; the
	@# guard mirrors it as a constant here because cpnos.sym is built
	@# before the lineprog ELF exists.
	@IVT_BASE=0xEB00; \
	 N=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 NV=$$((0x$$N)); \
	 SZ=$$(wc -c < cpnos-build/d/cpnos.sys); \
	 MAX=$$(( $$IVT_BASE - NV )); \
	 if [ "$$SZ" -gt "$$MAX" ]; then \
	     echo "ERROR: cpnos.sys is $$SZ B at NDOS=0x$$N -> tail at $$(printf '0x%04X' $$((NV + SZ - 1)))" \
	          " would clobber IVT at $$(printf '0x%04X' $$IVT_BASE) (max $$MAX B)"; \
	     rm -f $@.tmp; exit 1; \
	 fi; \
	 echo "cpnos.sys fits below IVT ($$(printf '0x%04X' $$IVT_BASE)): $$SZ B at 0x$$N (tail $$(printf '0x%04X' $$((NV + SZ - 1))), $$(($$MAX - SZ)) B clearance)"
	@# INIT-vs-cpnos.com overlap guard (user-flagged invariant 2026-06-04):
	@# .init runs in place at 0xC000..0xC000+__init_size and is reclaimed
	@# as TPA after handoff.  cpnos.com's lowest byte is NDOSRL.  If the
	@# init region ever grew above NDOSRL the server LDIR would land
	@# bytes into the still-running init code -- silent corruption.
	@# Today: init is 605 B (max 640 B per payload.ld INIT LENGTH), cpnos
	@# NDOSRL is 0xDA80, so guaranteed gap is at least 6144 B = 6 KB.  Lock
	@# the invariant against silent drift: an edit to INIT LENGTH in
	@# payload.ld or to DATA_BASE in cpnos-build/Makefile that breaks the
	@# inequality fails the build here.
	@#
	@# Source of truth for the init ceiling is the INIT LENGTH in
	@# payload.ld (0x0280 = 0xC000..0xC27F).  Mirrored as a constant here
	@# because the lineprog ELF that holds __init_end isn't built yet at
	@# cpnos_addrs.h generation time; the linker still ASSERTs init <=
	@# 0x0280 independently as backup.
	@INIT_CEIL=$$((0xC280)); \
	 NDOSRL=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOSRL\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 NV=$$((0x$$NDOSRL)); \
	 if [ "$$NV" -lt "$$INIT_CEIL" ]; then \
	     echo "ERROR: cpnos.sys NDOSRL=0x$$NDOSRL is below INIT ceiling $$(printf '0x%04X' $$INIT_CEIL)"; \
	     echo "       — cpnos.sys payload load would corrupt init region."; \
	     echo "       Bump cpnos-build/Makefile DATA_BASE up, or shrink payload.ld INIT LENGTH."; \
	     rm -f $@.tmp; exit 1; \
	 fi; \
	 echo "init region (max $$(printf '0x%04X' $$INIT_CEIL)) clear of cpnos.sys NDOSRL (0x$$NDOSRL): $$((NV - INIT_CEIL)) B gap"
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
_DUMMY_BUILDINFO := $(shell $(SHARED)/scripts/regen_buildinfo.sh \
    $(BUILDDIR)/cpnos_buildinfo.h)
endif

# No-op rule -- the file is created/updated by $(shell) at parse time.
$(BUILDDIR)/cpnos_buildinfo.h: ;

$(BUILDDIR)/cpnos_main.o: cpnos_main.c hal.h $(BUILDDIR)/cpnos_addrs.h $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/resident.o: resident.c hal.h $(BUILDDIR)/cpnos_addrs.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/snios_c.o: snios_c.c $(SHARED)/include/cfgtbl.h compiler/compat.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# init.c is the merged cold-boot TU: cfgtbl + hardware bring-up +
# netboot_mpm + cold orchestrator.  See file header for source order.
$(BUILDDIR)/init.o: init.c hal.h $(SHARED)/include/cfgtbl.h transport.h $(BUILDDIR)/cpnos_addrs.h $(BUILDDIR)/cpnos_buildinfo.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/transport_sio.o: transport_sio.c transport.h hal.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/transport_pio.o: transport_pio.c transport.h hal.h compiler/compat.h
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Relocator: includes init/payload byte arrays via `#include "*.inc"`.
# Each .inc is a comma-separated byte stream generated from the
# matching .bin by $(SHARED)/scripts/bin2inc.py.  The mechanism is
# compiler-portable: clang and SDCC see the same C source, with the
# .inc resolved via per-compiler -I.  C23 `#embed` would be cleaner
# but SDCC doesn't implement it.  See tasks/sdcc-port.md.
#
# Relocator compile flags: same as CFLAGS but without the
# `-Xclang -target-feature -Xclang +static-stack` sequence.  The
# ---- Size check (PROM1-only line program) ------------------------
# Print the lineprog size + cap status; defers to the prom1-lineprog
# rule for the actual size enforcement (errors over 2048 B for clang).
cpnos-size: prom1-lineprog
	@echo "(see 'PROM1 line program: ... B (... B free; hard cap 2048 B)' above)"

# ---- Split for burner --------------------------------------------
#
# `cpnos-burn` provided by $(SHARED)/common.mk.

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
#
# Target `mame-roms-cpnos` (and MAME_ROMS_DIR default) provided by
# $(SHARED)/common.mk.

# ---- Inspection --------------------------------------------------

cpnos-disasm: prom1-lineprog
	$(OBJDUMP) -d --triple=z80 $(BUILDDIR)-prom1lineprog/prom1-lineprog.elf

# ---- MAME boot test ----------------------------------------------
#
# MAME, MAME_PROM0, MAME_PROM1 defaults provided by $(SHARED)/common.mk.

# Disk-image install: rebuild cpnos.com from cpnos-build/ and inject the
# fresh blob into both MP/M library disks.  Prevents the "PROM updated
# but disk still has stale cpnos.com" trap (2026-04-25 incident — see
# memory: project_cpnos_address_coupling_brittle).  The launcher prefers
# cpnetsmk-1.dsk if present, so updating only mpm-net2-1.dsk silently
# fails to take effect — both must be refreshed.
MPM_DISK_LIB = ../z80pack/cpmsim/disks/library
MPM_DISK_LOCAL = ../z80pack/cpmsim/disks/local
cpnos-disk-install: cpnos-build/d/cpnos.sys
	@echo "=== stamping cpnos.sys + prepending 384 B locale prefix ==="
	@python3 cpnos-build/stamp_cpnos.py cpnos-build/d/cpnos.sys $(BUILDDIR)/cpnos_stamped.sys \
	    --locale $(CPNOS_LOCALE_TAG)
	@python3 cpnos-build/gen_locale_prefix.py $(BUILDDIR)/locale_prefix.bin
	@cat $(BUILDDIR)/locale_prefix.bin $(BUILDDIR)/cpnos_stamped.sys > $(BUILDDIR)/cpnos_with_locale.img
	@echo "  cpnos.img = 384 B prefix + $$(wc -c < $(BUILDDIR)/cpnos_stamped.sys) B stamped cpnos.sys = $$(wc -c < $(BUILDDIR)/cpnos_with_locale.img) B"
	@cpmrm -f ibm-3740 $(MPM_DISK_LIB)/mpm-net2-1.dsk 0:cpnos.img 2>/dev/null || true
	cpmcp -f ibm-3740 $(MPM_DISK_LIB)/mpm-net2-1.dsk \
	    $(BUILDDIR)/cpnos_with_locale.img 0:cpnos.img
	@if [ -f $(MPM_DISK_LIB)/cpnetsmk-1.dsk ]; then \
	    cpmrm -f ibm-3740 $(MPM_DISK_LIB)/cpnetsmk-1.dsk 0:cpnos.img 2>/dev/null || true; \
	    cpmcp -f ibm-3740 $(MPM_DISK_LIB)/cpnetsmk-1.dsk \
	        $(BUILDDIR)/cpnos_with_locale.img 0:cpnos.img; \
	    echo "  refreshed (locale) cpnos.img on cpnetsmk-1.dsk"; \
	 fi
	@echo "  refreshed (locale) cpnos.img on mpm-net2-1.dsk"
	@# CRITICAL: the mpm-net2 launcher BOOTS disks/local/mpm-net2-1.dsk
	@# (the GENSYS-rebuilt MPM.SYS carrying the FN 105/gettod-patched
	@# SERVER.RSP -- see cpnet/REBUILDING_MPM_SYS.md + timeline 2026-06-11),
	@# NOT disks/library/.  Refreshing only library/ silently serves a
	@# STALE cpnos.img to the slave (2026-06-28 incident: slave booted an
	@# image weeks old; symptomatically the netboot oracle reaches E> with
	@# the wrong build).  Refresh the BOOTED disk too whenever it exists.
	@if [ -f $(MPM_DISK_LOCAL)/mpm-net2-1.dsk ]; then \
	    cpmrm -f ibm-3740 $(MPM_DISK_LOCAL)/mpm-net2-1.dsk 0:cpnos.img 2>/dev/null || true; \
	    cpmcp -f ibm-3740 $(MPM_DISK_LOCAL)/mpm-net2-1.dsk \
	        $(BUILDDIR)/cpnos_with_locale.img 0:cpnos.img; \
	    echo "  refreshed (locale) cpnos.img on local/mpm-net2-1.dsk (BOOTED disk)"; \
	 else \
	    echo "  WARNING: $(MPM_DISK_LOCAL)/mpm-net2-1.dsk absent --"; \
	    echo "           run cpnet/mpm-server/rebuild-mpm-sys.sh --install first"; \
	 fi

# Variant: prepend 384 B locale prefix (US-ASCII outcon + Danish
# inconv) before installing.  The PROM1-only cpnos slave (v3 layout)
# loads this prefix-prepended cpnos.img, LDIRs the prefix to its
# runtime home at 0xF680..0xF7FF, and runs impl_conout/impl_conin
# through the tables.  Two-PROM slaves cannot consume this image
# (their pio_rx_buf is at 0xF700; LDIR would corrupt the IRQ ring)
# -- they must use plain `cpnos-disk-install` instead.
cpnos-disk-install-with-locale: cpnos-build/d/cpnos.sys
	@echo "=== stamping cpnos.sys + prepending 384 B locale prefix ==="
	@python3 cpnos-build/stamp_cpnos.py cpnos-build/d/cpnos.sys $(BUILDDIR)/cpnos_stamped.sys \
	    --locale $(CPNOS_LOCALE_TAG)
	@python3 cpnos-build/gen_locale_prefix.py $(BUILDDIR)/locale_prefix.bin
	@cat $(BUILDDIR)/locale_prefix.bin $(BUILDDIR)/cpnos_stamped.sys > $(BUILDDIR)/cpnos_with_locale.img
	@echo "  cpnos.img = 384 B prefix + $$(wc -c < $(BUILDDIR)/cpnos_stamped.sys) B stamped cpnos.sys = $$(wc -c < $(BUILDDIR)/cpnos_with_locale.img) B"
	@cpmrm -f ibm-3740 $(MPM_DISK_LIB)/mpm-net2-1.dsk 0:cpnos.img 2>/dev/null || true
	cpmcp -f ibm-3740 $(MPM_DISK_LIB)/mpm-net2-1.dsk \
	    $(BUILDDIR)/cpnos_with_locale.img 0:cpnos.img
	@if [ -f $(MPM_DISK_LIB)/cpnetsmk-1.dsk ]; then \
	    cpmrm -f ibm-3740 $(MPM_DISK_LIB)/cpnetsmk-1.dsk 0:cpnos.img 2>/dev/null || true; \
	    cpmcp -f ibm-3740 $(MPM_DISK_LIB)/cpnetsmk-1.dsk \
	        $(BUILDDIR)/cpnos_with_locale.img 0:cpnos.img; \
	    echo "  refreshed (locale) cpnos.img on cpnetsmk-1.dsk"; \
	 fi
	@echo "  refreshed (locale) cpnos.img on mpm-net2-1.dsk"
.PHONY: cpnos-disk-install-with-locale

# Force cpnos.com to rebuild whenever any of its sources change.
.PHONY: cpnos-disk-install
cpnos-build/d/cpnos.sys: $(wildcard cpnos-build/src/*.asm cpnos-build/src/*.s) cpnos-build/Makefile
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

# Unified lineprog binary path (depends on COMPILER) — used by the
# wire-mode preflight checks below and by anything else that wants to
# inspect the just-built PROM1 line program.  BUILDDIR-prom1lineprog/
# is the layout convention: clang-prom1lineprog/ vs sdcc-prom1lineprog/.
LINEPROG_BIN = $(BUILDDIR)-prom1lineprog/prom1-lineprog.bin

# Full install: autoload-PROM0 + cpnos PROM1-lineprog into MAME +
# cpmsim disk-side cpnos.com.  prom1-lineprog-install (defined below)
# chains autoload-prom-install + prom1-lineprog-mame-install +
# cpnos-disk-install.
cpnos-install: prom1-lineprog-install

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
#   - MP/M is running as a backgrounded process (see START_MPM /
#     z80pack/cpmsim/mpm-net2, PID in $(MPM_PIDFILE)).  Target restarts
#     it so the drive staging is fresh.
#   - cpnos-rom is built and installed into MAME.
#
# Prints PASS or FAIL and exits accordingly.
MPM_DIR ?= $(CURDIR)/../z80pack/cpmsim
# MP/M CP/NET master (mpm-net2) lifecycle -- kill by SAVED PID, not `pkill -f`.
#
# We keep launching under `screen`: cpmsim needs a PTY on its console stdin so
# MP/M's operator-console read BLOCKS at `0A>`.  With a plain `</dev/null` the
# console gets instant EOF and busy-loops, starving the CP/NET server task so
# the slave never finishes booting to E> (verified 2026-07-06).  screen -dmS
# gives that PTY.
#
# START_MPM launches the named session AND records the screen session PID in
# $(MPM_PIDFILE).  _kill-mpm then reaps cpmsim by killing the CHILDREN OF THAT
# EXACT PID (`pkill -P $$PID`, parent-PID-targeted) rather than a broad
# `pkill -f cpmsim` that could hit an unrelated cpmsim on the same host.
MPM_PIDFILE = /tmp/mpm-net2.pid
START_MPM   = cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2 && sleep 0.3 && \
	screen -ls | grep -oE '[0-9]+\.mpm' | head -1 | cut -d. -f1 > $(MPM_PIDFILE)
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
# The "wire-mode tag" baked into the cpnos banner (visible at runtime
# as e.g. "RC702 CP/NOS 55K PIO clang ...") comes from the
# TRANSPORT_NAME macro the Makefile passes via -DTRANSPORT_NAME=...
# print_banner emits it as part of the banner string in cpnos.bin.
# Targets assert the right wire-mode is present (or absent) to avoid
# the topology-mismatch class of bug from 2026-04-28 (Phase 27c — see
# tasks/timeline.md).
#
# Pattern note: the banner has format "RC702 CP/NOS NNK <NAME> ..."
# where <NAME> is " PIO " or " SIO " (space-bounded).  Grep for the
# space-bounded NAME to disambiguate from any future field that might
# contain similar substrings.
#
# Likewise we check that MAME_IRQ exists with the cpnet_bridge gate
# fix before pio-irq-* targets launch — otherwise the slave's IRQ
# path silently drops bytes when poll_tick over-strobes.

# Slave was built with TRANSPORT=pio-irq (banner contains " PIO ")
_check-tag-pio-irq:
	@if ! strings $(LINEPROG_BIN) 2>/dev/null | grep -q ' PIO '; then \
	    echo "FAIL: $(LINEPROG_BIN) does not contain wire-mode tag ' PIO '."; \
	    echo "      This target requires a TRANSPORT=pio-irq build."; \
	    exit 1; \
	fi

# Slave was NOT built for pio-irq (cpnet-smoke wires SIO-A, not PIO-B)
_check-tag-not-pio-irq:
	@if strings $(LINEPROG_BIN) 2>/dev/null | grep -q ' PIO '; then \
	    echo "FAIL: $(LINEPROG_BIN) reports wire-mode ' PIO ' but this target"; \
	    echo "      wires SIO-A only.  Either rebuild cpnos with"; \
	    echo "      TRANSPORT=sio or use 'make pio-irq-smoke' instead."; \
	    exit 1; \
	fi


# MAME_IRQ tree contains the cpnet_bridge gate fix (commit 60e2b9a032f
# on pio-mpm-irq-fix branch).  We check by source-grep, not by binary
# inspection — robust against the binary being rebuilt without the fix.
_check-mame-irq:
	@if [ ! -x $(MAME)/regnecentralend ]; then \
	    echo "FAIL: $(MAME)/regnecentralend not found or not executable"; \
	    exit 1; \
	fi
	@if [ ! -f $(MAME)/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp ]; then \
	    echo "FAIL: $(MAME) is not a MAME tree (no cpnet_bridge.cpp)"; \
	    exit 1; \
	fi
	@if ! grep -q 'm_brdy_high' $(MAME)/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp; then \
	    echo "FAIL: $(MAME) cpnet_bridge.cpp missing the gate fix."; \
	    echo "      Need branch with poll_tick gated on m_brdy_high"; \
	    echo "      (commit 60e2b9a032f on ravn/mame:pio-mpm-irq-fix)."; \
	    exit 1; \
	fi
	@if [ ! $(MAME)/regnecentralend -nt $(MAME)/src/devices/bus/rc702/pio_port/cpnet_bridge.cpp ]; then \
	    echo "FAIL: $(MAME)/regnecentralend is older than cpnet_bridge.cpp."; \
	    echo "      Rebuild MAME (cd $(MAME) && make)."; \
	    exit 1; \
	fi

# ---- _verify-bench: shared bench verifier (post-MAME) -----------
# Asserts SIO-B contains the workload's finish marker, prints the
# smoke_inject "bench=X.XXXs" timing, and (for filecopy) extracts
# SUMTEST.ASM + SUMTEST.CPY from the master's drivea.dsk and byte-
# compares them.  WORKLOAD must already be set by the caller.
# Comprehensive shutdown of the mpm-net2 / cpmsim master from a previous
# run.  Entry-side safety net (subsequent test runs always find :4002
# clean even if a prior run aborted without exit-side cleanup) and
# exit-side reaper (so daemons don't accumulate across sessions).
#
# PID-based (see START_MPM): kills the exact PID recorded in $(MPM_PIDFILE)
# at launch, escalating TERM -> KILL; then, as a fallback for an orphan left
# without a pidfile, kills whatever `lsof -t` reports still holding :4002 (by
# PID, never a broad `pkill -f`).  Verifies :4002 is actually free at the end
# so callers get a hard error if cleanup didn't take.
#
# Use as `$(MAKE) _kill-mpm` (errors if cleanup fails) at the entry of
# any test target spawning the mpm-net2 daemon; use as
# `-$(MAKE) _kill-mpm` (best-effort) right after MAME exits to reap
# on the happy path.  See ravn/rc700-gensmedet#99.
.PHONY: _kill-mpm
_kill-mpm:
	@# Reap the master by the SAVED screen-session PID ($(MPM_PIDFILE)), not a
	@# broad `pkill -f cpmsim` that could hit an unrelated cpmsim.  cpmsim runs
	@# as a child of that screen session, so `pkill -P $$PID` (parent-PID
	@# targeted) kills exactly our cpmsim; then quit the session and kill the
	@# screen backend itself.  A stale master from a crashed run can otherwise
	@# survive holding disk locks on mpm-net2-1.dsk and a non-LISTEN :4002
	@# socket, so a fresh master binds the port yet fails the CP/NET handshake
	@# (slave never reaches E>).
	@PID=$$(cat $(MPM_PIDFILE) 2>/dev/null); \
	 if [ -n "$$PID" ]; then \
	   for sig in TERM TERM KILL; do \
	     pkill -$$sig -P $$PID 2>/dev/null || true; \
	     sleep 0.5; \
	     pgrep -P $$PID >/dev/null 2>&1 || break; \
	   done; \
	   screen -S mpm -X quit >/dev/null 2>&1 || true; \
	   kill -KILL $$PID 2>/dev/null || true; \
	 fi; \
	 rm -f $(MPM_PIDFILE)
	@# Belt-and-braces: quit any lingering named session even without a pidfile.
	-@screen -S mpm -X quit >/dev/null 2>&1 || true
	@# Safety net for an orphan master left WITHOUT a pidfile (older sessions):
	@# find whatever still holds :4002 by PID via `lsof -t` and kill THAT exact
	@# PID -- still surgical, still never a broad pkill.
	@PORTPID=$$(lsof -nP -iTCP:4002 -sTCP:LISTEN -t 2>/dev/null); \
	 if [ -n "$$PORTPID" ]; then \
	   for sig in TERM KILL; do \
	     kill -$$sig $$PORTPID 2>/dev/null || break; \
	     sleep 0.5; \
	     lsof -nP -iTCP:4002 -sTCP:LISTEN -t >/dev/null 2>&1 || break; \
	   done; \
	 fi
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 still bound after _kill-mpm:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi

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
	python3 $(SHARED)/testutil/mksmokeasm.py
	$(SHARED)/testutil/mksmokedisk.sh
	@echo "=== 2/5 restarting MP/M with fresh drive D: ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 3/5 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@sleep 4
	@echo "=== 4/5 launching MAME + smoke injector (workload: $(WORKLOAD)) ==="
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_smoke_inject.log /tmp/cpnos_boot_marks.txt
	@python3 -u $(SHARED)/testutil/smoke_inject.py $(SMOKE_PORT) \
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
	    -autoboot_script $(SHARED)/mame/porttap.lua
	@kill $$(cat /tmp/cpnos_smoke_inject.pid) 2>/dev/null || true
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort so verify-bench still runs on cleanup error
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
# MAME_IRQ removed 2026-05-18 -- consolidated to single MAME tree.  All
# previous $(MAME_IRQ) references rewritten to $(MAME); the cross-tree
# sync steps that clobbered freshly-installed PROMs are now no-ops and
# stripped below.  See common.mk for the canonical $(MAME) default.
pio-irq-netboot: cpnos-install _check-tag-pio-irq _check-mame-irq
	@echo "=== 1/4 restarting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 2/4 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_screen.txt /tmp/cpnos_boot_marks.txt
	@echo "=== 4/4 launching MAME (PIO-B -> mpm-net2 :4002) ==="
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 30 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script $(SHARED)/mame/porttap.lua
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
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
	python3 $(SHARED)/testutil/mksmokeasm.py
	$(SHARED)/testutil/mksmokedisk.sh
	@echo "=== 2/5 restarting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_wboot.txt /tmp/cpnos_boot_result.txt \
	    /tmp/cpnos_smoke_inject.log /tmp/cpnos_boot_marks.txt
	@echo "=== 4/5 launching smoke_inject + MAME (workload: $(WORKLOAD)) ==="
	@python3 -u $(SHARED)/testutil/smoke_inject.py $(SMOKE_PORT) \
	    --workload $(WORKLOAD) \
	    --log /tmp/cpnos_siob.raw --timeout 240 \
	    > /tmp/cpnos_smoke_inject.log 2>&1 & \
	 echo $$! > /tmp/cpnos_smoke_inject.pid
	@sleep 0.4
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 1200 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 socket.127.0.0.1:$(SMOKE_PORT) \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script $(SHARED)/mame/porttap.lua
	@kill $$(cat /tmp/cpnos_smoke_inject.pid) 2>/dev/null || true
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
	@$(MAKE) _verify-bench WORKLOAD=$(WORKLOAD)

# ---- drive I: canonical tool folder (= slave E:, the shared tool drive) ---
# The contents of E: are synchronised with ONE repo folder:
#   $(SHARED)/drive_i/            <-- single source of truth, git-tracked
# so every test target sees the SAME drive and new tools are added by
# dropping a file in that folder.  I: is rebuilt fresh (blank 4 MB HD) each
# run and re-populated from the folder; slave CFGTBL maps E:->I:
# (init.c cfgtbl_init_template) and the E:-tests build cpnos with
# CPNOS_DEFAULT_DRIVE=0x04 so the slave cold-boots into E:.
#
#   make stage-drivei-tools   folder -> fresh drive I:  (before a test run)
#   make sync-drivei-back     drive I: -> folder        (capture E: changes)
#
# drive_i_sync.sh encapsulates the cpmtools quirks (z80pack-hd segfault-on-
# cleanup) and case normalisation.  See $(SHARED)/drive_i/README.md.
DRIVEI_DIR  = $(SHARED)/drive_i
DRIVEI_SYNC = $(SHARED)/drive_i_sync.sh
DRIVEI_DSK  = $(MPM_DIR)/disks/library/mpm-net2-drivei.dsk

.PHONY: stage-drivei-tools stage-drivei-ppas sync-drivei-back
stage-drivei-ppas: stage-drivei-tools    # backward-compat alias
stage-drivei-tools:
	@echo "=== syncing $(DRIVEI_DIR)/ -> master drive I (slave E:) ==="
	@which cpmcp >/dev/null 2>&1 || { \
	  echo "ERROR: cpmcp not in PATH; install cpmtools" >&2; exit 1; }
	@# mkdskimg writes ./disks/drive<x>.dsk in its CWD -- chdir, run, move.
	@rm -f $(DRIVEI_DSK)
	@cd $(MPM_DIR) && rm -f disks/drivei.dsk && ./srctools/mkdskimg i
	@mv $(MPM_DIR)/disks/drivei.dsk $(DRIVEI_DSK)
	@sh $(DRIVEI_SYNC) to-disk $(DRIVEI_DIR) $(DRIVEI_DSK)
	@# Verify every folder file landed (grep the CP/M directory area for the
	@# padded 8+3 name; cpm* rcs are unreliable on z80pack-hd).
	@for src in $(DRIVEI_DIR)/*; do \
	   base=$$(basename "$$src"); \
	   case "$$base" in README*|readme*|.*) continue;; esac; \
	   nm=$$(printf '%s' "$${base%.*}" | tr 'a-z' 'A-Z'); \
	   ext=$$(printf '%s' "$${base##*.}" | tr 'a-z' 'A-Z'); \
	   pat=$$(printf '%-8s%-3s' "$$nm" "$$ext"); \
	   head -c 16384 $(DRIVEI_DSK) | grep -qaF "$$pat" || { \
	     echo "ERROR: '$$base' ($$pat) missing on drive I after sync" >&2; exit 1; }; \
	 done
	@echo "    synced: $$(ls $(DRIVEI_DIR) | grep -viE 'readme' | tr '\n' ' ')"

# Merge whatever is on drive I: (= slave E:) back into the repo folder --
# captures files the slave created/modified during a session (compiled
# .REL/.COM, saved COMAL/Pascal sources, etc.).  Review `git status` and
# commit intentionally; this is deliberately a separate, explicit target so
# ordinary test runs don't churn the tree.
sync-drivei-back:
	@[ -f $(DRIVEI_DSK) ] || { echo "ERROR: $(DRIVEI_DSK) not found (run a test first)" >&2; exit 1; }
	@sh $(DRIVEI_SYNC) from-disk $(DRIVEI_DIR) $(DRIVEI_DSK)
	@echo "    review with: git status $(DRIVEI_DIR)"

# PolyPascal regression: drive cpnos through "PPAS PRIMES" / "R" / "Q"
# (PPAS is the PolyPascal interpreter command), verify primes are
# printed (looks for the last prime, 29989), and verify Q returns to
# the CCP E> prompt.  Forces MIRROR_SIOB=1 so the Lua script can
# scrape /tmp/cpnos_siob.raw for completion markers.  MP/M is
# restarted from scratch so the run is hermetic.
cpnos-polypascal-test-no-mirror:
	@# Variant of polypascal-test with MIRROR_SIOB=0 -- the slave's
	@# impl_conout doesn't busy-wait on SIO-B TX after every console
	@# byte.  Comparison probe: does removing the per-char ~1 ms SIO-B
	@# transmit wait speed up the PPAS PRIMES test wall-clock?  Lua
	@# variant polls 25x80 display RAM at 0xF800 instead of SIO-B raw
	@# for the stage markers.
	@echo "=== 1/4 building cpnos-rom with MIRROR_SIOB=0 + installing ==="
	$(MAKE) MIRROR_SIOB=0 cpnos-install
	@echo "=== 2/4 (re)starting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 3/4 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@# CRITICAL (#119 root cause, found 2026-07-06): the health-gate ping above
	@# CONSUMES the mpm-net2 master's single CP/NET connection and leaves its
	@# protocol state machine wedged mid-frame — a verified 2nd connection gets
	@# ENQ (0x05) back instead of ACK.  MAME's slave is that 2nd connection, so
	@# without a restart it hangs forever in _transport_recv_byte after printing
	@# its banner and never reaches E> (both transports, both compilers — exactly
	@# the parked polypascal-hang symptom).  The ping was added in eb116e9
	@# (2026-07-04) as a startup gate but silently broke the test it guards.
	@# Fix: keep the ping (real health-check value) but restart the master FRESH
	@# afterwards so MAME connects to a pristine, un-probed one.
	@$(MAKE) _kill-mpm
	$(START_MPM)
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 restart-after-ping did not reopen :4002 within 20s"; exit 1; fi; sleep 0.5; done
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_polypascal_log.txt /tmp/cpnos_polypascal_result.txt
	@KH=$$($(NM) $(BUILDDIR)/payload.elf | awk '/_kbd_head$$/{print $$1}'); \
	 KR=$$($(NM) $(BUILDDIR)/payload.elf | awk '/_kbd_ring$$/{print $$1}'); \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@cat $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@echo "=== launching MAME with no-mirror PolyPascal test driver ==="
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh polypascal_no_mirror_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(SECONDS_TO_RUN_POLYPASCAL) \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script $(SHARED)/mame/polypascal_test_no_mirror.lua
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
	@echo "--- polypascal-test (no-mirror) log tail ---"
	@tail -30 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

# Fast CP/NET smoke test for iterating on #115 Phase 2: boot the slave
# to E> prompt and run DIR.  ~15s end-to-end vs polypascal's ~50s.
# DIR walks BDOS-66/67 SEARCH-FIRST/NEXT — exercises snios_rcvmsg_c
# enough that a broken INIR refactor will surface here too.
#
# Usage:
#   make cpnos-dir-test COMPILER=clang TRANSPORT=pio-irq
#   make cpnos-dir-test COMPILER=clang TRANSPORT=sio
.PHONY: cpnos-dir-test
cpnos-dir-test:
	@echo "========================================================="
	@echo "  cpnos-dir-test  COMPILER=$(COMPILER)  TRANSPORT=$(TRANSPORT_NAME)"
	@echo "========================================================="
	@echo "=== 1/5 building prom1-lineprog ($(COMPILER)) + installing ==="
	$(MAKE) MIRROR_SIOB=1 CPNOS_DEFAULT_DRIVE=0x04 prom1-lineprog-install
	@echo "=== 2/5 refreshing disk-side cpnos.img (locale prefix) ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-disk-install
	$(MAKE) stage-drivei-ppas
	@echo "=== 3/5 (re)starting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 4/5 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@# CRITICAL (#119 root cause, found 2026-07-06): the health-gate ping above
	@# CONSUMES the mpm-net2 master's single CP/NET connection and leaves its
	@# protocol state machine wedged mid-frame — a verified 2nd connection gets
	@# ENQ (0x05) back instead of ACK.  MAME's slave is that 2nd connection, so
	@# without a restart it hangs forever in _transport_recv_byte after printing
	@# its banner and never reaches E> (both transports, both compilers — exactly
	@# the parked polypascal-hang symptom).  The ping was added in eb116e9
	@# (2026-07-04) as a startup gate but silently broke the test it guards.
	@# Fix: keep the ping (real health-check value) but restart the master FRESH
	@# afterwards so MAME connects to a pristine, un-probed one.
	@$(MAKE) _kill-mpm
	$(START_MPM)
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 restart-after-ping did not reopen :4002 within 20s"; exit 1; fi; sleep 0.5; done
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_polypascal_log.txt /tmp/cpnos_polypascal_result.txt
	@echo "=== 5/5 generating addr file ($(BUILDDIR)) ==="
ifeq ($(COMPILER),sdcc)
	@KH=$$(awk '/^_kbd_head[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 KR=$$(awk '/^_kbd_ring[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
else
	@KH=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_head$$/{print $$1}'); \
	 KR=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_ring$$/{print $$1}'); \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
endif
	@echo "=== launching MAME with dir_test.lua autoboot (~30s budget) ==="
ifeq ($(TRANSPORT),sio)
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh dir_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 60 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    $(TRACE_ARGS) \
	    -autoboot_script $(SHARED)/mame/dir_test.lua
else
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh dir_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 60 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -log \
	    $(TRACE_ARGS) \
	    -autoboot_script $(SHARED)/mame/dir_test.lua
	-cp -f error.log /tmp/cpnos_dir_bridge.log 2>/dev/null
endif
	-$(MAKE) _kill-mpm
	@echo "--- dir-test log tail ---"
	@tail -20 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

# Same as cpnos-dir-test, but injects MAME's debugger trace command so the
# instruction stream + (interrupted at PC, IRQ N) annotations get
# interleaved with the LOG=1 z80pio/cpnet_bridge logerror output.  Used
# for diagnosing INIR/ISR races (rc700-gensmedet#115 Phase 0).  Cost:
# ~20% additional emulation slowdown; test still completes in ~16s.
# Requires regnecentralend built with z80pio.cpp LOG=1 — see
# rc700-gensmedet/cpnos-in-c/tasks/session-2026-06-13-phase4-inir-and-mame-findings.md.
.PHONY: cpnos-dir-test-trace
cpnos-dir-test-trace: TRACE_ARGS = -debug -debugger none -debugscript /tmp/inir.ds
cpnos-dir-test-trace: _gen_trace_debugscript cpnos-dir-test
	@echo "--- trace tail ---"
	@wc -l /tmp/z80_trace.txt 2>/dev/null
	@grep -c '(interrupted' /tmp/z80_trace.txt 2>/dev/null \
	  | awk '{ print "(interrupted at) annotations:", $$1 }'

.PHONY: _gen_trace_debugscript
_gen_trace_debugscript:
	@# MAME debugger trace command takes COMMA-separated args:
	@#   trace <filename>,<CPU>,[noloop|logerror][,<action>]
	@# CPU index 0 = first/main Z80; logerror flag interleaves logerror
	@# output inline with the instruction trace.
	@printf 'trace /tmp/z80_trace.txt,0,logerror\ngo\n' > /tmp/inir.ds
	@rm -f /tmp/z80_trace.txt
	@# Earlier experiment tried `ln -sf /dev/null error.log` to test
	@# whether MAME's -log fprintfs were the source of polypascal-test-
	@# trace flakiness.  Ruled out by trace evidence (mpm-net2 itself
	@# goes silent at sim 4 s, not the slave); see commit 93de84e + the
	@# rc700-gensmedet#flakiness investigation in tasks/.  Reverted to
	@# a real file so MAME's `-log` writes succeed normally.
	@rm -f error.log

# INIR-refactor instrumentation via GDB stub (issue #115 phase 0).
#
# A Lua-based probe was attempted first (target `cpnos-inir-baseline`
# below + cpnos-shared/mame/inir_probe.lua) but MAME's Lua tap
# callbacks are unreliable in this build: program-space
# install_write_tap callbacks die after the autoload PROM disable, and
# reading state["PC"].value from any tap callback crashes MAME in the
# chained-dofile arrangement.  See docs/mame_gdb_debugging.md for the
# verified GDB-stub setup this target uses instead.
#
# Output trace: /tmp/cpnos_inir_trace.log on the host (mounted into the
# z80-gdb docker container as /trace).
#
# Usage:
#   make cpnos-inir-baseline-gdb COMPILER=clang TRANSPORT=pio-irq
#
# Prerequisites:
#   - docker image `z80-gdb` (build with: docker build -t z80-gdb -f
#     scripts/z80-gdb.Dockerfile scripts/)
.PHONY: cpnos-inir-baseline-gdb
cpnos-inir-baseline-gdb:
	@echo "========================================================="
	@echo "  cpnos-inir-baseline-gdb  COMPILER=$(COMPILER)  TRANSPORT=$(TRANSPORT_NAME)"
	@echo "========================================================="
	@echo "=== 1/6 verifying z80-gdb docker image ==="
	@docker image inspect z80-gdb >/dev/null 2>&1 || { \
	  echo "ERROR: z80-gdb docker image missing.  Build with:"; \
	  echo "  docker build -t z80-gdb -f scripts/z80-gdb.Dockerfile scripts/"; \
	  exit 1; }
	@echo "=== 2/6 building prom1-lineprog ($(COMPILER)) + installing ==="
	$(MAKE) MIRROR_SIOB=1 CPNOS_DEFAULT_DRIVE=0x04 prom1-lineprog-install
	@echo "=== 3/6 refreshing disk-side cpnos.img (locale prefix) ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-disk-install
	$(MAKE) stage-drivei-ppas
	@echo "=== 4/6 (re)starting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 5/6 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@# CRITICAL (#119 root cause, found 2026-07-06): the health-gate ping above
	@# CONSUMES the mpm-net2 master's single CP/NET connection and leaves its
	@# protocol state machine wedged mid-frame — a verified 2nd connection gets
	@# ENQ (0x05) back instead of ACK.  MAME's slave is that 2nd connection, so
	@# without a restart it hangs forever in _transport_recv_byte after printing
	@# its banner and never reaches E> (both transports, both compilers — exactly
	@# the parked polypascal-hang symptom).  The ping was added in eb116e9
	@# (2026-07-04) as a startup gate but silently broke the test it guards.
	@# Fix: keep the ping (real health-check value) but restart the master FRESH
	@# afterwards so MAME connects to a pristine, un-probed one.
	@$(MAKE) _kill-mpm
	$(START_MPM)
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 restart-after-ping did not reopen :4002 within 20s"; exit 1; fi; sleep 0.5; done
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_polypascal_log.txt /tmp/cpnos_polypascal_result.txt \
	       /tmp/cpnos_inir_trace.log
	@touch /tmp/cpnos_inir_trace.log
	@echo "=== 5b/6 generating addr files (clang) ==="
	@KH=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_head$$/{print $$1}'); \
	 KR=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_ring$$/{print $$1}'); \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@echo "=== 6/6 launching MAME (gdbstub on :23946) + gdb client ==="
	@# MAME starts with -debug -debugger gdbstub.  Z80 pauses at PC=0
	@# waiting for GDB.  We launch MAME in the background, wait for the
	@# stub port to listen, then attach gdb-multiarch in docker.
	@( COMPILER=$(COMPILER) \
	   MAME_BIN=$(MAME)/regnecentralend \
	   $(CURDIR)/../scripts/mame_capture.sh inirgdb_$(COMPILER)_$(TRANSPORT) -- \
	     rc702 -rompath $(MAME)/roms \
	     -nothrottle -window -skip_gameinfo \
	     -seconds_to_run 240 \
	     -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	     -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	     -piob cpnet_bridge \
	     -bitb3 socket.127.0.0.1:4002 \
	     -debug -debugger gdbstub \
	     -debugger_host 0.0.0.0 -debugger_port 23946 \
	     -autoboot_script $(SHARED)/mame/polypascal_test.lua ) &
	@# Sleep a few seconds for MAME to come up + bind the stub.  DO NOT
	@# probe the stub port with `nc -z` first: MAME's gdbstub accepts
	@# only ONE connection per run, and the probe's open-then-close
	@# consumes that single accept slot, leaving gdb-multiarch hanging.
	@# Sleep is the safe wait.
	@MAME_PID=$$!; \
	 echo "MAME PID=$$MAME_PID; sleeping 5s for gdbstub to come up"; \
	 sleep 5; \
	 echo "attaching gdb-multiarch in docker"; \
	 docker run --rm \
	     -v $(CURDIR)/clang-prom1lineprog:/elf \
	     -v /tmp:/trace \
	     -v $(CURDIR)/../scripts:/gdbscript \
	     z80-gdb \
	     gdb-multiarch -batch -x /gdbscript/inir_gdb.gdb \
	     2>&1 | tee /tmp/cpnos_inir_gdb_stdout.log; \
	 wait $$MAME_PID 2>/dev/null || true
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
	@echo "--- polypascal-test log tail ---"
	@tail -30 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@echo "--- inir trace event count ---"
	@wc -l /tmp/cpnos_inir_trace.log 2>/dev/null
	@echo "--- inir trace tail (last 20 lines) ---"
	@tail -20 /tmp/cpnos_inir_trace.log 2>/dev/null
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

# INIR-refactor instrumentation probe (issue #115 phase 0).
#
# Runs the same polypascal-test workload but with inir_probe.lua as
# the autoboot script, which attaches memory + I/O watch taps to the
# PIO-B receive path and dumps a per-event trace to
# /tmp/cpnos_inir_trace.log.  The probe chains into polypascal_test.lua
# at the bottom, so this target generates BOTH the polypascal addrs
# (for the keystroke driver) AND the inir addrs (for the watch taps).
#
# Usage:
#   make cpnos-inir-baseline COMPILER=clang TRANSPORT=pio-irq
#
# After two reproducible green runs, save:
#   cp /tmp/cpnos_inir_trace.log tasks/inir-baseline-trace-$(date +%F).log
cpnos-inir-baseline:
	@echo "========================================================="
	@echo "  cpnos-inir-baseline  COMPILER=$(COMPILER)  TRANSPORT=$(TRANSPORT_NAME)"
	@echo "========================================================="
	@echo "=== 1/5 building prom1-lineprog ($(COMPILER)) + installing ==="
	$(MAKE) MIRROR_SIOB=1 CPNOS_DEFAULT_DRIVE=0x04 prom1-lineprog-install
	@echo "=== 2/5 refreshing disk-side cpnos.img (locale prefix) ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-disk-install
	$(MAKE) stage-drivei-ppas
	@echo "=== 3/5 (re)starting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 4/5 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@# CRITICAL (#119 root cause, found 2026-07-06): the health-gate ping above
	@# CONSUMES the mpm-net2 master's single CP/NET connection and leaves its
	@# protocol state machine wedged mid-frame — a verified 2nd connection gets
	@# ENQ (0x05) back instead of ACK.  MAME's slave is that 2nd connection, so
	@# without a restart it hangs forever in _transport_recv_byte after printing
	@# its banner and never reaches E> (both transports, both compilers — exactly
	@# the parked polypascal-hang symptom).  The ping was added in eb116e9
	@# (2026-07-04) as a startup gate but silently broke the test it guards.
	@# Fix: keep the ping (real health-check value) but restart the master FRESH
	@# afterwards so MAME connects to a pristine, un-probed one.
	@$(MAKE) _kill-mpm
	$(START_MPM)
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 restart-after-ping did not reopen :4002 within 20s"; exit 1; fi; sleep 0.5; done
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_polypascal_log.txt /tmp/cpnos_polypascal_result.txt \
	       /tmp/cpnos_inir_trace.log
	@echo "=== 5/5 generating addr files ($(BUILDDIR)) ==="
ifeq ($(COMPILER),sdcc)
	@# z88dk's prom1-lineprog map `sdcc/cpnos_lp.map` lines look like:
	@#   _kbd_head    = $ED10 ; addr, public, ...
	@KH=$$(awk '/^_kbd_head[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 KR=$$(awk '/^_kbd_ring[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	   echo "ERROR: kbd_head/kbd_ring missing from $(BUILDDIR)/cpnos_lp.map"; exit 1; }; \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@PH=$$(awk '/^_pio_rx_head[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 PT=$$(awk '/^_pio_rx_tail[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 IP=$$(awk '/^_isr_pio_par[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 TR=$$(awk '/^_transport_pio_recv_byte[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 SR=$$(awk '/^_snios_rcvmsg_c[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 [ -n "$$PH" ] && [ -n "$$PT" ] && [ -n "$$IP" ] && [ -n "$$TR" ] && [ -n "$$SR" ] || { \
	   echo "ERROR: one of pio_rx_head/pio_rx_tail/isr_pio_par/transport_pio_recv_byte/snios_rcvmsg_c missing from $(BUILDDIR)/cpnos_lp.map"; exit 1; }; \
	 printf 'return {\n  pio_rx_head = 0x%s,\n  pio_rx_tail = 0x%s,\n  isr_pio_par = 0x%s,\n  transport_pio_recv_byte = 0x%s,\n  snios_rcvmsg_c = 0x%s,\n}\n' \
	   "$$PH" "$$PT" "$$IP" "$$TR" "$$SR" \
	   > $(BUILDDIR)/cpnos_inir_addrs.lua
else
	@KH=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_head$$/{print $$1}'); \
	 KR=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_ring$$/{print $$1}'); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	   echo "ERROR: kbd_head/kbd_ring missing from $(PROM1ONLY_PAYLOAD_ELF)"; exit 1; }; \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@PH=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/ _pio_rx_head$$/{print $$1}'); \
	 PT=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/ _pio_rx_tail$$/{print $$1}'); \
	 IP=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/ _isr_pio_par$$/{print $$1}'); \
	 TR=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/ _transport_pio_recv_byte$$/{print $$1}'); \
	 SR=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/ _snios_rcvmsg_c$$/{print $$1}'); \
	 [ -n "$$PH" ] && [ -n "$$PT" ] && [ -n "$$IP" ] && [ -n "$$TR" ] && [ -n "$$SR" ] || { \
	   echo "ERROR: one of pio_rx_head/pio_rx_tail/isr_pio_par/transport_pio_recv_byte/snios_rcvmsg_c missing from $(PROM1ONLY_PAYLOAD_ELF)"; exit 1; }; \
	 printf 'return {\n  pio_rx_head = 0x%s,\n  pio_rx_tail = 0x%s,\n  isr_pio_par = 0x%s,\n  transport_pio_recv_byte = 0x%s,\n  snios_rcvmsg_c = 0x%s,\n}\n' \
	   "$$PH" "$$PT" "$$IP" "$$TR" "$$SR" \
	   > $(BUILDDIR)/cpnos_inir_addrs.lua
endif
	@echo "--- polypascal addrs ---"
	@cat $(BUILDDIR)/cpnos_polypascal_addrs.lua
	@echo "--- inir addrs ---"
	@cat $(BUILDDIR)/cpnos_inir_addrs.lua
	@echo "=== launching MAME with inir_probe.lua autoboot (max ~4 min) ==="
ifeq ($(TRANSPORT),sio)
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh inirprobe_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(SECONDS_TO_RUN_POLYPASCAL) \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -autoboot_script $(SHARED)/mame/inir_probe.lua
else
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh inirprobe_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(SECONDS_TO_RUN_POLYPASCAL) \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script $(SHARED)/mame/inir_probe.lua
endif
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
	@echo "--- polypascal-test log tail ---"
	@tail -30 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@echo "--- inir trace head (first 50 lines) ---"
	@head -50 /tmp/cpnos_inir_trace.log 2>/dev/null || echo '(no trace file)'
	@echo "--- inir trace event count ---"
	@wc -l /tmp/cpnos_inir_trace.log 2>/dev/null || echo '(no trace file)'
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

cpnos-polypascal-test:
	@# PROM1-only topology (session 73j-end onwards): autoload-in-c
	@# ROA375 in PROM0 + cpnos-in-c PROM1 line program in PROM1.  The
	@# two-PROM cpnos build is PARKED (see cpnos-in-c/TWO_PROM_PARKED.md)
	@# so this target no longer drives cpnos-install (which would fail
	@# in the sdcc/cpnos.cim link at __stack_top).  cpnos-disk-install
	@# is still needed: mpm-net2 serves the 384 B locale-prefix +
	@# cpnos.com image to the slave at handoff (locale tables travel
	@# with the disk image, not the PROM).
	@#
	@# PROM0 (autoload-in-c ROA375) is assumed already installed in
	@# MAME's roms/rc702/roa375.ic66 by `cd ../autoload-in-c && make
	@# clang_prom` (or the SDCC equivalent).  We don't touch it here --
	@# only PROM1 gets swapped in by this target.
	@echo "========================================================="
	@echo "  cpnos-polypascal-test  COMPILER=$(COMPILER)  TRANSPORT=$(TRANSPORT_NAME) (env TRANSPORT=$(TRANSPORT))"
	@echo "========================================================="
	@echo "=== 1/5 building prom1-lineprog ($(COMPILER)) + installing ==="
	$(MAKE) MIRROR_SIOB=1 CPNOS_DEFAULT_DRIVE=0x04 prom1-lineprog-install
	@echo "=== 2/5 refreshing disk-side cpnos.img (locale prefix) ==="
	$(MAKE) MIRROR_SIOB=1 cpnos-disk-install
	$(MAKE) stage-drivei-ppas
	@echo "=== 3/5 (re)starting MP/M with fresh disks ==="
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 4/5 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@# CRITICAL (#119 root cause, found 2026-07-06): the health-gate ping above
	@# CONSUMES the mpm-net2 master's single CP/NET connection and leaves its
	@# protocol state machine wedged mid-frame — a verified 2nd connection gets
	@# ENQ (0x05) back instead of ACK.  MAME's slave is that 2nd connection, so
	@# without a restart it hangs forever in _transport_recv_byte after printing
	@# its banner and never reaches E> (both transports, both compilers — exactly
	@# the parked polypascal-hang symptom).  The ping was added in eb116e9
	@# (2026-07-04) as a startup gate but silently broke the test it guards.
	@# Fix: keep the ping (real health-check value) but restart the master FRESH
	@# afterwards so MAME connects to a pristine, un-probed one.
	@$(MAKE) _kill-mpm
	$(START_MPM)
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 restart-after-ping did not reopen :4002 within 20s"; exit 1; fi; sleep 0.5; done
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_polypascal_log.txt /tmp/cpnos_polypascal_result.txt
	@echo "=== 5/5 generating $(BUILDDIR)/cpnos_polypascal_addrs.lua ==="
ifeq ($(COMPILER),sdcc)
	@# z88dk's prom1-lineprog map `sdcc/cpnos_lp.map` lines look like:
	@#   _kbd_head    = $ED10 ; addr, public, ...
	@KH=$$(awk '/^_kbd_head[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 KR=$$(awk '/^_kbd_ring[ \t]+=[ \t]+\$$/ {gsub(/.*\$$|[ \t].*/,"",$$0); print $$0}' \
	         $(BUILDDIR)/cpnos_lp.map | head -1); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	   echo "ERROR: kbd_head/kbd_ring missing from $(BUILDDIR)/cpnos_lp.map"; exit 1; }; \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(BUILDDIR)/cpnos_polypascal_addrs.lua
else
	@KH=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_head$$/{print $$1}'); \
	 KR=$$($(NM) $(PROM1ONLY_PAYLOAD_ELF) | awk '/_kbd_ring$$/{print $$1}'); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	   echo "ERROR: kbd_head/kbd_ring missing from $(PROM1ONLY_PAYLOAD_ELF)"; exit 1; }; \
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
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh polypascal_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(SECONDS_TO_RUN_POLYPASCAL) \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    $(TRACE_ARGS) \
	    -autoboot_script $(SHARED)/mame/polypascal_test.lua
else
	-COMPILER=$(COMPILER) \
	MAME_BIN=$(MAME)/regnecentralend \
	$(CURDIR)/../scripts/mame_capture.sh polypascal_$(COMPILER)_$(TRANSPORT) -- \
	    rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(SECONDS_TO_RUN_POLYPASCAL) \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -log \
	    $(TRACE_ARGS) \
	    -autoboot_script $(SHARED)/mame/polypascal_test.lua
	-cp -f error.log /tmp/cpnos_dir_bridge.log 2>/dev/null
endif
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
	@echo "--- polypascal-test log tail ---"
	@tail -30 /tmp/cpnos_polypascal_log.txt 2>/dev/null
	@echo "--- result ---"
	@cat /tmp/cpnos_polypascal_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_polypascal_result.txt 2>/dev/null

# Same as cpnos-polypascal-test, but with debugger trace.  See
# cpnos-dir-test-trace.  Estimated runtime ~90 s wall-clock; produces
# ~35 MB /tmp/z80_trace.txt.  Use for INIR/ISR race diagnosis under
# heavy CP/NET load.
.PHONY: cpnos-polypascal-test-trace
# -oslog: send logerror() output to stderr (in addition to error.log)
# -verbose: enable MAME's startup + shutdown verbose logging
# These let us see WHY MAME exits early (which it's been doing
# without writing a stage result) -- the relevant info shows up on
# stderr instead of being silently dropped between MAME and the
# mame_capture.sh wrapper.
cpnos-polypascal-test-trace: TRACE_ARGS = -debug -debugger none -debugscript /tmp/inir.ds -oslog -verbose
# DOT_WATCH_SKIP=1 disables the dot_watch install_write_tap in
# polypascal_test.lua.  Under -debug + LOG=1 the tap fires for every
# slave-side screen-char write, and each invocation now allocates a
# fresh sol coroutine (post mame#10 fix, ravn/mame 7ff2271).  Thousands
# of writes per simulated second pushes the PolyPascal compile past
# its deadline.  The dot_watch buffer is diagnostic-only; skipping it
# is fine here -- the per-instruction Z80 trace + Z80PIO logerror
# stream is the actual race-investigation signal.
cpnos-polypascal-test-trace: export DOT_WATCH_SKIP = 1
# Scale all per-stage Lua deadlines because under LOG=1 + per-
# instruction trace the slave's CP/NET RX rate drops from ~2.2 kB/sec
# baseline to ~1.1 kB/sec (~2x slowdown), AND the trace I/O occasion-
# ally blocks the emu thread, so PPAS load + execution takes a lot
# longer.  20x covers the worst case empirically; the test still
# PASSes well under the 1200 sim-sec MAME cap.
cpnos-polypascal-test-trace: export TRACE_DEADLINE_MULT = 20
cpnos-polypascal-test-trace: SECONDS_TO_RUN_POLYPASCAL = 1200
cpnos-polypascal-test-trace: _gen_trace_debugscript cpnos-polypascal-test
	@echo "--- trace tail ---"
	@wc -l /tmp/z80_trace.txt 2>/dev/null
	@grep -c '(interrupted' /tmp/z80_trace.txt 2>/dev/null \
	  | awk '{ print "(interrupted at) annotations:", $$1 }'

# Targeted-window variant.  Boot + most of the test runs untracked
# (~300 % real-time, mpm-net2 stays in sync), then polypascal_test.lua
# enables `trace ...` at TRACE_STAGE_START and disables it at
# TRACE_STAGE_STOP.  The default window covers stage 25 (the L PRIMES
# load -- ~1.5 sim sec of CP/NET-heavy RX, exactly the path INIR
# variant H is targeting) and turns trace off as soon as stage 3
# (PRIMES execution -- CPU-bound, no protocol activity) begins.
#
# Why not trace the whole run: the per-instruction logerror cost drops
# MAME to ~5-10 % real-time, while mpm-net2 keeps wall-clock pace ->
# master frame-level timeouts fire mid-PPAS-load and the master
# wedges.  A short window doesn't accumulate enough wall-clock skew
# to push mpm-net2 out of state.
#
# Override the window via env, e.g.:
#   make cpnos-polypascal-test-trace-window TRACE_STAGE_START=2 TRACE_STAGE_STOP=25
# would trace the initial PPAS load instead.  Stage numbers come from
# cpnos-shared/mame/polypascal_test.lua: 1=E>, 2=PPAS startup,
# 25=L PRIMES load, 3=primes output, 4=post-Run >>, 5=back to E>.
.PHONY: cpnos-polypascal-test-trace-window
cpnos-polypascal-test-trace-window: TRACE_ARGS = -debug -debugger none -debugscript /tmp/inir_window.ds -oslog -verbose
cpnos-polypascal-test-trace-window: export DOT_WATCH_SKIP = 1
cpnos-polypascal-test-trace-window: export TRACE_STAGE_START ?= 25
cpnos-polypascal-test-trace-window: export TRACE_STAGE_STOP  ?= 3
cpnos-polypascal-test-trace-window: SECONDS_TO_RUN_POLYPASCAL = 300
cpnos-polypascal-test-trace-window: _gen_window_debugscript cpnos-polypascal-test
	@echo "--- trace tail ---"
	@wc -l /tmp/z80_trace.txt 2>/dev/null
	@grep -c '(interrupted' /tmp/z80_trace.txt 2>/dev/null \
	  | awk '{ print "(interrupted at) annotations:", $$1 }'
	@echo "--- window:  stage $(TRACE_STAGE_START) -> stage $(TRACE_STAGE_STOP) ---"

.PHONY: _gen_window_debugscript
_gen_window_debugscript:
	@# Init script does NOT enable trace -- polypascal_test.lua toggles
	@# it at the stage boundaries via manager.machine.debugger:command().
	@printf 'go\n' > /tmp/inir_window.ds
	@rm -f /tmp/z80_trace.txt

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
	$(MAKE) _kill-mpm
	$(START_MPM)
	@echo "=== 3/4 waiting for MP/M CP/NET server on :4002 ==="
	@i=0; until nc -z 127.0.0.1 4002 2>/dev/null; do i=$$((i+1)); if [ $$i -ge 40 ]; then echo "ERROR: mpm-net2 did not open :4002 within 20s (see 'screen -r mpm' for the crash)"; exit 1; fi; sleep 0.5; done
	@python3 $(CURDIR)/scripts/cpnet_ping.py 127.0.0.1 4002 --timeout=5 || { echo "ERROR: mpm-net2 has :4002 open but did not answer a CP/NET LOGIN ""round-trip -- see 'screen -r mpm'"; exit 1; }
	@sleep 2
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_sioa.raw \
	       /tmp/cpnos_bios_jt_trace.log
	@echo "=== 4/4 launching MAME with BIOS-JT trace lua (~30s) ==="
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 30 \
	    -rs232a null_modem -bitb1 /tmp/cpnos_sioa.raw \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -piob cpnet_bridge \
	    -bitb3 socket.127.0.0.1:4002 \
	    -autoboot_script $(SHARED)/mame/bios_jt_trace.lua
	-$(MAKE) _kill-mpm  # exit-side reap; best-effort
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
cpnos-lis: $(BUILDDIR)/payload.elf $(SHARED)/scripts/check_no_helper_calls.py
	$(OBJDUMP) -d -S -r --symbolize-operands --triple=z80 $< > $(BUILDDIR)/cpnos.lis
	@echo "wrote $(BUILDDIR)/cpnos.lis (with C source + symbol-resolved operands)"
	@# Same helper-call gate as the SDCC build.  The clang build's
	@# ___umodqi3 / ___mulhi3 etc. ARE register-ABI-compatible (clang's
	@# compiler-rt), so technically safe -- but cpnos-rom has tight PROM
	@# budgets and a helper call costs ~10 B per site + 30+ B helper
	@# body.  Keep the resident image helper-free.
	python3 $(SHARED)/scripts/check_no_helper_calls.py $(BUILDDIR)/cpnos.lis

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

# ---- PROM1-only line program (experimental, clang only) ----------
# Builds cpnos-in-c as a single 2 KB PROM1 line program (signature
# at 0x2000) that pairs with autoload-in-c in PROM0.  See
# tasks/zx0-prom1-only-plan-2026-05-17.md for the full design.
#
# Two ZX0-compressed blobs share one 68 B decoder:
#   - init.zx0     init.bin relinked at VMA 0xC000 (RAM)
#   - payload.zx0  resident at VMA 0xED00 (unchanged from main build)
# Bootstrap (~30 B) decompresses both, then jp 0xC000 -> cpnos_cold_entry.

PROM1ONLY_DIR     = clang-prom1lineprog
PROM1ONLY_LD      = $(PROM1ONLY_DIR)/payload.ld
PROM1ONLY_PAYLOAD_ELF = $(PROM1ONLY_DIR)/payload.elf
PROM1ONLY_INIT_BIN    = $(PROM1ONLY_DIR)/init.bin
PROM1ONLY_PAYLOAD_BIN = $(PROM1ONLY_DIR)/payload.bin
PROM1ONLY_INIT_ZX0    = $(PROM1ONLY_DIR)/init.zx0
PROM1ONLY_PAYLOAD_ZX0 = $(PROM1ONLY_DIR)/payload.zx0
PROM1ONLY_BIN         = $(PROM1ONLY_DIR)/prom1-lineprog.bin

ZX0_BIN  = $(CURDIR)/../../z88dk/src/zx0/z88dk-zx0
DZX0_BIN = $(CURDIR)/../../z88dk/src/zx0/z88dk-dzx0

.PHONY: prom1-lineprog
ifeq ($(COMPILER),clang)
prom1-lineprog: $(PROM1ONLY_BIN)
endif
# COMPILER=sdcc binding is defined further down (next to the SDCC
# pipeline rule) so the SDCC variables it references are in scope.

# Re-link the payload objects with init relocated to VMA 0xC000.
# PROM1-only is dual-transport: both transport_pio.o and transport_sio.o
# are linked (transport_sio.o is in PAYLOAD_OBJS and the SIO symbol
# references in init.c's install_transport() keep it alive under
# --gc-sections), and xport_jt.o provides 3-byte JP-NN trampolines for
# _xport_send_byte / _xport_recv_byte that init.c patches at cold-init
# based on SW1 bit 2 (S03).  TRANSPORT_DEFSYMS is overridden to empty
# so the legacy --defsym aliases don't clash with the asm-emitted
# symbols.
$(PROM1ONLY_PAYLOAD_ELF): TRANSPORT_DEFSYMS =
$(PROM1ONLY_PAYLOAD_ELF): $(PAYLOAD_OBJS) $(BUILDDIR)/xport_jt.o $(PROM1ONLY_LD) cpnos-build/d/cpnos.sym
	@mkdir -p $(PROM1ONLY_DIR)
	@N=$$(perl -ne 'while (/([0-9A-Fa-f]{4})\s+NDOS\b/g) { print "$$1"; last }' cpnos-build/d/cpnos.sym); \
	 [ -n "$$N" ] || { echo "ERROR: NDOS symbol missing from cpnos.sym"; exit 1; }; \
	 NEND=$$(printf '0x%X' $$(( 0x$$N + 0xC80 ))); \
	 echo "prom1-lineprog payload.elf: __cpnos_load_end = $$NEND"; \
	 $(LD) --gc-sections -T $(PROM1ONLY_LD) \
	    --defsym=__cpnos_load_end=$$NEND \
	    $(TRANSPORT_DEFSYMS) $(PAYLOAD_OBJS) $(BUILDDIR)/xport_jt.o -o $@

$(PROM1ONLY_INIT_BIN): $(PROM1ONLY_PAYLOAD_ELF)
	$(OBJCOPY) -O binary --only-section=.init $< $@

$(PROM1ONLY_PAYLOAD_BIN): $(PROM1ONLY_PAYLOAD_ELF) cpnos-build/patch_payload_checksum.py
	$(OBJCOPY) -O binary --only-section=.payload $< $@
	python3 cpnos-build/patch_payload_checksum.py $@

# ZX0 compress + host-side roundtrip verify (must reproduce input
# exactly; build fails on mismatch).  Mirrors autoload-in-c pattern.
$(PROM1ONLY_INIT_ZX0): $(PROM1ONLY_INIT_BIN)
	$(ZX0_BIN) -f $< $@
	@rm -f /tmp/cpnos_prom1_init_rt.bin
	$(DZX0_BIN) $@ /tmp/cpnos_prom1_init_rt.bin
	cmp $< /tmp/cpnos_prom1_init_rt.bin || { echo "FAIL: init ZX0 roundtrip"; exit 1; }
	@echo "  init: $$(wc -c < $<) -> $$(wc -c < $@) B, roundtrip OK"

$(PROM1ONLY_PAYLOAD_ZX0): $(PROM1ONLY_PAYLOAD_BIN)
	$(ZX0_BIN) -f $< $@
	@rm -f /tmp/cpnos_prom1_payload_rt.bin
	$(DZX0_BIN) $@ /tmp/cpnos_prom1_payload_rt.bin
	cmp $< /tmp/cpnos_prom1_payload_rt.bin || { echo "FAIL: payload ZX0 roundtrip"; exit 1; }
	@echo "  payload: $$(wc -c < $<) -> $$(wc -c < $@) B, roundtrip OK"

$(PROM1ONLY_DIR)/bootstrap.o: $(PROM1ONLY_DIR)/bootstrap.s
	$(CC) --target=z80 -c $< -o $@

$(PROM1ONLY_DIR)/dzx0_standard.o: $(PROM1ONLY_DIR)/dzx0_standard.s
	$(CC) --target=z80 -c $< -o $@

$(PROM1ONLY_DIR)/init_zx0.o: $(PROM1ONLY_DIR)/init_zx0.s $(PROM1ONLY_INIT_ZX0)
	$(CC) --target=z80 -c $< -o $@

$(PROM1ONLY_DIR)/payload_zx0.o: $(PROM1ONLY_DIR)/payload_zx0.s $(PROM1ONLY_PAYLOAD_ZX0)
	$(CC) --target=z80 -c $< -o $@

PROM1ONLY_OBJS = $(PROM1ONLY_DIR)/bootstrap.o $(PROM1ONLY_DIR)/dzx0_standard.o \
                 $(PROM1ONLY_DIR)/init_zx0.o $(PROM1ONLY_DIR)/payload_zx0.o

$(PROM1ONLY_BIN): $(PROM1ONLY_OBJS) $(PROM1ONLY_DIR)/prom1.ld $(PROM1ONLY_PAYLOAD_ELF)
	@# Extract the sentinel byte's address from the payload ELF so
	@# bootstrap.s's `ld (_prom1_only_sentinel), a` resolves at the
	@# final PROM1 link.  payload.elf is the resident's ELF (BSS lives
	@# there); the final link here only sees bootstrap.o + decoder +
	@# the compressed payload/init blobs, so the symbol has to be
	@# injected via --defsym.
	@S=$$(/Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm $(PROM1ONLY_PAYLOAD_ELF) | awk '/ _prom1_only_sentinel$$/ {print "0x"$$1; exit}'); \
	 [ -n "$$S" ] || { echo "ERROR: _prom1_only_sentinel not found in payload.elf"; exit 1; }; \
	 echo "PROM1-only link: _prom1_only_sentinel = $$S"; \
	 $(LD) -T $(PROM1ONLY_DIR)/prom1.ld --defsym=_prom1_only_sentinel=$$S $(PROM1ONLY_OBJS) \
	    -o $(PROM1ONLY_DIR)/prom1-lineprog.elf
	$(OBJCOPY) -O binary $(PROM1ONLY_DIR)/prom1-lineprog.elf $@
	@SZ=$$(wc -c < $@ | tr -d ' '); \
	 HARD=2048; \
	 CAP=$(CPNOS_PROM1_CAP); \
	 echo "PROM1 line program: $$SZ / $$CAP B ($$((CAP - SZ)) B free; hard cap $$HARD B)"; \
	 if [ $$SZ -gt $$CAP ]; then \
	   echo "ERROR: PROM1 lineprog exceeds $$CAP B cap by $$((SZ - CAP)) B"; \
	   exit 1; \
	 fi; \
	 if [ $$SZ -gt $$HARD ]; then \
	   echo "WARN: PROM1 lineprog exceeds $$HARD B (hard cap on real RC702 hardware) by $$((SZ - HARD)) B."; \
	   echo "      Build will pad to $$CAP B and is MAME-only.  Shrink before merging to main."; \
	 fi; \
	 { cat $@; perl -e "print \"\\xff\" x ($$CAP - $$SZ)"; } > $@.padded; \
	 mv $@.padded $@
	@echo "wrote $@ ($$(wc -c < $@) B padded)"

# ---- SDCC PROM1-only line program: stage 2 try ---------------------
#
# Relink SDCC objects using sdcc-prom1lineprog/sections.asm (INIT_CODE
# at 0xC000, no RESET / PAYLOAD_HEADER) plus bootstrap.asm + dzx0.
# Emits per-section .bin via z88dk-zcc -create-app.  Stage 2.
#
# Status: experimental.  Expected to surface link errors -- iterate.
ifeq ($(COMPILER),sdcc)
SDCC_LP_DIR = sdcc-prom1lineprog
SDCC_LP_ASM_SRCS = $(SDCC_LP_DIR)/sections.asm \
                   $(SDCC_LP_DIR)/bootstrap.asm \
                   $(SDCC_LP_DIR)/dzx0_standard.asm \
                   $(SDCC_LP_DIR)/init_zx0.asm \
                   $(SDCC_LP_DIR)/payload_zx0.asm \
                   sdcc/bios_jt.asm sdcc/snios.asm sdcc/hal.asm \
                   sdcc/runtime.asm

# SDCC PROM1-lineprog uses the same C-object list as the (now-removed)
# two-PROM SDCC build — bootstrap.asm replaces what relocator.o used
# to do, and relocator.o was dropped from SDCC_C_OBJS in the 2026-06-03
# two-PROM cleanup.
SDCC_LP_C_OBJS = $(SDCC_C_OBJS)

# prom1-lineprog binding for COMPILER=sdcc: same target name as the
# clang path above; SDCC pipeline is below.  Two legacy aliases kept
# so previous-session invocations don't break: `sdcc-prom1lineprog`
# and `sdcc-prom1lineprog-try` both resolve to the same target.
.PHONY: prom1-lineprog sdcc-prom1lineprog sdcc-prom1lineprog-try
sdcc-prom1lineprog-try: prom1-lineprog
sdcc-prom1lineprog: prom1-lineprog

# Two-pass build (mirrors clang's clang-prom1lineprog two-pass):
#   pass 1: link with empty init.zx0 / payload.zx0 -> extract real
#           init_code.bin + resident.bin from per-section .bin output
#   ZX0:    compress + roundtrip verify
#   pass 2: relink -- INCBIN now picks up real ZX0 blobs
#   pad:    output the final 4 KB sdcc-prom1lineprog/prom1-lineprog.bin
prom1-lineprog: $(SDCC_LP_C_OBJS) $(BUILDDIR)/cpnos_layout.asm $(BUILDDIR)/xport_aliases.asm \
                    $(SDCC_LP_DIR)/sections.asm $(SDCC_LP_DIR)/bootstrap.asm \
                    $(SDCC_LP_DIR)/dzx0_standard.asm \
                    $(SDCC_LP_DIR)/init_zx0.asm $(SDCC_LP_DIR)/payload_zx0.asm
	@mkdir -p $(SDCC_LP_DIR)
	@# Ensure ZX0 placeholders exist before pass 1
	@touch $(SDCC_LP_DIR)/init.zx0 $(SDCC_LP_DIR)/payload.zx0
	@echo "=== sdcc-prom1lineprog pass 1: link with empty ZX0 ==="
	@cd $(BUILDDIR) && $(CC) $(ZFLAGS_BASE) $(SDCC_ZLFLAGS) \
	    $(addprefix ../,$(SDCC_LP_ASM_SRCS)) \
	    xport_aliases.asm cpnos_layout.asm \
	    $(notdir $(SDCC_LP_C_OBJS)) \
	    -o cpnos_lp > /tmp/sdcc_lp_pass1.log 2>&1 || { \
	      tail -30 /tmp/sdcc_lp_pass1.log; exit 1; }
	@echo "=== sdcc-prom1lineprog patch resident checksum BEFORE ZX0 ==="
	@# User direction (session 73j-late): "i still want the payload
	@# checksum before the xz0 unpacking starts".  Patches the last 2
	@# bytes of the resident bin so word-additive sum = 0xCAFE; the
	@# magic ends up INSIDE the ZX0-compressed blob and decompresses
	@# faithfully, so the relocator/bootstrap can verify the resident
	@# image is intact after dzx0.  Without this, post-decompress
	@# checksum would be undefined.
	python3 cpnos-build/patch_payload_checksum.py $(BUILDDIR)/cpnos_lp_RESIDENT_JUMPTABLE.bin
	@echo "=== sdcc-prom1lineprog ZX0 compress + roundtrip ==="
	$(ZX0_BIN) -f $(BUILDDIR)/cpnos_lp_INIT_CODE.bin $(SDCC_LP_DIR)/init.zx0
	@rm -f /tmp/sdcc_lp_init_rt.bin
	$(DZX0_BIN) $(SDCC_LP_DIR)/init.zx0 /tmp/sdcc_lp_init_rt.bin
	cmp $(BUILDDIR)/cpnos_lp_INIT_CODE.bin /tmp/sdcc_lp_init_rt.bin || \
	    { echo "FAIL: SDCC init.zx0 roundtrip"; exit 1; }
	$(ZX0_BIN) -f $(BUILDDIR)/cpnos_lp_RESIDENT_JUMPTABLE.bin $(SDCC_LP_DIR)/payload.zx0
	@rm -f /tmp/sdcc_lp_payload_rt.bin
	$(DZX0_BIN) $(SDCC_LP_DIR)/payload.zx0 /tmp/sdcc_lp_payload_rt.bin
	cmp $(BUILDDIR)/cpnos_lp_RESIDENT_JUMPTABLE.bin /tmp/sdcc_lp_payload_rt.bin || \
	    { echo "FAIL: SDCC payload.zx0 roundtrip"; exit 1; }
	@echo "=== sdcc-prom1lineprog pass 2: relink with real ZX0 ==="
	@cd $(BUILDDIR) && $(CC) $(ZFLAGS_BASE) $(SDCC_ZLFLAGS) \
	    $(addprefix ../,$(SDCC_LP_ASM_SRCS)) \
	    xport_aliases.asm cpnos_layout.asm \
	    $(notdir $(SDCC_LP_C_OBJS)) \
	    -o cpnos_lp > /tmp/sdcc_lp_pass2.log 2>&1 || { \
	      tail -30 /tmp/sdcc_lp_pass2.log; exit 1; }
	@cp $(BUILDDIR)/cpnos_lp_LINEPROG_HEADER.bin $(SDCC_LP_DIR)/prom1-lineprog.bin
	@SZ=$$(wc -c < $(SDCC_LP_DIR)/prom1-lineprog.bin | tr -d ' '); \
	 echo "  raw: $$SZ B"; \
	 PAD=4096; \
	 if [ $$SZ -gt $$PAD ]; then \
	   echo "ERROR: SDCC PROM1-only image > $$PAD B; bump pad or shrink"; exit 1; \
	 fi; \
	 { cat $(SDCC_LP_DIR)/prom1-lineprog.bin; \
	   perl -e "print \"\\xff\" x ($$PAD - $$SZ)"; } > $(SDCC_LP_DIR)/prom1-lineprog.bin.tmp; \
	 mv $(SDCC_LP_DIR)/prom1-lineprog.bin.tmp $(SDCC_LP_DIR)/prom1-lineprog.bin; \
	 echo "  padded: $$(wc -c < $(SDCC_LP_DIR)/prom1-lineprog.bin | tr -d ' ') B (target $$PAD)"; \
	 echo "  init.zx0:    $$(wc -c < $(SDCC_LP_DIR)/init.zx0 | tr -d ' ') B"; \
	 echo "  payload.zx0: $$(wc -c < $(SDCC_LP_DIR)/payload.zx0 | tr -d ' ') B"
	@echo "wrote $(SDCC_LP_DIR)/prom1-lineprog.bin"
endif

# ---- prom1-lineprog → MAME install --------------------------------
#
# Installs the full PROM1-only topology into MAME's roms/rc702/:
#   PROM0 (roa375.ic66) <- autoload-in-c/clang/prom.clang.bin (autoload)
#   PROM1 (prom1.ic65)  <- freshly-built prom1-lineprog.bin (clang or SDCC)
#
# Parallel to cpnos-mame-install but for the PROM1-only topology
# (session 73j-end onwards).  The two-PROM cpnos-mame-install is
# parked alongside the two-PROM build (TWO_PROM_PARKED.md).
.PHONY: prom1-lineprog-mame-install prom1-lineprog-install autoload-prom-install
ifeq ($(COMPILER),clang)
PROM1LP_SRC = $(PROM1ONLY_BIN)
else
PROM1LP_SRC = $(SDCC_LP_DIR)/prom1-lineprog.bin
endif

# Build + install autoload-in-c's clang PROM as PROM0.  Delegates to
# autoload-in-c's Makefile which writes to $(MAME)/roms/rc702/roa375.ic66
# directly (its own MAME default resolves to the same tree this Makefile
# uses post-consolidation).
#
# COMPILER=clang is HARD-PINNED — autoload's SDCC variant is 2214 B
# (won't fit the 2 KB hard PROM0 limit per project_rc702_2kb_prom_hard_limit),
# and the lineprog topology already requires clang's autoload (the only
# combination tested to work at session 73j-end).  Doesn't matter what
# COMPILER cpnos itself is built with -- PROM0 is always the clang
# autoload, PROM1 is the cpnos lineprog (clang or SDCC).
autoload-prom-install:
	$(MAKE) -C ../autoload-in-c COMPILER=clang prom

prom1-lineprog-mame-install: prom1-lineprog
	cp $(PROM1LP_SRC) $(MAME_PROM1)
	@echo "installed prom1-lineprog ($(COMPILER)) -> $(MAME_PROM1)"

prom1-lineprog-install: autoload-prom-install prom1-lineprog-mame-install cpnos-disk-install

# ---- SDCC PROM1-only line program (WIP) ---------------------------
#
# Stage 1 (measurement): take the existing SDCC two-PROM build's
# concatenated resident bytes (resident_a.bin + resident_b.bin = 2192 B
# at HEAD), ZX0-compress, and ROUND-TRIP-VERIFY.  Gives a reliable
# size measurement for the eventual PROM1-only SDCC build without
# requiring the full sdcc-prom1lineprog/ link pipeline.
#
# Stage 2 (future): mirror clang's prom1-lineprog using
# sdcc-prom1lineprog/sections.asm + bootstrap.asm + dzx0_standard.asm
# (scaffolding committed, Makefile rule outstanding -- see
# cpnos-in-c/sdcc-prom1lineprog/README.md for the hand-off plan).
#
# Run: `COMPILER=sdcc make sdcc-resident-zx0-probe`
SDCC_PROM1LP_DIR = sdcc-prom1lineprog

.PHONY: sdcc-resident-zx0-probe
sdcc-resident-zx0-probe: sdcc/resident_a.bin sdcc/resident_b.bin
	@mkdir -p $(SDCC_PROM1LP_DIR)
	@cat sdcc/resident_a.bin sdcc/resident_b.bin > $(SDCC_PROM1LP_DIR)/resident.bin
	@RAW=$$(wc -c < $(SDCC_PROM1LP_DIR)/resident.bin | tr -d ' '); \
	 echo "SDCC resident: $$RAW B raw (cat resident_a + resident_b)"
	$(ZX0_BIN) -f $(SDCC_PROM1LP_DIR)/resident.bin $(SDCC_PROM1LP_DIR)/resident.zx0
	@rm -f /tmp/sdcc_resident_rt.bin
	$(DZX0_BIN) $(SDCC_PROM1LP_DIR)/resident.zx0 /tmp/sdcc_resident_rt.bin
	@cmp $(SDCC_PROM1LP_DIR)/resident.bin /tmp/sdcc_resident_rt.bin \
	    || { echo "FAIL: SDCC resident ZX0 roundtrip mismatch"; exit 1; }
	@RAW=$$(wc -c < $(SDCC_PROM1LP_DIR)/resident.bin | tr -d ' '); \
	 Z=$$(wc -c < $(SDCC_PROM1LP_DIR)/resident.zx0 | tr -d ' '); \
	 SAVED=$$((RAW - Z)); \
	 PCT=$$(( (Z * 100) / RAW )); \
	 echo "  $(SDCC_PROM1LP_DIR)/resident.zx0: $$RAW -> $$Z B ($$PCT%, -$$SAVED B); roundtrip OK"
	@echo "Stage 1 done.  Stage 2 (sdcc-prom1lineprog full link pipeline)"
	@echo "still outstanding -- see sdcc-prom1lineprog/README.md."

# ---- Clean --------------------------------------------------------

cpnos-clean:
	rm -rf clang clang-prom1lineprog
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
# override per-file --codeseg.  init.c (the merged cold-init TU) gets
# redirected to INIT_CODE (PROM0 anchor group) below — pushes the
# cold-boot code into PROM0 to keep PROM1 usage under the 1.5 KB
# display-RAM-clearance limit.
CFLAGS += -Cs"--codeseg RESIDENT_CODE" -Cs"--constseg RESIDENT_RODATA"

# Per-target CFLAGS override — init.c goes to PROM0 INIT_CODE.
# Snapshot CFLAGS now (immediate `:=`) so the per-target assignment
# below doesn't recurse on itself.
SDCC_RESIDENT_CFLAGS := $(CFLAGS)
SDCC_PRE_CFLAGS := $(filter-out -Cs"--codeseg RESIDENT_CODE" -Cs"--constseg RESIDENT_RODATA",$(CFLAGS)) \
                   -Cs"--codeseg RESIDENT_PRE_CODE" -Cs"--constseg RESIDENT_PRE_RODATA"
# Two-PROM-only SDCC bits (INIT_CFLAGS for relocator.o, the relocator.o
# compile rule, payload_header_data.s generation, sdcc/reset.asm,
# cpnos.cim/cpnos.bin recipes) were removed 2026-06-03 along with the
# rest of the two-PROM build.  SDCC's production path is now SDCC
# PROM1-only line program (sdcc-prom1lineprog/), which has its own
# bootstrap.asm in place of reset.asm and embeds payload metadata
# differently.  See TWO_PROM_PARKED.md (and its removal).
# init.c is the merged cold-init TU (cfgtbl + hardware bring-up +
# netboot_mpm + cold orchestrator).  Its code runs once before
# resident_handoff's `OUT (0x18),A` disables the PROMs and is never
# reached again.  Routing the file to INIT_CODE/INIT_RODATA (PROM0
# anchor group) instead of RESIDENT_PRE_CODE (RAM) frees the RAM
# bytes, mirroring clang's `.init` section.  cfgtbl's BSS variable
# stays in bss_compiler regardless -- only the cold-init code/rodata
# moves to PROM-only.
SDCC_INIT_CFLAGS := $(filter-out -Cs"--codeseg RESIDENT_CODE" -Cs"--constseg RESIDENT_RODATA",$(CFLAGS)) \
                    -Cs"--codeseg INIT_CODE" -Cs"--constseg INIT_RODATA"
$(BUILDDIR)/init.o:           CFLAGS := $(SDCC_INIT_CFLAGS)
$(BUILDDIR)/transport_sio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)
# transport_pio.c absorbed isr.c in Phase 60 — both halves shared
# RESIDENT_PRE_CODE so the merge was free.
$(BUILDDIR)/transport_pio.o:  CFLAGS := $(SDCC_PRE_CFLAGS)

# Per-compiler PAYLOAD_OBJS list.  No relocator.o in the SDCC list now
# — the PROM1-lineprog build uses bootstrap.asm + dzx0_standard.asm.
SDCC_C_OBJS = $(BUILDDIR)/cpnos_main.o \
              $(BUILDDIR)/resident.o $(BUILDDIR)/init.o \
              $(BUILDDIR)/snios_c.o \
              $(BUILDDIR)/transport_sio.o $(BUILDDIR)/transport_pio.o

# Hand-written z88dk asm files (live in sdcc/ as tracked source).
SDCC_ASM_SRCS = sdcc/sections.asm \
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

# Content-driven generation: re-write only when the embedded TRANSPORT=
# header line doesn't match the current $(TRANSPORT).  Caught 2026-05-18
# when an earlier `TRANSPORT=sio` build left the .asm pointing at the
# SIO transport, the transport_stamp dep didn't fire on a later
# `TRANSPORT=pio-irq` build (the .asm was newer than the stamp), so
# the SDCC PROM1-only slave silently dispatched CP/NET to SIO-A
# (= /tmp/cpnos_sioa.raw, no master) instead of PIO -- looked like a
# LOGIN-time hang in cpnos-polypascal-test.  Same $(shell) pattern as
# transport_stamp above.
ifeq ($(filter clean cpnos-clean,$(MAKECMDGOALS)),)
_DUMMY_XPORT_ALIASES := $(shell mkdir -p $(BUILDDIR); \
    if ! grep -q "from TRANSPORT=$(TRANSPORT)\." $(BUILDDIR)/xport_aliases.asm 2>/dev/null; then \
        { \
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
        } > $(BUILDDIR)/xport_aliases.asm; \
        echo "xport_aliases: regenerated for TRANSPORT=$(TRANSPORT)" >&2; \
    fi)
endif

$(BUILDDIR)/xport_aliases.asm: ;

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
	   echo ""; \
	   echo "defc CPNOS_NDOSRL = 0x$$NDOSRL    ; cpnos.com DATA region base"; \
	   echo "defc CPNOS_NDOS   = 0x$$NDOS    ; cpnos.com CODE region base (loaded by netboot)"; \
	   echo "defc CPNOS_BDOS   = 0x$$BDOS    ; BDOS dispatch (programs CALL ZP[5..7] -> jp here)"; \
	   echo ""; \
	   echo "; __stack_top is NOT emitted from this file.  Two callers:"; \
	   echo ";   - PROM1-only (sdcc-prom1lineprog/bootstrap.asm): hardcodes"; \
	   echo ";     SP=0xF680 directly; ignores this file entirely.  Runtime SP"; \
	   echo ";     observed 0xF65A..0xF668, plenty of slack vs resident."; \
	   echo ";   - Two-PROM (sdcc/reset.asm): historical EXTERN __stack_top"; \
	   echo ";     pointing at NDOSRL.  Two-PROM is PARKED (see tasks/"; \
	   echo ";     TWO_PROM_PARKED.md); breaking that symbol is acceptable."; \
	   echo ";   If two-PROM SDCC is ever revived, re-emit __stack_top here"; \
	   echo ";   or move the SP literal into reset.asm directly."; \
	} > $@

# The SDCC audit / cpnos.cim / cpnos.bin two-PROM rules were removed
# 2026-06-03 along with the rest of the two-PROM build.  SDCC's
# production path is `make prom1-lineprog COMPILER=sdcc` (single 4 KB
# MAME-only artefact in sdcc-prom1lineprog/prom1-lineprog.bin).
# Note: SDCC code-quality audits (check_no_frame_ptr / no_helper_calls
# / sdcc_layout / unreferenced_publics) were attached to the deleted
# cpnos.cim rule; consider re-adding them as a gate on the SDCC
# prom1-lineprog target as a finishing-checklist follow-up.
endif
