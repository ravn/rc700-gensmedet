#!/usr/bin/env python3
"""Extract raw sequential sector data from an IMD disk image.

Reads Track 0 (both sides) from an IMD file and outputs raw sector data
in sequential order. Handles RC702 8" maxi format:
  T0S0: FM, 26 sectors x 128 bytes
  T0S1: MFM, 26 sectors x 256 bytes

Also handles 5.25" mini format:
  T0S0: FM, 16 sectors x 128 bytes
  T0S1: MFM, 16 sectors x 256 bytes

Sectors are sorted by sector number to produce sequential data regardless
of physical order in the IMD file.
"""

import sys


def parse_imd(path):
    """Parse IMD file, return list of (cyl, head, sectors) tuples.

    Each sector is (sector_number, data_bytes).
    """
    data = open(path, 'rb').read()
    hdr_end = data.index(0x1a)
    pos = hdr_end + 1

    tracks = []
    while pos < len(data):
        mode = data[pos]
        cyl = data[pos + 1]
        head = data[pos + 2] & 0x3f  # bits 0-5 = head, bit 6 = has cyl map, bit 7 = has head map
        has_cyl_map = (data[pos + 2] & 0x80) != 0
        has_head_map = (data[pos + 2] & 0x40) != 0
        nsect = data[pos + 3]
        sectsize_code = data[pos + 4]
        sectsize = 128 << sectsize_code
        pos += 5

        # Sector numbering map (always present)
        secnums = list(data[pos:pos + nsect])
        pos += nsect

        # Optional cylinder map
        if has_cyl_map:
            pos += nsect

        # Optional head map
        if has_head_map:
            pos += nsect

        # Read sector data
        sectors = []
        for i in range(nsect):
            stype = data[pos]
            pos += 1
            if stype == 0x00:
                # Sector data unavailable
                sectors.append((secnums[i], bytes(sectsize)))
            elif stype == 0x01:
                # Normal data
                sectors.append((secnums[i], data[pos:pos + sectsize]))
                pos += sectsize
            elif stype == 0x02:
                # Compressed (fill byte)
                sectors.append((secnums[i], bytes([data[pos]]) * sectsize))
                pos += 1
            elif stype == 0x03:
                # Normal data, deleted mark
                sectors.append((secnums[i], data[pos:pos + sectsize]))
                pos += sectsize
            elif stype == 0x04:
                # Compressed, deleted mark
                sectors.append((secnums[i], bytes([data[pos]]) * sectsize))
                pos += 1
            elif stype == 0x05:
                # Normal data, error
                sectors.append((secnums[i], data[pos:pos + sectsize]))
                pos += sectsize
            elif stype == 0x06:
                # Compressed, error
                sectors.append((secnums[i], bytes([data[pos]]) * sectsize))
                pos += 1
            elif stype == 0x07:
                # Normal data, deleted+error
                sectors.append((secnums[i], data[pos:pos + sectsize]))
                pos += sectsize
            elif stype == 0x08:
                # Compressed, deleted+error
                sectors.append((secnums[i], bytes([data[pos]]) * sectsize))
                pos += 1
            else:
                print(f"Unknown sector type 0x{stype:02X} at offset {pos - 1}",
                      file=sys.stderr)
                sys.exit(1)

        tracks.append((cyl, head, mode, nsect, sectsize, sectors))

    return tracks


def extract_track0(imd_path, output_path):
    """Extract Track 0 (both sides) as raw sequential data."""
    tracks = parse_imd(imd_path)

    out = bytearray()
    for cyl, head, mode, nsect, sectsize, sectors in tracks:
        if cyl != 0:
            break
        # Sort sectors by sector number
        sectors.sort(key=lambda s: s[0])
        mode_str = "FM" if mode in (0x00, 0x01, 0x02) else "MFM"
        print(f"  T0S{head}: {mode_str} {nsect}x{sectsize}B "
              f"(sectors {sectors[0][0]}-{sectors[-1][0]})")
        for secnum, data in sectors:
            out.extend(data)

    with open(output_path, 'wb') as f:
        f.write(out)
    print(f"  Total: {len(out)} bytes -> {output_path}")
    return out


def extract_boot_region(imd_path, output_path, ntracks):
    """Extract the leading ntracks (all sides) as one raw boot region.

    Emits sectors in (cylinder, head, sector-ID) order -- the same order
    z88dk appmake's sector-level ``-s bootfile`` expects for the RC702
    ``rc700-8dd`` / ``rc700-5dd`` formats (its IMD writer iterates track
    outer, side inner, then sector ID).  Unlike ``extract_track0`` (which
    fishes out just Track 0 = the BIOS/cold-boot loader), this pulls the
    whole reserved system region: for the 8" DD disk that is Track 0
    (FM 26x128 + MFM 26x256) plus Track 1 (MFM 15x512 x2) = 25344 bytes.

    Sorting by (cyl, head) makes the output independent of the physical
    track order inside the IMD file.
    """
    tracks = parse_imd(imd_path)
    wanted = [t for t in tracks if t[0] < ntracks]
    wanted.sort(key=lambda t: (t[0], t[1]))  # (cyl, head)

    out = bytearray()
    for cyl, head, mode, nsect, sectsize, sectors in wanted:
        sectors = sorted(sectors, key=lambda s: s[0])
        mode_str = "FM" if mode in (0x00, 0x01, 0x02) else "MFM"
        print(f"  T{cyl}S{head}: {mode_str} {nsect}x{sectsize}B "
              f"(sectors {sectors[0][0]}-{sectors[-1][0]})")
        for secnum, data in sectors:
            out.extend(data)

    with open(output_path, 'wb') as f:
        f.write(out)
    print(f"  Total: {len(out)} bytes -> {output_path}")
    return out


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        print(f"usage: {sys.argv[0]} <image.imd> <output.bin> [ntracks]",
              file=sys.stderr)
        print("  ntracks omitted -> Track 0 only (BIOS/boot loader).",
              file=sys.stderr)
        print("  ntracks=2 -> full boot region for appmake -s bootfile "
              "(RC702 8\"/5.25\" DD).", file=sys.stderr)
        sys.exit(1)
    if len(sys.argv) == 3:
        extract_track0(sys.argv[1], sys.argv[2])
    else:
        extract_boot_region(sys.argv[1], sys.argv[2], int(sys.argv[3]))
