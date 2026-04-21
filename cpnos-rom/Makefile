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
         -DRC702_SLAVEID=0x70 \
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

OBJS = clang/reset.o clang/runtime.o clang/bios_jt.o clang/cpnos_main.o \
       clang/resident.o clang/rc700_console.o clang/cfgtbl.o clang/init.o \
       clang/transport_sio.o clang/netboot.o clang/snios.o clang/isr.o
LDSCRIPT = cpnos_rom.ld

.PHONY: all cpnos cpnos-size cpnos-burn cpnos-disasm cpnos-clean

all: cpnos

cpnos: clang/cpnos.bin cpnos-size cpnos-lis

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

clang/resident.o: resident.c rc700_console.h hal.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/rc700_console.o: rc700_console.c rc700_console.h hal.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/cfgtbl.o: cfgtbl.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/init.o: init.c
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/transport_sio.o: transport_sio.c transport.h hal.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

clang/netboot.o: netboot.c transport.h
	@mkdir -p clang
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Link ---------------------------------------------------------

clang/cpnos.elf: $(OBJS) $(LDSCRIPT)
	$(LD) --gc-sections --emit-relocs -T $(LDSCRIPT) $(OBJS) -o $@

# The linker puts PROM0 at 0x0000 (2KB) and PROM1 at 0x2000 (2KB) with a
# 6KB hole between them.  objcopy -O binary produces a 10KB file with
# 6KB of zero fill between the two regions; we carve out each 2KB half,
# pad empty halves with 0xFF, and concatenate for verification.
clang/cpnos.bin: clang/cpnos.elf
	$(OBJCOPY) -O binary --gap-fill=0xFF --pad-to=0x2800 $< clang/cpnos.raw
	dd if=clang/cpnos.raw of=clang/prom0.bin bs=2048 count=1 status=none
	dd if=clang/cpnos.raw of=clang/prom1.bin bs=2048 skip=4 count=1 status=none
	@# If PROM1 is all zeros (unused), replace with 0xFF pad so an
	@# unprogrammed EPROM is burned to a recognisable state.
	@if ! od -An -tx1 clang/prom1.bin | grep -qv ' 00 '; then \
	  perl -e 'print "\xff" x 2048' > clang/prom1.bin; \
	fi
	cat clang/prom0.bin clang/prom1.bin > $@

# ---- Size check ---------------------------------------------------

cpnos-size: clang/cpnos.bin
	@P0=$$(wc -c < clang/prom0.bin | tr -d ' '); \
	 P1=$$(wc -c < clang/prom1.bin | tr -d ' '); \
	 TOTAL=$$(wc -c < clang/cpnos.bin | tr -d ' '); \
	 echo "PROM0:  $$P0 / 2048 bytes"; \
	 echo "PROM1:  $$P1 / 2048 bytes"; \
	 echo "TOTAL:  $$TOTAL / 4096 bytes"; \
	 test $$TOTAL -eq 4096 || { echo "ERROR: image not exactly 4096 bytes"; exit 1; }
	@echo "--- section sizes ---"
	@$(OBJDUMP) --headers clang/cpnos.elf | awk '/\.(reset|init|prom1|resident|scratch)/ { printf "%-16s 0x%s VMA=0x%s\n", $$2, $$3, $$4 }'
	@echo "--- top symbols ---"
	@$(NM) --numeric-sort --size-sort --reverse-sort clang/cpnos.elf | head -10
	@echo "--- actual code bytes in PROM0 (non-0xFF) ---"
	@od -An -tx1 clang/prom0.bin | tr -s ' ' '\n' | grep -v '^$$' | grep -v '^ff$$' | wc -l | awk '{ printf "%d non-padding bytes\n", $$1 }'

# ---- Split for burner --------------------------------------------

cpnos-burn: clang/cpnos.bin
	@echo "PROM0 (0x0000-0x07FF): clang/prom0.bin ($$(wc -c < clang/prom0.bin | tr -d ' ') B)"
	@echo "PROM1 (0x2000-0x27FF): clang/prom1.bin ($$(wc -c < clang/prom1.bin | tr -d ' ') B)"

# ---- Inspection --------------------------------------------------

cpnos-disasm: clang/cpnos.elf
	$(OBJDUMP) -d --triple=z80 $<

# ---- MAME boot test ----------------------------------------------

MAME = /Users/ravn/git/mame
MAME_PROM0 = $(MAME)/roms/rc702/roa375.ic66
MAME_PROM1 = $(MAME)/roms/rc702/prom1.ic65

# Install prom0.bin (4KB slot, 0xFF-padded) and prom1.bin (2KB).
# Session 30: PROM1 now carries .resident_pre (RC700 console helpers),
# loaded via ROM_LOAD_OPTIONAL in the MAME rc702 driver.
cpnos-install: clang/cpnos.bin
	@P0=$$(wc -c < clang/prom0.bin | tr -d ' '); \
	 { cat clang/prom0.bin; perl -e "print \"\\xff\" x (4096 - $$P0)"; } \
	   > clang/prom0_padded.ic66
	cp clang/prom0_padded.ic66 $(MAME_PROM0)
	cp clang/prom1.bin $(MAME_PROM1)
	@echo "installed cpnos prom0 -> $(MAME_PROM0)"
	@echo "installed cpnos prom1 -> $(MAME_PROM1)"

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
cpnos-lis: clang/cpnos.elf
	$(OBJDUMP) -d -S -r --symbolize-operands --triple=z80 $< > clang/cpnos.lis
	@echo "wrote clang/cpnos.lis (with C source + symbol-resolved operands)"

cpnos-map: clang/cpnos.elf
	$(NM) --numeric-sort $<

# Note: per-TU listings from .o files don't work reliably because
# unlinked object files have incomplete DWARF (relocations unresolved
# until link).  The linked-ELF listing from cpnos-lis gives the same
# C-source-interleaved output for the whole program; see it there.

# ---- Clean --------------------------------------------------------

cpnos-clean:
	rm -rf clang
