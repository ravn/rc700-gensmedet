# Build CP/NOS from cpnet-z80 sources via VirtualCpm (DRI RMAC+LINK).
# Produces d/cpnos.com (4KB monolithic image).
#
# Prereqs:
#   - java on PATH
#   - /Users/ravn/z80/cpnet-z80 cloned (source + VirtualCpm.jar + vcpm tools)
#   - RMAC needs CRLF line endings (handled by the asm -> asm rule).

VCPM := java -jar /Users/ravn/z80/cpnet-z80/tools/VirtualCpm.jar
SRC  := /Users/ravn/z80/cpnet-z80/dist/src
# Local overrides for DRI sources we've replaced (RC702-specific vs
# Altos).  If src/<name>.asm exists it wins over $(SRC)/<name>.asm.
LOCAL_SRC := src

# Link addresses.  cpnos.com's CODE section is 0xC0D B but the .COM
# file on disk is record-padded to 0xC80 B (with 0x1A trailing fill);
# netboot_mpm.c loads the full 0xC80 B (records can't be partial).
# So CODE_BASE + 0xC80 must sit at or below cpnos-rom's resident BIOS
# (0xED00) to avoid corrupting it during the READ-SEQ loop.
#
# Option β (2026-04-30, post init/resident split): scratch BSS + IVT
# moved to upper RAM (0xF410..0xF6FF) so the entire 0xEB20..0xECFF
# range is now available for cpnos.com.  Max CODE_BASE = 0xED00 -
# 0xC80 = 0xE080.
#   CODE 0xE080..0xECFF   NDOS E083, end butts against resident BIOS
#                         at 0xED00 with 0 B headroom
#   DATA 0xDC80..0xE07F   NDOSRL DC80, BDOSDS DE6A (offsets shifted +0x1E0)
# TPA = 0x0100..0xDC7F = 0xDB80 = 56192 B (54.875 KB strict; reported
# via NDOSE rounding to ~56K).
# Was Phase B: CODE LDEA0 / DATA LDAA0 (TPA 55K).
# Path 3 (2026-05-01): BIOS_BASE raised 0xED00 -> 0xEE00 in cpnos-rom
# (resident moves up 256 B; upper-RAM scratch + IVT shift to stay
# below the new stack top at 0xF700).  Max CODE_BASE = 0xEE00 - 0xC80
# = 0xE180 (+0x100 vs Option β).
#   CODE 0xE180..0xEDFF   NDOS E183, end butts against resident BIOS
#                         at 0xEE00 with 0 B headroom
#   DATA 0xDD80..0xE17F   NDOSRL DD80, BDOSDS DF6A
# TPA = 0x0100..0xDD7F = 0xDC80 = 56448 B (55.125 KB strict;
# CPNOS_TPA_KB rounds to 57).
#
# Path 4 (2026-05-06): CODE_BASE shifted 0x200 down to 0xDF80 to give
# 512 B of free RAM at 0xEC00..0xEDFF for the SDCC build's larger BSS
# (libsdcc adds ~280 B vs clang's 220 B baseline).  Both compiler
# builds now share this layout — clang accepts the smaller TPA fine
# (its BSS already lives at 0xF524).
#
# Path 5 (2026-05-07): CODE_BASE shifted 0x100 further down to 0xDE80
# to give an extra 256 B of slave-side RAM at 0xEB00..0xEBFF for the
# SDCC build's page-aligned IVT slot (#29 / plan #19 step 7).  cpnos-rom
# SCRATCH_BSS org moves from 0xEC00 -> 0xEB00 in lockstep, freeing a
# fresh page boundary at 0xEB00 for `bss_ivt` while leaving bss_pio_rx
# at 0xEC00 and bss_compiler at 0xED00 unchanged (no ISR or rx-buf
# changes needed).  TPA shrinks 256 B, reported as ~54 KB.
#
# Path 6 (2026-05-08): CODE_BASE shifted 0x100 further down to 0xDD80
# to extend cpnos-rom's resident region by 256 B (lower bound 0xEE00 ->
# 0xED00).  Triggered by SDCC build hitting the 2560 B resident cap
# (couldn't fit even a 4-byte SIO-B trace probe needed for diagnosing
# the post-handoff hang under PIO-IRQ).  NIOS=0xED33 in cpnios-shim.asm
# matches the new _snios_jt = 0xED33 (= bios_boot 0xED00 + 51).  TPA
# shrinks another 256 B (~53 KB).
#   CODE 0xDD80..0xE9FF   NDOS DD83, ends 256 B earlier
#   DATA 0xD980..0xDD7F   NDOSRL D980, BDOSDS DB6A
# TPA = 0x0100..0xD97F = 0xD880 = 55424 B (54.125 KB; CPNOS_TPA_KB ~53).
CODE_BASE ?= LDD80
DATA_BASE ?= DD980

export CPMDrive_D := $(CURDIR)/d
export CPMDrive_A := $(CURDIR)/a
export CPMDefault := d:

MODULES := cpndos cpnios cpbdos

.PHONY: all clean
all: d/cpnos.com

# Named-shim override: src/cpnios-shim.asm is our thin JP-to-0xEA00
# trampoline into cpnos-rom's resident SNIOS.  RMAC+LINK still needs
# the monolith module name to be cpnios (NDOS calls `call NIOS+N*3`
# where NIOS is the label in that module), so the source file carries
# the -shim suffix but the built .asm lands in d/ as cpnios.asm.
d/cpnios.asm: $(LOCAL_SRC)/cpnios-shim.asm
	@mkdir -p d
	perl -pe 's/\r?\n/\r\n/g' $< > $@

# Local asm (our overrides) wins over upstream for any other module.
d/%.asm: $(LOCAL_SRC)/%.asm
	@mkdir -p d
	perl -pe 's/\r?\n/\r\n/g' $< > $@

d/%.asm: $(SRC)/%.asm
	@mkdir -p d
	perl -pe 's/\r?\n/\r\n/g' $< > $@

d/%.rel: d/%.asm
	cd $(CURDIR) && $(VCPM) rmac $* 2>&1 | tail -3

# Phase 2B (2026-04-26): cpnos.asm entry stub deleted.  cpnos.com now
# starts directly at NDOS+0 (cpndos's first byte = JP NDOSE).  PROM C
# (cpnos-rom/cpnos_main.c::nos_handoff) sets ZP[5..7] = JP BDOS using
# an address extracted from cpnos.sym at PROM build time, then enters
# at 0xD003 (NDOS+3 = COLDST).
#
# `cpnos=cpndos,...` is DRI LINK's explicit destination-filename
# syntax — output goes to cpnos.com regardless of which module is
# first in the input list.
d/cpnos.com: $(addsuffix .rel,$(addprefix d/,$(MODULES)))
	cd $(CURDIR) && $(VCPM) link 'cpnos=cpndos,cpnios,cpbdos[$(CODE_BASE),$(DATA_BASE)]' 2>&1 | tail -15

clean:
	rm -f d/*.rel d/*.prn d/*.sym d/*.com d/tiny*.* d/test.*
