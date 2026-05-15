# cpnos-shared/common.mk — shared Makefile fragments for cpnos variants.
#
# Used by:
#   ../cpnos-in-c/Makefile
#   ../cpnos-in-asm/Makefile   (planned)
#
# Variables the includer MUST set before `include`:
#   BUILDDIR   — output directory holding prom0.bin, prom1.bin,
#                cpnos.bin, and prom0_padded.ic66 (4 KB).
#   SHARED     — relative path to this directory (typically ../cpnos-shared).
#
# Variables this fragment defaults (override before include if needed):
#   MAME            — primary MAME tree path
#   MAME_PROM0      — destination path for prom0 install
#   MAME_PROM1      — destination path for prom1 install
#   MAME_ROMS_DIR   — alternate MAME tree's rc702 roms dir
#
# MAME_IRQ is a separate alternate-tree handle that recipes probe for
# (used by pio-irq targets that need cpnet_bridge instrumentation).  The
# includer sets it; if undefined or non-existent at install time the
# recipes degrade gracefully.

MAME           ?= /Users/ravn/git/mame
MAME_PROM0     ?= $(MAME)/roms/rc702/roa375.ic66
MAME_PROM1     ?= $(MAME)/roms/rc702/prom1.ic65
MAME_ROMS_DIR  ?= $(CURDIR)/../../mame/roms/rc702

# ---- MAME ROM install --------------------------------------------------
#
# Two halves: install (cpnos-mame-install) and verify (verify-mame-roms-current).
# Used as a pre-flight check before any direct MAME launch (`regnecentralend`
# outside Make).  HARD RULE feedback_check_banner_timestamp.md.
#
# Mirrors to MAME_IRQ tree if it exists -- pio-irq targets and
# cpnos-bios-jt-trace launch from there; an ad-hoc `regnecentralend`
# against MAME_IRQ would otherwise pick up whatever the previous
# polypascal-test left in $(MAME_IRQ)/roms/rc702 and silently boot a
# stale build.  Conditional `-d` check so the rule passes when MAME_IRQ
# doesn't exist on a given checkout.

$(MAME_PROM0): $(BUILDDIR)/prom0_padded.ic66
	cp $< $@
	@if [ -n "$(MAME_IRQ)" ] && [ -d $(MAME_IRQ)/roms/rc702 ]; then \
	    cp $@ $(MAME_IRQ)/roms/rc702/$(notdir $@); \
	    echo "installed cpnos prom0 -> $@ (+ MAME_IRQ)"; \
	else \
	    echo "installed cpnos prom0 -> $@"; \
	fi

$(MAME_PROM1): $(BUILDDIR)/prom1.bin
	cp $< $@
	@if [ -n "$(MAME_IRQ)" ] && [ -d $(MAME_IRQ)/roms/rc702 ]; then \
	    cp $@ $(MAME_IRQ)/roms/rc702/$(notdir $@); \
	    echo "installed cpnos prom1 -> $@ (+ MAME_IRQ)"; \
	else \
	    echo "installed cpnos prom1 -> $@"; \
	fi

.PHONY: cpnos-mame-install
cpnos-mame-install: $(MAME_PROM0) $(MAME_PROM1)

# Switch the alternate MAME tree (MAME_ROMS_DIR) into cpnos boot mode.
# RC702 has two PROM slots loaded from separate files:
#     PROM 0 ($0000..$07FF) <- mame/roms/rc702/roa375.ic66
#     PROM 1 ($2000..$27FF) <- mame/roms/rc702/prom1.ic65
#
# Both MUST be refreshed in lockstep — refreshing only one mismatches
# the patcher's checksum correction (which lives in payload_b ->
# prom1.bin) against today's body sum, triggering the cpnos PROM's
# BAD CHECKSUM infinite loop (visible as a black screen with
# "BAD CHECKSUM" at row 0 of the CRT).
#
# Mode swap: to go back to rcbios standalone (autoload-PROM) boot mode,
# run `make prom` in ../autoload-in-c/, which writes autoload-in-c's
# prom.bin -> roa375.ic66 (overwriting cpnos's PROM 0).

.PHONY: mame-roms-cpnos
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

# Pre-flight check: verify the installed MAME PROMs match the latest
# build.  Fails with a clear error message + remediation if stale.
.PHONY: verify-mame-roms-current
verify-mame-roms-current:
	@if [ ! -f $(MAME_PROM0) ] || [ $(BUILDDIR)/prom0_padded.ic66 -nt $(MAME_PROM0) ]; then \
	    echo "STALE ROM: $(MAME_PROM0) older than $(BUILDDIR)/prom0_padded.ic66"; \
	    echo "  remediation: make cpnos-mame-install"; \
	    exit 1; \
	fi
	@if [ ! -f $(MAME_PROM1) ] || [ $(BUILDDIR)/prom1.bin -nt $(MAME_PROM1) ]; then \
	    echo "STALE ROM: $(MAME_PROM1) older than $(BUILDDIR)/prom1.bin"; \
	    echo "  remediation: make cpnos-mame-install"; \
	    exit 1; \
	fi
	@echo "MAME ROMs current ($(MAME_PROM0), $(MAME_PROM1))"

# ---- Burn helper -------------------------------------------------------

.PHONY: cpnos-burn
cpnos-burn: $(BUILDDIR)/cpnos.bin
	@echo "PROM0 (0x0000-0x07FF): $(BUILDDIR)/prom0.bin ($$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' ') B)"
	@echo "PROM1 (0x2000-0x27FF): $(BUILDDIR)/prom1.bin ($$(wc -c < $(BUILDDIR)/prom1.bin | tr -d ' ') B)"
