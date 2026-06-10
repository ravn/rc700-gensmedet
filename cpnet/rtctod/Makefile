# rtctod.com — read host RTC via cpmsim ports 25/26 and print.
# Built with z88dk (+cpm target, sccz80 frontend).

Z88DK   ?= ../../../z88dk
ZCC     ?= $(Z88DK)/bin/zcc
DISKS   ?= ../../z80pack/cpmsim/disks/library

# zcc shells out to z88dk-z80asm; needs Z88DK/bin on PATH.
export PATH := $(Z88DK)/bin:$(PATH)

ZCC_FLAGS = +cpm -compiler=sccz80 -create-app -O2

all: RTCTOD.COM

RTCTOD.COM: rtctod.c
	$(ZCC) $(ZCC_FLAGS) rtctod.c -o rtctod
	@# z88dk +cpm -create-app emits RTCTOD.COM (uppercase by CP/M convention).

# Install onto the mpm-net2-1 boot diskette so MAME-launched MP/M can
# run it from A:.  Override DISK to target a different diskette image.
DISK    ?= $(DISKS)/mpm-net2-1.dsk

install: RTCTOD.COM
	@test -f $(DISK) || { echo "missing $(DISK)"; exit 1; }
	cpmrm -f ibm-3740 $(DISK) 0:RTCTOD.COM 2>/dev/null || true
	cpmcp -f ibm-3740 $(DISK) RTCTOD.COM 0:RTCTOD.COM
	@echo "installed RTCTOD.COM on $(DISK)"

clean:
	rm -f RTCTOD.COM rtctod *.o *.bin *.map *.lis

.PHONY: all install clean
