# todsrv.com — master-side TOD responder.
# Built with z88dk (+cpm target, sccz80 frontend).

Z88DK   ?= ../../../z88dk
ZCC     ?= $(Z88DK)/bin/zcc
DISKS   ?= ../../z80pack/cpmsim/disks/library

export PATH := $(Z88DK)/bin:$(PATH)

ZCC_FLAGS = +cpm -compiler=sccz80 -create-app -O2

all: TODSRV.COM

TODSRV.COM: todsrv.c
	$(ZCC) $(ZCC_FLAGS) todsrv.c -o todsrv

DISK    ?= $(DISKS)/mpm-net2-1.dsk

install: TODSRV.COM
	@test -f $(DISK) || { echo "missing $(DISK)"; exit 1; }
	cpmrm -f ibm-3740 $(DISK) 0:TODSRV.COM 2>/dev/null || true
	cpmcp -f ibm-3740 $(DISK) TODSRV.COM 0:TODSRV.COM
	@echo "installed TODSRV.COM on $(DISK)"

clean:
	rm -f TODSRV.COM todsrv *.o *.bin *.map *.lis

.PHONY: all install clean
