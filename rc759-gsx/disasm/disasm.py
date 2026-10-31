#!/usr/bin/env python3
"""CMD-aware disassembly of a GSX-86 .sys driver.

The file is a CP/M-86 .CMD/.SYS binary:
  * 128-byte header: 8 group descriptors × 9 bytes, zero-padded
  * CODE group  (type 1): 8086 code
  * DATA group  (type 2): initialized data, including GIOS jump table @ 0x100
  * EXTRA group (type 3): more data (BSS-like / lookup tables)
  * trailing: relocation records (not parsed yet)

The GIOS dispatcher at CS:0x0000 (= file 0x80) reads opcode from contrl[0]
and does CALL [BX+0x100] with DS = DATA-group segment, i.e. it looks up
a near function pointer in the DATA group at offset 0x100.

Usage: disasm.py <driver.sys> [--symbols sym.txt] > out.a86
"""
from __future__ import annotations

import sys
from pathlib import Path

from capstone import Cs, CS_ARCH_X86, CS_MODE_16

HEADER_LEN = 0x80
JUMP_TABLE_IN_DATA = 0x100   # DATA offset where the GIOS jump table lives
NUM_OPCODES = 35             # dispatcher accepts BX <= 0x22

GDOS_OPCODE_NAMES = {
    0:  'invalid',
    1:  'OPEN_WORKSTATION',
    2:  'CLOSE_WORKSTATION',
    3:  'CLEAR_WORKSTATION',
    4:  'UPDATE_WORKSTATION',
    5:  'ESCAPE',
    6:  'POLYLINE',
    7:  'POLYMARKER',
    8:  'TEXT',
    9:  'FILLED_AREA',
    10: 'CELL_ARRAY',
    11: 'GDP',
    12: 'SET_CHAR_HEIGHT',
    13: 'SET_CHAR_UP_VECTOR',
    14: 'SET_COLOR_REP',
    15: 'SET_LINETYPE',
    16: 'SET_LINE_WIDTH',
    17: 'SET_LINE_COLOR',
    18: 'SET_MARKER_TYPE',
    19: 'SET_MARKER_SCALE',
    20: 'SET_MARKER_COLOR',
    21: 'SET_TEXT_FONT',
    22: 'SET_TEXT_COLOR',
    23: 'SET_FILL_STYLE',
    24: 'SET_FILL_INDEX',
    25: 'SET_FILL_COLOR',
    26: 'INQUIRE_COLOR_REP',
    27: 'opcode_27',
    28: 'opcode_28',
    29: 'opcode_29',
    30: 'opcode_30',
    31: 'opcode_31',
    32: 'SET_WRITING_MODE',
    33: 'SET_INPUT_MODE',
    34: 'INQUIRE_INPUT_MODE',
}

GROUP_TYPES = {1: 'CODE', 2: 'DATA', 3: 'EXTRA', 4: 'STACK', 9: 'SHARED'}

# Int 28h function names from PICCOLINE Programmers Guide v2 Appendix A.
INT28_FUNCS = {
    0:  'InitGraphics(AH=1hi/2med, DS:CX=gcb)',
    1:  'ExitGraphics',
    3:  'GetNVMAddr',
    4:  'GetConfig',
    5:  'FloppyRecalibrate',
    8:  'FloppyStepIn',
    9:  'FloppyStepOut',
    10: 'FloppyWriteTrack',
    11: 'FloppyReadTrack',
    12: 'SoundOut(DL)',
    13: 'GetDiskStats',
    19: 'Get16msCounter',
    20: 'DefineAltChar(CL,DS:DX)',
    21: 'GetDisplayList',
    22: 'GetCursorPos',
    23: 'iSBX351Status',
    24: 'iSBX351Init',
    26: 'CassetteReadHeader',
    27: 'CassetteWriteHeader',
    28: 'CassetteReadData',
    29: 'CassetteWriteData',
    30: 'Mouse(CL=1init/2deinit/3status)',
    31: 'DefinePalette(DS:DX)',
    35: 'WriteStringToConsole(DL=col,DH=row,CX,DS:SI)',
    36: 'SetCursorPos(BH,BL)',
    37: 'GetAttributes',
    38: 'SetAttributes(AH)',
    39: 'UpdateScreen',
    40: 'CassetteWriteEOF',
    41: 'DPCParallel(AH=1res/2rel)',
    42: 'SharedDisk(AH=1res/2rel)',
    50: 'iSBX351Reset',
    51: 'GetFont(CX,DS:DX)',
    52: 'DefineFont(CX,DS:DX)',
    53: 'GetXIOSVersion',
}

# BDOS / CCP/M-86 functions reached via Int E0h (CL = function).
INTE0_FUNCS = {
    6:   'BDOS_DirectConsoleIO(DL)',
    141: 'CCPM_Delay(DX=ticks)',
    153: 'CCPM_GetConsoleNo',
    156: 'CCPM_GetProcessDescriptor',
}


def parse_header(data: bytes):
    groups = []  # list of (type, length_bytes, file_offset)
    file_off = HEADER_LEN
    for g in range(8):
        hdr = data[g * 9 : g * 9 + 9]
        t = hdr[0]
        if t == 0:
            continue
        length_para = int.from_bytes(hdr[1:3], 'little')
        base_para = int.from_bytes(hdr[3:5], 'little')
        min_para = int.from_bytes(hdr[5:7], 'little')
        max_para = int.from_bytes(hdr[7:9], 'little')
        length_bytes = length_para * 16
        groups.append(
            dict(
                type=t,
                name=GROUP_TYPES.get(t, f'type{t}'),
                length=length_bytes,
                base=base_para,
                min=min_para,
                max=max_para,
                file_offset=file_off,
            )
        )
        file_off += length_bytes
    return groups


def build_symbol_table(data: bytes, code: dict, data_grp: dict) -> dict[int, str]:
    """Return {code_offset: label} map derived from the jump table."""
    syms: dict[int, str] = {0: 'DISPATCHER'}
    jt_file = data_grp['file_offset'] + JUMP_TABLE_IN_DATA
    for op in range(NUM_OPCODES):
        off = jt_file + op * 2
        tgt = int.from_bytes(data[off : off + 2], 'little')
        name = GDOS_OPCODE_NAMES.get(op, f'op{op:02d}')
        existing = syms.get(tgt)
        if existing:
            syms[tgt] = f'{existing}+{name}'
        else:
            syms[tgt] = f'op{op:02d}_{name}'
    return syms


def dump_header(data: bytes, groups) -> list[str]:
    out = [
        '; ===== CP/M-86 CMD header (0x00..0x80) =====',
        '; Group descriptors (8 slots x 9 bytes):',
    ]
    for g in groups:
        out.append(
            f";   type={g['type']} ({g['name']:5s})  len={g['length']:#06x}B  "
            f"base={g['base']:#06x}para  min={g['min']:#06x}  max={g['max']:#06x}  "
            f"@file [{g['file_offset']:#06x}..{g['file_offset']+g['length']:#06x})"
        )
    # Non-zero bytes outside the group table (0x48..0x7F)
    tail_nonzero = [
        (i, b) for i, b in enumerate(data[0x48:HEADER_LEN], start=0x48) if b
    ]
    if tail_nonzero:
        out.append('; Non-zero bytes in header tail (0x48..0x7F):')
        for off, b in tail_nonzero:
            out.append(f';   {off:04x}: {b:#04x}')
    out.append('')
    return out


def dump_jump_table(data: bytes, data_grp: dict) -> list[str]:
    out = [f"; ===== GIOS jump table @ DATA:{JUMP_TABLE_IN_DATA:#06x} (file {data_grp['file_offset']+JUMP_TABLE_IN_DATA:#06x}) ====="]
    jt_file = data_grp['file_offset'] + JUMP_TABLE_IN_DATA
    for op in range(NUM_OPCODES):
        off = jt_file + op * 2
        tgt = int.from_bytes(data[off : off + 2], 'little')
        name = GDOS_OPCODE_NAMES.get(op, f'op{op:02d}')
        out.append(f';   op {op:2d} {name:22s} -> CS:{tgt:#06x}')
    out.append('')
    return out


def disassemble_code(data: bytes, code_grp: dict, syms: dict[int, str]) -> list[str]:
    """Disassemble the CODE group, labelling known function entries.

    Also annotates each `INT 0x28` / `INT 0xE0` with the XIOS/BDOS function
    name, inferred from the preceding `MOV AL, imm` / `MOV CL, imm` instruction.
    """
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    md.detail = False
    md.skipdata = True
    code = data[code_grp['file_offset'] : code_grp['file_offset'] + code_grp['length']]
    insns = list(md.disasm(code, 0))
    # First pass: build an al/cl history so we can label the INT at point of call.
    labels_for: dict[int, str] = {}
    last_al = None
    last_cl = None
    for insn in insns:
        m, op = insn.mnemonic, insn.op_str
        # Track AL / CL immediate loads.
        if m == 'mov':
            if op.startswith('al, '):
                try: last_al = int(op[4:], 0)
                except Exception: last_al = None
            elif op.startswith('cl, '):
                try: last_cl = int(op[4:], 0)
                except Exception: last_cl = None
            elif op.startswith('ax, '):
                # AH:AL — only track if whole AX fits in a byte
                try:
                    v = int(op[4:], 0)
                    last_al = v & 0xFF
                except Exception: pass
            elif op.startswith('cx, '):
                try:
                    v = int(op[4:], 0)
                    last_cl = v & 0xFF
                except Exception: pass
        elif m == 'int':
            try:
                vec = int(op, 0)
            except Exception:
                vec = None
            if vec == 0x28 and last_al is not None:
                name = INT28_FUNCS.get(last_al, f'xios_fn_{last_al}')
                labels_for[insn.address] = f'XIOS fn {last_al}: {name}'
            elif vec == 0xE0 and last_cl is not None:
                name = INTE0_FUNCS.get(last_cl, f'bdos_fn_{last_cl}')
                labels_for[insn.address] = f'BDOS/CCPM fn {last_cl}: {name}'
    out = [
        f"; ===== CODE segment (file {code_grp['file_offset']:#06x}..{code_grp['file_offset']+code_grp['length']:#06x}, "
        f"CS-relative 0x0000..{code_grp['length']:#06x}) ====="
    ]
    for insn in insns:
        if insn.address in syms:
            out.append('')
            out.append(f'; ---------- {syms[insn.address]} ----------')
        hexbytes = insn.bytes.hex()
        hint = f'    ; {labels_for[insn.address]}' if insn.address in labels_for else ''
        out.append(
            f'{insn.address:04x}:  {hexbytes:<14s}  {insn.mnemonic:<7s} {insn.op_str}{hint}'
        )
    # Warn about any symbols NOT landed on an instruction boundary (= misaligned linear sweep)
    hit = {insn.address for insn in md.disasm(code, 0)}
    missed = sorted(a for a in syms if a not in hit and a < code_grp['length'])
    if missed:
        out.append('')
        out.append('; ===== symbols that did NOT land on linear-sweep instruction boundary =====')
        for a in missed:
            out.append(f';   {a:#06x} ({syms[a]}) — need recursive disasm from this point')
    return out


def dump_data(data: bytes, data_grp: dict) -> list[str]:
    out = [
        f"; ===== DATA segment (file {data_grp['file_offset']:#06x}..{data_grp['file_offset']+data_grp['length']:#06x}) ====="
    ]
    start = data_grp['file_offset']
    for i in range(0, data_grp['length'], 16):
        off = start + i
        row = data[off : off + 16]
        hb = ' '.join(f'{b:02x}' for b in row)
        asc = ''.join(chr(b) if 32 <= b < 127 else '.' for b in row)
        out.append(f'; D{i:04x}:  {hb:<48s}  |{asc}|')
    out.append('')
    return out


def main() -> int:
    path = Path(sys.argv[1])
    data = path.read_bytes()
    groups = parse_header(data)
    code = next(g for g in groups if g['type'] == 1)
    data_grp = next(g for g in groups if g['type'] == 2)
    syms = build_symbol_table(data, code, data_grp)

    lines: list[str] = [
        f'; disassembly of {path.name} ({len(data)} bytes = {len(data):#06x})',
        '',
    ]
    lines += dump_header(data, groups)
    lines += dump_jump_table(data, data_grp)
    lines += disassemble_code(data, code, syms)
    lines += ['', '']
    lines += dump_data(data, data_grp)
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    sys.exit(main())
