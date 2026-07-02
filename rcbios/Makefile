# RC702 CP/M BIOS - assembly, extraction, and analysis
#
# Assembly targets (from jbox.dk sources with conditional assembly):
#   make rel21-mini  - Build rel.2.1 BIOS (5.25" mini, 56K)
#   make rel22-mini  - Build rel.2.2 BIOS (5.25" mini, 56K)
#   make rel14-maxi  - Build rel.1.4 BIOS (8" maxi, 58K)
#   make verify      - Build all and verify against reference binaries
#
# Language selection (default: Danish):
#   make rel23-mini KBLANG=US_ASCII
#   make rel30-mini KBLANG=SWEDISH
#   Available: DANISH SWEDISH GERMAN UK_ASCII US_ASCII FRENCH LIBRARY
#
# Patch and test:
#   make patch-test  - Patch BIOS onto disk images and boot-test in emulator
#
# Disassembly targets:
#   make rel14_bios.asm  - Regenerate annotated rel.1.4 disassembly
#
# Extraction targets (require emulator and disk images):
#   make dumps    - Extract RAM dumps from disk images
#   make bios     - Extract BIOS binaries from RAM dumps
#   make disasm   - Disassemble extracted BIOS binaries

ZMAC = ../zmac/bin/zmac
ZMFLAGS = -z --dri -I src

# Language conversion table: DANISH (default), SWEDISH, GERMAN,
# UK_ASCII, US_ASCII, FRENCH, LIBRARY
# Pass KBLANG=<language> to select. Omit or KBLANG=DANISH for default.
KBLANG ?= DANISH
ifneq ($(KBLANG),DANISH)
ZMFLAGS += -D$(KBLANG)
endif

RC700 = $(HOME)/git/rc700
EMU = $(RC700)/rc700-vt100

# Disk image locations
IMG_RCCPM22 = $(RC700)/rccpm22.imd
IMG_COMAL80 = $(HOME)/Downloads/CPM_med_COMAL80.imd
IMG_REL22   = $(HOME)/Downloads/CPM_v.2.2_rel.2.2.bin
IMG_COMPAS  = $(HOME)/Downloads/Compas_v.2.13DK.imd
IMG_SW1711  = $(HOME)/Downloads/SW1711-I8.imd
IMG_RC703R12 = $(HOME)/Downloads/RC703_CPM_v2.2_r1.2.bin

# RAM dumps
DUMPS = rccpm22_ram.bin cpm_comal80_ram.bin cpm22_rel22_ram.bin compas_ram.bin

# BIOS binaries and disassemblies
BIOS_BINS = ref/rccpm22_bios.bin ref/cpm22_rel22_bios.bin ref/compas_bios.bin
BIOS_ASMS = rccpm22_bios.asm cpm22_rel22_bios.asm rel14_bios.asm

.PHONY: all rel20-mini rel21-mini rel22-mini rel23-mini rel23-maxi rel30-mini rel30-maxi rel13-mini rel14-mini rel14-maxi rc703-rel10 rc703-rel11 rc703-rel12 rc703-reltfj rc702e-rel201 rc702e-rel220 verify verify-rc702e verify-summary dumps bios disasm clean emu patch-test mame-test

all: verify

# ============================================================
# Assembly targets
# ============================================================

# BIOS offset in output: BIOS base - START (code start)
# 56K: DA00 - D480 = 0x580
# 58K: E200 - DD00 = 0x500
BIOS_OFFSET_56K = 0x580
BIOS_OFFSET_58K = 0x500

# Reference offset within extracted_bios/ files (BIOS offset - boot entry offset)
# 56K: 0x580 - 0x280 = 0x300
# 58K: 0x500 - 0x380 = 0x180
EXTREF_OFFSET_56K = 0x300
EXTREF_OFFSET_58K = 0x180

rel20-mini: src/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL20 -DMINI src/BIOS.MAC

rel21-mini: src/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL21 -DMINI src/BIOS.MAC

rel22-mini: src/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL22 -DMINI src/BIOS.MAC

rel23-mini: src/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL23 -DMINI src/BIOS.MAC

rel23-maxi: src/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL23 -DMAXI src/BIOS.MAC

rel30-mini: src/BIOS.MAC
	@mkdir -p zout
	@echo "	DB	'$$(date +%Y-%m-%d\ %H:%M)'" > zout/BUILDDATE.MAC
	$(ZMAC) $(ZMFLAGS) -I zout -DREL30 -DMINI src/BIOS.MAC

rel30-maxi: src/BIOS.MAC
	@mkdir -p zout
	@echo "	DB	'$$(date +%Y-%m-%d\ %H:%M)'" > zout/BUILDDATE.MAC
	$(ZMAC) $(ZMFLAGS) -I zout -DREL30 -DMAXI src/BIOS.MAC

# 58K BIOS targets (separate source tree)
rel13-mini: src-58k/BIOS_58K.MAC
	$(ZMAC) $(ZMFLAGS) -DREL13 src-58k/BIOS_58K.MAC

rel14-mini rel14-maxi: src-58k/BIOS_58K_14.MAC
	$(ZMAC) $(ZMFLAGS) -DREL14 src-58k/BIOS_58K_14.MAC

# RC703 BIOS targets (separate source tree)
rc703-rel12: src-rc703/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL12 src-rc703/BIOS.MAC

rc703-reltfj: src-rc703/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DRELTFJ src-rc703/BIOS.MAC

rc703-rel10: src-rc703/BIOS_REL10.MAC
	$(ZMAC) $(ZMFLAGS) -DREL10 src-rc703/BIOS_REL10.MAC

rc703-rel11: src-rc703/BIOS_REL11.MAC
	$(ZMAC) $(ZMFLAGS) -DREL11 src-rc703/BIOS_REL11.MAC

# RC702E BIOS targets (modular source, two variants)
rc702e-rel201: src-rc702e/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL201 src-rc702e/BIOS.MAC
	cp zout/BIOS.hex zout/BIOS_E201.hex

rc702e-rel220: src-rc702e/BIOS.MAC
	$(ZMAC) $(ZMFLAGS) -DREL220 src-rc702e/BIOS.MAC
	cp zout/BIOS.hex zout/BIOS_E220.hex

# Verify all variants against reference binaries
verify: verify-rel20-mini verify-rel21-mini verify-rel22-mini verify-rel23-mini verify-rel23-maxi verify-rel13-mini verify-rel14-mini verify-rel14-maxi verify-rc703-rel10 verify-rc703-rel11 verify-rc703-rel12 verify-rc703-reltfj verify-rc702e-rel201 verify-rc702e-rel220 verify-summary

verify-rel20-mini: rel20-mini
	python3 verify_bios.py zout/BIOS.hex extracted_bios/cpm22_56k_rel2.0_mini.bin $(BIOS_OFFSET_56K) $(EXTREF_OFFSET_56K)

verify-rel21-mini: rel21-mini
	python3 verify_bios.py zout/BIOS.hex extracted_bios/cpm22_56k_rel2.1_mini.bin $(BIOS_OFFSET_56K) $(EXTREF_OFFSET_56K)

verify-rel22-mini: rel22-mini
	python3 verify_bios.py zout/BIOS.hex extracted_bios/cpm22_56k_rel2.2_mini.bin $(BIOS_OFFSET_56K) $(EXTREF_OFFSET_56K)

verify-rel23-mini: rel23-mini
	python3 verify_bios.py zout/BIOS.hex extracted_bios/cpm22_56k_rel2.3_mini.bin $(BIOS_OFFSET_56K) $(EXTREF_OFFSET_56K)

verify-rel23-maxi: rel23-maxi
	python3 verify_bios.py zout/BIOS.hex extracted_bios/cpm22_56k_rel2.3_maxi.bin $(BIOS_OFFSET_56K) $(EXTREF_OFFSET_56K)

# 58K verification (separate source tree, disassembly-based)
verify-rel13-mini: rel13-mini
	python3 verify_58k.py zout/BIOS_58K.hex extracted_bios/cpm22_58k_rel1.3_mini.bin

# 58K rel.1.4 verification (separate source tree, disassembly-based)
# Mini and maxi share the same 5248-byte code; maxi appends 0xE5 filler.
verify-rel14-mini: rel14-mini
	python3 verify_58k.py zout/BIOS_58K_14.hex extracted_bios/cpm22_58k_rel1.4_mini.bin

verify-rel14-maxi: rel14-maxi
	python3 verify_58k.py zout/BIOS_58K_14.hex extracted_bios/cpm22_58k_rel1.4_mini.bin

# RC703 verification (separate source tree, different binary layout)
verify-rc703-rel10: rc703-rel10
	python3 verify_rc703.py zout/BIOS_REL10.hex extracted_bios/cpm22_56k_rel1.0_rc703_maxi.bin --full

verify-rc703-rel11: rc703-rel11
	python3 verify_rc703.py zout/BIOS_REL11.hex extracted_bios/cpm22_56k_rel1.1_rc703.bin --full

verify-rc703-rel12: rc703-rel12
	python3 verify_rc703.py zout/BIOS.hex extracted_bios/cpm22_56k_rel1.2_rc703.bin --full

verify-rc703-reltfj: rc703-reltfj
	python3 verify_rc703.py zout/BIOS.hex extracted_bios/cpm22_56k_relTFj_rc703.bin --code

# RC702E verification (modular source, different ORGs)
verify-rc702e-rel201: rc702e-rel201
	python3 verify_rc702e.py zout/BIOS_E201.hex extracted_bios/cpm22_56k_rc702e_rel2.01_mini.bin --mini

verify-rc702e-rel220: rc702e-rel220
	python3 verify_rc702e.py zout/BIOS_E220.hex extracted_bios/cpm22_56k_rc702e_rel2.20_rc703.bin --qd

verify-rc702e: verify-rc702e-rel201 verify-rc702e-rel220

verify-summary:
	@echo "=== BIOS build summary ==="
	@echo "  RC700 56K: 5 byte-verified (rel.2.0-2.3 mini, rel.2.3 maxi)"
	@echo "  RC700 58K: 3 byte-verified (rel.1.3 mini, rel.1.4 mini/maxi)"
	@echo "  RC703:     4 byte-verified (rel.1.0, rel.1.1, rel.1.2 full, rel.TFj code)"
	@echo "  RC702E:    2 byte-verified (rel.2.01 mini, rel.2.20 qd)"

# ============================================================
# Extraction and disassembly targets
# ============================================================

# Build the emulator with --memdump support
emu:
	cd $(RC700) && cc -DSDL_main=main -DSDL_MAIN_HANDLED \
		-o rc700-vt100 -O3 -Wno-unused-result \
		cpu0.c cpu1.c cpu2.c cpu3.c cpu4.c cpu5.c cpu6.c cpu7.c \
		rom.c charrom.c charram.c pio.c sio.c ctc.c dma.c crt.c \
		fdc.c wdc.c ftp.c disk.c fifo.c monitor.c disasm.c \
		rob358.c rc700.c rcterm-vt100.c

# Extract RAM dumps
dumps: $(DUMPS)

rccpm22_ram.bin: $(EMU) $(IMG_RCCPM22)
	$(EMU) -memdump $@ $(IMG_RCCPM22) > /dev/null 2>$@.log

cpm_comal80_ram.bin: $(EMU) $(IMG_COMAL80)
	$(EMU) -memdump $@ $(IMG_COMAL80) > /dev/null 2>$@.log

cpm22_rel22_ram.bin: $(EMU) /tmp/cpm22_rel22.imd
	$(EMU) -memdump $@ /tmp/cpm22_rel22.imd > /dev/null 2>$@.log

/tmp/cpm22_rel22.imd: $(IMG_REL22) bin2imd.py
	python3 bin2imd.py $(IMG_REL22) $@

compas_ram.bin: $(EMU) $(IMG_COMPAS)
	$(EMU) -maxi -memdump $@ $(IMG_COMPAS) > /dev/null 2>$@.log

# Extract BIOS binaries from RAM dumps
bios: $(BIOS_BINS)

ref/rccpm22_bios.bin ref/cpm22_rel22_bios.bin ref/compas_bios.bin: extract_bios.py $(DUMPS)
	python3 extract_bios.py ref/

# Extract rel.1.4 BIOS from disk image (Track 0)
ref/rel14_bios_disk.bin: imd2raw.py $(IMG_COMPAS)
	python3 imd2raw.py $(IMG_COMPAS) ref/compas_disk_t0.bin
	python3 -c "d=open('ref/compas_disk_t0.bin','rb').read(); open('$@','wb').write(d[0x500:0x500+5632])"

# Extract rel.1.2 RC703 BIOS from raw disk image (contiguous multi-density layout)
ref/rc703_rel12_bios.bin ref/rc703_rel12_t0.bin: $(IMG_RC703R12)
	python3 -c "d=open('$(IMG_RC703R12)','rb').read(); open('ref/rc703_rel12_t0.bin','wb').write(d[:6144])"
	python3 -c "d=open('$(IMG_RC703R12)','rb').read(); b=d[0x580:0x2381]; open('ref/rc703_rel12_bios.bin','wb').write(b)"

# Disassemble
disasm: $(BIOS_ASMS)

rccpm22_bios.asm: ref/rccpm22_bios.bin syms_56k_z80dasm.sym blocks_56k.def
	z80dasm -a -l -g 0xDA00 -S syms_56k_z80dasm.sym -b blocks_56k.def \
		-o $@ $< 2>/dev/null

cpm22_rel22_bios.asm: ref/cpm22_rel22_bios.bin syms_56k_z80dasm.sym blocks_56k.def
	z80dasm -a -l -g 0xDA00 -S syms_56k_z80dasm.sym -b blocks_56k.def \
		-o $@ $< 2>/dev/null

rel14_bios.asm: ref/rel14_bios_disk.bin syms_rel14_z80dasm.sym blocks_rel14.def
	z80dasm -a -l -g 0xE200 -S syms_rel14_z80dasm.sym -b blocks_rel14.def \
		-o $@ $< 2>/dev/null
	sed -i '' '/^trailing_end:.*equ/d' $@
	python3 defb2str.py $@
	python3 portnames.py $@

# ============================================================
# Patch test: build BIOS, patch onto disk image, boot in emulator
# ============================================================
# NOTE: Requires a patched version of the rc700 emulator that supports
# -memdump (auto-exit after boot with RAM snapshot).  This patched
# emulator is not currently available, so this target will fail.

# Patch rel.2.2 BIOS onto rel.2.1 mini image — signon should change
# Patch rel.2.3 BIOS onto SW1711 maxi image — should boot identically
patch-test: rel22-mini
	cp zout/BIOS.cim /tmp/rel22_mini.cim
	$(MAKE) rel23-maxi
	cp zout/BIOS.cim /tmp/rel23_maxi.cim
	python3 patch_bios.py $(IMG_RCCPM22) /tmp/rel22_mini.cim -o /tmp/patched_mini.imd
	python3 patch_bios.py $(IMG_SW1711) /tmp/rel23_maxi.cim -o /tmp/patched_maxi.imd
	$(EMU) -memdump /tmp/patched_mini_ram.bin /tmp/patched_mini.imd > /dev/null 2>/tmp/patched_mini.log
	grep -q 'rel\. 2\.2' /tmp/patched_mini.log && echo "MINI: rel. 2.2 signon OK" || (echo "MINI: FAILED"; exit 1)
	$(EMU) -maxi -memdump /tmp/patched_maxi_ram.bin /tmp/patched_maxi.imd > /dev/null 2>/tmp/patched_maxi.log
	grep -q 'rel\. 2\.3' /tmp/patched_maxi.log && echo "MAXI: rel. 2.3 signon OK" || (echo "MAXI: FAILED"; exit 1)
	@echo "patch-test: PASS"

# ============================================================
# MAME boot test: boot all disk images and verify signon
# ============================================================

mame-test:
	bash mame_boot_test.sh

clean:
	rm -f $(DUMPS) $(BIOS_BINS) $(BIOS_ASMS) *.log /tmp/cpm22_rel22.imd
	rm -f *_auto.sym
	rm -rf zout
