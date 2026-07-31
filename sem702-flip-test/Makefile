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

COM = flip_test.com

all: $(COM)

font296.h: gen_font296.py $(ROMS)/rc702/roa296.rom
	python3 gen_font296.py $(ROMS)/rc702/roa296.rom font296.h

$(COM): flip_test.c font296.h
	$(ZCC) +cpm -o $(COM) flip_test.c

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
	rm -f $(COM) flip_test_BSS.bin font296.h $(WORKDISK)

.PHONY: all run clean
