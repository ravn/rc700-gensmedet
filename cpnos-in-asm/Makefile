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

# Regenerate build/buildinfo.inc with local-time date + short git
# hash at every make invocation.  $(shell ...) at parse time -- the
# .inc's mtime only changes when content differs, so dependent .o /
# .cim rebuild precisely when the build-info string differs from
# what's already on disk.  See cpnos-shared/scripts/regen_buildinfo_asm.sh.
ifeq ($(filter clean cpnos-clean,$(MAKECMDGOALS)),)
_DUMMY_BUILDINFO := $(shell mkdir -p build && \
    $(SHARED)/scripts/regen_buildinfo_asm.sh build/buildinfo.inc)
endif

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

$(PROM1_BIN): $(SRC)/prom1.asm $(BUILDDIR)/buildinfo.inc
	@mkdir -p $(BUILDDIR)
	$(ZMAC) -z -I $(BUILDDIR) -o $(BUILDDIR)/prom1.cim --oo cim $(SRC)/prom1.asm
	@cp $(BUILDDIR)/prom1.cim $(PROM1_BIN)
	@$(call PAD_TO_2048,$(PROM1_BIN))
	@echo "prom1.bin: $$(wc -c < $(PROM1_BIN) | tr -d ' ') B"

# buildinfo.inc is regenerated at parse time by $(shell ...) above;
# this declares it as an explicit prereq so make's dep graph still
# knows about it.  The recipe is empty -- the shell invocation
# already did the work.
$(BUILDDIR)/buildinfo.inc: ;
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

EXPECTED_BANNER     = RC702 CP/NOS asm
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

# SIO-A no-master check.  Since phase 3d-β the slave waits for ACK
# before emitting the rest of a frame; since phase 3f the send is
# wrapped in MAXRETRY = 10 retries (per CP/NET 1.2 spec) so with no
# master on the wire the slave emits exactly 10 ENQ bytes then gives
# up.  File-backed null_modem only captures TX -- no RX delivered.
# A real master + handshake is exercised by cpnos-cpnet-test +
# cpnos-mpm-test.
cpnos-sioa-test: cpnos-mame-install
	@rm -f $(SIOA_RAW)
	@echo "=== launching MAME for SIO-A no-master check (~$(BOOT_DEADLINE_S) s) ==="
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
	    ok = (d == b'\x05' * 3); \
	    sys.exit(0 if ok else (print(f'FAIL: expected 3 ENQs (0x05*3), got {d.hex()}') or 1))" \
	    && echo "PASS: slave sent 3 ENQs (MAXRETRY=3, no master to ACK)" \
	    || { echo "FAIL"; exit 1; }

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

# Bidirectional CP/NET 1.2 frame exchange against a Python fake master.
#
# Phase A (slave -> master, exercises phase 3d-β send handshake):
#   slave sends ENQ              master replies ACK
#   slave sends header + HCS     master replies ACK
#   slave sends data + CKS + EOT master replies ACK
#
# Phase B (master -> slave, exercises phase 3d-γ receive state machine):
#   master sends ENQ             slave replies ACK
#   master sends header + HCS    slave validates and replies ACK
#   master sends data + CKS + EOT slave validates and replies ACK
#
# PASS = all 6 ACKs exchanged.
#
# To talk to the real master (z80pack mpm-net2): our slave would
# need to send a LOGIN frame (FNC=64, password "PASSWORD") instead
# of the current INIT (FNC=0xFF), since mpm-net2 doesn't recognise
# our FNC=0xFF init request.  See cpnos-in-c/Makefile
# cpnos-polypascal-test for the master-side wire-up pattern.
CPNET_PORT       = 4446
CPNET_RESULT     = /tmp/cpnos_asm_cpnet_result.txt
CPNET_LOG        = /tmp/cpnos_asm_cpnet_master.log

.PHONY: cpnos-cpnet-test
cpnos-cpnet-test: cpnos-mame-install
	@rm -f $(CPNET_RESULT) $(CPNET_LOG)
	@echo "=== starting fake-master on :$(CPNET_PORT) (background) ==="
	@python3 tasks/sio_a_fake_master.py $(CPNET_PORT) $(CPNET_RESULT) \
	    >$(CPNET_LOG) 2>&1 & echo $$! > /tmp/cpnos_asm_cpnet_master.pid
	@for i in 1 2 3 4 5; do \
	    if grep -q "listening" $(CPNET_LOG) 2>/dev/null; then break; fi; \
	    sleep 0.2; \
	 done
	@rm -f /tmp/cpnos_asm_cpnet_siob.raw
	@echo "=== launching MAME (~12 s, longer than other oracles -- A+B exchange takes ~6 s) ==="
	-$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 15 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:$(CPNET_PORT) \
	    -rs232b null_modem -bitb2 /tmp/cpnos_asm_cpnet_siob.raw \
	    -snapname cpnos_asm_cpnet \
	    >/tmp/cpnos_asm_mame.log 2>&1
	@echo "--- SIO-B capture (slave's view of forwarded SIO-A + ACK dump markers) ---"
	@xxd /tmp/cpnos_asm_cpnet_siob.raw 2>/dev/null | head -20
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if [ -f $(CPNET_RESULT) ]; then break; fi; sleep 0.5; \
	 done
	@if [ -f /tmp/cpnos_asm_cpnet_master.pid ]; then \
	    kill $$(cat /tmp/cpnos_asm_cpnet_master.pid) 2>/dev/null; \
	    rm -f /tmp/cpnos_asm_cpnet_master.pid; \
	 fi
	@echo "--- fake-master log tail ---"
	@tail -20 $(CPNET_LOG) 2>/dev/null
	@echo "--- result ---"
	@cat $(CPNET_RESULT) 2>/dev/null || { echo "no result file"; exit 1; }
	@grep -q '^PASS' $(CPNET_RESULT)
	@# Phase 3g: also verify the slave's decode_rx_frame emitted
	@# "LOGIN OK\r\n" on SIO-B (the test captured SIO-B above).
	@if grep -aq "LOGIN OK" /tmp/cpnos_asm_cpnet_siob.raw; then \
	    echo "PASS: slave decoded LOGIN response and emitted 'LOGIN OK' on SIO-B"; \
	 else \
	    echo "FAIL: 'LOGIN OK' missing from SIO-B"; \
	    xxd /tmp/cpnos_asm_cpnet_siob.raw | tail -3; \
	    exit 1; \
	 fi

# End-to-end test against the real z80pack mpm-net2 master.
# Slave's LOGIN frame (FNC=64, password "PASSWORD" for slave 0x01)
# triggers a real LOGIN response from mpm-net2 (FMT=1, DID=1, SID=0,
# FNC=0x40, SIZ=0, DAT=0x00).  Pattern matches cpnos-in-c's
# cpnos-polypascal-test mpm-net2 wire-up.
#
# Slave's dump_rx_to_siob wraps the received frame in 0xAA marker
# bytes on SIO-B; we grep for those markers around the expected
# response header to confirm the receive state machine fired.
MPM_DIR     ?= $(CURDIR)/../z80pack/cpmsim
MPM_SIOB    = /tmp/cpnos_asm_mpm_siob.raw

.PHONY: cpnos-mpm-test _kill-mpm
_kill-mpm:
	@pkill -TERM -f cpmsim 2>/dev/null || true
	@sleep 1
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN >/dev/null 2>&1; then \
	    pkill -KILL -f cpmsim 2>/dev/null || true; \
	    sleep 1; \
	 fi

cpnos-mpm-test: cpnos-mame-install _kill-mpm
	@rm -f $(MPM_SIOB)
	@echo "=== starting z80pack mpm-net2 in background ==="
	@if [ ! -x "$(MPM_DIR)/mpm-net2" ]; then \
	    echo "ERROR: $(MPM_DIR)/mpm-net2 missing -- build z80pack first"; \
	    exit 1; \
	 fi
	@cd $(MPM_DIR) && (./mpm-net2 >/tmp/mpm_net2.log 2>&1 &)
	@echo "=== waiting for :4002 to listen (up to 5 s) ==="
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if nc -z 127.0.0.1 4002 2>/dev/null; then break; fi; sleep 0.5; \
	 done
	@nc -z 127.0.0.1 4002 || { echo "ERROR: mpm-net2 didn't start"; exit 1; }
	@echo "=== launching MAME (~$(BOOT_DEADLINE_S) s) ==="
	-$(CURDIR)/../../mame/regnecentralend rc702 \
	    -rompath $(CURDIR)/../../mame/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run $(BOOT_DEADLINE_S) \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 $(MPM_SIOB) \
	    >/tmp/cpnos_asm_mame.log 2>&1
	@$(MAKE) _kill-mpm 2>/dev/null || true
	@echo "--- SIO-B hex tail ---"
	@xxd $(MPM_SIOB) | tail -5
	@python3 tasks/verify_mpm_login_response.py $(MPM_SIOB) \
	    && echo "PASS: real-master CP/NET LOGIN exchange verified" \
	    || { echo "FAIL: mpm-net2 didn't reply correctly"; exit 1; }

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
