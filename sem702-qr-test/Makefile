# sem702-qr-test/Makefile
#
# Build one CP/M .COM that paints two QR codes of the same URL on the
# RC702 display via SEM702 sextants -- 1x scale on the left, 2x on the
# right -- so we can A/B compare scannability at different physical
# sizes in a single screenshot.  After ~10 s the .COM warm-boots back
# to CCP.
#
# Targets:
#   make            Build qrtest.com.
#   make floppy     Build .COM + inject into /tmp/sem702_qrtest.imd
#                   (copy of $(FLOPPY); $(FLOPPY) is never modified).
#   make run        Build floppy + boot rc702sem702 with autoboot lua;
#                   snapshot lands in snap/qrtest_*.png.
#   make clean      Remove asm + .com + work floppy.

PY        ?= python3
ZMAC      ?= $(CURDIR)/../zmac/bin/zmac
MAME      ?= $(CURDIR)/../../mame
CPMCP     ?= cpmcp
FLOPPY    ?= $(HOME)/Downloads/SW1711-I8.imd
WORK_IMD  ?= /tmp/sem702_qrtest.imd
URL       ?= https://github.com/ravn

ASM       := qrtest.asm
COM       := zout/qrtest.cim

.PHONY: all floppy run clean

all: $(COM)

$(ASM): gen_qrtest.py
	$(PY) gen_qrtest.py --url "$(URL)" --output $@

$(COM): $(ASM) $(ZMAC)
	$(ZMAC) -z --dri --od zout $(ASM)
	@printf '%s\n' "qrtest.com: $$(wc -c < $(COM) | tr -d ' ') bytes"

floppy: $(WORK_IMD)

$(WORK_IMD): $(COM) $(FLOPPY)
	@test -f "$(FLOPPY)" || { echo "missing FLOPPY=$(FLOPPY)"; exit 1; }
	cp "$(FLOPPY)" "$(WORK_IMD)"
	$(CPMCP) -f rc702-8dd "$(WORK_IMD)" "$(COM)" 0:QRTEST.COM
	@echo "--- floppy after injection ---"
	@cpmls -f rc702-8dd "$(WORK_IMD)" | grep -i qrtest || true

run: $(WORK_IMD)
	$(MAME)/regnecentralend rc702sem702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 35 \
	    -autoboot_script qrtest_run.lua \
	    -snapname qrtest \
	    -flop1 "$(WORK_IMD)" 2>&1 | tail -8
	@ls -1t snap/qrtest*.png 2>/dev/null | head -1

clean:
	rm -rf zout $(ASM) $(WORK_IMD)
