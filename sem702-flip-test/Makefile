# SEM702 flip test -- proves the MAME rc702sem702 SEM702 RAM chargen works
# end-to-end by rendering text via the SEM702 and flipping the font in place.
#
#   make         build flip_test.com
#   make run     build a disk, run rc702sem702, capture two snapshots
#
# Snapshots land in $(MAME)/snap/: sem702_A_normal.png (upright) and
# sem702_B_flipped.png (font reprogrammed flipped -> same chars upside-down).

MAME     ?= ../../mame
ROMS     ?= $(MAME)/roms
BASEDISK ?= ../autoload-in-c/test-disks/SW1711-I8.imd
DISKDEFS ?= ../rcbios/diskdefs
WORKDISK  = /tmp/sem702_flip.imd

ZCC      ?= ../../z88dk/bin/zcc
export ZCCCFG = $(abspath ../../z88dk/lib/config)
export PATH  := $(abspath ../../z88dk/bin):$(PATH)
LLVMZ80EXE   ?= $(abspath ../../llvm-z80/build-macos/bin/clang)

COM = flip_test.com
CHKCOM   = chk_test.com
CHKDISK  = /tmp/sem702_chk.imd
ROMBIN   = /tmp/ROA296.BIN
ROMBIN2  = /tmp/ROA327.BIN

all: $(COM)

font296.h: gen_font296.py $(ROMS)/rc702/roa296.rom
	python3 gen_font296.py $(ROMS)/rc702/roa296.rom font296.h

$(COM): flip_test.c font296.h
	LLVMZ80EXE=$(LLVMZ80EXE) $(ZCC) +cpm -subtype=rc700 -compiler=llvmz80 -o $(COM) flip_test.c

$(WORKDISK): $(COM)
	cp $(BASEDISK) $(WORKDISK)
	cpmcp -f rc702-8dd $(WORKDISK) $(COM) 0:FLIP.COM

run: $(WORKDISK)
	cd $(MAME) && rm -f snap/sem702_A_normal.png snap/sem702_B_flipped.png && \
	./mame rc702sem702 -rompath roms -flop1 $(WORKDISK) \
	  -window -nothrottle -skip_gameinfo -seconds_to_run 90 \
	  -autoboot_script $(abspath flip_test.lua)
	@echo "Snapshots: $(MAME)/snap/sem702_A_normal.png (upright), sem702_B_flipped.png (flipped)"

clean:
	rm -f $(COM) flip_test_BSS.bin $(CHKCOM) chk_test_BSS.bin font296.h $(WORKDISK) $(CHKDISK) $(ROMBIN) $(ROMBIN2)

# ---- SEM702 chargen validation (checkerboard, then ROA296 from a file) ----
# Phase A: all glyphs = 1px checkerboard.  Phase B: ROA296.BIN read at runtime
# and loaded per glyph.  Two screenshots under $(MAME)/snap/.
$(CHKCOM): chk_test.c
	LLVMZ80EXE=$(LLVMZ80EXE) $(ZCC) +cpm -subtype=rc700 -compiler=llvmz80 -o $(CHKCOM) chk_test.c

$(CHKDISK): $(CHKCOM) $(ROMS)/rc702/roa296.rom $(ROMS)/rc702/roa327.rom
	cp $(BASEDISK) $(CHKDISK)
	cpmcp -f rc702-8dd $(CHKDISK) $(CHKCOM) 0:CHK.COM
	cp $(ROMS)/rc702/roa296.rom $(ROMBIN)
	cpmcp -f rc702-8dd $(CHKDISK) $(ROMBIN) 0:ROA296.BIN
	cp $(ROMS)/rc702/roa327.rom $(ROMBIN2)
	cpmcp -f rc702-8dd $(CHKDISK) $(ROMBIN2) 0:ROA327.BIN

chk: $(CHKDISK)
	cd $(MAME) && rm -f snap/sem702_A_checkerboard.png snap/sem702_B_roa296.png \
	  snap/sem702_C_flipped.png snap/sem702_D_roa327.png && \
	./mame rc702sem702 -rompath roms -flop1 $(CHKDISK) \
	  -window -nothrottle -skip_gameinfo -seconds_to_run 120 \
	  -autoboot_script $(abspath chk_test.lua)
	@echo "Snapshots: $(MAME)/snap/sem702_{A_checkerboard,B_roa296,C_flipped,D_roa327}.png"

.PHONY: all run chk clean
