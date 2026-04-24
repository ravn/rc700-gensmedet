#!/usr/bin/env python3
"""Convert raw RC702/RC703 disk images to IMD format.

Supported formats (auto-detected by file size):

  RC702 mini (5.25" DD, 4 MHz FDC, 250 kbps):
    Track 0, Side 0: 16 sectors x 128 bytes (FM)
    Track 0, Side 1: 16 sectors x 256 bytes (MFM)
    Track 1+, Side 0: 9 sectors x 512 bytes (MFM)
    Track 1+, Side 1: 9 sectors x 512 bytes (MFM)

  RC702 maxi (8" DSDD, 4 MHz FDC, 500 kbps) — uniform MFM variant:
    All tracks, both sides: 15 sectors x 512 bytes (MFM)
    77 cylinders, no mixed-density Track 0 (rc702-8dd diskdef).
    File size = 77 * 2 * 15 * 512 = 1,182,720 bytes.

  RC703 mini (5.25" QD 80-track, 4 MHz FDC, 250 kbps):
    All tracks, both sides: 10 sectors x 512 bytes (MFM)
    80 cylinders, uniform format throughout

IMD mode bytes: 0=500kbps FM, 2=250kbps FM, 3=500kbps MFM, 5=250kbps MFM
IMD sector size codes: 0=128, 1=256, 2=512
"""

import sys
import struct

def write_track(out, mode, cyl, head, nsect, sectsize_code, sectors, sector_base=1):
    """Write one track in IMD format."""
    out.write(bytes([mode, cyl, head, nsect, sectsize_code]))
    # Sector numbering map
    out.write(bytes(range(sector_base, sector_base + nsect)))
    # Sector data
    for s in sectors:
        out.write(b'\x01')  # normal data record
        out.write(s)

def convert_rc702_mini(data, imdpath):
    """Convert RC702 mini (multi-density Track 0) raw image."""
    t0s0_size = 16 * 128   # 2048
    t0s1_size = 16 * 256   # 4096
    track_size = 2 * 9 * 512  # 9216 per track (both sides)

    remaining = len(data) - t0s0_size - t0s1_size
    num_data_tracks = remaining // track_size
    total_tracks = 1 + num_data_tracks
    print(f"RC702 mini: {total_tracks} tracks (track 0 + {num_data_tracks} data tracks)")

    with open(imdpath, 'wb') as out:
        header = "IMD 1.18: RC702 mini raw2imd conversion\r\n"
        out.write(header.encode('ascii'))
        out.write(b'\x1a')

        pos = 0

        # Track 0, Side 0: FM 250kbps, 16 sectors x 128 bytes
        sectors = []
        for s in range(16):
            sectors.append(data[pos:pos+128])
            pos += 128
        write_track(out, 0x02, 0, 0, 16, 0, sectors)

        # Track 0, Side 1: MFM 250kbps, 16 sectors x 256 bytes
        sectors = []
        for s in range(16):
            sectors.append(data[pos:pos+256])
            pos += 256
        write_track(out, 0x05, 0, 1, 16, 1, sectors)

        # Tracks 1-N, both sides: MFM 250kbps, 9 sectors x 512 bytes
        for cyl in range(1, total_tracks):
            for head in range(2):
                sectors = []
                for s in range(9):
                    sectors.append(data[pos:pos+512])
                    pos += 512
                write_track(out, 0x05, cyl, head, 9, 2, sectors)

        assert pos == len(data), f"pos={pos} != len={len(data)}"

    print(f"Wrote {imdpath} ({total_tracks} tracks, {total_tracks*2} track/sides)")

def convert_rc703_mini(data, imdpath):
    """Convert RC703 mini (uniform MFM 512B sectors) raw image."""
    track_size = 2 * 10 * 512  # 10240 per track (both sides)
    total_tracks = len(data) // track_size
    print(f"RC703 mini: {total_tracks} tracks x 2 sides x 10 sectors x 512 bytes")

    with open(imdpath, 'wb') as out:
        header = "IMD 1.18: RC703 mini raw2imd conversion\r\n"
        out.write(header.encode('ascii'))
        out.write(b'\x1a')

        pos = 0

        # All tracks: MFM 250kbps, 10 sectors x 512 bytes
        # RC703 uses 80-track QD drives at 300 RPM with 250 kbps data rate
        for cyl in range(total_tracks):
            for head in range(2):
                sectors = []
                for s in range(10):
                    sectors.append(data[pos:pos+512])
                    pos += 512
                write_track(out, 0x05, cyl, head, 10, 2, sectors)

        assert pos == len(data), f"pos={pos} != len={len(data)}"

    print(f"Wrote {imdpath} ({total_tracks} tracks, {total_tracks*2} track/sides)")

def convert_rc702_maxi(data, imdpath):
    """Convert RC702 maxi 8" DSDD uniform-MFM raw image.

    Matches cpmtools' rc702-8dd diskdef output — used by cpnos-rom's
    acceptance-test disk builder.  No mixed-density Track 0; all 77
    cylinders × 2 sides carry 15 × 512 B MFM at 500 kbps."""
    assert len(data) == 77 * 2 * 15 * 512, f"wrong size for rc702 maxi: {len(data)}"
    print(f"RC702 maxi 8\" DSDD: 77 cylinders x 2 sides x 15 sec x 512 B")
    with open(imdpath, 'wb') as out:
        out.write("IMD 1.18: RC702 maxi 8\" DSDD uniform MFM\r\n".encode('ascii'))
        out.write(b'\x1a')
        pos = 0
        for cyl in range(77):
            for head in range(2):
                sectors = []
                for _ in range(15):
                    sectors.append(data[pos:pos + 512])
                    pos += 512
                # mode 0x03 = 500 kbps MFM; sectsize_code 2 = 512 B
                write_track(out, 0x03, cyl, head, 15, 2, sectors)
        assert pos == len(data)
    print(f"Wrote {imdpath}")


def convert(binpath, imdpath):
    with open(binpath, 'rb') as f:
        data = f.read()

    # RC702 maxi: exact size 1,182,720 B, uniform MFM
    if len(data) == 77 * 2 * 15 * 512:
        convert_rc702_maxi(data, imdpath)
        return

    # RC703 mini: uniform 10 sectors x 512 bytes x 2 sides
    rc703_track_size = 2 * 10 * 512
    if len(data) % rc703_track_size == 0 and len(data) >= rc703_track_size * 40:
        convert_rc703_mini(data, imdpath)
        return

    # RC702 mini: multi-density Track 0
    t0s0_size = 16 * 128
    t0s1_size = 16 * 256
    rc702_track_size = 2 * 9 * 512
    remaining = len(data) - t0s0_size - t0s1_size
    if remaining > 0 and remaining % rc702_track_size == 0:
        convert_rc702_mini(data, imdpath)
        return

    # RC702 mini with incomplete last track: truncate trailing 0xE5 to track boundary
    if remaining > 0:
        excess = remaining % rc702_track_size
        if excess > 0 and all(b == 0xE5 for b in data[-excess:]):
            print(f"Note: truncating {excess} trailing 0xE5 bytes to track boundary")
            data = data[:-excess]
            convert_rc702_mini(data, imdpath)
            return

    print(f"ERROR: file size {len(data)} doesn't match any known disk geometry", file=sys.stderr)
    sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <raw.bin> <output.imd>", file=sys.stderr)
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
