#!/usr/bin/env python3
"""
check_preserves_regs.py — Verify that functions annotated with __preserves_regs
do not clobber any promised registers in their generated machine code for rcbios.

Usage:
    check_preserves_regs.py <bios.map> <bios_BIOS.bin> <z88dk-dis-path> [base_addr_hex]
"""

import sys
import os
import re
import subprocess

# Functions and the register components they MUST NOT modify (lowercase)
CHECKED_FUNCTIONS = {
    "_fdc_write": {
        "preserves": ["b", "d", "e", "h", "l", "de", "hl", "iy"],
        "forbidden_dest": {"b", "d", "e", "h", "l", "de", "hl", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_fdc_read": {
        "preserves": ["b", "c", "d", "e", "h", "l", "bc", "de", "hl", "iy"],
        "forbidden_dest": {"b", "c", "d", "e", "h", "l", "bc", "de", "hl", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_fdc_irq_wait": {
        "preserves": ["b", "c", "d", "e", "h", "l", "bc", "de", "hl", "iy"],
        "forbidden_dest": {"b", "c", "d", "e", "h", "l", "bc", "de", "hl", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_fdc_irq_arm": {
        "preserves": ["b", "c", "d", "e", "bc", "de", "iy"],
        "forbidden_dest": {"b", "c", "d", "e", "bc", "de", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_fdstop": {
        "preserves": ["b", "c", "d", "e", "h", "l", "bc", "de", "hl", "iy"],
        "forbidden_dest": {"b", "c", "d", "e", "h", "l", "bc", "de", "hl", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_carriage_return": {
        "preserves": ["a", "b", "c", "d", "e", "bc", "de", "iy"],
        "forbidden_dest": {"a", "b", "c", "d", "e", "bc", "de", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_goto00": {
        "preserves": ["a", "b", "c", "d", "e", "bc", "de", "iy"],
        "forbidden_dest": {"a", "b", "c", "d", "e", "bc", "de", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    },
    "_home": {
        "preserves": ["a", "b", "c", "d", "e", "bc", "de", "iy"],
        "forbidden_dest": {"a", "b", "c", "d", "e", "bc", "de", "ix", "iy", "ixh", "ixl", "iyh", "iyl"}
    }
}

def parse_map(map_path):
    syms = {}
    with open(map_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            m = re.match(r"^([a-zA-Z0-9_]+)\s+=\s+\$([0-9A-Fa-f]+)", line)
            if m:
                syms[m.group(1)] = int(m.group(2), 16)
    return syms

def get_function_range(syms, fn_name):
    if fn_name not in syms:
        return None, None
    start = syms[fn_name]
    # Find next non-local symbol address (> start)
    after = [addr for name, addr in syms.items() 
             if addr > start and not name.startswith("l_") and not name.startswith("__") and (addr - start) < 512]
    if not after:
        end = start + 64
    else:
        end = min(after)
    return start, end

def instruction_modifies(line, forbidden):
    # Normalize
    line = line.strip().lower()
    if not line or line.startswith(";"):
        return None
    
    # ex de, hl modifies de and hl
    if "ex" in line and "de,hl" in line:
        if any(r in forbidden for r in ["d", "e", "de", "h", "l", "hl"]):
            return "ex de,hl"
    if "exx" in line:
        if any(r in forbidden for r in ["b", "c", "d", "e", "h", "l"]):
            return "exx"
    if "ex" in line and "(sp),hl" in line:
        if any(r in forbidden for r in ["h", "l", "hl"]):
            return "ex (sp),hl"
            
    # Check simple dest pattern: "mnemonic dest, ..."
    m = re.match(r"^(?:ld|inc|dec|pop|add|adc|sub|sbc|and|xor|or|cp|rlc|rrc|rl|rr|sla|sra|srl)\s+([^,;]+)", line)
    if m:
        dest = m.group(1).strip()
        if dest in forbidden:
            return f"{line} (modifies {dest})"
        # If dest is 16-bit register (e.g. hl), check if h or l in forbidden
        if dest == "hl" and any(r in forbidden for r in ["h", "l", "hl"]):
            return f"{line} (modifies hl)"
        if dest == "de" and any(r in forbidden for r in ["d", "e", "de"]):
            return f"{line} (modifies de)"
        if dest == "bc" and any(r in forbidden for r in ["b", "c", "bc"]):
            return f"{line} (modifies bc)"

    return None

def main():
    if len(sys.argv) < 4:
        print("Usage: check_preserves_regs.py <mapfile> <raw_bin> <z88dk-dis> [base_addr_hex]")
        sys.exit(1)
        
    map_file = sys.argv[1]
    raw_bin = sys.argv[2]
    dis_bin = sys.argv[3]
    base_addr = sys.argv[4] if len(sys.argv) > 4 else "0xDA00"
    
    if not os.path.isfile(map_file):
        print(f"ERROR: map file not found: {map_file}")
        sys.exit(1)
    if not os.path.isfile(raw_bin):
        print(f"ERROR: raw binary not found: {raw_bin}")
        sys.exit(1)
    if not os.path.isfile(dis_bin):
        print(f"ERROR: disassembler not found: {dis_bin}")
        sys.exit(1)

    syms = parse_map(map_file)
    errors = 0

    print("=== check_preserves_regs: verifying callee-save invariants for rcbios ===")
    for fn, rules in CHECKED_FUNCTIONS.items():
        start, end = get_function_range(syms, fn)
        if start is None:
            print(f"  WARNING: {fn} not found in map, skipping")
            continue
        
        # Disassemble
        cmd = [dis_bin, "-mz80", "-o", base_addr, "-s", hex(start), "-e", hex(end), raw_bin]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            print(f"  ERROR: disassembler failed for {fn}: {res.stderr}")
            errors += 1
            continue
            
        disasm_lines = res.stdout.splitlines()
        forbidden = rules["forbidden_dest"]
        fn_violations = []
        
        for line in disasm_lines:
            # strip comment
            instr = line.split(";")[0].strip()
            v = instruction_modifies(instr, forbidden)
            if v:
                fn_violations.append(v)
                
        if fn_violations:
            print(f"  FAIL: {fn} (0x{start:04x}..0x{end:04x}) VIOLATES __preserves_regs:")
            for v in fn_violations:
                print(f"    -> {v}")
            errors += 1
        else:
            preserves_str = ", ".join(rules["preserves"])
            length = end - start
            print(f"  PASS: {fn} (0x{start:04x}..0x{end:04x}, {length} bytes) verified to preserve {preserves_str}")

    if errors > 0:
        print(f"FAIL: {errors} __preserves_regs violation(s) detected!")
        sys.exit(1)

if __name__ == "__main__":
    main()
