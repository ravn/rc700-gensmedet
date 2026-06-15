# AVR cross-target value oracle for AES corpus.
# Compiles the same aes256.c source under clang --target=avr -mmcu=atmega328p,
# links with avr-gcc + avr-libc, runs in simavr master (built from source —
# distro packages ship pre-mmcu 1.6, see ../README.md and the avr-oracle handoff).
#
# Docker invocation policy: ONE `docker run` per `make` target.  avr-gcc +
# simavr both live in the `avr-tools` image, so the linker step and the run
# step are batched in a single container invocation per target.  Compile
# (clang, host-native) is separate because clang is on the host.

CLANG    ?= /Users/ravn/z80/llvm-z80/build-macos/bin/clang
AES_SRC  := ../aes256.c
MCU      := atmega328p
HERE     := $(CURDIR)

# Docker batched-shell wrapper.  Mounts /Users/ravn/z80 at same absolute path
# so absolute paths in arguments resolve inside the container.
DOCKER_RUN := docker run --rm --platform linux/amd64 \
              -v /Users/ravn/z80:/Users/ravn/z80 \
              -v /tmp:/tmp \
              -w $(HERE) \
              avr-tools sh -c

AVR_CFLAGS := --target=avr -mmcu=$(MCU) -Os \
              -std=c89 -Wno-deprecated-non-prototype \
              -I/Users/ravn/z80/simavr/simavr/sim

all: avr_aes.elf

aes256.o: $(AES_SRC)
	$(CLANG) $(AVR_CFLAGS) -c $< -o $@

avr_main.o: avr_main.c
	$(CLANG) $(AVR_CFLAGS) -c $< -o $@

# Single docker invocation: link + report size.
avr_aes.elf: avr_main.o aes256.o
	$(DOCKER_RUN) 'avr-gcc -mmcu=$(MCU) avr_main.o aes256.o -o avr_aes.elf && avr-size avr_aes.elf'

# Single docker invocation: link-then-run (avoids a second container startup
# vs. `make all run`).  Forces relink since simavr should always see the
# latest object code.
run: avr_main.o aes256.o
	@echo "=== link + simavr (single docker run) ==="
	@$(DOCKER_RUN) \
	  'avr-gcc -mmcu=$(MCU) avr_main.o aes256.o -o avr_aes.elf && \
	   avr-size avr_aes.elf && \
	   echo "--- simavr ---" && \
	   timeout 30 simavr avr_aes.elf'

avr_gflog_cycles.o: avr_gflog_cycles.c
	$(CLANG) $(AVR_CFLAGS) -c $< -o $@

# Bug 4 unpark Phase 1: cycle measurement.  Builds + runs the gf_log harness
# through simavr in a single docker invocation.  Prints CYCLES=<8hexdigits>
# on the last line (total cycles for 256 gf_log calls).  Total runtime
# typically ~5-10 wall-clock seconds.
gf_log-cycles: avr_gflog_cycles.o aes256.o
	@echo "=== link + simavr (gf_log cycles, single docker run) ==="
	@$(DOCKER_RUN) \
	  'avr-gcc -mmcu=$(MCU) avr_gflog_cycles.o aes256.o -o avr_gflog.elf && \
	   avr-size --format=berkeley avr_gflog.elf && \
	   echo "--- gf_log function size ---" && \
	   avr-objdump -d avr_gflog.elf | awk "/<gf_log>:/{flag=1} flag{print; if (/^[0-9a-f]+ <(?!gf_log).*>:/) exit}" | head -60 && \
	   echo "--- simavr ---" && \
	   timeout 30 simavr avr_gflog.elf'

clean:
	rm -f *.o *.elf

.PHONY: all run clean gf_log-cycles
