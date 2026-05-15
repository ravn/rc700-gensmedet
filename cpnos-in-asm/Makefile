# Makefile for cpnos-in-asm — pure-Z80-asm CP/NOS slave (PROM1-fit target).
#
# Phase 1: stub slave that boots in MAME with a banner.  No protocol
# logic.  PROM0 does minimal DMA+CRT init then jumps to PROM1; PROM1
# stamps "RC702 CP/NOS asm phase 1 alive" into display memory and halts.
#
# Toolchain: zmac (in ../../zmac/bin/zmac, built from source).
# Shared assets (MAME-install, verify, burn): ../cpnos-shared/common.mk.

SHARED   ?= ../cpnos-shared
SRC       = src
BUILDDIR  = build
ZMAC      = $(CURDIR)/../zmac/bin/zmac

# Pin MAME to the in-tree z80/mame checkout (same one cpnos-in-c's
# polypascal-test uses via MAME_IRQ).  common.mk's default points at
# /Users/ravn/git/mame which is a different tree on this machine, so
# without this override MAME would launch with stale PROMs from the
# wrong rom dir.
MAME ?= $(CURDIR)/../../mame

# zmac produces $(BUILDDIR)/prom0.cim and $(BUILDDIR)/prom1.cim under
# its --od dir.  We copy them to the .bin / .ic65 names common.mk
# expects.  cpnos.bin is the concatenated 4 KB image (PROM0 + PROM1).
PROM0_BIN = $(BUILDDIR)/prom0.bin
PROM1_BIN = $(BUILDDIR)/prom1.bin
CPNOS_BIN = $(BUILDDIR)/cpnos.bin
PROM0_PADDED = $(BUILDDIR)/prom0_padded.ic66   # 4 KB padded image used by MAME

.PHONY: all cpnos cpnos-size cpnos-clean help status
all: cpnos

cpnos: $(CPNOS_BIN) cpnos-mame-install cpnos-size

# Assemble prom0.asm -> prom0.bin.  zmac writes prom0.cim in --od dir;
# rename + verify size.
# Pad a zmac .cim to exactly 2048 bytes with 0xFF.  zmac's .cim output
# is the raw assembled bytes from `org` onward (no leading zeros for
# higher-org files), so both prom0 (org 0x0000) and prom1 (org 0x2000)
# .cims start at the first instruction byte and just need trailing
# 0xFF padding to fill the EPROM image.
define PAD_TO_2048
SZ=$$(wc -c < $(1) | tr -d ' '); \
if [ "$$SZ" -lt 2048 ]; then \
    python3 -c "import sys; d=open('$(1)','rb').read(); open('$(1)','wb').write(d + b'\xFF' * (2048 - len(d)))"; \
elif [ "$$SZ" -gt 2048 ]; then \
    echo "ERROR: $(1) is $$SZ B, expected <= 2048"; exit 1; \
fi
endef

$(PROM0_BIN): $(SRC)/prom0.asm
	@mkdir -p $(BUILDDIR)
	$(ZMAC) -z -o $(BUILDDIR)/prom0.cim --oo cim $(SRC)/prom0.asm
	@cp $(BUILDDIR)/prom0.cim $(PROM0_BIN)
	@$(call PAD_TO_2048,$(PROM0_BIN))
	@echo "prom0.bin: $$(wc -c < $(PROM0_BIN) | tr -d ' ') B"

$(PROM1_BIN): $(SRC)/prom1.asm
	@mkdir -p $(BUILDDIR)
	$(ZMAC) -z -o $(BUILDDIR)/prom1.cim --oo cim $(SRC)/prom1.asm
	@cp $(BUILDDIR)/prom1.cim $(PROM1_BIN)
	@$(call PAD_TO_2048,$(PROM1_BIN))
	@echo "prom1.bin: $$(wc -c < $(PROM1_BIN) | tr -d ' ') B"

# 4 KB concatenated image (PROM0 then PROM1).
$(CPNOS_BIN): $(PROM0_BIN) $(PROM1_BIN)
	cat $(PROM0_BIN) $(PROM1_BIN) > $(CPNOS_BIN)
	@SZ=$$(wc -c < $(CPNOS_BIN) | tr -d ' '); \
	 test "$$SZ" = "4096" || { echo "ERROR: cpnos.bin is $$SZ B, expected 4096"; exit 1; }

# MAME slot 0 expects a 4 KB image (the 2 KB PROM0 + 2 KB padding/PROM1).
# common.mk's $(MAME_PROM0) rule depends on $(BUILDDIR)/prom0_padded.ic66.
# For cpnos-in-asm the concatenated image is exactly that 4 KB blob.
$(PROM0_PADDED): $(CPNOS_BIN)
	cp $(CPNOS_BIN) $(PROM0_PADDED)

# Pull in MAME-install / verify / burn recipes from cpnos-shared.  Must
# come AFTER BUILDDIR + PROM0_PADDED targets are visible.
include $(SHARED)/common.mk

# Size report — much simpler than cpnos-in-c's: no ELF, no symbol table,
# just byte counts of the two PROM halves.
cpnos-size: $(CPNOS_BIN)
	@P0=$$(wc -c < $(PROM0_BIN) | tr -d ' '); \
	 P1=$$(wc -c < $(PROM1_BIN) | tr -d ' '); \
	 TOTAL=$$(wc -c < $(CPNOS_BIN) | tr -d ' '); \
	 echo "PROM0: $$P0 / 2048 bytes"; \
	 echo "PROM1: $$P1 / 2048 bytes"; \
	 echo "TOTAL: $$TOTAL / 4096 bytes"
	@echo "--- actual code bytes in PROM1 (non-0xFF) ---"
	@od -An -tx1 $(PROM1_BIN) | tr -s ' ' '\n' | grep -v '^$$' | grep -v '^ff$$' | wc -l | awk '{ printf "%d non-padding bytes\n", $$1 }'

# ---- Phase 1 value oracle: banner reaches display memory ---------
#
# Launch MAME headless with the asm_banner_check.lua harness; it
# dumps the first three rows of display memory and exits.  We grep
# the dump for the banner string.  PASS = banner present.

EXPECTED_BANNER = RC702 CP/NOS asm phase 1 alive

.PHONY: cpnos-banner-test
cpnos-banner-test: cpnos-mame-install
	@rm -f /tmp/cpnos_asm_banner.txt
	@echo "=== launching MAME for phase 1 banner check (~5 s) ==="
	$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 8 \
	    -autoboot_script $(SHARED)/mame/asm_banner_check.lua \
	    -snapname cpnos_asm_phase1 \
	    >/tmp/cpnos_asm_mame.log 2>&1 \
	    || { echo "MAME exited non-zero; log tail:"; tail -10 /tmp/cpnos_asm_mame.log; exit 1; }
	@echo "--- display memory rows 0..2 ---"
	@cat /tmp/cpnos_asm_banner.txt 2>/dev/null || { echo "no dump produced"; exit 1; }
	@grep -q "$(EXPECTED_BANNER)" /tmp/cpnos_asm_banner.txt \
	    && echo "PASS: banner present in display memory" \
	    || { echo "FAIL: expected banner not found"; exit 1; }

cpnos-clean:
	rm -rf $(BUILDDIR)

status:
	@echo "cpnos-in-asm phase 1: stub slave with banner."
	@echo
	@echo "Targets:"
	@echo "  make            - build prom0.bin + prom1.bin + cpnos.bin, install to MAME"
	@echo "  make cpnos-size - print PROM sizes"
	@echo "  make cpnos-burn - print byte counts for EPROM burner"
	@echo "  make cpnos-clean - remove $(BUILDDIR)/"

help: status
