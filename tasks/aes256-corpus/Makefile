# AES-256 compiler-efficiency benchmark — clang vs zsdcc.
#
# Source: http://z80.eu/downloads/aes256.zip
# Original by Ilya O. Levin (literatecode.com, 2007-2009);
# CP/M-80 C compiler portability tweaks by Peter Dassow (z80.eu).
#
# Reference: DEMO.COM in this directory is 9216 B as built by Peter
# Dassow's CP/M-targeted compiler (probably HiTech or BDS — provenance
# not in zip).
#
# Verification: test_main.c sets up demo.c's known test vector, runs
# encrypt+decrypt, and writes a 35-byte result vector at 0xC000:
#   [0..15]:  ciphertext
#   [16]:     encrypt-matches-expected sentinel (1 = PASS)
#   [17..32]: decrypted plaintext
#   [33]:     decrypt-matches-original sentinel (1 = PASS)
#   [34]:     0xA5 end-of-test sentinel
#
# K&R notes:
# - aes256.c uses K&R-style function definitions throughout
#   (`uint8_t gf_alog(x) uint8_t x; { ... }`).
# - clang -std=c23 (the default) rejects these. We compile with
#   -std=c89 -Wno-deprecated-non-prototype to keep the source as
#   distributed.
# - SDCC accepts K&R natively, no flags needed.

Z88DK ?= /Users/ravn/z80/z88dk
CLANG ?= /Users/ravn/z80/llvm-z80/build-macos/bin/clang
LLDLD ?= /Users/ravn/z80/llvm-z80/build-macos/bin/ld.lld
LLVMOBJCOPY ?= /Users/ravn/z80/llvm-z80/build-macos/bin/llvm-objcopy
LLVMNM ?= /Users/ravn/z80/llvm-z80/build-macos/bin/llvm-nm
TICKS ?= $(Z88DK)/bin/z88dk-ticks

ZCC_ENV = ZCCCFG=$(Z88DK)/lib/config PATH=$(Z88DK)/bin:$$PATH
ZCC = $(ZCC_ENV) $(Z88DK)/bin/zcc

SRCS = aes256.c test_main.c

.PHONY: all clean test sizes sweep sweep_clang sweep_sdcc zsdcc clang

all: test

# Re-run BOTH compiler flag sweeps + update both tables.
# Catch regressions by `git diff *-flag-sweep.md` after a run.
# Writes:
#   sweep/results.tsv         — clang sweep machine-readable
#   sweep/results_sdcc.tsv    — sdcc sweep machine-readable
#   clang-flag-sweep.md       — clang markdown table (in git)
#   sdcc-flag-sweep.md        — sdcc  markdown table (in git)
sweep: sweep_clang sweep_sdcc

sweep_clang: clang.bin
	@bash ./flag_sweep.sh

sweep_sdcc: zsdcc.bin
	@bash ./flag_sweep_sdcc.sh

# ---------- zsdcc — match cpnos-rom production flags ----------
# (Same flag set as sccz80-oracle-corpus, including the sdcccall-1
# pair — aes256.c has no helper calls so this is safe.)
ZSDCC_FLAGS = +z80 -compiler=sdcc -clib=sdcc_iy \
              --opt-code-size -SO3 \
              -Cs"--sdcccall 1" -Cs"--disable-warning 296" \
              -Cs"--max-allocs-per-node 25000" \
              -Cs"--fomit-frame-pointer" \
              -create-app

zsdcc.bin: $(SRCS)
	$(ZCC) $(ZSDCC_FLAGS) -o zsdcc $(SRCS) 2>&1 | tail -10
	@test -f zsdcc.bin || (echo "zsdcc.bin missing"; false)

# ANSI variant: aes256_ansi.c is the K&R-to-ANSI converted source
# (with rj_sb_inv reverted to K&R to work around the clang silent
# miscompile filed as ravn/llvm-z80#159). Both compilers PASS.
zsdcc_ansi.bin: aes256_ansi.c test_main.c
	$(ZCC) $(ZSDCC_FLAGS) -o zsdcc_ansi aes256_ansi.c test_main.c 2>&1 | tail -10
	@test -f zsdcc_ansi.bin || (echo "zsdcc_ansi.bin missing"; false)

zsdcc: zsdcc.bin
zsdcc_ansi_target: zsdcc_ansi.bin

# ---------- clang ----------
# K&R prototypes survived in aes256.c; -std=c89 + Wno-deprecated keeps
# us source-faithful without modifying upstream.
CLANG_FLAGS = --target=z80 -Oz -nostdlib -ffreestanding \
              -std=c89 -Wno-deprecated-non-prototype

reset_clang.s:
	@printf '%s\n' \
	    '    .section .reset, "ax"' \
	    '    .global _start' \
	    '_start:' \
	    '    di' \
	    '    ld sp, 0xFFFE' \
	    '    call _main' \
	    '_done:' \
	    '    halt' \
	    '    jp _done' \
	    > $@

clang.ld:
	@printf '%s\n' \
	    'ENTRY(_start)' \
	    'MEMORY {' \
	    '  RAM (rwx) : ORIGIN = 0x0000, LENGTH = 0xC000' \
	    '}' \
	    'SECTIONS {' \
	    '  .text 0x0000 : { *(.reset) *(.text*) } > RAM' \
	    '  .rodata : { *(.rodata*) } > RAM' \
	    '  .data : { *(.data*) } > RAM' \
	    '  .bss : { *(.bss*) *(COMMON) } > RAM' \
	    '}' \
	    > $@

clang.elf: $(SRCS) reset_clang.s clang.ld
	$(CLANG) $(CLANG_FLAGS) -c reset_clang.s -o reset_clang.o
	$(CLANG) $(CLANG_FLAGS) -c aes256.c -o aes256_clang.o
	$(CLANG) $(CLANG_FLAGS) -c test_main.c -o test_main_clang.o
	$(LLDLD) -T clang.ld -o clang.elf reset_clang.o aes256_clang.o test_main_clang.o

clang.bin: clang.elf
	$(LLVMOBJCOPY) -O binary clang.elf clang.bin

# ANSI variant build (clang).
clang_ansi.elf: aes256_ansi.c test_main.c reset_clang.s clang.ld
	$(CLANG) $(CLANG_FLAGS) -c reset_clang.s -o reset_clang_ansi.o
	$(CLANG) $(CLANG_FLAGS) -c aes256_ansi.c -o aes256_ansi_clang.o
	$(CLANG) $(CLANG_FLAGS) -c test_main.c -o test_main_ansi_clang.o
	$(LLDLD) -T clang.ld -o clang_ansi.elf reset_clang_ansi.o aes256_ansi_clang.o test_main_ansi_clang.o

clang_ansi.bin: clang_ansi.elf
	$(LLVMOBJCOPY) -O binary clang_ansi.elf clang_ansi.bin

clang: clang.bin
clang_ansi_target: clang_ansi.bin

# ---------- Test runner ----------
# z88dk-ticks exit conditions (verified from src/ticks/ticks.c):
#   - `pc == end` (the -end <hex-pc> flag value)
#   - `st >= counter` (the -counter N flag value)
# That's all. HALT does NOT terminate ticks — the emulator faithfully
# spins waiting for IRQ. OUT (n),A goes to the iochar hook and returns.
# JP 0 re-executes the crt0. So for an accurate runtime measurement we
# MUST use -end pointing at a known post-main address per binary:
#   clang : _done in reset_clang.s, at PC 0x0007 (linker-determined,
#           extracted from clang.elf via llvm-nm — robust to source
#           changes since the reset stub instruction layout is fixed)
#   zsdcc : HALT after main return in z88dk +z80 crt0 — at PC 0x00B7
#           in current builds, extracted by scanning zsdcc.bin for
#           the byte pattern `e5 f3 e1 76` (push hl; di; pop hl; halt)
#           that uniquely identifies this site.
# Counter is a safety deadline (300M tstates) in case -end never fires.

clang.end_addr: clang.elf
	@$(LLVMNM) clang.elf | awk '$$3=="_done"{print "0x" $$1; exit}' > $@
	@test -s $@ || (echo "couldn't extract _done from clang.elf"; rm -f $@; false)

zsdcc.end_addr: zsdcc.bin
	@python3 -c "import re; d=open('zsdcc.bin','rb').read(); \
	    m=re.search(b'\\xe5\\xf3\\xe1\\x76', d); \
	    print(f'0x{m.start()+3:04X}') if m else exit(1)" > $@
	@test -s $@ || (echo "couldn't find post-main HALT pattern in zsdcc.bin"; rm -f $@; false)

clang.ram clang.tstates: clang.bin clang.end_addr
	@$(TICKS) -mz80 -end $$(cat clang.end_addr) -counter 300000000 \
	          -output clang.ram clang.bin 2>&1 | tail -1 > clang.tstates
	@printf '%-16s tstates=%s\n' clang_kr "$$(cat clang.tstates)"

zsdcc.ram zsdcc.tstates: zsdcc.bin zsdcc.end_addr
	@$(TICKS) -mz80 -end $$(cat zsdcc.end_addr) -counter 300000000 \
	          -output zsdcc.ram zsdcc.bin 2>&1 | tail -1 > zsdcc.tstates
	@printf '%-16s tstates=%s\n' zsdcc_kr "$$(cat zsdcc.tstates)"

# ANSI variant runs — separate end_addrs (clang's _done addr is
# linker-determined, same reset stub so still 0x0007; zsdcc's HALT
# pattern same crt0).
clang_ansi.end_addr: clang_ansi.elf
	@$(LLVMNM) clang_ansi.elf | awk '$$3=="_done"{print "0x" $$1; exit}' > $@
	@test -s $@ || (echo "couldn't extract _done from clang_ansi.elf"; rm -f $@; false)

zsdcc_ansi.end_addr: zsdcc_ansi.bin
	@python3 -c "import re; d=open('zsdcc_ansi.bin','rb').read(); \
	    m=re.search(b'\\xe5\\xf3\\xe1\\x76', d); \
	    print(f'0x{m.start()+3:04X}') if m else exit(1)" > $@

clang_ansi.ram clang_ansi.tstates: clang_ansi.bin clang_ansi.end_addr
	@$(TICKS) -mz80 -end $$(cat clang_ansi.end_addr) -counter 300000000 \
	          -output clang_ansi.ram clang_ansi.bin 2>&1 | tail -1 > clang_ansi.tstates
	@printf '%-16s tstates=%s\n' clang_ansi "$$(cat clang_ansi.tstates)"

zsdcc_ansi.ram zsdcc_ansi.tstates: zsdcc_ansi.bin zsdcc_ansi.end_addr
	@$(TICKS) -mz80 -end $$(cat zsdcc_ansi.end_addr) -counter 300000000 \
	          -output zsdcc_ansi.ram zsdcc_ansi.bin 2>&1 | tail -1 > zsdcc_ansi.tstates
	@printf '%-16s tstates=%s\n' zsdcc_ansi "$$(cat zsdcc_ansi.tstates)"

RAMS = zsdcc.ram clang.ram zsdcc_ansi.ram clang_ansi.ram

# Vector layout: [0..15] ciphertext, [16] enc PASS, [17..32] plaintext,
# [33] dec PASS, [34] 0xA5 end sentinel.
EXPECTED_CT  = 8e a2 b7 ca 51 67 45 bf ea fc 49 90 4b 49 60 89
EXPECTED_PT  = 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff

test: $(RAMS)
	@echo "--- AES-256 verification at 0xC000 (35 bytes) ---"
	@echo "expected         ct: $(EXPECTED_CT)  enc=01"
	@echo "expected         pt: $(EXPECTED_PT)  dec=01  end=a5"
	@for c in zsdcc clang zsdcc_ansi clang_ansi; do \
	    printf "%-16s " $$c; \
	    python3 -c "import sys; d=open('$$c.ram','rb').read(); v=d[0xC000:0xC023]; \
		print('ct:',' '.join(f'{b:02x}' for b in v[0:16]), \
		      'enc='+f'{v[16]:02x}', \
		      'dec='+f'{v[33]:02x}', \
		      'end='+f'{v[34]:02x}', \
		      '[PASS]' if v[16]==1 and v[33]==1 and v[34]==0xA5 else '[FAIL]')"; \
	done
	@echo ""
	@echo "--- 4-cell benchmark matrix (variant x compiler) ---"
	@python3 bench_table.py

# ---------- Size reporting ----------
sizes: clang.bin zsdcc.bin clang_ansi.bin zsdcc_ansi.bin
	@echo "--- Binary sizes ---"
	@for f in clang.bin clang_ansi.bin zsdcc.bin zsdcc_ansi.bin DEMO.COM; do \
	    if [ -f $$f ]; then \
		printf "%-18s %6d B\n" $$f $$(wc -c < $$f); \
	    fi; \
	done
	@echo ""
	@echo "--- aes256.c text size (clang, per variant) ---"
	@printf "%-18s " clang_kr; \
	    $(LLVMNM) --print-size --size-sort aes256_clang.o 2>/dev/null | \
	    python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t, 'bytes')"
	@printf "%-18s " clang_ansi; \
	    $(LLVMNM) --print-size --size-sort aes256_ansi_clang.o 2>/dev/null | \
	    python3 -c "import sys; t=sum(int(p[1],16) for p in (l.split() for l in sys.stdin) if len(p)>=4 and p[2] in 'tT'); print(t, 'bytes')"

clean:
	rm -f *.o *.bin *.map *.elf *.ram *.end_addr *.tstates \
	      reset_clang.s clang.ld \
	      zsdcc clang zsdcc_ansi clang_ansi \
	      *_CODE.bin *_DATA.bin *_BSS.bin \
	      aes256.c.lis test_main.c.lis aes256.lis test_main.lis \
	      aes256_ansi.c.lis aes256_ansi.lis
