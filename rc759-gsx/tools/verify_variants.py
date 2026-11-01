#!/usr/bin/env python3
"""Freshly build RC759 variants and compare complete images to originals."""

import argparse
from contextlib import redirect_stdout
from datetime import datetime
import hashlib
from io import StringIO
import json
from pathlib import Path

from build_emu2_current import build
from compare_sys_cmd import compare


ROOT = Path(__file__).resolve().parents[1]
VARIANTS = tuple(f"{family}{console}" for family in ("h", "hd", "hm", "m", "md", "mm")
                 for console in (1, 4))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", action="store_true",
                        help="compare a fresh unmodified H1 build to every target")
    parser.add_argument("variants", nargs="*", metavar="VARIANT",
                        help="variants to rebuild (default: all twelve)")
    args = parser.parse_args()
    if any(variant not in VARIANTS for variant in args.variants):
        parser.error("variants must be one of: " + ", ".join(VARIANTS))
    work = ROOT / "scratch" / f"unified-check-{datetime.now():%Y%m%d-%H%M%S-%f}"
    work.mkdir(parents=True, exist_ok=False)
    originals = {variant: (ROOT / "bin" / f"dd759{variant}.sys").read_bytes()
                 for variant in VARIANTS}
    baseline = build() if args.baseline else None
    results = {}
    for variant in args.variants or VARIANTS:
        original = ROOT / "bin" / f"dd759{variant}.sys"
        result = {"status": "FAIL", "original_sha256":
                  hashlib.sha256(originals[variant]).hexdigest()}
        try:
            rebuilt = baseline if baseline else build(variant, unified=True)
            output = StringIO()
            with redirect_stdout(output):
                passed = compare(original, rebuilt)
            print(output.getvalue(), end="")
            (work / f"{variant}.compare.log").write_text(output.getvalue())
            result.update(
                status="PASS" if passed else "FAIL",
                rebuild_sha256=hashlib.sha256(rebuilt.read_bytes()).hexdigest(),
                rebuild=str(rebuilt.relative_to(ROOT)),
            )
        except (OSError, RuntimeError, ValueError) as error:
            result["error"] = str(error)
            print(f"{variant}: FAIL: {error}")
        results[variant] = result
    for variant, image in originals.items():
        if (ROOT / "bin" / f"dd759{variant}.sys").read_bytes() != image:
            raise RuntimeError(f"original oracle changed during verification: {variant}")
    (work / "matrix.json").write_text(json.dumps(results, indent=2) + "\n")
    print("\nVariant matrix" + (" (fresh H1 baseline):" if args.baseline else ":"))
    for variant, result in results.items():
        print(f"  {variant:4} {result['status']}")
    print(f"Evidence: {work / 'matrix.json'}")
    return 0 if all(result["status"] == "PASS" for result in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
