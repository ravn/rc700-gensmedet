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

ENABLE_FDC ?= 0

LLVM_Z80 = $(CURDIR)/../../llvm-z80
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
         -DRC702_SLAVEID=0x01 \
         $(SERVER_CFLAGS) \
         -Iclang -I. \
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

# Server side: default is standard MP/M II (cpmsim mpm-net2).
# Override with SERVER=proxy to use the legacy Python netboot_server.py
# (FMT=0xB0 custom protocol).
SERVER ?= mpm

ifeq ($(SERVER),mpm)
NETBOOT_OBJ = clang/netboot_mpm.o
SERVER_CFLAGS =
else ifeq ($(SERVER),proxy)
NETBOOT_OBJ = clang/netboot.o
SERVER_CFLAGS = -DNETBOOT_LEGACY
else
$(error SERVER must be 'mpm' or 'proxy')
endif

# ---- Payload (linked at 0xED00, no PROM knowledge) ----------------
# The payload is the single contiguous blob of everything that runs
# at runtime.  The payload linker doesn't know about the two EPROMs;
# a separate relocator stitches it back together at cold boot.
PAYLOAD_OBJS = clang/runtime.o clang/bios_jt.o clang/cpnos_main.o \
               clang/resident.o clang/cfgtbl.o clang/init.o \
               clang/transport_sio.o $(NETBOOT_OBJ) \
               clang/snios.o clang/isr.o clang/fdc.o
PAYLOAD_LD = payload.ld

# ---- Relocator (PROM0 reset + #embed'd payload halves) -----------
# Tiny: reset.s for stack setup, relocator.c with two #embed arrays.
# Linked with PROM knowledge so the chunks land in physical ROM.
RELOC_OBJS = clang/reset.o clang/relocator.o
RELOC_LD = relocator.ld

ALL_OBJS = $(PAYLOAD_OBJS) $(RELOC_OBJS)

.PHONY: all cpnos cpnos-size cpnos-burn cpnos-disasm cpnos-clean

all: cpnos

cpnos: clang/cpnos.bin cpnos-size cpnos-lis

# Flag changes (e.g. -DRC702_SLAVEID=) must invalidate all objects.
$(ALL_OBJS): Makefile

# ---- Compile ------------------------------------------------------

clang/reset.o: reset.s
	@mkdir -p clang
	$(CC) $(ASFLAGS) -c $< -o $@

clang/runtime.o: runtime.s
	@mkdir -p clang
	$(CC) $(ASFLAGS) -c $< -o $@

clang/bios_jt.o: bios_jt.s
	@mkdir -p clang
	$(CC) $(ASFLAGS) -c $< -o $@

clang/snios.o: snios.s
	@mkdir -p clang
	$(CC) $(ASFLAGS) -c $< -o $@

clang/isr.o: isr.s
	@mkdir -p clang
	$(CC) $(ASFLAGS) -c $< -o $@

clang/cpnos_main.o: cpnos_main.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/resident.o: resident.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/cfgtbl.o: cfgtbl.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/init.o: init.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/fdc.o: fdc.c fdc.h hal.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/transport_sio.o: transport_sio.c transport.h hal.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/netboot.o: netboot.c transport.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/netboot_mpm.o: netboot_mpm.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

# Relocator #embed's payload_a.bin/payload_b.bin — depend on them so
# a payload change retriggers the relocator compile.
clang/relocator.o: relocator.c clang/payload_a.bin clang/payload_b.bin
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Link payload (no PROM awareness) ----------------------------

clang/payload.elf: $(PAYLOAD_OBJS) $(PAYLOAD_LD)
	$(LD) --gc-sections --emit-relocs -T $(PAYLOAD_LD) $(PAYLOAD_OBJS) -o $@

clang/payload.bin: clang/payload.elf
	$(OBJCOPY) -O binary $< $@

# Split payload into the two chunks the relocator #embed's.  Split
# point matches relocator.ld's .prom0_tail base (0x80): 1920 bytes
# fit in PROM0 after the relocator.
PROM0_TAIL_SIZE = 1920
clang/payload_a.bin clang/payload_b.bin: clang/payload.bin
	dd if=$< of=clang/payload_a.bin bs=1 count=$(PROM0_TAIL_SIZE) status=none
	dd if=$< of=clang/payload_b.bin bs=1 skip=$(PROM0_TAIL_SIZE) status=none

# ---- Link relocator ----------------------------------------------
# --defsym injects _cpnos_cold_entry's address from the payload ELF
# (extracted via nm) so relocator.c's extern reference resolves.

clang/relocator.elf: $(RELOC_OBJS) $(RELOC_LD) clang/payload.elf
	@addr=$$($(NM) clang/payload.elf | awk '/ _cpnos_cold_entry$$/ {print "0x"$$1}'); \
	 test -n "$$addr" || { echo "ERROR: _cpnos_cold_entry not found in payload"; exit 1; }; \
	 echo "relocator: _cpnos_cold_entry=$$addr"; \
	 $(LD) --gc-sections -T $(RELOC_LD) --defsym=_cpnos_cold_entry=$$addr \
	       $(RELOC_OBJS) -o $@

# ---- Produce prom0.bin / prom1.bin --------------------------------

clang/cpnos.bin: clang/relocator.elf
	$(OBJCOPY) -O binary --gap-fill=0xFF --pad-to=0x2800 $< clang/cpnos.raw
	dd if=clang/cpnos.raw of=clang/prom0.bin bs=2048 count=1 status=none
	dd if=clang/cpnos.raw of=clang/prom1.bin bs=2048 skip=4 count=1 status=none
	cat clang/prom0.bin clang/prom1.bin > $@

# ---- Size check ---------------------------------------------------

cpnos-size: clang/cpnos.bin
	@P0=$$(wc -c < clang/prom0.bin | tr -d ' '); \
	 P1=$$(wc -c < clang/prom1.bin | tr -d ' '); \
	 PLD=$$(wc -c < clang/payload.bin | tr -d ' '); \
	 TOTAL=$$(wc -c < clang/cpnos.bin | tr -d ' '); \
	 echo "payload:  $$PLD bytes (linked at 0xED00)"; \
	 echo "PROM0:    $$P0 / 2048 bytes"; \
	 echo "PROM1:    $$P1 / 2048 bytes"; \
	 echo "TOTAL:    $$TOTAL / 4096 bytes"; \
	 test $$TOTAL -eq 4096 || { echo "ERROR: image not exactly 4096 bytes"; exit 1; }
	@echo "--- payload section sizes ---"
	@$(OBJDUMP) --headers clang/payload.elf | awk '/\.(payload|scratch)/ { printf "%-16s 0x%s VMA=0x%s\n", $$2, $$3, $$4 }'
	@echo "--- top payload symbols ---"
	@$(NM) --numeric-sort --size-sort --reverse-sort clang/payload.elf | head -10
	@echo "--- actual code bytes in PROM0 (non-0xFF) ---"
	@od -An -tx1 clang/prom0.bin | tr -s ' ' '\n' | grep -v '^$$' | grep -v '^ff$$' | wc -l | awk '{ printf "%d non-padding bytes\n", $$1 }'

# ---- CP/M .COM loader (test PROMs without burning) ---------------
#
# Produces a ~4 KB .COM that, when executed from the CP/M prompt,
# copies prom0.bin into 0x0000 and prom1.bin into 0x2000 then JPs
# to 0x0000 — mimicking a cold boot against new PROM payloads
# without touching physical EPROMs.  See build_loader.py for layout.

cpnos-loader: clang/cpnos.bin
	python3 build_loader.py clang/prom0.bin clang/prom1.bin clang/cpnos_loader.com
	cp clang/cpnos_loader.com testutil/cpnosldr.com
	@echo "staged testutil/cpnosldr.com (run 'cpnosldr' from CP/M A>)"

# ---- Split for burner --------------------------------------------

cpnos-burn: clang/cpnos.bin
	@echo "PROM0 (0x0000-0x07FF): clang/prom0.bin ($$(wc -c < clang/prom0.bin | tr -d ' ') B)"
	@echo "PROM1 (0x2000-0x27FF): clang/prom1.bin ($$(wc -c < clang/prom1.bin | tr -d ' ') B)"

# ---- Inspection --------------------------------------------------

cpnos-disasm: clang/payload.elf clang/relocator.elf
	$(OBJDUMP) -d --triple=z80 clang/payload.elf
	@echo '=== relocator ==='
	$(OBJDUMP) -d --triple=z80 clang/relocator.elf

# ---- MAME boot test ----------------------------------------------

MAME = /Users/ravn/git/mame
MAME_PROM0 = $(MAME)/roms/rc702/roa375.ic66

# Install prom0.bin into MAME (4KB slot, pad with 0xFF).  PROM1 at
# 0x2000 in MAME is 0xFF by default — fine for Phase 1 where our
# PROM1 is unused.
MAME_PROM1 = $(MAME)/roms/rc702/prom1.ic65
cpnos-install: clang/cpnos.bin
	@P0=$$(wc -c < clang/prom0.bin | tr -d ' '); \
	 { cat clang/prom0.bin; perl -e "print \"\\xff\" x (4096 - $$P0)"; } \
	   > clang/prom0_padded.ic66
	cp clang/prom0_padded.ic66 $(MAME_PROM0)
	cp clang/prom1.bin         $(MAME_PROM1)
	@echo "installed cpnos prom0 -> $(MAME_PROM0)"
	@echo "installed cpnos prom1 -> $(MAME_PROM1)"

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
cpnet-smoke: cpnos-install
	@echo "=== 1/5 regenerating sumtest.asm + smoke disk ==="
	python3 testutil/mksmokeasm.py
	testutil/mksmokedisk.sh
	@echo "=== 2/5 restarting MP/M with fresh drive D: ==="
	-screen -S mpm -X quit >/dev/null 2>&1 || true
	@sleep 1
	@# Guard: make sure nothing else is squatting on :4002 (stray
	@# netboot_server.py, orphan cpmsim, ...) — any phantom listener
	@# will intercept MAME's netboot and produce misleading results.
	@if lsof -nP -iTCP:4002 -sTCP:LISTEN 2>/dev/null | grep -q .; then \
	    echo "ERROR: port 4002 already bound — kill the squatter first:"; \
	    lsof -nP -iTCP:4002 -sTCP:LISTEN; \
	    exit 1; \
	fi
	cd $(MPM_DIR) && screen -dmS mpm ./mpm-net2
	@echo "=== 3/5 waiting for MP/M CP/NET server on :4002 ==="
	@until nc -z 127.0.0.1 4002 2>/dev/null; do sleep 0.5; done
	@sleep 4
	@echo "=== 4/5 launching MAME + smoke injector ==="
	@rm -f /tmp/cpnos_siob.raw /tmp/cpnos_smoke_inject.log
	@python3 -u testutil/smoke_inject.py $(SMOKE_PORT) \
	    --log /tmp/cpnos_siob.raw --timeout 240 \
	    > /tmp/cpnos_smoke_inject.log 2>&1 & \
	 echo $$! > /tmp/cpnos_smoke_inject.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 1200 \
	    -rs232a null_modem -bitb1 socket.127.0.0.1:4002 \
	    -rs232b null_modem -bitb2 socket.127.0.0.1:$(SMOKE_PORT) \
	    -autoboot_script mame_smoke_dump.lua
	@kill $$(cat /tmp/cpnos_smoke_inject.pid) 2>/dev/null || true
	@echo "=== 5/5 verifying ==="
	@echo --- injector log ---
	@cat /tmp/cpnos_smoke_inject.log
	@echo --- SIO-B tail ---
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw | tail -c 400 || true
	@echo
	@echo --- BDOS FNC counter snapshot ---
	@tail -40 /tmp/cpnos_fnc_counters.txt 2>/dev/null || echo "(no counter file)"
	@grep -q 'CPNET OK A314' /tmp/cpnos_siob.raw \
	    && echo "PASS: slave-assembled program printed CPNET OK A314" \
	    || (echo "FAIL: expected 'CPNET OK A314' not found in /tmp/cpnos_siob.raw"; exit 1)

cpnos-mame: cpnos-install
	$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 8 \
	    -rs232a null_modem \
	    -bitb1 /tmp/cpnos_sioa.raw \
	    -autoboot_script mame_boot_test.lua

# End-to-end netboot test: Python server on localhost, MAME bridged to
# it over SIO-A null_modem.
NETBOOT_PORT ?= 9000
SIOB_PORT    ?= 9001
SIOB_TRIGGER ?=
SIOB_INJECT  ?=
cpnos-netboot: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log
	@python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) \
	    $(if $(SIOB_TRIGGER),--trigger '$(SIOB_TRIGGER)') \
	    $(if $(SIOB_INJECT),--inject '$(SIOB_INJECT)') \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 70 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)" \
	    -autoboot_script mame_boot_test.lua
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- server log ---"
	@cat /tmp/cpnos_netboot_server.log
	@echo "--- SIO-B driver log ---"
	@cat /tmp/cpnos_siob_driver.log
	@echo "--- SIO-B capture (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw 2>/dev/null || true
	@echo
	@echo "--- boot test ---"
	@cat /tmp/cpnos_boot_result.txt
	@grep -q '^PASS' /tmp/cpnos_boot_result.txt

# Step 1 of the smoke plan: ^C warm boot via SIO-B injection.
# Runs long enough for cold boot + ^C + full CCP.SPR reload, then
# asserts the server observed two OPEN events for CCP.SPR.
cpnos-warmboot-test: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log
	@python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) \
	    --trigger 'A>' --inject '\x03' --timeout 30 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 25 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)"
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- server log (OPEN events) ---"
	@grep -E 'opened|FNC=0x0f' /tmp/cpnos_netboot_server.log || true
	@echo "--- SIO-B driver log ---"
	@cat /tmp/cpnos_siob_driver.log
	@echo "--- SIO-B capture (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw 2>/dev/null || true
	@echo
	@echo "--- assertion ---"
	@n=$$(grep -cE '    opened ' /tmp/cpnos_netboot_server.log); \
	 echo "CCP.SPR OPEN count: $$n"; \
	 [ "$$n" -ge 2 ] || { echo 'FAIL: expected >= 2 OPEN events'; exit 1; }; \
	 echo 'PASS: warm boot re-fetched CCP.SPR'

# Auto-run a canned CP/NOS session via $70.SUB (native CP/M batch
# mechanism — the server seeds the SUB file, CCP reads+executes it
# at the first prompt, then deletes it).  Pass commands pipe-separated:
#   make cpnos-sub-test CPNOS_SUB='dir'
#   make cpnos-sub-test CPNOS_SUB='dir|pip foo.txt=login.com|dir'
# Asserts that the SUB file is opened (proving execution) and that
# afterwards CCP is idle at the prompt (no SNIOS traffic for >2 s).
CPNOS_SUB ?= dir
cpnos-sub-test: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log /tmp/cpnos_boot_result.txt
	@CPNOS_SUB='$(CPNOS_SUB)|done' python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) --timeout 30 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 70 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)" \
	    -autoboot_script mame_sub_test.lua
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- SIO-B (printable) ---"
	@tr -cd '\11\12\15\40-\176' < /tmp/cpnos_siob.raw | sed 's/$$/ /'
	@echo
	@echo "--- result ---"
	@cat /tmp/cpnos_boot_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_boot_result.txt

# ---- CONOUT acid test --------------------------------------------
#
# Builds testutil/acid.com with z88dk (+cpm), boots CP/NOS via
# netboot_server.py with CPNOS_SUB='acid' so CCP runs it at first
# prompt, then mame_acid_test.lua dumps the 8275 display RAM at
# 0xF800 and asserts the known pixel pattern the 15 RC700 control
# codes are supposed to produce.
#
# Finish marker: the .COM emits "DONE\r\n" through BIOS CONOUT,
# which mirrors to SIO-B -- same gate as mame_sub_test.lua.
Z88DK_ROOT = $(CURDIR)/../z88dk
Z88DK_ZCC  = $(Z88DK_ROOT)/bin/zcc
testutil/acid.com: testutil/acid.c
	cd testutil && \
	    PATH=$(Z88DK_ROOT)/bin:$$PATH \
	    ZCCCFG=$(Z88DK_ROOT)/lib/config \
	    zcc +cpm --opt-code-size \
	    -create-app -o acid acid.c
	@echo "built testutil/acid.com ($$(wc -c < testutil/acid.com | tr -d ' ') B)"

conout-acid: cpnos-install testutil/acid.com
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log /tmp/cpnos_boot_result.txt /tmp/cpnos_display.txt
	@CPNOS_SUB='acid|done' python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) --timeout 90 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 100 \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)" \
	    -autoboot_script mame_acid_test.lua
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true
	@echo "--- display dump ---"
	@cat /tmp/cpnos_display.txt 2>/dev/null || echo '(no display dump)'
	@echo "--- result ---"
	@cat /tmp/cpnos_boot_result.txt 2>/dev/null || echo '(no result file)'
	@grep -q '^PASS' /tmp/cpnos_boot_result.txt

# Interactive: boot CP/NOS, leave MAME running at the A> prompt so a
# human can type on the native keyboard (PIO-A path).  SIO-B output
# still streams to /tmp/cpnos_siob.raw so the other side can watch
# what got typed + echoed.  Exit by closing the MAME window (Esc).
cpnos-interactive: cpnos-install
	@rm -f /tmp/cpnos_netboot_server.log /tmp/cpnos_siob.raw /tmp/cpnos_siob_driver.log
	@python3 -u netboot_server.py $(NETBOOT_PORT) > /tmp/cpnos_netboot_server.log 2>&1 & \
	 echo $$! > /tmp/cpnos_netboot_server.pid
	@python3 -u sio_b_driver.py $(SIOB_PORT) --timeout 3600 \
	    > /tmp/cpnos_siob_driver.log 2>&1 & \
	 echo $$! > /tmp/cpnos_siob_driver.pid
	@sleep 0.3
	@echo "netboot server pid=$$(cat /tmp/cpnos_netboot_server.pid)"
	@echo "sio-b driver  pid=$$(cat /tmp/cpnos_siob_driver.pid)"
	@echo "Watch typed output:  tail -f /tmp/cpnos_siob.raw"
	-$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -window -skip_gameinfo \
	    -rs232a null_modem \
	    -bitb1 "socket.127.0.0.1:$(NETBOOT_PORT)" \
	    -rs232b null_modem \
	    -bitb2 "socket.127.0.0.1:$(SIOB_PORT)"
	@kill $$(cat /tmp/cpnos_netboot_server.pid) 2>/dev/null || true
	@kill $$(cat /tmp/cpnos_siob_driver.pid) 2>/dev/null || true

# CPU trace: captures every executed instruction to /tmp/cpnos_trace.log.
# Use for debugging control-flow issues.  Pipe through tail or head to
# avoid filling the disk (per project memory).
cpnos-trace: cpnos-install
	$(MAME)/regnecentralend rc702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 2 \
	    -autoboot_script mame_boot_test.lua \
	    -debug -debugscript trace.dbg
	@echo "trace written to /tmp/cpnos_trace.log"

# Source-interleaved disassembly (requires -g, enabled in CFLAGS).
# The -S flag interleaves the original C lines with emitted Z80 asm.
cpnos-lis: clang/payload.elf
	$(OBJDUMP) -d -S -r --symbolize-operands --triple=z80 $< > clang/cpnos.lis
	@echo "wrote clang/cpnos.lis (with C source + symbol-resolved operands)"

cpnos-map: clang/payload.elf
	$(NM) --numeric-sort $<

# Note: per-TU listings from .o files don't work reliably because
# unlinked object files have incomplete DWARF (relocations unresolved
# until link).  The linked-ELF listing from cpnos-lis gives the same
# C-source-interleaved output for the whole program; see it there.

# ---- Clean --------------------------------------------------------

cpnos-clean:
	rm -rf clang
