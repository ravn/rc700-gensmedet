#!/usr/bin/env python3
"""Host-side reference: extract a file from an RC700/RC703 CP/M IMD exactly as
CP/M reads it, and print its size + CRC-32 + FNV-1a-32 for cross-checking
against the on-disk PROG output (ravn/z88dk#36).

Rebuilds the logical linear image from the IMD by INVERTING appmake's sector
skew (logical record L is stored at physical sector `skew[L] + first_sector`),
reads the CP/M 2.2 directory, and follows the block pointers -- 16-bit (word)
pointers when byte_size_extents=0 (rc700 5"/8" DD), 8-bit (byte) pointers
otherwise. The extracted stream is record-padded (multiple of 128 bytes) with
the 0xE5 filler, matching exactly what a CP/M sequential read returns to EOF.

Skew is applied by inverting appmake's write-side skew on the data area
(track 2 and forward). appmake itself handles skew automatically when it builds
the IMD (has_skew=1 -> skew_sector() in cpmdisk.c); on real hardware CP/M's BIOS
sectran undoes it. cpmref re-derives the inverse INDEPENDENTLY (it does not call
appmake or run CP/M) so it can catch a skew/layout bug rather than agree with
appmake by construction. The rc700 specs leave skew_track_start=0 (skew from
track 0), but the boot tracks 0/1 are zero-filled (boot_zero_tracks=2), so their
sector order is immaterial and cpmref simply concatenates them raw.

The geometry for every non-jbox RC700/RC703 format is in FORMATS below, mirrored
from z88dk src/appmake/cpm2.c so the SAME checksum program (PROG) can validate
each format later -- only the host geometry changes, not the program.

Usage:
  python3 cpmref.py <image.imd> [FILENAME] [--format NAME]
    FILENAME  default PROG.COM
    NAME      default rc700-8dd (one of the FORMATS keys)
"""
import sys, zlib

# Geometry per appmake disc_spec (src/appmake/cpm2.c). Fields we need for the
# logical linear rebuild + directory walk:
#   spt   sectors_per_track      secsz sector_size
#   sides sides                  boottracks reserved system tracks (side-tracks)
#   dirent directory_entries     bsize extent_size (block/allocation size)
#   word  True if byte_size_extents==0 (16-bit block pointers, else 8-bit)
#   fso   first_sector_offset (physical sector IDs are 1-based on MAME/real HW)
#   skew  skew_tab (len == spt)
# Derived: data_start_cyl = boottracks // sides ; dir_off = boottracks*spt*secsz.
FORMATS = {
    # 8" DS/DD, 77 cyl, 15x512 MFM500, 4:1 skew, word pointers.
    "rc700-8dd": dict(spt=15, secsz=512, sides=2, boottracks=4, dirent=128,
                      bsize=2048, word=True, fso=1,
                      skew=[0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11]),
    # 5.25" DS/DD, 36 cyl, 9x512 MFM250, 2:1 skew, word pointers.
    "rc700-5dd": dict(spt=9, secsz=512, sides=2, boottracks=4, dirent=128,
                      bsize=2048, word=True, fso=1,
                      skew=[0, 2, 4, 6, 8, 1, 3, 5, 7]),
    # 8" SS/SD (IBM 3740), 77 trk, 26x128 FM500, 6:1 skew, byte pointers.
    "rc700-8sd": dict(spt=26, secsz=128, sides=1, boottracks=2, dirent=64,
                      bsize=1024, word=False, fso=1,
                      skew=[0, 6, 12, 18, 24, 4, 10, 16, 22, 2, 8, 14, 20, 1,
                            7, 13, 19, 25, 5, 11, 17, 23, 3, 9, 15, 21]),
    # RC-703 5.25" DS/QD, 80 cyl, 10x512 MFM250, 2:1 skew, byte pointers.
    "rc703-qd":  dict(spt=10, secsz=512, sides=2, boottracks=4, dirent=256,
                      bsize=2048, word=False, fso=1,
                      skew=[0, 2, 4, 6, 8, 1, 3, 5, 7, 9]),
}
DEFAULT_FORMAT = "rc700-8dd"


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


def linear(path, fmt=DEFAULT_FORMAT):
    g = FORMATS[fmt]
    spt, secsz, sides = g["spt"], g["secsz"], g["sides"]
    skew, fso = g["skew"], g["fso"]
    data_start_cyl = g["boottracks"] // sides   # DD: 4//2 = 2  (skew from track 2)
    tr = parse_imd(path); img = bytearray(); maxc = max(c for c, h in tr)
    for cyl in range(maxc + 1):
        for head in range(sides):
            k = (cyl, head)
            if k not in tr:
                img += b'\x00' * (spt * secsz); continue
            size, secs = tr[k]
            if cyl >= data_start_cyl:  # data area (track 2+): invert skew
                for L in range(spt):
                    img += secs.get(skew[L] + fso, b'\x00' * secsz)
            else:                      # boot tracks 0/1: NO skew, raw concat
                tb = bytearray()
                for sid in sorted(secs): tb += secs[sid]
                if len(tb) < spt * secsz: tb += b'\x00' * (spt * secsz - len(tb))
                img += tb[:spt * secsz]
    return bytes(img)


def dir_off(fmt=DEFAULT_FORMAT):
    g = FORMATS[fmt]; return g["boottracks"] * g["spt"] * g["secsz"]


def read_dir(img, fmt=DEFAULT_FORMAT):
    g = FORMATS[fmt]; base = dir_off(fmt); span = g["dirent"] * 32
    return [img[o:o+32] for o in range(base, base + span, 32) if img[o] != 0xE5]


def fname(e):
    nm = bytes(b & 0x7f for b in e[1:9]).decode('latin1').rstrip()
    ex = bytes(b & 0x7f for b in e[9:12]).decode('latin1').rstrip()
    return nm + ('.' + ex if ex else '')


def extract(img, target, fmt=DEFAULT_FORMAT):
    g = FORMATS[fmt]; base = dir_off(fmt); bsize = g["bsize"]; word = g["word"]
    blocks_per_ext = 16384 // bsize            # 16 KB logical extent / block size
    ents = []
    for e in read_dir(img, fmt):
        if e[0] != 0 or fname(e).upper() != target.upper(): continue
        if word:
            blocks = [e[16 + k*2] | (e[16 + k*2 + 1] << 8) for k in range(8)]
        else:
            blocks = [e[16 + k] for k in range(16)]
        extno = (e[14] << 5) | e[12]           # (S2<<5)|EX  physical extent number
        ents.append((extno, e[15], blocks))    # (extno, record count RC, blocks)
    if not ents: raise SystemExit("not found: " + target)
    data = bytearray()
    # One directory entry can map more than one logical 16 KB extent (byte
    # pointers, 16 blocks x 2 KB = 32 KB). CP/M sets RC to the records in the
    # LAST module of the entry (128 if that module is full), so the entry's
    # total records = (n_logical_extents - 1)*128 + RC. This is pointer-width
    # independent: word entries always hold exactly one 16 KB extent.
    for extno, rc, blocks in sorted(ents):
        nz = [b for b in blocks if b != 0]
        n_ext = max(1, (len(nz) + blocks_per_ext - 1) // blocks_per_ext)
        need = ((n_ext - 1) * 128 + rc) * 128; got = 0
        for b in nz:
            off = base + b * bsize             # block 0 = start of directory
            take = min(bsize, need - got)
            data += img[off:off + take]; got += take
            if got >= need: break
    return bytes(data)


def fnv1a32(d):
    h = 2166136261
    for b in d: h ^= b; h = (h * 16777619) & 0xFFFFFFFF
    return h


if __name__ == "__main__":
    args = sys.argv[1:]
    fmt = DEFAULT_FORMAT
    if "--format" in args:
        j = args.index("--format"); fmt = args[j+1]; del args[j:j+2]
    if fmt not in FORMATS:
        raise SystemExit("unknown format %r; known: %s" % (fmt, ", ".join(FORMATS)))
    if not args:
        raise SystemExit("usage: cpmref.py <image.imd> [FILENAME] [--format NAME]\n"
                         "formats: " + ", ".join(FORMATS))
    image = args[0]
    target = args[1] if len(args) > 1 else "PROG.COM"
    img = linear(image, fmt)
    d = extract(img, target, fmt)
    print("FORMAT=%s" % fmt)
    print("FILE=%s" % target)
    print("BYTES=%08X (%d)" % (len(d), len(d)))
    print("CRC32=%08X" % (zlib.crc32(d) & 0xFFFFFFFF))
    print("FNV32=%08X" % fnv1a32(d))
