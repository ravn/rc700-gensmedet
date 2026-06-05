# sem702-raster/Makefile
#
# Build one CP/M .COM that validates the SEM702 reprogramming pipeline
# (ISR sync + GPA0 + per-frame glyph rewrite) by cycling 4 glyphs through
# 4 animation patterns.  After ~10 s the .COM warm-boots back to CCP.
#
# Targets:
#   make            Build raster.com.
#   make floppy     Build .COM + inject into /tmp/sem702_raster.imd.
#   make run        Build floppy + boot rc702sem702 with autoboot lua;
#                   snapshot lands in snap/raster_*.png.
#   make clean      Remove .com + work floppy.

PY        ?= python3
ZMAC      ?= $(CURDIR)/../zmac/bin/zmac
MAME      ?= $(CURDIR)/../../mame
CPMCP     ?= cpmcp
CPMLS     ?= cpmls
FLOPPY    ?= $(HOME)/Downloads/SW1711-I8.imd
WORK_IMD  ?= /tmp/sem702_raster.imd

ASM       := raster.asm
COM       := zout/raster.cim
BENCH_ASM := bench.asm
BENCH_COM := zout/bench.cim

.PHONY: all bench floppy bench-floppy run bench-run clean

all: $(COM)

bench: $(BENCH_COM)

$(COM): $(ASM) | $(ZMAC)
	$(ZMAC) -z --dri --od zout $(ASM)
	@printf '%s\n' "raster.com: $$(wc -c < $(COM) | tr -d ' ') bytes"

$(BENCH_COM): $(BENCH_ASM) | $(ZMAC)
	$(ZMAC) -z --dri --od zout $(BENCH_ASM)
	@printf '%s\n' "bench.com: $$(wc -c < $(BENCH_COM) | tr -d ' ') bytes"

$(ZMAC):
	@echo "missing zmac at $(ZMAC); run 'make' in ../zmac first" && exit 1

floppy: $(WORK_IMD)

$(WORK_IMD): $(COM) $(FLOPPY)
	@test -f "$(FLOPPY)" || { echo "missing FLOPPY=$(FLOPPY)"; exit 1; }
	cp "$(FLOPPY)" "$(WORK_IMD)"
	$(CPMCP) -f rc702-8dd "$(WORK_IMD)" "$(COM)" 0:RASTER.COM
	@echo "--- floppy after injection ---"
	@$(CPMLS) -f rc702-8dd "$(WORK_IMD)" | grep -i raster || true

run: $(WORK_IMD)
	$(MAME)/regnecentralend rc702sem702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 25 \
	    -autoboot_script raster_run.lua \
	    -snapname raster \
	    -flop1 "$(WORK_IMD)" 2>&1 | tail -8
	@ls -1t snap/raster*.png 2>/dev/null | head -1

BENCH_WORK_IMD ?= /tmp/sem702_bench.imd

bench-floppy: $(BENCH_WORK_IMD)

$(BENCH_WORK_IMD): $(BENCH_COM) $(FLOPPY)
	@test -f "$(FLOPPY)" || { echo "missing FLOPPY=$(FLOPPY)"; exit 1; }
	cp "$(FLOPPY)" "$(BENCH_WORK_IMD)"
	$(CPMCP) -f rc702-8dd "$(BENCH_WORK_IMD)" "$(BENCH_COM)" 0:BENCH.COM
	@echo "--- floppy after injection ---"
	@$(CPMLS) -f rc702-8dd "$(BENCH_WORK_IMD)" | grep -i bench || true

bench-run: $(BENCH_WORK_IMD)
	$(MAME)/regnecentralend rc702sem702 -rompath $(MAME)/roms \
	    -nothrottle -window -skip_gameinfo \
	    -seconds_to_run 25 \
	    -autoboot_script bench_run.lua \
	    -snapname bench \
	    -flop1 "$(BENCH_WORK_IMD)" 2>&1 | tail -16
	@ls -1t snap/bench*.png 2>/dev/null | head -1

clean:
	rm -rf zout $(WORK_IMD) $(BENCH_WORK_IMD)
