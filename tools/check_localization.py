#!/usr/bin/env python3
"""Check that every NSLocalizedString key used in Swift code exists in the
English and Chinese Localizable.strings files.

Inline `NSLocalizedString("key", value: "…")` calls are used for strings that
are new or that a page owns locally. Every such key must still be present in
both .lproj files, otherwise the English build silently falls back to the
Chinese default.

Usage:
    python3 tools/check_localization.py [--root .]
Exit code 1 when keys are missing.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

SWIFT_KEY = re.compile(r'NSLocalizedString\(\s*"([^"]+)"')
# The codebase also uses a `localized(_:fallback:)` helper.
LOCALIZED_KEY = re.compile(r'localized\(\s*"([^"]+)"\s*,\s*fallback:\s*"((?:[^"\\]|\\.)*)"')
STRINGS_KEY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"', re.M)


def swift_keys(root: Path) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in sorted(root.rglob("*.swift")):
        if ".build" in path.parts or "DerivedData" in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for key in SWIFT_KEY.findall(text):
            found.setdefault(key, []).append(str(path.relative_to(root)))
        for match in LOCALIZED_KEY.finditer(text):
            found.setdefault(match.group(1), []).append(str(path.relative_to(root)))
    return found


def strings_keys(path: Path) -> set[str]:
    if not path.exists():
        return set()
    text = path.read_text(encoding="utf-8", errors="replace")
    return {m.group(1).replace('\\"', '"') for m in STRINGS_KEY.finditer(text)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root

    used = {k: v for k, v in swift_keys(root).items() if "\\(" not in k}
    en = strings_keys(root / "FruitTreeScanner" / "en.lproj" / "Localizable.strings")
    zh = strings_keys(root / "FruitTreeScanner" / "zh.lproj" / "Localizable.strings")

    missing_en = {k: v for k, v in used.items() if k not in en}
    missing_zh = {k: v for k, v in used.items() if k not in zh}

    report = {
        "root": str(root),
        "swift_key_count": len(used),
        "en_key_count": len(en),
        "zh_key_count": len(zh),
        "missing_in_en": {k: v[:3] for k, v in sorted(missing_en.items())},
        "missing_in_zh": {k: v[:3] for k, v in sorted(missing_zh.items())},
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if missing_en or missing_zh:
        print("\nMISSING LOCALIZATION ENTRIES", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
