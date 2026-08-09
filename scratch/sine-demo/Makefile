# ---------------------------------------------------------------------------
# gfxtest / sine-demo  -  RC700 graphics demo build + MAME run recipe
# ---------------------------------------------------------------------------
# Captures the *verified working* pipeline discovered 2026-08-07:
#
#   1. Compile the C demo with z88dk +cpm for either compiler:
#        - COMPILER=llvmz80  -> ravn/llvm-z80 clang (routes graphics to the
#                               native _callee / cc133 variants)
#        - COMPILER=sccz80   -> stock sccz80 (reference "known-good" render)
#   2. Package for MAME by cpmcp-injecting the .com onto a COPY of a real
#      RC702 CP/M system disk (SW1711-I8.imd).  This is the ONLY disk format
#      the rc702 FDC in MAME reads reliably.
#        !! Do NOT use `appmake +cpmdisk -f rc700-8dd/-jbox --container imd`.
#           Those images (1188165 B / 324209 B) give "Bdos Err On B: Bad
#           Sector" in MAME.  The working disk is a cpmcp'd copy of SW1711.
#   3. Boot MAME (rc702) with the system disk in A: and the demo disk in B:,
#      autoboot `gfxtest_run.lua` which types `B:GFXTEST`, waits, snapshots.
#
# Quick start:
#   make run                      # llvmz80 (callee) build -> MAME snapshot
#   make run COMPILER=sccz80      # sccz80 reference build -> MAME snapshot
#   make compare                  # build+run both, drop both PNGs in ./snap
# ---------------------------------------------------------------------------

# ---- Tool / path configuration (override on the command line if needed) ----
Z80ROOT      ?= /Users/ravn/z80
LLVMZ80_CLANG?= $(Z80ROOT)/llvm-z80/build-macos/bin/clang
Z88DK_BIN    ?= $(Z80ROOT)/z88dk/bin
ZCCCFG       ?= $(Z80ROOT)/z88dk/lib/config
CPMTOOLS_BIN ?= $(HOME)/.local/bin
MAME_BIN     ?= $(Z80ROOT)/mame/regnecentralend
MAME_ROMS    ?= $(Z80ROOT)/mame/roms

# RC702 CP/M system disk used both as the A: boot disk and as the base image
# that the demo .com is injected into to make the B: disk.
BASE_DISK    ?= $(Z80ROOT)/rc700-gensmedet/autoload-in-c/test-disks/SW1711-I8.imd
DISKFMT      ?= rc702-8dd
LUA          ?= gfxtest_run.lua

# zcc needs to shell out to a binary literally named `llvmz80-clang` found on
# PATH (see z88dk src/zcc/zcc.c).  We stage a symlink in ./.tools for that.
TOOLS_DIR    := .tools
LLVMZ80_LINK := $(TOOLS_DIR)/llvmz80-clang

SRC          ?= gfxtest.c
COMPILER     ?= llvmz80          # llvmz80 | sccz80
CFLAGS       ?=                  # extra flags for zcc, e.g. -DREPS=5
GRAPHICS_H   ?= $(Z80ROOT)/z88dk/include/graphics.h
NAME         := gfxtest-$(COMPILER)
COM          := $(NAME).com
DISK         := $(NAME)-B.imd
SNAPDIR      := snap
SNAP         := $(SNAPDIR)/$(NAME).png

# RC700 graphics needs the classic clib + display export.  -subtype=rc700
# pulls in -D__RC700__, rc700.lib and -pragma-export:RC700_DISPLAY=0xF800.
ZCC_FLAGS    := +cpm -subtype=rc700

# MAME run mode.  Defaults are headless + unthrottled for fast timing runs.
# The `watch` target overrides these to show a real (brown) RC700 window at
# normal speed so the pixel wipe is actually visible.
VIDEO        ?= none
THROTTLE     ?= -nothrottle
SECONDS      ?= 120
WINDOW       ?=

export ZCCCFG

.PHONY: all run build disk mame compare clean help bench

all: build

help:
	@sed -n '1,32p' Makefile

# ---- 1. compile -----------------------------------------------------------
$(LLVMZ80_LINK):
	@mkdir -p $(TOOLS_DIR)
	@ln -sf $(LLVMZ80_CLANG) $(LLVMZ80_LINK)

build: $(COM)

ifeq ($(COMPILER),llvmz80)
$(COM): $(SRC) $(LLVMZ80_LINK) $(GRAPHICS_H)
	PATH="$(CURDIR)/$(TOOLS_DIR):$(Z88DK_BIN):$$PATH" \
	  zcc $(ZCC_FLAGS) -compiler=llvmz80 $(CFLAGS) -o $(NAME) $(SRC)
	@# z88dk +cpm output is already a CP/M binary at 0x100; normalise the name.
	@cp -f $(NAME) $(COM)
	@ls -l $(COM)
else
$(COM): $(SRC) $(GRAPHICS_H)
	PATH="$(Z88DK_BIN):$$PATH" zcc $(ZCC_FLAGS) $(CFLAGS) -o $(NAME) $(SRC)
	@cp -f $(NAME) $(COM)
	@ls -l $(COM)
endif

# ---- 2. package: inject .com onto a copy of the RC702 system disk ---------
disk: $(DISK)

$(DISK): $(COM)
	cp -f $(BASE_DISK) $(DISK)
	PATH="$(CPMTOOLS_BIN):$$PATH" cpmcp -f $(DISKFMT) $(DISK) $(COM) 0:GFXTEST.COM
	@PATH="$(CPMTOOLS_BIN):$$PATH" cpmls -f $(DISKFMT) $(DISK) | grep -i gfxtest
	@ls -l $(DISK)

# ---- 3. run in MAME, capture a snapshot ----------------------------------
run: mame
mame: $(DISK)
	@mkdir -p $(SNAPDIR)
	rm -rf $(SNAPDIR)/rc702
	$(MAME_BIN) rc702 -rompath $(MAME_ROMS) $(THROTTLE) $(WINDOW) -video $(VIDEO) -sound none \
	  -skip_gameinfo -flop1 $(BASE_DISK) -flop2 $(CURDIR)/$(DISK) \
	  -autoboot_script $(LUA) -snapshot_directory $(SNAPDIR) -seconds_to_run $(SECONDS)
	@cp -f $(SNAPDIR)/rc702/0000.png $(SNAP) 2>/dev/null || true
	@echo "snapshot -> $(SNAP)"

# ---- convenience: build+run both compilers for an A/B render comparison ---
compare:
	$(MAKE) run COMPILER=llvmz80
	$(MAKE) run COMPILER=sccz80
	@echo "compare snap/gfxtest-llvmz80.png  vs  snap/gfxtest-sccz80.png"

clean:
	rm -rf $(TOOLS_DIR) gfxtest-*.com gfxtest-*-B.imd gfxtest-llvmz80 gfxtest-sccz80 \
	       *_BSS.bin $(SNAPDIR)/rc702

# ---- benchmark: draw+erase every pixel REPS times, time it with clock() -----
# Usage:  make bench COMPILER=llvmz80 REPS=5
#         make bench COMPILER=sccz80  REPS=5
REPS ?= 3
bench:
	$(MAKE) mame SRC=gfxbench.c CFLAGS="-DREPS=$(REPS)" LUA=gfxbench_run.lua \
	  COMPILER=$(COMPILER) SNAP=$(SNAPDIR)/gfxbench-$(COMPILER).png

# ---- watch: run the benchmark in a real MAME window at normal speed --------
# Use a big REPS so the wipe runs long enough to watch.  Ctrl-C / close window
# to stop.  Video on, throttled to ~real time, long run cap.
#   make watch COMPILER=llvmz80 REPS=50
watch:
	$(MAKE) mame SRC=gfxbench.c CFLAGS="-DREPS=$(REPS)" LUA=gfxbench_run.lua \
	  COMPILER=$(COMPILER) SNAP=$(SNAPDIR)/gfxbench-$(COMPILER).png \
	  VIDEO=auto THROTTLE= SECONDS=600 WINDOW=-window
