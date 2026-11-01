#!/usr/bin/env python3
"""Profile original H1 TEXT using Unicorn; no OS, DMA or display timing.

Run: python3 tools/benchmark_vector_text.py
Requires existing unicorn and capstone modules (install only in a venv).
Cycle estimates use the Intel-derived 80186 timing table in MAME i186.cpp;
they exclude wait states, bus contention, interrupts and XIOS execution.
"""

from collections import Counter
from pathlib import Path
import hashlib
import json
import math
import struct

from capstone import Cs, CS_ARCH_X86, CS_MODE_16
from capstone.x86 import X86_OP_MEM, X86_OP_IMM
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE, UC_HOOK_INTR
from unicorn.x86_const import (
    UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS,
    UC_X86_REG_SP, UC_X86_REG_AX,
    UC_X86_REG_CX, UC_X86_REG_DX,
)

ROOT = Path(__file__).resolve().parents[1]
CS, DS, EXTRA, CALLER, STACK, GRAPHICS = 0x1000, 0x2000, 0x3000, 0x5000, 0x6000, 0x7000
STOP = 0x100
EXPECTED_SHA = "dcbe221f5efc105c9f983f63d31327a7a39df0739d9c050a110d917dbe8eddfe"
DECODER = Cs(CS_ARCH_X86, CS_MODE_16)
DECODER.detail = True


def cycles(insn, taken=False):
    """Nominal 80186 core costs, not a hardware stopwatch."""
    op = insn.mnemonic
    operands = insn.operands
    memory = any(o.type == X86_OP_MEM for o in operands)
    immediate = bool(operands and operands[-1].type == X86_OP_IMM)
    prefix = 2 * sum(p in (0x26, 0x2e, 0x36, 0x3e) for p in insn.prefix)
    if op == "mov":
        segment = any(insn.reg_name(o.reg) in ("ds", "es", "ss", "cs")
                      for o in operands if o.type not in (X86_OP_MEM, X86_OP_IMM))
        if segment:
            cost = 11 if memory else 2
        elif immediate:
            cost = (12 if operands[0].size == 1 else 13) if memory else (
                3 if operands[0].size == 1 else 4)
        elif memory:
            cost = 9 if operands[0].type != X86_OP_MEM else 12
            if insn.opcode[0] in (0xa0, 0xa1, 0xa2, 0xa3):
                cost = 8 if operands[0].type != X86_OP_MEM else 9
        else:
            cost = 2
    elif op in ("add", "sub", "adc", "sbb", "and", "or", "xor", "cmp", "test"):
        cost = (16 if immediate and op not in ("cmp", "test") else 10) if memory else (
            4 if immediate else 3)
    elif op in ("inc", "dec"):
        cost = 15 if memory else 3
    elif op in ("neg", "not"):
        cost = 10 if memory else 3
    elif op in ("shl", "shr", "sar", "ror", "rol", "rcl", "rcr"):
        count = operands[-1]
        if count.type != X86_OP_IMM:
            raise ValueError("Variable shift must be resolved by the hook")
        cost = (15 if memory else 2) if count.imm == 1 else (
            (17 if memory else 5) + count.imm)
    elif op == "imul":
        cost = (40 if memory else 34) if operands[0].size == 2 else (31 if memory else 25)
    elif op in ("cbw", "cwde"):
        cost = 2
    elif op == "xchg":
        cost = 17 if memory else (3 if 0x90 <= insn.opcode[0] <= 0x97 else 4)
    elif op == "push":
        segment = insn.op_str in ("ds", "es", "ss", "cs")
        cost = 16 if memory else (9 if segment else 10)
    elif op == "pop":
        segment = insn.op_str in ("ds", "es", "ss", "cs")
        cost = 20 if memory else (8 if segment else 10)
    elif op == "call":
        cost = 15 if immediate else (19 if memory else 13)
    elif op == "ret":
        cost = 16
    elif op == "retf":
        cost = 22
    elif op == "jmp":
        cost = 14 if immediate else (17 if memory else 11)
    elif op == "jcxz":
        cost = 15 if taken else 5
    elif op.startswith("j"):
        cost = 13 if taken else 4
    elif op == "loop":
        cost = 16 if taken else 6
    elif op == "les":
        cost = 18
    elif op in ("lodsb", "lodsw"):
        cost = 12
    elif op in ("cld", "std"):
        cost = 2
    else:
        raise ValueError(f"Unsupported timing: {op} {insn.op_str}")
    return cost + prefix


class Driver:
    def __init__(self):
        image = (ROOT / "bin/dd759h1.sys").read_bytes()
        assert hashlib.sha256(image).hexdigest() == EXPECTED_SHA
        self.cpu = Uc(UC_ARCH_X86, UC_MODE_16)
        self.cpu.mem_map(0, 0x100000)
        code = bytearray(image[0x80:0x10c0])
        data = bytearray(image[0x10c0:0x1d00])
        for offset, segment in ((5, DS), (0x20, DS), (0x1016, EXTRA), (0x101d, DS)):
            struct.pack_into("<H", code, offset, segment)
        struct.pack_into("<H", data, 0x58d, EXTRA)
        self.cpu.mem_write(CS * 16, bytes(code))
        self.cpu.mem_write(DS * 16, bytes(data))
        self.cpu.mem_write(EXTRA * 16, image[0x1d00:0x20e0])
        self.cpu.hook_add(UC_HOOK_INTR, self.interrupt)
        self.cpu.hook_add(UC_HOOK_CODE, self.hook)
        self.profile = False
        self.pending = None
        self.count = Counter()
        self.cost = Counter()
        self.decode = {}
        self.completed = False

    def word(self, address, value):
        self.cpu.mem_write(address, struct.pack("<H", value & 0xffff))

    def interrupt(self, cpu, number, _):
        if number == 0x28 and cpu.reg_read(UC_X86_REG_AX) & 255 == 0:
            self.word(DS * 16 + 0x58d, GRAPHICS)
        else:
            raise RuntimeError(f"Unexpected interrupt {number:x}")

    def account(self, insn, offset, next_address):
        taken = next_address != CS * 16 + offset + insn.size
        region = self.region(offset)
        self.count[region] += 1
        self.cost[region] += cycles(insn, taken)
        self.count["total"] += 1
        if insn.mnemonic == "imul":
            self.count["imul"] += 1

    @staticmethod
    def region(offset):
        if 0x637 <= offset < 0x66f:
            return "transform"
        if 0x66f <= offset < 0x6d7:
            return "advance_transform"
        if 0x44a <= offset < 0x46a:
            return "pixel"
        if 0x337 <= offset < 0x44a or 0x46a <= offset < 0x492:
            return "line"
        if 0x5ae <= offset < 0x637:
            return "glyph_decode"
        if 0x305 <= offset < 0x337:
            return "segment_setup"
        return "dispatch_and_text"

    def hook(self, cpu, address, size, _):
        if self.pending is not None:
            self.account(*self.pending, address)
            self.pending = None
        if address == CALLER * 16 + STOP:
            self.completed = True
            cpu.emu_stop()
            return
        if not self.profile:
            return
        offset = address - CS * 16
        if not 0 <= offset < 0x1040:
            raise RuntimeError(f"Execution outside driver: {address:x}")
        if offset == 0x637:
            self.count["points"] += 1
        if offset == 0x44a:
            self.count["pixels"] += 1
        if address not in self.decode:
            self.decode[address] = next(DECODER.disasm(bytes(cpu.mem_read(address, size)), address))
        insn = self.decode[address]
        # Record runtime counts for CL shifts separately from fixed costs.
        if insn.mnemonic in ("shl", "shr", "sar", "ror", "rol", "rcl", "rcr") and (
                insn.operands[-1].type != X86_OP_IMM):
            memory = any(o.type == X86_OP_MEM for o in insn.operands)
            prefix = 2 * sum(p in (0x26, 0x2e, 0x36, 0x3e) for p in insn.prefix)
            self.count["total"] += 1
            region = self.region(offset)
            self.count[region] += 1
            self.cost[region] += (17 if memory else 5) + (cpu.reg_read(UC_X86_REG_CX) & 255) + prefix
        else:
            self.pending = insn, offset

    def call(self, opcode, intin, ptsin):
        base = CALLER * 16
        arrays = (0x200, 0x300, 0x500, 0x700, 0x900)
        for i, offset in enumerate(arrays):
            self.word(base + 4 * i, offset)
            self.word(base + 4 * i + 2, CALLER)
        control = [opcode, len(ptsin) // 2, 0, len(intin), 0, 0, 0, 0, 0]
        for offset, values in zip(arrays, (control, intin, ptsin, [], [])):
            self.cpu.mem_write(base + offset, b"\0" * 256)
            for i, value in enumerate(values):
                self.word(base + offset + i * 2, value)
        self.cpu.reg_write(UC_X86_REG_CS, CS)
        self.cpu.reg_write(UC_X86_REG_DS, CALLER)
        self.cpu.reg_write(UC_X86_REG_SS, STACK)
        self.cpu.reg_write(UC_X86_REG_SP, 0xff00)
        self.cpu.reg_write(UC_X86_REG_DX, 0)
        self.word(STACK * 16 + 0xff00, STOP)
        self.word(STACK * 16 + 0xff02, CALLER)
        self.completed = False
        self.cpu.emu_start(CS * 16, 0xfffff, timeout=10_000_000, count=2_000_000)
        if not self.completed:
            raise RuntimeError("Instruction/time budget exhausted")

    def bitmap(self):
        result = set()
        memory = bytes(self.cpu.mem_read(GRAPHICS * 16, 32768))
        for x in range(560):
            mask = 1 << (15 - x % 16)
            for y in range(256):
                offset = 2 * ((x // 16) * 256 + 255 - y)
                if struct.unpack_from("<H", memory, offset)[0] & mask:
                    result.add((x, y))
        return result


def run(text, scale=None, angle=None):
    driver = Driver()
    driver.call(1, [1] * 10, [])
    # Set internal transform state deliberately: isolate raster work from
    # the GSX angle/height setters' independent quantization behavior.
    if angle is not None:
        driver.word(DS * 16 + 990, round(2048 * math.sin(math.radians(angle))))
        driver.word(DS * 16 + 992, round(2048 * math.cos(math.radians(angle))))
    if scale is not None:
        driver.word(DS * 16 + 994, scale)
    driver.profile = True
    driver.call(8, list(text.encode("ascii")), [20, 50])
    pixels = driver.bitmap()
    assert pixels, "No visible output"
    return driver, pixels


def main():
    driver, actual = run("A")
    expected = {(x, y) for x in (20, 24) for y in range(50, 55)}
    expected |= {(20, 54), (21, 55), (22, 56), (23, 55), (24, 54)}
    expected |= {(x, 53) for x in range(20, 25)}
    assert actual == expected, f"Default A oracle mismatch: {actual ^ expected}"
    assert driver.count["points"] == 7 and driver.count["imul"] == 48
    control, control_pixels = run("A", 32, 0)
    assert (control_pixels, control.count, control.cost) == (actual, driver.count, driver.cost)
    print("PASS: original default A matches hand-worked pixels (7 points, 42 point IMUL + 6 advance IMUL)")
    repeated, pixels = run("AAAAAAAA", 32, 0)
    expected_repeated = {(x + 8 * i, y) for i in range(8) for x, y in expected}
    assert pixels == expected_repeated
    assert repeated.count["points"] == 56 and repeated.count["pixels"] == 8 * driver.count["pixels"]
    assert cycles(next(DECODER.disasm(b"\xf7\x2e\xec\x03", 0))) == 40
    assert cycles(next(DECODER.disasm(b"\x75\x02", 0)), False) == 4
    assert cycles(next(DECODER.disasm(b"\x75\x02", 0)), True) == 13
    print("PASS: eight A glyphs preserve 8-pixel advance; model IMUL/JNE timing controls passed")
    for scale, angle in ((32, 0), (64, 0), (128, 0), (32, 45)):
        driver, bitmap = run("ABCabc12", scale, angle)
        repeat, repeat_bitmap = run("ABCabc12", scale, angle)
        assert (repeat_bitmap, repeat.count, repeat.cost) == (bitmap, driver.count, driver.cost)
        total = sum(driver.cost.values())
        output = {
            "text": "ABCabc12", "scale": scale, "angle": angle,
            "instructions": driver.count["total"], "points": driver.count["points"],
            "plot_calls": driver.count["pixels"], "imul": driver.count["imul"],
            "nominal_cycles_model": total,
            "transform_cycle_share": round(driver.cost["transform"] / total, 3),
            "pixel_cycle_share": round(driver.cost["pixel"] / total, 3),
            "free_transform_speedup_ceiling": round(total / (total - driver.cost["transform"]), 2),
            "visible_pixels": len(bitmap),
            "cycle_shares": {key: round(value / total, 3)
                             for key, value in sorted(driver.cost.items())},
        }
        print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
