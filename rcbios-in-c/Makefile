# RC702 CP/M BIOS in C (REL30)
#
# Usage:
#   make bios                 Build with default compiler (clang)
#   make bios COMPILER=sdcc   Build with SDCC via z88dk
#   make mame-maxi            Build + boot in MAME
#   make cycle-test            Cycle benchmark (ASM FILEX + TYPE FILEX.PRN)
#   make size                 Check binary size
#   make clean                Clean both compiler outputs
#
# Each compiler produces its own distinguishable artifact from shared sources:
#   clang -> clang/bios.clang.cim  (annotated listing: clang/bios.clang.lis,
#                                    tracked in git)
#   sdcc  -> sdcc/bios.cim
# Distinct filenames let both compilers build in parallel without colliding.
# Use $(BIOS_CIM) / $(BIOS_ELF) below to refer to the artifacts compiler-
# agnostically.

# ================================================================
# Compiler selection
# ================================================================

COMPILER ?= clang

# Compiler-distinct artifact names (avoids clang/sdcc parallel-build
# collisions, makes it obvious from the filename which toolchain produced
# a given .cim).
ifeq ($(COMPILER),clang)
  BIOS_CIM    = clang/bios.clang.cim
  BIOS_ELF    = clang/bios.clang.elf
  BIOS_TARGET = bios.clang.cim
else
  BIOS_CIM    = sdcc/bios.cim
  BIOS_ELF    = sdcc/bios.elf
  BIOS_TARGET = bios.cim
endif

# ================================================================
# Shared configuration
# ================================================================

CC = cc
CFLAGS = -Wall -Wextra -std=c99 -DHOST_TEST

# Language conversion table: DANISH (default), SWEDISH, GERMAN,
# UK_ASCII, US_ASCII, FRENCH, LIBRARY
KBLANG ?= DANISH

# Keyboard PIO port: A (default, stock RC702) or B (frees A for host link)
KBDPORT ?= A

# CP/M memory layout — single source of truth for MSIZE.
MSIZE ?= 56
BIAS  = $(shell echo $$(( ($(MSIZE) - 20) * 1024 )))
CPMB  = $(shell printf '0x%04X' $$(( 0x3400 + $(BIAS) )))
BIOSAD = $(shell printf '0x%04X' $$(( 0x3400 + $(BIAS) + 0x1600 )))

# LLVM-Z80 toolchain
LLVM_Z80 = $(CURDIR)/../../llvm-z80

# Disk image tools
PATCH = python3 ../rcbios/patch_bios.py
IMDINFO = python3 ../rcbios/imdinfo.py

# MAME — default to the submodule inside the workspace so the path
# works on any machine that has `z80-compiler-suite-workspace` checked
# out with submodules initialised.  Override with `make MAME=/path/to/mame`
# if you keep MAME somewhere else.
MAME ?= $(CURDIR)/../../mame
# Prefer the debug binary (`regnecentralend`) over the release
# (`regnecentralen`) when both exist; use whichever is present.
MAME_BIN ?= $(firstword $(wildcard $(MAME)/regnecentralend $(MAME)/regnecentralen))
FLOPTOOL = $(MAME)/floptool

# Parallelism for `make mame-debug`.  Defaults to nproc/2 so a 4-core
# box builds with -j 2 (safe for ~4 GB headroom); override on bigger
# machines with `make mame-debug MAME_BUILD_JOBS=10`.
MAME_BUILD_JOBS ?= $(shell n=$$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2); echo $$(( n > 1 ? n / 2 : 1 )))

# Disk images for testing
IMG_MINI = $(HOME)/Downloads/CPM_med_COMAL80.imd
IMG_MAXI = $(HOME)/Downloads/SW1711-I8.imd
IMG_DATA = $(HOME)/Downloads/PolyPascal_3.10.imd

# Size limits (bytes)
MINI_LIMIT = 6144
MAXI_LIMIT = 9984

# zmac assembler
ifneq ($(wildcard ../zmac/bin/zmac),)
ZMAC = ../zmac/bin/zmac
else
ZMAC = zmac
endif
CPMCP ?= cpmcp

.PHONY: all bios size clean mame-mini mame-maxi mame-test conout-test bgstar-test \
        asm-test cycle-test cycle-baseline profile profile-baseline test \
        mame-debug mame-roms siob-iobyte-test

all: bios size

# ================================================================
# Build timestamp (shared by both compilers)
# ================================================================

builddate.h: FORCE
	@echo '#define BUILDDATE "'$$(date +%Y-%m-%d\ %H:%M)'"' > $@.$$$$; \
	 cmp -s $@.$$$$ $@ 2>/dev/null && rm -f $@.$$$$ || mv $@.$$$$ $@

builddate.inc: FORCE
	@echo '    defm " C-BIOS '$$(date +%Y-%m-%d\ %H:%M)' /Thorbjoern Ravn Andersen"' > $@.$$$$; \
	 cmp -s $@.$$$$ $@ 2>/dev/null && rm -f $@.$$$$ || mv $@.$$$$ $@

FORCE:

# ================================================================
# Compiler dispatch: make bios → $(BIOS_CIM)
# ================================================================

bios: builddate.h verify-skew
	$(MAKE) -C $(COMPILER) $(BIOS_TARGET) MSIZE=$(MSIZE) KBLANG=$(KBLANG) KBDPORT=$(KBDPORT)

# Verify the hand-written sector skew tables in bios.c match the CP/M
# skew algorithm (analog of the original DRI assembler XLT macro).
# Runs before every BIOS build; build fails if tables drift from spec.
verify-skew:
	@python3 verify_skew.py bios.c > /dev/null

# SDCC build rules are in sdcc/Makefile

# ================================================================
# Size check
# ================================================================

size: bios
	@SIZE=$$(wc -c < $(BIOS_CIM) | tr -d ' '); \
	echo "$(COMPILER) BIOS: $$SIZE bytes"; \
	if [ $$SIZE -le $(MINI_LIMIT) ]; then \
		echo "  MINI (5.25\"): OK ($$(($(MINI_LIMIT) - SIZE)) bytes to spare)"; \
	else \
		echo "  MINI (5.25\"): OVER by $$((SIZE - $(MINI_LIMIT))) bytes"; \
	fi; \
	if [ $$SIZE -le $(MAXI_LIMIT) ]; then \
		echo "  MAXI (8\"):   OK ($$(($(MAXI_LIMIT) - SIZE)) bytes to spare)"; \
	else \
		echo "  MAXI (8\"):   OVER by $$((SIZE - $(MAXI_LIMIT))) bytes"; \
	fi

# ================================================================
# MAME boot targets — use $(BIOS_CIM)
# ================================================================

mame-mini: bios
	@if [ "$(FORCE)" = "1" ] || [ ! -f /tmp/bios_c_mini.mfi ]; then \
		cp $(IMG_MINI) /tmp/bios_c_mini.imd; \
		$(PATCH) /tmp/bios_c_mini.imd $(BIOS_CIM); \
		rm -f /tmp/bios_c_mini.mfi; \
		$(FLOPTOOL) flopconvert auto mfi /tmp/bios_c_mini.imd /tmp/bios_c_mini.mfi >/dev/null 2>&1; \
		rm -f /tmp/bios_c_mini.imd; \
		echo "Created fresh MFI: /tmp/bios_c_mini.mfi"; \
	else \
		echo "Reusing existing MFI: /tmp/bios_c_mini.mfi (use FORCE=1 to recreate)"; \
	fi
	$(MAME_BIN) rc702mini -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_mini.mfi \
		-skip_gameinfo -window -resolution 1100x720

mame-maxi: bios
	@if [ "$(FORCE)" = "1" ] || [ ! -f /tmp/bios_c_maxi.mfi ]; then \
		cp $(IMG_MAXI) /tmp/bios_c_maxi.imd; \
		$(PATCH) /tmp/bios_c_maxi.imd $(BIOS_CIM); \
		rm -f /tmp/bios_c_maxi.mfi; \
		$(FLOPTOOL) flopconvert auto mfi /tmp/bios_c_maxi.imd /tmp/bios_c_maxi.mfi >/dev/null 2>&1; \
		rm -f /tmp/bios_c_maxi.imd; \
		echo "Created fresh A: drive MFI: /tmp/bios_c_maxi.mfi"; \
	else \
		echo "Reusing existing A: drive MFI (use FORCE=1 to recreate)"; \
	fi
	@if [ ! -f /tmp/bios_c_data.mfi ]; then \
		cp $(IMG_DATA) /tmp/bios_c_data.imd; \
		rm -f /tmp/bios_c_data.mfi; \
		$(FLOPTOOL) flopconvert auto mfi /tmp/bios_c_data.imd /tmp/bios_c_data.mfi >/dev/null 2>&1; \
		rm -f /tmp/bios_c_data.imd; \
		echo "Created B: data disk: /tmp/bios_c_data.mfi"; \
	else \
		echo "Reusing existing B: data disk"; \
	fi
	$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_maxi.mfi \
		-flop2 /tmp/bios_c_data.mfi \
		-skip_gameinfo -window -resolution 1100x720 \
		-autoboot_script $(CURDIR)/mame_enable_siob_debug.lua

# mame-siob-debug — boot MAME with SIO-B bridged to an interactive stdio
# console (DIP S01 set → IOBYTE_CON_JOINED, console I/O mirrored on SIO-B).
# Python bridge listens on SIOB_DEBUG_PORT; MAME connects via -bitb2.
SIOB_DEBUG_PORT ?= 4023
mame-siob-debug: bios
	@if [ "$(FORCE)" = "1" ] || [ ! -f /tmp/bios_c_maxi.mfi ]; then \
		cp $(IMG_MAXI) /tmp/bios_c_maxi.imd; \
		$(PATCH) /tmp/bios_c_maxi.imd $(BIOS_CIM); \
		rm -f /tmp/bios_c_maxi.mfi; \
		$(FLOPTOOL) flopconvert auto mfi /tmp/bios_c_maxi.imd /tmp/bios_c_maxi.mfi >/dev/null 2>&1; \
		rm -f /tmp/bios_c_maxi.imd; \
	fi
	@echo "=== SIO-B debug console ==="
	@echo "  Connecting MAME SIO-B to stdio on port $(SIOB_DEBUG_PORT)"
	@echo "  Type to send; Ctrl-] then q to quit"
	@python3 -u siob_interactive.py $(SIOB_DEBUG_PORT) & echo $$! > /tmp/siob_interactive.pid; \
	sleep 0.3; \
	$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_maxi.mfi \
		-rs232b null_modem \
		-bitb2 "socket.127.0.0.1:$(SIOB_DEBUG_PORT)" \
		-skip_gameinfo -window -resolution 1100x720 \
		-autoboot_script $(CURDIR)/mame_enable_siob_debug.lua; \
	kill $$(cat /tmp/siob_interactive.pid) 2>/dev/null; \
	rm -f /tmp/siob_interactive.pid

# ================================================================
# Test targets
# ================================================================

# sio-echo-test — run 4096-byte bidirectional error-free echo tests on
# both SIO-A and SIO-B, using BIOS routines directly.  Each test:
#   - builds a fresh MFI from IMG_MAXI + patched BIOS + echo .COM
#   - starts a Python feeder that waits for a 0xA5 sync byte from the
#     program, then sends 4096 bytes (0x00..0xFF repeated 16x) at the
#     TCP/null_modem rate (throttled at 38400 baud by null_modem)
#   - CP/M echo program reads each byte via BIOS READER/CONIN, verifies,
#     echoes back via BIOS PUNCH/LIST; writes result block at 0x180
#   - PASS criterion: result block shows count=4096 mismatch=0 status=0xAA
ZMAC_ABS = $(abspath $(ZMAC))

tests/zout/bios_echo_big.cim: tests/bios_echo_big.asm
	@mkdir -p tests/zout
	cd /tmp && $(ZMAC_ABS) -c --oo cim $(CURDIR)/tests/bios_echo_big.asm
	@cp /tmp/zout/bios_echo_big.cim tests/zout/bios_echo_big.cim

tests/zout/bios_echo_siob.cim: tests/bios_echo_siob.asm
	@mkdir -p tests/zout
	cd /tmp && $(ZMAC_ABS) -c --oo cim $(CURDIR)/tests/bios_echo_siob.asm
	@cp /tmp/zout/bios_echo_siob.cim tests/zout/bios_echo_siob.cim

.PHONY: sio-a-echo-test sio-b-echo-test sio-echo-test
sio-a-echo-test: bios tests/zout/bios_echo_big.cim
	SIOA_FEED_BYTES="$$(python3 -c 'import sys; sys.stdout.write("".join(f"{i%256:02x}" for i in range(4096)))')" \
	    SIOA_FEED_SYNC_BYTE=A5 SIOA_FEED_INTERCHAR_MS=0 SIOA_FEED_LISTEN_SECS=20 \
	    bash tests/run_sioa_rx_test.sh sioa_echo ECHO.COM tests/zout/bios_echo_big.cim 1600
	@grep -q 'count=4096 mismatch=0 status=0xAA' /tmp/sioa_test/sioa_echo/sioa.csv \
	    && echo '=== SIO-A 4096-byte echo PASS ===' \
	    || (echo '=== SIO-A 4096-byte echo FAIL ==='; \
	        grep '# result' /tmp/sioa_test/sioa_echo/sioa.csv; exit 1)

sio-b-echo-test: bios tests/zout/bios_echo_siob.cim
	SIOA_FEED_BYTES="$$(python3 -c 'import sys; sys.stdout.write("".join(f"{i%256:02x}" for i in range(4096)))')" \
	    SIOA_FEED_SYNC_BYTE=A5 SIOA_FEED_INTERCHAR_MS=0 SIOA_FEED_LISTEN_SECS=20 \
	    PORT=4002 \
	    bash tests/run_siob_echo_test.sh siob_echo ECHOBB.COM tests/zout/bios_echo_siob.cim 1600
	@grep -q 'count=4096 mismatch=0 status=0xAA' /tmp/siob_test/siob_echo/trace.csv \
	    && echo '=== SIO-B 4096-byte echo PASS ===' \
	    || (echo '=== SIO-B 4096-byte echo FAIL ==='; \
	        grep '# result' /tmp/siob_test/siob_echo/trace.csv; exit 1)

sio-echo-test: sio-a-echo-test sio-b-echo-test
	@echo '=== Both SIO-A and SIO-B 4096-byte echo tests PASSED ==='

# CONOTEST.COM — display control code exercise (CP/M program, built with SDCC)
conotest: conout_test.c builddate.h
	export PATH="$(Z88DK)/bin:$$PATH" && \
	export ZCCCFG="$(ZCCCFG)" && \
	$(ZCC) +cpm -clib=sdcc_iy -SO3 --opt-code-size \
		-Cs"--std-sdcc23" -create-app -o conotest conout_test.c
	@echo "conotest.com: $$(wc -c < conotest.com | tr -d ' ') bytes"

conout-test: bios conotest
	cp $(IMG_MAXI) /tmp/bios_c_conout.imd
	$(PATCH) /tmp/bios_c_conout.imd $(BIOS_CIM)
	$(CPMCP) -f rc702-8dd /tmp/bios_c_conout.imd conotest.com 0:CONOTEST.COM
	$(eval KBBUF_ADDR := $(shell grep '_kbbuf ' $(COMPILER)/bios.map 2>/dev/null | sed 's/.*= \$$\([0-9A-F]*\).*/0x\1/' || echo 0))
	$(eval KBHEAD_ADDR := $(shell grep '_kbhead ' $(COMPILER)/bios.map 2>/dev/null | sed 's/.*= \$$\([0-9A-F]*\).*/0x\1/' || echo 0))
	sed 's/KBBUF_ADDR/$(KBBUF_ADDR)/g; s/KBHEAD_ADDR/$(KBHEAD_ADDR)/g' mame_conout_autotest.lua > /tmp/bios_c_conout_test.lua
	$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_conout.imd \
		-skip_gameinfo -window -resolution 1100x720 \
		-nothrottle \
		-autoboot_script /tmp/bios_c_conout_test.lua
	@echo "--- CONOUT test result ---"
	@cat /tmp/conout_result.txt
	@grep -q '^PASS' /tmp/conout_result.txt && echo "=== CONOUT TEST PASSED ===" || (echo "=== CONOUT TEST FAILED ==="; exit 1)

IMG ?= $(IMG_MAXI)
mame-test: bios
	cp $(IMG) /tmp/bios_c_test.imd
	$(PATCH) /tmp/bios_c_test.imd $(BIOS_CIM)
	python3 verify_checksums.py /tmp/bios_c_test.imd > /tmp/expected_checksums.txt
	$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_test.imd \
		-skip_gameinfo -window -resolution 1100x720 \
		-nothrottle \
		-autoboot_script mame_disk_test.lua
	@echo "--- MAME screen ---"
	@cat /tmp/screen.txt
	@echo "--- Expected ---"
	@cat /tmp/expected_checksums.txt

bgstar-test: bios bgstar_test.asm mame_bgstar_test.lua
	$(ZMAC) -z --dri bgstar_test.asm
	cp $(IMG_MAXI) /tmp/bios_c_bgtest.imd
	$(PATCH) /tmp/bios_c_bgtest.imd $(BIOS_CIM)
	$(CPMCP) -f rc702-8dd /tmp/bios_c_bgtest.imd zout/bgstar_test.cim 0:BGTEST.COM
	rm -f /tmp/bios_c_bgtest.mfi
	$(FLOPTOOL) flopconvert auto mfi /tmp/bios_c_bgtest.imd /tmp/bios_c_bgtest.mfi >/dev/null 2>&1
	rm -f /tmp/bios_c_bgtest.imd
	$(eval KBBUF_ADDR := $(shell grep '_kbbuf ' $(COMPILER)/bios.map 2>/dev/null | sed 's/.*= \$$\([0-9A-F]*\).*/0x\1/' || echo 0))
	$(eval KBHEAD_ADDR := $(shell grep '_kbhead ' $(COMPILER)/bios.map 2>/dev/null | sed 's/.*= \$$\([0-9A-F]*\).*/0x\1/' || echo 0))
	sed 's/KBBUF_ADDR/$(KBBUF_ADDR)/g; s/KBHEAD_ADDR/$(KBHEAD_ADDR)/g' mame_bgstar_test.lua > /tmp/bios_c_bgstar_test.lua
	$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_bgtest.mfi \
		-skip_gameinfo -window -resolution 1100x720 \
		-nothrottle \
		-autoboot_script /tmp/bios_c_bgstar_test.lua
	@echo "--- BGSTAR test results ---"
	@cat /tmp/bgstar_screens.txt

asm-test: bios
	./run_mame.sh -t

cycle-test: bios
	./run_mame.sh -c

cycle-baseline:
	./run_mame.sh -oc

profile: bios
	./run_mame.sh -p

profile-baseline:
	./run_mame.sh -op

# ================================================================
# MAME build (regnecentralen subtarget, debug)
# ================================================================
#
# Builds the MAME binary used by every mame-* target in this file.
# Uses the exact recipe from mame/src/mame/regnecentralen/README.md:
#
#   make SUBTARGET=regnecentralen DEBUG=1 \
#        SOURCES=src/mame/regnecentralen/rc702.cpp \
#        TOOLS=1 SYMLEVEL=3 SYMBOLS=1 OSD=sdl -j ...
#
# Notes:
#   - Produces $(MAME)/regnecentralend (the "d" suffix is DEBUG=1).
#   - OSD=sdl forces SDL2 rather than MAME's default SDL3.  This is
#     correct when only libsdl2-dev is installed (macOS via brew-less
#     path, and most current Ubuntu releases).  If you have libsdl3-dev
#     installed and want to test it, override OSD: `make mame-debug OSD=sdl3`.
#   - MAME_BUILD_JOBS defaults to nproc/2 to keep the peak RSS under
#     ~4 GB per link.  Override with `make mame-debug MAME_BUILD_JOBS=10`.

OSD ?= sdl

mame-debug:
	@if [ ! -d "$(MAME)" ]; then \
		echo "ERROR: MAME directory not found at $(MAME)"; \
		echo "Initialise the submodule: git submodule update --init --depth 1 mame"; \
		exit 1; \
	fi
	@echo "=== Building MAME regnecentralen (debug) with -j $(MAME_BUILD_JOBS) ==="
	$(MAKE) -C $(MAME) \
		SUBTARGET=regnecentralen \
		DEBUG=1 \
		SOURCES=src/mame/regnecentralen/rc702.cpp \
		TOOLS=1 SYMLEVEL=3 SYMBOLS=1 \
		OSD=$(OSD) \
		-j $(MAME_BUILD_JOBS)
	@echo "=== Binary at $(MAME)/regnecentralend ==="
	@ls -lh $(MAME)/regnecentralend

# ================================================================
# RC702 ROMs (roa375, roa296, roa327, rob357, rob358)
# ================================================================
#
# Downloads the boot PROM and character generator ROMs that rc702.cpp
# references, from github.com/ravn/rc700.  Normally run once per
# workspace checkout.  Individual ROM files are listed so `make` can
# fetch missing ones incrementally.

RC702_ROM_DIR = $(MAME)/roms/rc702
RC702_ROM_BASE = https://github.com/ravn/rc700/raw/refs/heads/master
RC702_ROMS = \
	$(RC702_ROM_DIR)/roa296.rom \
	$(RC702_ROM_DIR)/roa327.rom \
	$(RC702_ROM_DIR)/rob357.rom \
	$(RC702_ROM_DIR)/rob358.rom \
	$(RC702_ROM_DIR)/roa375.ic66

mame-roms: $(RC702_ROMS)
	@echo "=== RC702 ROMs present in $(RC702_ROM_DIR) ==="
	@ls -l $(RC702_ROM_DIR)

# Switch MAME into rcbios standalone boot mode -- installs the
# original hand-assembled autoload PROM into roa375.ic66.  This is
# the value-oracle PROM: pairs with a CP/M floppy image to boot
# rcbios end-to-end (no host-side server needed).  See
# llvm-z80/tasks/lessons-2026-05-04-structural-fix-failures.md.
#
# NOTE: the C reimplementation in autoload-in-c/ is currently broken
# -- it gets stuck in `_fdc_detect_sector_size_and_density` and
# never hands off to the BIOS.  Until that is fixed, the assembly
# original is the working autoload PROM for rcbios standalone mode.
# See ../autoload-in-c/tasks/known-bugs.md.
mame-roms-rcbios: $(RC702_ROM_DIR)/roa375.ic66
	cp ../roa375/roa375.rom $(RC702_ROM_DIR)/roa375.ic66
	@echo "Switched MAME into rcbios standalone mode (assembly autoload PROM)"
	@echo "  $(RC702_ROM_DIR)/roa375.ic66 (roa375 hand-assembly)"
	@echo "To switch into cpnos mode, run:"
	@echo "  cd ../cpnos-in-c && make mame-roms-cpnos"

$(RC702_ROM_DIR)/%.rom:
	@mkdir -p $(RC702_ROM_DIR)
	curl -fsSL -o $@ $(RC702_ROM_BASE)/$(notdir $@)

# roa375 has the .rom source file but is installed as .ic66 (MAME
# references the IC designator for PROM sockets).
$(RC702_ROM_DIR)/roa375.ic66:
	@mkdir -p $(RC702_ROM_DIR)
	curl -fsSL -o $@ $(RC702_ROM_BASE)/roa375.rom

# ================================================================
# SIO-B IOBYTE routing test
# ================================================================
#
# Verifies that STAT RDR:=UR1: routes RDR: through SIO-B (the new
# IOB_BAT arm in bios_reader_body).  Wires SIO-B to a TCP server and
# runs PIP CON:=RDR:[E] inside MAME, screen-scraping for a marker.
#
# Requires:
#   - MAME with -rs232b null_modem support (rc702 driver)
#   - python3 for the TCP server
#
# Pass: /tmp/siob_iobyte_result starts with "PASS"
# Fail: non-zero exit; inspect /tmp/siob_iobyte_result and MAME window

SIOB_PORT ?= 4323
SIOB_MARKER = SIOB-IOBYTE-TEST-OK

siob-iobyte-test: bios mame-roms
	@echo "=== SIO-B IOBYTE test ==="
	@if [ -z "$(MAME_BIN)" ]; then \
		echo "ERROR: no MAME binary found at $(MAME)/regnecentralend or $(MAME)/regnecentralen"; \
		echo "Run 'make mame-debug' first to build it."; \
		exit 1; \
	fi
	@echo "Using MAME_BIN=$(MAME_BIN)"
	cp $(IMG_MAXI) /tmp/bios_c_siob.imd
	$(PATCH) /tmp/bios_c_siob.imd $(BIOS_CIM)
	@# Payload the server will send over SIO-B.  The Lua script scrapes
	@# the CRT for $(SIOB_MARKER) after PIP echoes it.
	@printf '$(SIOB_MARKER)\r\n' > /tmp/siob_iobyte_payload.txt
	@rm -f /tmp/siob_iobyte_trigger /tmp/siob_iobyte_result
	@echo "Starting SIO-B server on port $(SIOB_PORT) ..."
	@python3 siob_iobyte_server.py /tmp/siob_iobyte_payload.txt $(SIOB_PORT) \
		> /tmp/siob_iobyte_server.log 2>&1 & echo $$! > /tmp/siob_iobyte_server.pid
	@sleep 0.5
	-$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_siob.imd \
		-bitb2 "socket.localhost:$(SIOB_PORT)" \
		-skip_gameinfo -window -resolution 1100x720 \
		-autoboot_script $(CURDIR)/mame_siob_iobyte_test.lua
	@# Kill the server if it's still running (Lua already wrote the result)
	@if [ -f /tmp/siob_iobyte_server.pid ]; then \
		kill $$(cat /tmp/siob_iobyte_server.pid) 2>/dev/null; \
		rm -f /tmp/siob_iobyte_server.pid; \
	fi
	@echo ""
	@echo "--- SIO-B server log ---"
	@cat /tmp/siob_iobyte_server.log 2>/dev/null || echo "(no log)"
	@echo ""
	@echo "--- Lua result ---"
	@cat /tmp/siob_iobyte_result 2>/dev/null || (echo "(no result file — Lua did not finish)"; exit 1)
	@head -1 /tmp/siob_iobyte_result | grep -q '^PASS' \
		&& echo "=== SIO-B IOBYTE test PASSED ===" \
		|| (echo "=== SIO-B IOBYTE test FAILED ==="; exit 1)

# ================================================================
# SIO-B direct BIOS test (no PIP/STAT — calls BIOS READER directly)
# ================================================================

siob-test: bios
	@echo "=== SIO-B direct BIOS test ==="
	../zmac/bin/zmac -z siob_test.asm
	cp $(IMG_MAXI) /tmp/bios_c_siob2.imd
	$(PATCH) /tmp/bios_c_siob2.imd $(BIOS_CIM)
	$(CPMCP) -f rc702-8dd /tmp/bios_c_siob2.imd zout/siob_test.cim 0:SIOBTEST.COM
	@printf '$(SIOB_MARKER)\r\n' > /tmp/siob_test_payload.txt
	@rm -f /tmp/siob_iobyte_trigger /tmp/siob_test_result
	@echo "Starting SIO-B server on port $(SIOB_PORT) ..."
	@python3 siob_iobyte_server.py /tmp/siob_test_payload.txt $(SIOB_PORT) \
		> /tmp/siob_test_server.log 2>&1 & echo $$! > /tmp/siob_test_server.pid
	@sleep 0.5
	-$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_siob2.imd \
		-bitb2 "socket.localhost:$(SIOB_PORT)" \
		-skip_gameinfo -window -resolution 1100x720 \
		-autoboot_script $(CURDIR)/mame_siob_test.lua
	@if [ -f /tmp/siob_test_server.pid ]; then \
		kill $$(cat /tmp/siob_test_server.pid) 2>/dev/null; \
		rm -f /tmp/siob_test_server.pid; \
	fi
	@echo ""
	@echo "--- SIO-B server log ---"
	@cat /tmp/siob_test_server.log 2>/dev/null || echo "(no log)"
	@echo ""
	@echo "--- Lua result ---"
	@cat /tmp/siob_test_result 2>/dev/null || (echo "(no result file)"; exit 1)
	@head -1 /tmp/siob_test_result | grep -q '^PASS' \
		&& echo "=== SIO-B direct test PASSED ===" \
		|| (echo "=== SIO-B direct test FAILED ==="; exit 1)

# ================================================================
# BIOS deploy via dual serial (SIO-B console + SIO-A data)
# Uploads Intel HEX, runs MLOAD+verify+SYSGEN, hard resets, verifies banner.
# Requires: cpm56_original.com, MLOAD.COM (assembled from cpm-utils/mload/)
# ================================================================

DEPLOY_CON_PORT ?= 4324
DEPLOY_DAT_PORT ?= 4325
MLOAD_COM = $(CURDIR)/../cpm-utils/mload/zout/mload.cim

clang-bios: builddate.h
	$(MAKE) -C clang bios.clang.cim MSIZE=$(MSIZE) KBLANG=$(KBLANG) KBDPORT=$(KBDPORT)

sdcc-bios: builddate.h
	$(MAKE) -C sdcc bios.cim MSIZE=$(MSIZE) KBLANG=$(KBLANG) KBDPORT=$(KBDPORT)

deploy-serial: clang-bios sdcc-bios
	@echo "=== BIOS deploy via serial (SDCC→clang) ==="
	@echo "  Disk boots with SDCC BIOS, clang BIOS deployed over serial"
	python3 mk_sysgen_hex.py clang/bios.clang.cim cpm56.hex
	@# BDOSCCP.COM: padding (0x0100-0x08FF) + CCP+BDOS (0x0900-0x44FF), no BIOS
	python3 -c "d=open('cpm56_original.com','rb').read(); open('/tmp/bdosccp.com','wb').write(d[:0x4400])"
	cp $(IMG_MAXI) /tmp/bios_deploy.imd
	$(PATCH) /tmp/bios_deploy.imd sdcc/bios.cim
	@# Put MLOAD.COM and BDOSCCP.COM on disk for overlay
	cpmcp -f rc702-8dd /tmp/bios_deploy.imd $(MLOAD_COM) 0:MLOAD.COM
	cpmcp -f rc702-8dd /tmp/bios_deploy.imd /tmp/bdosccp.com 0:BDOSCCP.COM
	@# Convert to MFI so MAME can write to disk (SYSGEN needs this)
	rm -f /tmp/bios_deploy.mfi
	$(FLOPTOOL) flopconvert auto mfi /tmp/bios_deploy.imd /tmp/bios_deploy.mfi >/dev/null 2>&1
	rm -f /tmp/bios_deploy.imd
	@rm -f /tmp/siob_deploy_trigger /tmp/siob_deploy_done /tmp/siob_deploy_result
	@echo "Starting deploy server..."
	@python3 -u siob_deploy_server.py cpm56.hex $(DEPLOY_CON_PORT) $(DEPLOY_DAT_PORT) \
		> /tmp/siob_deploy_server.log 2>&1 & echo $$! > /tmp/siob_deploy_server.pid
	@sleep 0.5
	-INITIAL_BANNER="C-bios/sdcc" EXPECTED_BANNER="C-bios/clang" \
		$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_deploy.mfi \
		-bitb1 "socket.localhost:$(DEPLOY_DAT_PORT)" \
		-bitb2 "socket.localhost:$(DEPLOY_CON_PORT)" \
		-skip_gameinfo -window -resolution 1100x720 -nothrottle \
		-autoboot_script $(CURDIR)/mame_siob_deploy_test.lua
	@if [ -f /tmp/siob_deploy_server.pid ]; then \
		kill $$(cat /tmp/siob_deploy_server.pid) 2>/dev/null; \
		rm -f /tmp/siob_deploy_server.pid; \
	fi
	@echo ""
	@echo "--- Deploy server log ---"
	@cat /tmp/siob_deploy_server.log 2>/dev/null || echo "(no log)"
	@echo ""
	@echo "--- Result ---"
	@cat /tmp/siob_deploy_result 2>/dev/null || (echo "(no result)"; exit 1)
	@head -1 /tmp/siob_deploy_result | grep -q '^PASS' \
		&& echo "=== DEPLOY TEST PASSED ===" \
		|| (echo "=== DEPLOY TEST FAILED ==="; exit 1)

# ================================================================
# SIO-B serial console integration test
# Sends DIR / ASM FILEX / TYPE FILEX.PRN via serial, verifies output
# appears on both CRT display and serial port.
# ================================================================

CONSOLE_PORT ?= 4324

siob-console-test: bios
	@echo "=== SIO-B serial console test ==="
	cp $(IMG_MAXI) /tmp/bios_c_console.imd
	$(PATCH) /tmp/bios_c_console.imd $(BIOS_CIM)
	@rm -f /tmp/siob_console_done /tmp/siob_console_result /tmp/siob_console_serial.txt /tmp/siob_console_crt.txt /tmp/siob_console_trigger
	@echo "Starting console server on port $(CONSOLE_PORT) ..."
	@python3 -u siob_console_server.py $(CONSOLE_PORT) \
		> /tmp/siob_console_server.log 2>&1 & echo $$! > /tmp/siob_console_server.pid
	@sleep 0.5
	-$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_console.imd \
		-bitb2 "socket.localhost:$(CONSOLE_PORT)" \
		-skip_gameinfo -window -resolution 1100x720 -nothrottle \
		-autoboot_script $(CURDIR)/mame_siob_console_test.lua
	@if [ -f /tmp/siob_console_server.pid ]; then \
		kill $$(cat /tmp/siob_console_server.pid) 2>/dev/null; \
		rm -f /tmp/siob_console_server.pid; \
	fi
	@echo ""
	@echo "--- Server log ---"
	@cat /tmp/siob_console_server.log 2>/dev/null || echo "(no log)"
	@echo ""
	@echo "--- Result ---"
	@cat /tmp/siob_console_result 2>/dev/null || (echo "(no result)"; exit 1)
	@head -1 /tmp/siob_console_result | grep -q '^PASS' \
		&& echo "=== SERIAL CONSOLE TEST PASSED ===" \
		|| (echo "=== SERIAL CONSOLE TEST FAILED ==="; exit 1)

# ================================================================
# SIO-B baud rate experiment
# Usage: make siob-baud BAUD_IDX=0  (38400 x16, baseline)
#        make siob-baud BAUD_IDX=1  (38400 x1, test x1 mode)
#        make siob-baud BAUD_IDX=2  (76800 x1)
#        make siob-baud BAUD_IDX=3  (115200 x1, 6.7% error)
# ================================================================

BAUD_IDX ?= 0
# Map BAUD_IDX to MAME RS232_BAUD value (decimal)
BAUD_MAME_0 = 11
BAUD_MAME_1 = 11
BAUD_MAME_2 = 23
BAUD_MAME_3 = 13
BAUD_MAME = $(BAUD_MAME_$(BAUD_IDX))

siob-baud: bios
	@echo "=== SIO-B baud rate test (idx=$(BAUD_IDX)) ==="
	@# Generate address include from current BIOS ELF
	@LLVMNM=$(firstword $(wildcard $(LLVM_Z80)/build-linux/bin/llvm-nm $(LLVM_Z80)/build-macos/bin/llvm-nm $(LLVM_Z80)/build/bin/llvm-nm)); \
	 WB=$$($$LLVMNM $(BIOS_ELF) | awk '/_wb$$/{print "0x"$$1}'); \
	 RXBUF=$$($$LLVMNM $(BIOS_ELF) | awk '/_rxbuf_b$$/{print "0x"$$1}'); \
	 printf '; Auto-generated from %s/bios.elf — do not edit\n' $(COMPILER) > siob_bios_addrs.inc; \
	 printf 'RXHEAD_B equ %s + 5\n' "$$WB" >> siob_bios_addrs.inc; \
	 printf 'RXTAIL_B equ %s + 6\n' "$$WB" >> siob_bios_addrs.inc; \
	 printf 'RXBUF_B  equ %s\n' "$$RXBUF" >> siob_bios_addrs.inc; \
	 echo "Generated siob_bios_addrs.inc: WB=$$WB RXBUF=$$RXBUF"
	$(ZMAC) -z siob_baud_test.asm
	cp $(IMG_MAXI) /tmp/bios_c_siob_baud.imd
	$(PATCH) /tmp/bios_c_siob_baud.imd $(BIOS_CIM)
	$(CPMCP) -f rc702-8dd /tmp/bios_c_siob_baud.imd zout/siob_baud_test.cim 0:SIOBBAUD.COM
	@printf '$(SIOB_MARKER)\r\n' > /tmp/siob_test_payload.txt
	@rm -f /tmp/siob_iobyte_trigger /tmp/siob_baud_result
	@python3 siob_iobyte_server.py /tmp/siob_test_payload.txt $(SIOB_PORT) \
		> /tmp/siob_baud_server.log 2>&1 & echo $$! > /tmp/siob_baud_server.pid
	@sleep 0.5
	-SIOB_BAUD_IDX=$(BAUD_IDX) SIOB_BAUD_MAME=$(BAUD_MAME) \
		$(MAME_BIN) rc702 -rompath $(MAME)/roms \
		-flop1 /tmp/bios_c_siob_baud.imd \
		-bitb2 "socket.localhost:$(SIOB_PORT)" \
		-skip_gameinfo -window -resolution 1100x720 \
		-autoboot_script $(CURDIR)/mame_siob_baud_test.lua
	@if [ -f /tmp/siob_baud_server.pid ]; then \
		kill $$(cat /tmp/siob_baud_server.pid) 2>/dev/null; \
		rm -f /tmp/siob_baud_server.pid; \
	fi
	@echo ""
	@echo "--- result ---"
	@cat /tmp/siob_baud_result 2>/dev/null || echo "(no result)"
	@head -1 /tmp/siob_baud_result | grep -q '^PASS' \
		&& echo "=== BAUD TEST PASSED ===" \
		|| (echo "=== BAUD TEST FAILED ==="; exit 1)

# ================================================================
# SIO-B SDLC experiment (physical RC702, MIC702 / PCB530)
# Sends one SDLC frame at 125 kbaud from SIO-B and captures it on
# FT2232D interface B via async bit-bang + software DPLL.
# Full flow:  make siob-sdlc
# ================================================================

sdlc-build:
	$(ZMAC) -z sioa_sdlc_tx.asm
	python3 cim_to_hex.py zout/sioa_sdlc_tx.cim /tmp/sioa_sdlc_tx.hex

sdlc: sdlc-build
	./sdlc_deploy.sh

# ================================================================
# Host tests (TODO)
# ================================================================

test:
	@echo "Host tests not yet implemented"

# ================================================================
# Clean
# ================================================================

clean:
	$(MAKE) -C clang clean
	$(MAKE) -C sdcc clean
	rm -f builddate.h builddate.inc
	rm -f /tmp/bios_c_mini.imd /tmp/bios_c_maxi.imd
