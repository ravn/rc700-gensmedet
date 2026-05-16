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

SNIOS_PAYLOAD_BIN = $(BUILDDIR)/snios_payload.bin

# SNIOS payload is assembled at org 0xED20 (trampoline + JT at 0xED33
# + impls + CFGTBL).  zmac's .cim output is the raw bytes starting at
# org -- no leading-zero pad -- which is exactly what we want for the
# incbin in prom1.asm.
$(SNIOS_PAYLOAD_BIN): $(SRC)/snios_payload.asm
	@mkdir -p $(BUILDDIR)
	@# zmac quirk: --oo cim,lst with -o file doesn't refresh the .lst
	@# (it generates only the named .cim and leaves zout/.lst stale).
	@# Use --od to redirect ALL outputs to build/zout/, then cp the
	@# .cim out -- this keeps the listing fresh for symbol extraction
	@# (cpnos-polypascal-test awks kbd_head/kbd_ring out of it).
	$(ZMAC) -z --od $(BUILDDIR)/zout $(SRC)/snios_payload.asm
	@cp $(BUILDDIR)/zout/snios_payload.cim $(BUILDDIR)/snios_payload.cim
	@cp $(BUILDDIR)/snios_payload.cim $(SNIOS_PAYLOAD_BIN)
	@echo "snios_payload.bin: $$(wc -c < $(SNIOS_PAYLOAD_BIN) | tr -d ' ') B"

$(PROM1_BIN): $(SRC)/prom1.asm $(BUILDDIR)/buildinfo.inc $(SNIOS_PAYLOAD_BIN)
	@mkdir -p $(BUILDDIR)
	@# Same --od trick as snios_payload: lets zmac emit the .lst so
	@# downstream tools (and humans) can see fresh symbol addresses
	@# without re-assembling.
	$(ZMAC) -z -I $(BUILDDIR) --od $(BUILDDIR)/zout $(SRC)/prom1.asm
	@cp $(BUILDDIR)/zout/prom1.cim $(BUILDDIR)/prom1.cim
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
	@# Phase 4a: cpnet_xact (no retries in inner-loop) -- slave
	@# sends one ENQ for LOGIN, times out, gives up, falls through
	@# to FETCH FAIL.  Exactly one 0x05 on SIO-A.
	@python3 -c "import sys; \
	    d = open('$(SIOA_RAW)', 'rb').read(); \
	    ok = (d == b'\x05'); \
	    sys.exit(0 if ok else (print(f'FAIL: expected 1 ENQ (0x05), got {d.hex()}') or 1))" \
	    && echo "PASS: slave sent 1 ENQ (no master to ACK)" \
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
	@# Install cpnos.com onto mpm-net2's library disks via cpnos-in-c's
	@# disk-install pipeline.  Slave's OPEN A:CPNOS.IMG would otherwise
	@# get rc=0xFF and netboot would FAIL.
	@echo "=== installing cpnos.com on mpm-net2 disks (via cpnos-in-c) ==="
	@$(MAKE) -C ../cpnos-in-c cpnos-disk-install >/tmp/cpnos_asm_diskinstall.log 2>&1 \
	    || { echo "ERROR: cpnos-disk-install failed; tail of log:"; \
	         tail -20 /tmp/cpnos_asm_diskinstall.log; exit 1; }
	@echo "=== starting z80pack mpm-net2 in background (screen) ==="
	@if [ ! -x "$(MPM_DIR)/mpm-net2" ]; then \
	    echo "ERROR: $(MPM_DIR)/mpm-net2 missing -- build z80pack first"; \
	    exit 1; \
	 fi
	@cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
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

# PolyPascal end-to-end test (mirrors cpnos-in-c/cpnos-polypascal-test).
# Drives the slave from boot prompt -> PPAS load -> R PRIMES.PAS -> Q,
# checks /tmp/cpnos_asm_siob.raw for "29989" + two ">>" + two "E>"
# markers.  Slave's impl_conin dequeues from kbd_ring (snios_payload),
# the Lua harness writes keystrokes directly into ring via cpu memory
# tap using addresses extracted at build time from the zmac listing
# below.
#
# Long-running (~4 min wall-clock).  Hermetic: kills any stale cpmsim,
# (re)starts mpm-net2 in screen, syncs ROMs to MAME_IRQ tree.
MAME_IRQ      ?= $(CURDIR)/../../mame
# Shared polypascal_test.lua hardcodes /tmp/cpnos_siob.raw and
# /tmp/cpnos_polypascal_{result,log}.txt -- use the same paths.
PPAS_SIOB     = /tmp/cpnos_siob.raw
PPAS_RESULT   = /tmp/cpnos_polypascal_result.txt
PPAS_LOG      = /tmp/cpnos_polypascal_log.txt
# Lua does `dofile($COMPILER .. "/cpnos_polypascal_addrs.lua")` relative
# to MAME's cwd, so the asm runner places its addrs file under asm/.
PPAS_ADDRS    = $(CURDIR)/asm/cpnos_polypascal_addrs.lua

.PHONY: cpnos-polypascal-test
cpnos-polypascal-test: cpnos-mame-install _kill-mpm
	@echo "=== 1/4 installing cpnos.com on mpm-net2 disks ==="
	@$(MAKE) -C ../cpnos-in-c cpnos-disk-install \
	    >/tmp/cpnos_asm_diskinstall.log 2>&1 \
	    || { echo "ERROR: cpnos-disk-install failed; tail:"; \
	         tail -20 /tmp/cpnos_asm_diskinstall.log; exit 1; }
	@# cpnos-in-c's `cpnos-disk-install` (and its build chain) installs
	@# cpnos-in-c's own roa375.ic66 + prom1.ic65 into $(MAME)/roms/rc702/,
	@# clobbering the asm slave we just installed.  Force-restore ours.
	@cp $(BUILDDIR)/prom0_padded.ic66 $(MAME)/roms/rc702/roa375.ic66
	@cp $(PROM1_BIN) $(MAME)/roms/rc702/prom1.ic65
	@echo "restored asm PROM0 + PROM1 after cpnos-in-c's install"
	@# HARD rule: any PROM mismatch between $(BUILDDIR) and the MAME ROM
	@# slot is an immediate build error -- a stale PROM in the slot means
	@# we'd test the wrong build and the result would be misleading.
	@cmp $(BUILDDIR)/prom0_padded.ic66 $(MAME)/roms/rc702/roa375.ic66 \
	    || { echo "ERROR: $(MAME)/roms/rc702/roa375.ic66 differs from $(BUILDDIR)/prom0_padded.ic66"; \
	         exit 1; }
	@cmp $(PROM1_BIN) $(MAME)/roms/rc702/prom1.ic65 \
	    || { echo "ERROR: $(MAME)/roms/rc702/prom1.ic65 differs from $(PROM1_BIN)"; \
	         exit 1; }
	@echo "=== 2/4 starting MP/M mpm-net2 in screen ==="
	@if [ ! -x "$(MPM_DIR)/mpm-net2" ]; then \
	    echo "ERROR: $(MPM_DIR)/mpm-net2 missing"; exit 1; \
	 fi
	@cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if nc -z 127.0.0.1 4002 2>/dev/null; then break; fi; sleep 0.5; \
	 done
	@nc -z 127.0.0.1 4002 || { echo "ERROR: mpm-net2 didn't start"; exit 1; }
	@sleep 2
	@rm -f $(PPAS_SIOB) $(PPAS_RESULT) $(PPAS_LOG)
	@echo "=== 3/4 generating $(PPAS_ADDRS) (kbd ring addrs from zmac listing) ==="
	@mkdir -p $(dir $(PPAS_ADDRS))
	@# zmac formats labels as `name<spaces>ADDR<spaces>DEC`; equ-defined
	@# constants come out as `name<spaces>=ADDR<spaces>DEC` (= leading the
	@# address).  Match either form so the bare-RAM kbd_head/kbd_ring
	@# equs we now use still get picked up.
	@KH=$$(awk '/^kbd_head[ \t]+=?[0-9A-Fa-f]+/ {sub(/=/,"",$$2); print $$2}' \
	         $(BUILDDIR)/zout/snios_payload.lst); \
	 KR=$$(awk '/^kbd_ring[ \t]+=?[0-9A-Fa-f]+/ {sub(/=/,"",$$2); print $$2}' \
	         $(BUILDDIR)/zout/snios_payload.lst); \
	 [ -n "$$KH" ] && [ -n "$$KR" ] || { \
	    echo "ERROR: kbd_head/kbd_ring missing from $(BUILDDIR)/zout/snios_payload.lst"; \
	    exit 1; }; \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(PPAS_ADDRS)
	@cat $(PPAS_ADDRS)
	@echo "=== 4/4 syncing ROMs to MAME_IRQ tree ==="
	@if [ -d $(MAME_IRQ)/roms/rc702 ] && [ "$(MAME_IRQ)" != "$(MAME)" ]; then \
	    cp $(MAME)/roms/rc702/roa375.ic66 $(MAME_IRQ)/roms/rc702/roa375.ic66; \
	    cp $(MAME)/roms/rc702/prom1.ic65  $(MAME_IRQ)/roms/rc702/prom1.ic65; \
	 fi
	@echo "=== launching MAME with polypascal_test.lua (~240 s) ==="
	-COMPILER=asm BUILDDIR=$(BUILDDIR) $(MAME_IRQ)/regnecentralend rc702 \
	    -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 240 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 $(PPAS_SIOB) \
	    -snapname cpnos_asm_ppas \
	    -autoboot_script $(SHARED)/mame/polypascal_test.lua \
	    >/tmp/cpnos_asm_mame.log 2>&1
	-@$(MAKE) _kill-mpm
	@echo "--- polypascal-test log tail ---"
	@tail -30 $(PPAS_LOG) 2>/dev/null || echo "(no log)"
	@echo "--- SIO-B hex tail (last 256 B) ---"
	@xxd $(PPAS_SIOB) 2>/dev/null | tail -16 || echo "(no SIO-B capture)"
	@echo "--- result ---"
	@cat $(PPAS_RESULT) 2>/dev/null || { echo "(no result file)"; exit 1; }
	@grep -q '^PASS' $(PPAS_RESULT) 2>/dev/null

# CONOTEST.COM stress-test for display control codes (0x01 insert
# line, 0x02 delete line, 0x06 XY addressing, 0x0A LF scroll, 0x0C
# clear screen).  CONOTEST.COM lives on the master's drive I (slave
# drive E:) and writes its PASS:/FAIL: verdict to BIOS CONOUT, which
# our impl_conout mirrors to SIO-B for the harness to scrape.
.PHONY: cpnos-conout-test
cpnos-conout-test: cpnos-mame-install _kill-mpm
	@echo "=== 1/4 installing cpnos.com + CONOTEST.COM ==="
	@$(MAKE) -C ../cpnos-in-c cpnos-disk-install \
	    >/tmp/cpnos_asm_diskinstall.log 2>&1 \
	    || { echo "ERROR: cpnos-disk-install failed"; \
	         tail -20 /tmp/cpnos_asm_diskinstall.log; exit 1; }
	@# cpmcp segfaults at exit on z80pack-hd format BUT the file is
	@# actually written to disk before the crash.  Tolerate exit code
	@# and verify via grep afterwards.  cpmtools bug (both ~/.local
	@# and cpmtools3 affected); written up in
	@# https://github.com/cpmtools/cpmtools/issues/N (TBD).
	-@cpmcp -f z80pack-hd \
	    $(MPM_DIR)/disks/library/mpm-net2-drivei.dsk \
	    ../rcbios-in-c/conotest.com 0:CONOTEST.COM \
	    >/dev/null 2>&1
	@grep -aq "CONOTEST" $(MPM_DIR)/disks/library/mpm-net2-drivei.dsk \
	    || { echo "ERROR: CONOTEST.COM not on drive I disk"; exit 1; }
	@cp $(BUILDDIR)/prom0_padded.ic66 $(MAME)/roms/rc702/roa375.ic66
	@cp $(PROM1_BIN) $(MAME)/roms/rc702/prom1.ic65
	@cmp $(BUILDDIR)/prom0_padded.ic66 $(MAME)/roms/rc702/roa375.ic66 \
	    || { echo "ERROR: PROM0 mismatch"; exit 1; }
	@cmp $(PROM1_BIN) $(MAME)/roms/rc702/prom1.ic65 \
	    || { echo "ERROR: PROM1 mismatch"; exit 1; }
	@echo "=== 2/4 starting MP/M mpm-net2 in screen ==="
	@cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if nc -z 127.0.0.1 4002 2>/dev/null; then break; fi; sleep 0.5; \
	 done
	@nc -z 127.0.0.1 4002 || { echo "ERROR: mpm-net2 didn't start"; exit 1; }
	@sleep 2
	@rm -f $(PPAS_SIOB) $(PPAS_RESULT) $(PPAS_LOG)
	@echo "=== 3/4 generating $(PPAS_ADDRS) ==="
	@mkdir -p $(dir $(PPAS_ADDRS))
	@KH=$$(awk '/^kbd_head[ \t]+=?[0-9A-Fa-f]+/ {sub(/=/,"",$$2); print $$2}' \
	         $(BUILDDIR)/zout/snios_payload.lst); \
	 KR=$$(awk '/^kbd_ring[ \t]+=?[0-9A-Fa-f]+/ {sub(/=/,"",$$2); print $$2}' \
	         $(BUILDDIR)/zout/snios_payload.lst); \
	 printf 'return {\n  kbd_head = 0x%s,\n  kbd_ring = 0x%s,\n}\n' "$$KH" "$$KR" \
	   > $(PPAS_ADDRS)
	@cat $(PPAS_ADDRS)
	@echo "=== 4/4 launching MAME with conotest_test.lua (max 120 s) ==="
	-COMPILER=asm BUILDDIR=$(BUILDDIR) $(MAME_IRQ)/regnecentralend rc702 \
	    -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 120 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 $(PPAS_SIOB) \
	    -snapname cpnos_asm_conout \
	    -autoboot_script $(SHARED)/mame/conotest_test.lua \
	    >/tmp/cpnos_asm_mame.log 2>&1
	-@$(MAKE) _kill-mpm
	@echo "--- conout-test log ---"
	@cat $(PPAS_LOG) 2>/dev/null
	@echo "--- SIO-B output (printable filter) ---"
	@tr -cd '\11\12\15\40-\176' < $(PPAS_SIOB) 2>/dev/null | tail -c 600 || true
	@echo
	@echo "--- result ---"
	@cat $(PPAS_RESULT) 2>/dev/null || { echo "(no result file)"; exit 1; }
	@grep -q '^PASS' $(PPAS_RESULT) 2>/dev/null

# Diagnostic: run the slave against mpm-net2 (no keystrokes) and have
# MAME's Lua dump CP/NOS memory structures at t=15/30/60 s.  Used to
# diff the asm slave's runtime state against cpnos-in-c when SELDSK
# errors out (NDOS Err 04, Func 0E).  Output: /tmp/cpnos_ndos_state.txt.
.PHONY: cpnos-dsp-watch
cpnos-dsp-watch: cpnos-mame-install _kill-mpm
	@$(MAKE) -C ../cpnos-in-c cpnos-disk-install \
	    >/tmp/cpnos_asm_diskinstall.log 2>&1 || true
	@cp $(BUILDDIR)/prom0_padded.ic66 $(MAME)/roms/rc702/roa375.ic66
	@cp $(PROM1_BIN) $(MAME)/roms/rc702/prom1.ic65
	@cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    nc -z 127.0.0.1 4002 2>/dev/null && break; sleep 0.5; \
	 done
	@sleep 2
	@rm -f /tmp/cpnos_dsp_watch.log /tmp/cpnos_siob.raw
	-$(MAME_IRQ)/regnecentralend rc702 \
	    -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 20 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -autoboot_script $(SHARED)/mame/watch_dsp_corruption.lua \
	    >/tmp/cpnos_asm_mame.log 2>&1
	-@$(MAKE) _kill-mpm
	@echo "--- dsp write-tap log (first 80 lines) ---"
	@head -80 /tmp/cpnos_dsp_watch.log

.PHONY: cpnos-ndos-dump
cpnos-ndos-dump: cpnos-mame-install _kill-mpm
	@$(MAKE) -C ../cpnos-in-c cpnos-disk-install \
	    >/tmp/cpnos_asm_diskinstall.log 2>&1 || true
	@cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	    nc -z 127.0.0.1 4002 2>/dev/null && break; sleep 0.5; \
	 done
	@sleep 2
	@rm -f /tmp/cpnos_ndos_state.txt /tmp/cpnos_siob.raw
	-NDOS_CFGTBL=0xEF7E $(MAME_IRQ)/regnecentralend rc702 \
	    -rompath $(MAME_IRQ)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 65 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 /tmp/cpnos_siob.raw \
	    -autoboot_script $(SHARED)/mame/dump_ndos_state.lua \
	    >/tmp/cpnos_asm_mame.log 2>&1
	-@$(MAKE) _kill-mpm
	@echo "--- ndos state dump ---"
	@cat /tmp/cpnos_ndos_state.txt
	@cp /tmp/cpnos_ndos_state.txt /tmp/cpnos_ndos_state.asm.txt

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
