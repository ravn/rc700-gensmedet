#!/usr/bin/env python3
"""Print the benchmark matrix from the build artifacts."""
import os
import sys


def main() -> int:
    def read_int(p):
        return int(open(p).read().strip())

    def size(p):
        return os.path.getsize(p)

    try:
        zk_ts = read_int("zsdcc.tstates")
        ck_ts = read_int("clang.tstates")
        za_ts = read_int("zsdcc_ansi.tstates")
        ca_ts = read_int("clang_ansi.tstates")
        zk_b = size("zsdcc.bin")
        ck_b = size("clang.bin")
        za_b = size("zsdcc_ansi.bin")
        ca_b = size("clang_ansi.bin")
    except FileNotFoundError as e:
        print(f"(missing artifact: {e.filename}; run `make test` first)", file=sys.stderr)
        return 1

    # clang_zcc is optional (zcc +cpm -compiler=llvmz80, -Os pipeline)
    cz_ts = read_int("clang_zcc.tstates") if os.path.exists("clang_zcc.tstates") else None
    cz_b  = size("clang_zcc.com")         if os.path.exists("clang_zcc.com")     else None

    print(
        f'{"Variant":8} {"zsdcc bin":>10} {"clang bin":>10} {"gap B":>8} {"x":>6}'
        f'   {"zsdcc ts":>11} {"clang ts":>11} {"x":>6}'
    )
    print(
        f'{"K&R":8} {zk_b:>10} {ck_b:>10} {ck_b - zk_b:>+8} {ck_b / zk_b:>5.2f}x'
        f'   {zk_ts:>11} {ck_ts:>11} {ck_ts / zk_ts:>5.2f}x'
    )
    print(
        f'{"ANSI":8} {za_b:>10} {ca_b:>10} {ca_b - za_b:>+8} {ca_b / za_b:>5.2f}x'
        f'   {za_ts:>11} {ca_ts:>11} {ca_ts / za_ts:>5.2f}x'
    )
    if cz_ts is not None:
        print(
            f'{"zcc(-Os)":8} {"n/a":>10} {cz_b:>10} {"(+CRT)":>8} {"":>6}'
            f'   {za_ts:>11} {cz_ts:>11} {cz_ts / za_ts:>5.2f}x'
        )
    print()
    print(
        f"ANSI vs K&R: clang.bin {ca_b - ck_b:+d} B ({(ca_b / ck_b - 1) * 100:+.1f}%), "
        f"zsdcc.bin {za_b - zk_b:+d} B ({(za_b / zk_b - 1) * 100:+.1f}%)"
    )
    if cz_ts is not None:
        print(
            f"clang_zcc vs clang_ansi: {cz_ts - ca_ts:+d} ts ({(cz_ts / ca_ts - 1) * 100:+.1f}%)"
            f"  [bin includes ~5 KB z88dk CRT+stdlib]"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
