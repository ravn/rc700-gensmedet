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
#
# Per user policy: during development it is OK to exceed the 2048 B
# PROM1 socket size to "make it work" first -- a shrink pass follows
# once the feature is correct.  Over-size builds WARN and pad up to
# the next 2 KB boundary (max 4 KB, the cpnos.bin file-format limit)
# rather than failing.  Burning to a real EPROM still requires <= 2048.
define PAD_TO_2048
SZ=$$(wc -c < $(1) | tr -d ' '); \
if [ "$$SZ" -lt 2048 ]; then \
    python3 -c "import sys; d=open('$(1)','rb').read(); open('$(1)','wb').write(d + b'\xFF' * (2048 - len(d)))"; \
elif [ "$$SZ" -le 4096 ]; then \
    echo "WARNING: $(1) is $$SZ B, exceeds 2048 B PROM1 socket by $$((SZ - 2048)) B"; \
    echo "  -- OK for dev per user policy; must shrink before burning EPROM."; \
    python3 -c "import sys; d=open('$(1)','rb').read(); open('$(1)','wb').write(d + b'\xFF' * (4096 - len(d)))"; \
else \
    echo "ERROR: $(1) is $$SZ B, exceeds 4096 B file-format limit"; exit 1; \
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
# Stitched length depends on the PROM1 pad target -- 2 KB when it fits
# the socket, 4 KB when it's in over-size dev mode.
$(CPNOS_BIN): $(AUTOLOAD_PROM0) $(PROM1_BIN)
	@mkdir -p $(BUILDDIR)
	@dd if=$(AUTOLOAD_PROM0) bs=2048 count=1 of=$(BUILDDIR)/prom0.bin 2>/dev/null
	cat $(BUILDDIR)/prom0.bin $(PROM1_BIN) > $(CPNOS_BIN)
	@SZ=$$(wc -c < $(CPNOS_BIN) | tr -d ' '); \
	 P1=$$(wc -c < $(PROM1_BIN) | tr -d ' '); \
	 EXPECT=$$((2048 + P1)); \
	 test "$$SZ" = "$$EXPECT" || { echo "ERROR: cpnos.bin is $$SZ B, expected $$EXPECT (2048 + prom1=$$P1)"; exit 1; }

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
SIOA_RAW            = /tmp/cpnos_asm_sioa.raw
SIOB_RAW            = /tmp/cpnos_asm_siob.raw
BOOT_DEADLINE_S     = 8

.PHONY: cpnos-banner-test cpnos-siob-test cpnos-sioa-test
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

# SIO-B = operator console.  Verifies the banner reaches the
# console wire after autoload hands over.  CP/NET frame inspection
# moved to cpnos-sioa-test below.
cpnos-siob-test: cpnos-mame-install
	@rm -f $(SIOB_RAW)
	@echo "=== launching MAME for SIO-B (console) check (~$(BOOT_DEADLINE_S) s) ==="
	$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(BOOT_DEADLINE_S) \
	    -rs232b null_modem -bitb2 $(SIOB_RAW) \
	    >/tmp/cpnos_asm_mame.log 2>&1 \
	    || { echo "MAME exited non-zero; log tail:"; tail -10 /tmp/cpnos_asm_mame.log; exit 1; }
	@echo "--- $(SIOB_RAW) head (printable bytes) ---"
	@LC_ALL=C tr -cd '\11\12\15\40-\176' < $(SIOB_RAW) | head -c 200; echo
	@LC_ALL=C grep -aq "$(EXPECTED_BANNER)" $(SIOB_RAW) \
	    && echo "PASS: banner present on SIO-B" \
	    || { echo "FAIL: banner not on SIO-B"; xxd $(SIOB_RAW) | head -4; exit 1; }

# SIO-A = CP/NET transport stream.  Verifies the full 12-byte CP/NET
# INIT frame the slave emits at boot, with both checksums valid.
# Expected raw bytes (no banner -- banner is SIO-B only):
#   SOH FMT DID SID FNC SIZ HCS  STX DAT[0] ETX CKS EOT
#   01  00  00  FF  FF  00  01   02  00     03  FB  04
# HCS makes bytes [0..6] sum to 0 mod 256.
# CKS makes bytes [7..10] (STX..CKS) sum to 0 mod 256.
# EOT (byte 11) is a raw delimiter, not in any checksum.
cpnos-sioa-test: cpnos-mame-install
	@rm -f $(SIOA_RAW)
	@echo "=== launching MAME for SIO-A (CP/NET) check (~$(BOOT_DEADLINE_S) s) ==="
	$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(BOOT_DEADLINE_S) \
	    -rs232a null_modem -bitb1 $(SIOA_RAW) \
	    >/tmp/cpnos_asm_mame.log 2>&1 \
	    || { echo "MAME exited non-zero; log tail:"; tail -10 /tmp/cpnos_asm_mame.log; exit 1; }
	@echo "--- $(SIOA_RAW) hex ---"
	@xxd $(SIOA_RAW) | head -3
	@python3 -c "import sys; \
	    d = open('$(SIOA_RAW)', 'rb').read(); \
	    i = d.find(b'\x01\x00\x00\xff\xff\x00'); \
	    ok = (i >= 0 \
	          and len(d) >= i + 12 \
	          and sum(d[i:i+7]) % 256 == 0 \
	          and d[i+7] == 0x02 \
	          and d[i+9] == 0x03 \
	          and sum(d[i+7:i+11]) % 256 == 0 \
	          and d[i+11] == 0x04); \
	    sys.exit(0 if ok else (print(f'FAIL frame at {i}: {d[max(0,i):i+12].hex() if i>=0 else \"-\"}') or 1))" \
	    && echo "PASS: full CP/NET INIT frame on SIO-A with valid HCS + CKS" \
	    || { echo "FAIL: CP/NET frame broken"; xxd $(SIOA_RAW); exit 1; }

# Phase 2b/integration: socket-backed SIO-B echo round-trip.
# Starts a Python TCP server in the background, then launches MAME
# with SIO-B routed to it (socket-mode null_modem).  The slave's
# banner + CP/NET frame land on the server; the server then probes
# the echo loop with "PING\r\n" and verifies the same bytes come back.
ECHO_PORT       = 4445
ECHO_RESULT     = /tmp/cpnos_asm_echo_result.txt
ECHO_SERVER_LOG = /tmp/cpnos_asm_echo_server.log

.PHONY: cpnos-echo-test
cpnos-echo-test: cpnos-mame-install
	@rm -f $(ECHO_RESULT) $(ECHO_SERVER_LOG)
	@echo "=== starting echo server on :$(ECHO_PORT) (background) ==="
	@python3 tasks/sio_b_echo_server.py $(ECHO_PORT) $(ECHO_RESULT) \
	    >$(ECHO_SERVER_LOG) 2>&1 & echo $$! > /tmp/cpnos_asm_echo_server.pid
	@# Wait briefly for the listener to bind before MAME tries to connect.
	@for i in 1 2 3 4 5; do \
	    if grep -q "listening on" $(ECHO_SERVER_LOG) 2>/dev/null; then break; fi; \
	    sleep 0.2; \
	 done
	@echo "=== launching MAME (~$(BOOT_DEADLINE_S) s) ==="
	-$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(BOOT_DEADLINE_S) \
	    -rs232b null_modem -bitb2 socket.127.0.0.1:$(ECHO_PORT) \
	    -autoboot_script $(SHARED)/mame/asm_banner_check.lua \
	    -snapname cpnos_asm_echo \
	    >/tmp/cpnos_asm_mame.log 2>&1
	@# Give the server up to 5 s to finish post-MAME-exit.
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if [ -f $(ECHO_RESULT) ]; then break; fi; sleep 0.5; \
	 done
	@# Reap the server if it's still running.
	@if [ -f /tmp/cpnos_asm_echo_server.pid ]; then \
	    kill $$(cat /tmp/cpnos_asm_echo_server.pid) 2>/dev/null; \
	    rm -f /tmp/cpnos_asm_echo_server.pid; \
	 fi
	@echo "--- server log tail ---"
	@tail -15 $(ECHO_SERVER_LOG) 2>/dev/null
	@echo "--- result ---"
	@cat $(ECHO_RESULT) 2>/dev/null || { echo "no result file (server may have crashed)"; exit 1; }
	@grep -q '^PASS' $(ECHO_RESULT)

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
