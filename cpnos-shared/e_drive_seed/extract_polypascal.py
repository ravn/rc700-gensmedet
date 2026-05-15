#!/usr/bin/env python3
"""Extract files from a CP/M-2.2 5.25" RC702 mini disk in IMD form.

Tested with `/Users/ravn/Downloads/PolyPascal_v3.10.imd` (RC702E rel.2.01,
40 cyl x 2 sides; T0S0 FM 16x128, T0S1 MFM 16x256, T1+ both sides MFM 9x512).

Layout (logical):
  - 4 boot "tracks" (= 2 cylinders both sides; the BIOS, CCP, BDOS).
  - 1 directory block of 2048 B (max 64 entries).
  - 2048-B data blocks, indexed by 1-byte alloc bytes in the dir.

Sector skew on data tracks: 0,2,4,6,8,1,3,5,7 (sectors numbered 1..9).

Usage:
  extract_polypascal.py <SRC.imd> <DST_DIR>

The IMD is parsed using `rcbios/imd2raw.py`'s parse_imd().  Each track is
sorted by sector number; sectors are then de-skewed and the resulting
linear stream is walked as a CP/M filesystem.
"""
import os, sys, importlib.util

# Pull in parse_imd() from the existing rcbios helper.
spec = importlib.util.spec_from_file_location(
    "imd2raw",
    os.path.join(os.path.dirname(__file__), "..", "..", "rcbios", "imd2raw.py"))
imd2raw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imd2raw)

# Sector translate table: SKEW[logical_sector_index] = physical_sector_index.
# Reading logical_sector i means reading physical sector SKEW[i].  The disk's
# bit-cell sector ordering is logical 0..8 -> physical 0,2,4,6,8,1,3,5,7.
SKEW = [0, 2, 4, 6, 8, 1, 3, 5, 7]

DIRBLK_SIZE = 2048

def linearize(imd_path):
    """Return one big bytestring representing the disk's data area in
    logical (de-skewed) order, starting at the first data track.

    Track-0 sides are skipped (boot tracks; all-FM/256B metadata).
    From cylinder 1 onwards, both sides are 9 x 512 B MFM with the skew
    table above.  The output is what cpmtools sees as the "data area".
    """
    tracks = imd2raw.parse_imd(imd_path)
    out = bytearray()
    for (cyl, head, mode, nsect, sectsize, sectors) in tracks:
        if cyl < 2:
            continue                       # cyl 0 boot (mixed density) +
                                           # cyl 1 (CCP/BDOS); both
                                           # outside the CP/M data area.
        if sectsize != 512 or nsect != 9:
            raise SystemExit(
                f"unexpected geometry C{cyl} H{head}: nsect={nsect} sz={sectsize}")
        # Sort by physical sector number, then de-skew to logical.
        by_secnum = {sn: data for (sn, data) in sectors}
        # Sectors are 1-based in CP/M; build a logical-order list.
        # phys[i] = sector number (i+1) in physical order.
        phys = [by_secnum[i + 1] for i in range(9)]
        logical = [phys[SKEW[i]] for i in range(9)]
        for sec in logical:
            out.extend(sec)
    return bytes(out)

def parse_dir(linear):
    files = {}                              # (user, name, ext) -> {ex_lo: (rc, blocks)}
    for off in range(0, DIRBLK_SIZE, 32):
        e = linear[off:off + 32]
        if e[0] == 0xE5 or e[0] > 0x0F:
            continue
        name = e[1:9].decode('ascii', errors='replace').rstrip()
        ext  = e[9:12].decode('ascii', errors='replace').rstrip()
        if not name:
            continue
        # Clear high bits used as file attributes.
        name = ''.join(c for c in name if c.isalnum() or c in '$-_')
        ext  = ''.join(c for c in ext  if c.isalnum() or c in '$-_')
        ex_lo = e[12]
        rc    = e[15]
        alloc = [b for b in e[16:32] if b != 0]
        files.setdefault((e[0], name, ext), {})[ex_lo] = (rc, alloc)
    return files

def extract(linear, out_dir):
    files = parse_dir(linear)
    BS = 2048
    for (user, name, ext), extents in sorted(files.items()):
        out_name = f"{name}.{ext}" if ext else name
        out_path = os.path.join(out_dir, out_name)
        all_blocks = []
        last_ex   = 0
        last_rc   = 0
        for ex_lo in sorted(extents):
            rc, alloc = extents[ex_lo]
            all_blocks += alloc
            last_ex = ex_lo
            last_rc = rc
        raw = b''.join(linear[b * BS : (b + 1) * BS] for b in all_blocks)
        # File size = highest_extent_lo * 16384 + last_rc * 128.
        keep = last_ex * 16384 + last_rc * 128
        full = raw[:keep]
        with open(out_path, 'wb') as f:
            f.write(full)
        print(f"  {out_name:14s} u={user} ex={sorted(extents)} blocks={len(all_blocks)} -> {len(full)} bytes")

def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <SRC.imd> <DST_DIR>")
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    linear = linearize(src)
    extract(linear, dst)

if __name__ == '__main__':
    main()
