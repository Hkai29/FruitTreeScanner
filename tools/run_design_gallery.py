#!/usr/bin/env python3
"""Run the native design-review gallery and collect the page screenshots.

Four passes, each with its own state, its own output directory and its own
result bundle:

  populated  — the archive holds synthetic scan fixtures (with locations), so
               the workspace, sheets, start flow and point cloud are real.
  empty      — the archive is emptied (by moving it aside, never by deleting),
               so the empty states are real.
  largetype  — the archive is populated again and the simulator runs at an
               accessibility text size, so the large-type layouts are real.
  previews   — the capture HUD and the result page, which need a device-free
               design-review preview in the simulator.

Every pass runs the UI test, which asserts that the page it is about to
capture is really on screen before taking the shot. Each pass keeps its own
screenshots so a later pass can never overwrite an earlier one, and the real
content size is always restored, including on failure.

Usage:
    python3 tools/run_design_gallery.py --simulator <UDID> --output <dir>
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEVELOPER_DIR = "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer"
BUNDLE_ID = "com.hkai29.fruitscanner"
SEEDER = REPO / "tools" / "seed_ui_review_fixtures.py"
EXTRACTOR = REPO / "tools" / "extract_gallery_screenshots.py"
TESTS = "FruitTreeScannerTests/DesignReviewGalleryTests"
CONTENT_SIZE = "accessibility-extra-large"
DEFAULT_SIZE = "medium"

PASSES = [
    {
        "name": "populated",
        "prefix": "",
        "tests": [
            f"{TESTS}/testCaptureWorkspaceTabs",
            f"{TESTS}/testCaptureToolScreens",
            f"{TESTS}/testCaptureArchiveScreens",
            f"{TESTS}/testCaptureCaptureFlows",
            f"{TESTS}/testCaptureLaunchAndCalibrationForm",
            f"{TESTS}/testCaptureEditingForms",
            f"{TESTS}/testCaptureAdaptiveLayouts",
        ],
        "required": [
            "00-launch",
            "01-workspace-orchard", "02-workspace-archive", "03-workspace-analysis",
            "04-calibration", "05-import", "06-history", "07-tag-management", "08-batch-export",
            "09-yield-report", "10-trends", "11-compare", "12-orchard-map",
            "13-settings", "14-variety", "16-help", "17-point-cloud",
            "18-start-scan", "18b-start-plot", "18c-start-season", "18d-start-tags",
            "18e-start-confirm", "19-quick-scan",
            "26-calibration-add",
            "30-point-cloud-tools", "31-point-cloud-measure",
            "15-variety-edit", "27-plot-edit", "28-tag-edit", "29-tree-tagging",
            "11b-compare-selected",
            "landscape-01-workspace-orchard", "ipad-01-workspace-orchard",
        ],
    },
    {
        "name": "empty",
        "prefix": "",
        "tests": [f"{TESTS}/testCaptureEmptyArchiveStates"],
        "required": ["24-workspace-empty", "25-archive-empty"],
    },
    {
        "name": "largetype",
        # 附件名本身已带 largetype- 前缀，合并时不再重复加。
        "prefix": "",
        "tests": [f"{TESTS}/testCaptureLargeTypeLayouts"],
        "required": [
            "largetype-01-workspace-orchard",
            "largetype-03-workspace-analysis",
        ],
    },
    {
        "name": "previews",
        "prefix": "",
        "tests": [f"{TESTS}/testCaptureDesignReviewPreviews"],
        "required": ["20-scan-hud", "21-result", "22-result-review", "23-result-no-estimate"],
    },
]


def env():
    return {"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=REPO, env=env(), **kwargs)


def simctl(*args, check=True):
    return run(["xcrun", "simctl", *args], check=check, capture_output=True, text=True)


def scans_dir(simulator: str) -> Path:
    result = simctl("get_app_container", simulator, BUNDLE_ID, "data")
    return Path(result.stdout.strip()) / "Documents" / "scans"


def source_fingerprint() -> str:
    """Hash every Swift source so a run can prove the tree did not change."""
    import hashlib
    digest = hashlib.sha256()
    for path in sorted((REPO / "FruitTreeScanner").rglob("*.swift")):
        digest.update(str(path.relative_to(REPO)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def seed(simulator: str) -> bool:
    result = run([sys.executable, str(SEEDER), "--simulator", simulator, "--trees", "8"],
                 capture_output=True, text=True)
    print((result.stdout or "").strip() or (result.stderr or "").strip())
    return result.returncode == 0


def move_aside(path: Path, tag: str) -> Path:
    """Move a directory aside under a new name. Nothing is ever deleted."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    stash = path.parent / f"{path.name}-{tag}-{stamp}"
    shutil.move(str(path), str(stash))
    return stash


def snapshot_archive(simulator: str) -> Path | None:
    """Keep the real archive untouched; work in a fresh directory."""
    directory = scans_dir(simulator)
    if not directory.exists():
        return None
    stash = move_aside(directory, "original")
    directory.mkdir(parents=True, exist_ok=True)
    print(f"real archive moved aside -> {stash.name}")
    return stash


def restore_archive(stash: Path | None) -> None:
    """Put the real archive back. The working directory is moved aside as well,
    so no synthetic fixture is ever deleted and no original is overwritten."""
    if stash is None or not stash.exists():
        return
    target = stash.parent / "scans"
    if target.exists():
        keep = move_aside(target, "synthetic")
        print(f"synthetic working archive kept -> {keep.name}")
    shutil.move(str(stash), str(target))
    print("real archive restored")


def empty_working_archive(simulator: str) -> Path | None:
    """Make the working archive empty for the empty-state pass."""
    directory = scans_dir(simulator)
    if not directory.exists():
        return None
    stash = move_aside(directory, "filled")
    directory.mkdir(parents=True, exist_ok=True)
    print(f"filled archive moved aside -> {stash.name}")
    return stash


def content_size(simulator: str) -> str:
    result = simctl("ui", simulator, "content_size", check=False)
    value = (result.stdout or "").strip()
    return value if value else "medium"


def run_tests(simulator: str, tests: list[str], bundle: Path) -> int:
    cmd = [
        "xcodebuild", "test",
        "-project", "FruitTreeScanner.xcodeproj",
        "-scheme", "FruitTreeScanner",
        "-destination", f"platform=iOS Simulator,id={simulator}",
        "-derivedDataPath", "/tmp/fts-dd",
        "-resultBundlePath", str(bundle),
    ]
    for test in tests:
        cmd += ["-only-testing", test]
    result = run(cmd, capture_output=True, text=True)
    tail = (result.stdout or "")[-2500:]
    print(tail)
    return result.returncode


def extract(bundle: Path, out: Path, required: list[str], report: Path) -> bool:
    cmd = [sys.executable, str(EXTRACTOR), str(bundle), str(out), "--report", str(report)]
    for slug in required:
        cmd += ["--require", slug]
    result = run(cmd, capture_output=True, text=True)
    print((result.stdout or "").strip())
    if result.returncode != 0:
        print((result.stderr or "").strip(), file=sys.stderr)
    return result.returncode == 0


def merge(flat: Path, pass_dir: Path, prefix: str) -> int:
    count = 0
    for source in sorted(pass_dir.glob("*.png")):
        shutil.copy2(source, flat / f"{prefix}{source.name}")
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    flat = output / "flat"
    flat.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    results_dir = output / f"results-{stamp}"
    results_dir.mkdir(parents=True, exist_ok=True)

    failures = []
    before = source_fingerprint()
    print(f"source fingerprint before gallery: {before[:16]}")

    original_size = content_size(args.simulator)
    original_archive = snapshot_archive(args.simulator)
    print(f"original content size: {original_size}")

    stash = None
    try:
        for spec in PASSES:
            name = spec["name"]
            print(f"\n=== pass: {name} ===")
            pass_dir = output / name
            pass_dir.mkdir(parents=True, exist_ok=True)

            if name == "empty":
                if not seed(args.simulator):
                    failures.append(f"{name}: seeding the archive failed")
                    continue
                stash = empty_working_archive(args.simulator)
            elif name in {"populated", "largetype"}:
                if not seed(args.simulator):
                    failures.append(f"{name}: seeding the archive failed")
                    continue

            if name == "largetype":
                simctl("ui", args.simulator, "content_size", CONTENT_SIZE)

            bundle = results_dir / f"{name}.xcresult"
            if bundle.exists():
                failures.append(f"{name}: result bundle already exists: {bundle}")
                continue

            code = run_tests(args.simulator, spec["tests"], bundle)
            if code != 0:
                failures.append(f"{name}: gallery tests failed (see {bundle})")

            report = results_dir / f"{name}-extraction.json"
            if not extract(bundle, pass_dir, spec["required"], report):
                failures.append(f"{name}: required screenshots were not all extracted")

            if name == "largetype":
                simctl("ui", args.simulator, "content_size", original_size)

            if name == "empty" and stash is not None:
                # Put the filled archive back so later passes still have fixtures.
                target = scans_dir(args.simulator)
                if target.exists():
                    move_aside(target, "emptied")
                if stash.exists():
                    shutil.move(str(stash), str(target))
                stash = None

            merge(flat, pass_dir, spec["prefix"])
    finally:
        if stash is not None:
            restore_archive(stash)
        # Always put the simulator back to the content size it had before.
        simctl("ui", args.simulator, "content_size", original_size, check=False)
        # And always put the real archive back.
        restore_archive(original_archive)

    after = source_fingerprint()
    print(f"\nsource fingerprint after gallery:  {after[:16]}")
    if before != after:
        failures.append("source changed while the gallery was running")

    summary = {
        "simulator": args.simulator,
        "output": str(output),
        "flat": str(flat),
        "results": str(results_dir),
        "source_before": before,
        "source_after": after,
        "source_stable": before == after,
        "failures": failures,
    }
    (output / f"gallery-summary-{stamp}.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print()
    if failures:
        print("GALLERY FAILURES:", file=sys.stderr)
        for item in failures:
            print(f"  - {item}", file=sys.stderr)
        return 1
    print(f"gallery screenshots in {flat}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
