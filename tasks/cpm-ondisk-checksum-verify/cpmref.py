#!/usr/bin/env python3
"""Host-side reference: extract a file from an rc700-8dd IMD exactly as CP/M
reads it, and print its size + CRC-32 + FNV-1a-32 for cross-checking against
the on-disk PROG output (ravn/z88dk#36).

Rebuilds the logical linear image from the IMD by INVERTING appmake's sector
skew (logical record L is stored at physical sector SKEW[L]+1), reads the CP/M
2.2 directory at linear offset 30720, and follows the 16-bit (word) block
pointers -- which is what byte_size_extents=0 emits for the rc700 5"/8" DD
formats. The extracted stream is record-padded (multiple of 128 bytes) with the
0xE5 filler, matching exactly what a CP/M sequential read returns to EOF.

Usage: python3 cpmref.py <image.imd> [FILENAME]      (default FILENAME=PROG.COM)
"""
import sys, zlib

SPT = 15; SECSZ = 512; SS = 2; DIR_OFF = 30720; BSIZE = 2048
SKEW = [0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11]


def parse_imd(path):
    d = open(path, 'rb').read(); i = d.index(b'\x1a') + 1; tr = {}
    while i < len(d):
        mode, cyl, head, nsec, ssz = d[i], d[i+1], d[i+2], d[i+3], d[i+4]; i += 5
        smap = list(d[i:i+nsec]); i += nsec
        if head & 0x80: i += nsec   # cylinder map
        if head & 0x40: i += nsec   # head map
        size = 128 << ssz; secs = {}
        for s in range(nsec):
            typ = d[i]; i += 1
            if typ == 0:                 secs[smap[s]] = b'\x00' * size
            elif typ in (1, 3, 5, 7):    secs[smap[s]] = d[i:i+size]; i += size
            elif typ in (2, 4, 6, 8):    secs[smap[s]] = bytes([d[i]]) * size; i += 1
            else: raise ValueError("IMD sector type %d" % typ)
        tr[(cyl, head & 0x3f)] = (size, secs)
    return tr


def linear(path):
    tr = parse_imd(path); img = bytearray(); maxc = max(c for c, h in tr)
    for cyl in range(maxc + 1):
        for head in range(SS):
            k = (cyl, head)
            if k not in tr:
                img += b'\x00' * (SPT * SECSZ); continue
            size, secs = tr[k]
            if cyl >= 2:  # data area: invert skew to rebuild logical order
                for L in range(SPT):
                    img += secs.get(SKEW[L] + 1, b'\x00' * SECSZ)
            else:         # boot tracks: raw concat, not needed for file data
                tb = bytearray()
                for sid in sorted(secs): tb += secs[sid]
                if len(tb) < SPT * SECSZ: tb += b'\x00' * (SPT * SECSZ - len(tb))
                img += tb[:SPT * SECSZ]
    return bytes(img)


def read_dir(img):
    return [img[o:o+32] for o in range(DIR_OFF, DIR_OFF + BSIZE, 32)
            if img[o] != 0xE5]


def fname(e):
    nm = bytes(b & 0x7f for b in e[1:9]).decode('latin1').rstrip()
    ex = bytes(b & 0x7f for b in e[9:12]).decode('latin1').rstrip()
    return nm + ('.' + ex if ex else '')


def extract(img, target):
    exts = {}
    for e in read_dir(img):
        if e[0] != 0 or fname(e).upper() != target.upper(): continue
        blocks = [e[16 + k*2] | (e[16 + k*2 + 1] << 8) for k in range(8)]
        exts[e[12]] = (e[15], blocks)          # EX -> (record count, blocks)
    if not exts: raise SystemExit("not found: " + target)
    data = bytearray()
    for ex in sorted(exts):
        rc, blocks = exts[ex]; need = rc * 128; got = 0
        for b in blocks:
            if b == 0: continue
            off = DIR_OFF + b * BSIZE          # block 0 = start of directory
            take = min(BSIZE, need - got)
            data += img[off:off + take]; got += take
            if got >= need: break
    return bytes(data)


def fnv1a32(d):
    h = 2166136261
    for b in d: h ^= b; h = (h * 16777619) & 0xFFFFFFFF
    return h


if __name__ == "__main__":
    img = linear(sys.argv[1])
    target = sys.argv[2] if len(sys.argv) > 2 else "PROG.COM"
    d = extract(img, target)
    print("FILE=%s" % target)
    print("BYTES=%08X (%d)" % (len(d), len(d)))
    print("CRC32=%08X" % (zlib.crc32(d) & 0xFFFFFFFF))
    print("FNV32=%08X" % fnv1a32(d))
