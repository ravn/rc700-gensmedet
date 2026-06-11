# todget.com — slave-side FN 105 test client.

Z88DK   ?= ../../../z88dk
ZCC     ?= $(Z88DK)/bin/zcc
DISKS   ?= ../../z80pack/cpmsim/disks/library

export PATH := $(Z88DK)/bin:$(PATH)

ZCC_FLAGS = +cpm -compiler=sccz80 -create-app -O2

all: TODGET.COM

TODGET.COM: todget.c
	$(ZCC) $(ZCC_FLAGS) todget.c -o todget

# Install on mpm-net2-1.dsk (slave's A: drive via master mapping).
DISK    ?= $(DISKS)/mpm-net2-1.dsk

install: TODGET.COM
	@test -f $(DISK) || { echo "missing $(DISK)"; exit 1; }
	cpmrm -f ibm-3740 $(DISK) 0:TODGET.COM 2>/dev/null || true
	cpmcp -f ibm-3740 $(DISK) TODGET.COM 0:TODGET.COM
	@echo "installed TODGET.COM on $(DISK)"

clean:
	rm -f TODGET.COM todget *.o *.bin *.map *.lis

.PHONY: all install clean
