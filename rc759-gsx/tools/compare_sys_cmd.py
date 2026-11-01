#!/usr/bin/env python3
"""Compare a linked CP/M-86 CMD image against an original SYS image."""

import argparse
from pathlib import Path


GROUP_NAMES = {
    1: "CODE",
    2: "DATA",
    3: "EXTRA",
    4: "STACK",
    9: "PURE CODE",
}


def parse_groups(image):
    if len(image) < 0x80:
        raise ValueError(f"file is shorter than the 128-byte CMD header: {len(image)}")

    groups = []
    image_offset = 0x80
    for index in range(8):
        desc_offset = index * 9
        group_type = image[desc_offset]
        paragraphs = int.from_bytes(image[desc_offset + 1 : desc_offset + 3], "little")
        length = paragraphs * 16
        if not group_type and not length:
            continue
        end = image_offset + length
        if end > len(image):
            raise ValueError(
                f"group {index} extends past EOF: "
                f"offset 0x{image_offset:x}, length 0x{length:x}"
            )
        groups.append(
            (
                index,
                GROUP_NAMES.get(group_type, f"TYPE {group_type:02X}"),
                image_offset,
                image[image_offset:end],
            )
        )
        image_offset = end

    return groups, image_offset


def mismatch_count(left, right):
    return sum(a != b for a, b in zip(left, right)) + abs(len(left) - len(right))


def first_differences(left, right, limit=8):
    return [
        offset
        for offset, (a, b) in enumerate(zip(left, right))
        if a != b
    ][:limit]


def report_region(name, left, right, left_offset=None, right_offset=None):
    count = mismatch_count(left, right)
    if count == 0:
        print(f"{name}: identical ({len(left)} bytes)")
        return

    print(
        f"{name}: {count} differing bytes "
        f"(original {len(left)}, rebuild {len(right)})"
    )
    offsets = first_differences(left, right)
    for offset in offsets:
        location = f"offset +0x{offset:04X}"
        if left_offset is not None and right_offset is not None:
            location += (
                f" (original file 0x{left_offset + offset:04X},"
                f" rebuild file 0x{right_offset + offset:04X})"
            )
        print(f"  first: {location}")
        break


def compare(original_path, rebuild_path):
    original = original_path.read_bytes()
    rebuild = rebuild_path.read_bytes()
    original_groups, original_trailer = parse_groups(original)
    rebuild_groups, rebuild_trailer = parse_groups(rebuild)

    print(f"Original: {original_path} ({len(original)} bytes)")
    print(f"Rebuild:  {rebuild_path} ({len(rebuild)} bytes)")
    report_region("Header", original[:0x80], rebuild[:0x80], 0, 0)

    for group_index in range(8):
        original_group = next(
            (group for group in original_groups if group[0] == group_index), None
        )
        rebuild_group = next(
            (group for group in rebuild_groups if group[0] == group_index), None
        )
        if original_group is None and rebuild_group is None:
            continue
        if original_group is None or rebuild_group is None:
            print(f"Group {group_index}: present in only one file")
            continue
        _, original_name, original_offset, original_payload = original_group
        _, rebuild_name, rebuild_offset, rebuild_payload = rebuild_group
        name = original_name
        if original_name != rebuild_name:
            name += f" (rebuild is {rebuild_name})"
        report_region(
            name,
            original_payload,
            rebuild_payload,
            original_offset,
            rebuild_offset,
        )

    report_region(
        "Relocation trailer",
        original[original_trailer:],
        rebuild[rebuild_trailer:],
        original_trailer,
        rebuild_trailer,
    )
    report_region("Whole file", original, rebuild, 0, 0)
    return original == rebuild


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path, help="original SYS image")
    parser.add_argument("rebuild", type=Path, help="RASM86/LINK86 CMD image")
    args = parser.parse_args()
    try:
        identical = compare(args.original, args.rebuild)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    return 0 if identical else 1


if __name__ == "__main__":
    raise SystemExit(main())
