# Makefile for cpnos-in-asm — pure-Z80-asm CP/NOS slave (PROM1-fit target).
#
# Architecture (session 73e):
#   PROM0 socket = ../autoload-in-c/clang/prom0.ic66  (production autoload)
#   PROM1 socket = $(BUILDDIR)/prom1.bin              (this dir; asm slave)
#
# autoload-in-c programs all hardware (DMA, 8275 CRT, CTC, PIO), tries
# floppy boot, fails, then jumps via the PROM1 signature contract
# (byte 0..1 = jump target; byte 2..7 = " RC702").  Our prom1.asm
# satisfies that contract and runs at PROM1.
#
# Toolchain: zmac for the asm; autoload-in-c's own Makefile for PROM0.

SHARED    ?= ../cpnos-shared
SRC        = src
BUILDDIR   = build
ZMAC       = $(CURDIR)/../zmac/bin/zmac
AUTOLOAD   = $(CURDIR)/../autoload-in-c
AUTOLOAD_PROM0 = $(AUTOLOAD)/clang/prom0.ic66

# Pin MAME to the in-tree z80/mame checkout (same one cpnos-in-c's
# polypascal-test uses via MAME_IRQ).  common.mk's default points at
# /Users/ravn/git/mame which is a different tree on this machine.
MAME ?= $(CURDIR)/../../mame

PROM1_BIN     = $(BUILDDIR)/prom1.bin
CPNOS_BIN     = $(BUILDDIR)/cpnos.bin
PROM0_PADDED  = $(BUILDDIR)/prom0_padded.ic66

.PHONY: all cpnos cpnos-size cpnos-clean help status
all: cpnos

cpnos: $(CPNOS_BIN) cpnos-mame-install cpnos-size

# Pad zmac's raw .cim to 2048 bytes with 0xFF.
define PAD_TO_2048
SZ=$$(wc -c < $(1) | tr -d ' '); \
if [ "$$SZ" -lt 2048 ]; then \
    python3 -c "import sys; d=open('$(1)','rb').read(); open('$(1)','wb').write(d + b'\xFF' * (2048 - len(d)))"; \
elif [ "$$SZ" -gt 2048 ]; then \
    echo "ERROR: $(1) is $$SZ B, expected <= 2048"; exit 1; \
fi
endef

# Build autoload-in-c's PROM0 if missing.  Delegated to its own
# Makefile so its build flags / toolchain stay authoritative.  The
# || true is because that Makefile's `prom` target exits non-zero on
# the MAME-install step when running outside the autoload dir context;
# the .ic66 file is produced regardless.
$(AUTOLOAD_PROM0):
	@echo "=== building autoload-in-c PROM0 ==="
	@cd $(AUTOLOAD) && $(MAKE) clang || true
	@test -f $(AUTOLOAD_PROM0) || { echo "ERROR: $(AUTOLOAD_PROM0) not produced"; exit 1; }

$(PROM1_BIN): $(SRC)/prom1.asm
	@mkdir -p $(BUILDDIR)
	$(ZMAC) -z -o $(BUILDDIR)/prom1.cim --oo cim $(SRC)/prom1.asm
	@cp $(BUILDDIR)/prom1.cim $(PROM1_BIN)
	@$(call PAD_TO_2048,$(PROM1_BIN))
	@echo "prom1.bin: $$(wc -c < $(PROM1_BIN) | tr -d ' ') B"

# cpnos.bin = autoload PROM0 (first 2 KB of its 4 KB .ic66) + our PROM1.
$(CPNOS_BIN): $(AUTOLOAD_PROM0) $(PROM1_BIN)
	@mkdir -p $(BUILDDIR)
	@dd if=$(AUTOLOAD_PROM0) bs=2048 count=1 of=$(BUILDDIR)/prom0.bin 2>/dev/null
	cat $(BUILDDIR)/prom0.bin $(PROM1_BIN) > $(CPNOS_BIN)
	@SZ=$$(wc -c < $(CPNOS_BIN) | tr -d ' '); \
	 test "$$SZ" = "4096" || { echo "ERROR: cpnos.bin is $$SZ B, expected 4096"; exit 1; }

# common.mk's $(MAME_PROM0) rule depends on prom0_padded.ic66 (4 KB
# image for the MAME slot).  Use autoload's pre-padded .ic66 directly.
$(PROM0_PADDED): $(AUTOLOAD_PROM0)
	@mkdir -p $(BUILDDIR)
	cp $(AUTOLOAD_PROM0) $(PROM0_PADDED)

include $(SHARED)/common.mk

cpnos-size: $(CPNOS_BIN)
	@P0=$$(wc -c < $(BUILDDIR)/prom0.bin | tr -d ' '); \
	 P1=$$(wc -c < $(PROM1_BIN) | tr -d ' '); \
	 TOTAL=$$(wc -c < $(CPNOS_BIN) | tr -d ' '); \
	 echo "PROM0 (autoload): $$P0 / 2048 bytes"; \
	 echo "PROM1 (asm slave): $$P1 / 2048 bytes"; \
	 echo "TOTAL:            $$TOTAL / 4096 bytes"
	@echo "--- actual code bytes in PROM1 (non-0xFF) ---"
	@od -An -tx1 $(PROM1_BIN) | tr -s ' ' '\n' | grep -v '^$$' | grep -v '^ff$$' | wc -l | awk '{ printf "%d non-padding bytes\n", $$1 }'

# ---- Phase 2a value oracles: CRT byte stamp + SIO-B TX -----------
#
# Both tests boot via autoload-in-c -> floppy fail -> prom1_if_present
# sig match -> jump_to(slave_entry).  Boot deadline 6 s (autoload's
# floppy-fail path is slower than my old PROM0 stub).

EXPECTED_BANNER     = RC702 CP/NOS asm phase
SIOB_RAW            = /tmp/cpnos_asm_siob.raw
BOOT_DEADLINE_S     = 8

.PHONY: cpnos-banner-test cpnos-siob-test
cpnos-banner-test: cpnos-mame-install
	@rm -f /tmp/cpnos_asm_banner.txt
	@echo "=== launching MAME for CRT-banner check (~$(BOOT_DEADLINE_S) s) ==="
	$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(BOOT_DEADLINE_S) \
	    -autoboot_script $(SHARED)/mame/asm_banner_check.lua \
	    -snapname cpnos_asm_phase2a \
	    >/tmp/cpnos_asm_mame.log 2>&1 \
	    || { echo "MAME exited non-zero; log tail:"; tail -10 /tmp/cpnos_asm_mame.log; exit 1; }
	@echo "--- display memory rows 0..2 ---"
	@cat /tmp/cpnos_asm_banner.txt 2>/dev/null || { echo "no dump produced"; exit 1; }
	@grep -q "$(EXPECTED_BANNER)" /tmp/cpnos_asm_banner.txt \
	    && echo "PASS: banner present in display memory" \
	    || { echo "FAIL: expected banner not found"; exit 1; }

cpnos-siob-test: cpnos-mame-install
	@rm -f $(SIOB_RAW)
	@echo "=== launching MAME for SIO-B TX check (~$(BOOT_DEADLINE_S) s) ==="
	$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(BOOT_DEADLINE_S) \
	    -rs232b null_modem -bitb2 $(SIOB_RAW) \
	    >/tmp/cpnos_asm_mame.log 2>&1 \
	    || { echo "MAME exited non-zero; log tail:"; tail -10 /tmp/cpnos_asm_mame.log; exit 1; }
	@echo "--- $(SIOB_RAW) head (printable bytes) ---"
	@tr -cd '\11\12\15\40-\176' < $(SIOB_RAW) | head -c 200; echo
	@grep -aq "$(EXPECTED_BANNER)" $(SIOB_RAW) \
	    && echo "PASS: banner present on SIO-B" \
	    || { echo "FAIL: banner not on SIO-B"; xxd $(SIOB_RAW) | head -4; exit 1; }

cpnos-clean:
	rm -rf $(BUILDDIR)

status:
	@echo "cpnos-in-asm phase 2a: SIO-B TX + CRT banner."
	@echo "PROM0 = autoload-in-c (its build), PROM1 = our asm slave."
	@echo
	@echo "Targets:"
	@echo "  make                  - build PROM1, install both PROMs to MAME"
	@echo "  make cpnos-banner-test - boot in MAME, verify banner in display RAM"
	@echo "  make cpnos-siob-test   - boot in MAME, verify banner on SIO-B"
	@echo "  make cpnos-size       - PROM size report"
	@echo "  make cpnos-burn       - byte counts for EPROM burner"
	@echo "  make cpnos-clean      - remove $(BUILDDIR)/"

help: status
