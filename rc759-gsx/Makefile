# Rebuild original RC759 GSX drivers through RASM-86/LINK-86 in emu2.
# Outputs and guest logs go to fresh scratch/emu2-current-* directories;
# originals/ contains immutable original SYS files, never build outputs.
# Requires Python 3 and the workspace emu2-cpm86 executable.

.DEFAULT_GOAL := all
.PHONY: all build verify help
.NOTPARALLEL:

# Omit VARIANT to build/verify all twelve; e.g. make VARIANT=hm4.
VARIANT ?=

all: build

build:
	sh tools/build.sh $(VARIANT)

verify:
	python3 tools/verify_variants.py $(VARIANT)

help:
	@printf '%s\n' \
	  'make                 Build and byte-compare all twelve variants' \
	  'make VARIANT=hm4     Build and byte-compare one variant' \
	  'make verify          Rebuild and byte-compare all twelve originals' \
	  'make verify VARIANT=hm4  Rebuild and compare one variant' \
	  'Variants: h1 h4 hd1 hd4 hm1 hm4 m1 m4 md1 md4 mm1 mm4' \
	  'Outputs/logs: fresh scratch/emu2-current-* directories' \
	  'Verification reports: scratch/unified-check-* directories'
