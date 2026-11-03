#!/usr/bin/env python3
"""Extract the design-review screenshots from an .xcresult bundle.

The gallery UI test stores each page as an XCTAttachment named
`design-review-<slug>`. Xcode's attachment name survives into the export
manifest as `suggestedHumanReadableName` (with a `_<index>_<UUID>` suffix), so
the export is matched by that name rather than by walking the result graph —
the root object of a bundle only points at the test tree, and the attachments
live underneath it.

The script **verifies** that every requested slug was found and exported.
A partial extraction is a failure, never a success.

Usage:
    python3 tools/extract_gallery_screenshots.py <xcresult-path> <output-dir> \
        [--require slug ...]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEVELOPER_DIR = "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer"
PREFIX = "design-review-"
# Xcode appends "_<index>_<UUID>" to the suggested name.
SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f-]{36}$")


def env():
    return {"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}


def export_attachments(bundle: Path, workdir: Path) -> list[dict]:
    """Run the official attachment export and return the manifest entries."""
    result = subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments",
         "--path", str(bundle), "--output-path", str(workdir)],
        env=env(), capture_output=True, text=True)
    manifest_path = workdir / "manifest.json"
    if not manifest_path.exists():
        print(result.stdout or "", file=sys.stderr)
        print(result.stderr or "", file=sys.stderr)
        raise SystemExit(f"no manifest produced for {bundle}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    entries = []
    for suite in manifest if isinstance(manifest, list) else [manifest]:
        for attachment in suite.get("attachments", []):
            entries.append(attachment)
    return entries


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--require", action="append", default=[],
                        help="slug that MUST be present; repeat for each")
    parser.add_argument("--report", type=Path, help="write a JSON summary here")
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    if not args.bundle.exists():
        print(f"result bundle not found: {args.bundle}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="fts-attach-") as tmp:
        workdir = Path(tmp)
        entries = export_attachments(args.bundle, workdir)

        # Map slug -> exported file name, using the attachment's own name.
        by_slug: dict[str, Path] = {}
        names: dict[str, str] = {}
        for entry in entries:
            suggested = entry.get("suggestedHumanReadableName") or ""
            if not suggested.startswith(PREFIX):
                continue
            # 名称形如 "<slug>_<index>_<UUID>.png"：先去掉扩展名，再去掉序号与 UUID。
            stem = Path(suggested).stem
            slug = SUFFIX.sub("", stem)
            slug = slug[len(PREFIX):]
            exported = workdir / entry.get("exportedFileName", "")
            if not exported.exists():
                continue
            if slug in by_slug:
                continue
            by_slug[slug] = exported
            names[slug] = suggested

        exported, failed = [], []
        for slug in sorted(by_slug):
            target = args.output / f"{slug}.png"
            shutil.copy2(by_slug[slug], target)
            if target.stat().st_size > 0:
                exported.append(slug)
            else:
                failed.append(slug)

    missing_required = [s for s in args.require if s not in exported]
    not_in_bundle = [s for s in args.require if s not in by_slug]

    summary = {
        "bundle": str(args.bundle),
        "output": str(args.output),
        "attachments_in_bundle": sorted(names),
        "exported": sorted(exported),
        "export_failed": sorted(failed),
        "required": sorted(args.require),
        "required_missing": sorted(missing_required),
        "required_not_in_bundle": sorted(not_in_bundle),
    }
    if args.report:
        args.report.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"exported {len(exported)} screenshot(s) into {args.output}")
    for slug in sorted(exported):
        print(f"  {slug}.png")
    if failed:
        print(f"export failures: {', '.join(sorted(failed))}", file=sys.stderr)
    if missing_required:
        print(
            f"REQUIRED SCREENSHOTS MISSING ({len(missing_required)}): "
            f"{', '.join(sorted(missing_required))}",
            file=sys.stderr,
        )
    if not_in_bundle:
        print(
            f"NOT PRESENT IN THE BUNDLE ({len(not_in_bundle)}): "
            f"{', '.join(sorted(not_in_bundle))}",
            file=sys.stderr,
        )

    if failed or missing_required:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
