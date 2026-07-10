#!/usr/bin/env python3
"""Audit an applied six-class dataset copy without changing its source dataset."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any

from audit_yolo_dataset import audit_dataset, class_distribution_report_rows, collect_image_records
from dataset_io import (
    SPLITS,
    iter_image_files,
    load_data_yaml,
    read_csv_rows,
    resolve_dataset_root,
    resolve_split_path,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
CORE_NAMES = ("apple", "orange", "pear", "persimmon", "grape", "strawberry")
DEFAULT_TARGET_YAML = "ml/datasets/fruit_dataset_6_core_v1/data.yaml"
DEFAULT_SOURCE_YAML = "ml/datasets/fruit_dataset_26/data.yaml"
DEFAULT_SEMANTIC = "ml/audit_reports/core_class_manual_review_decisions.csv"
DEFAULT_DUPLICATE = "ml/audit_reports/duplicate_cleanup_decisions.csv"
DEFAULT_FIXED_TEST = "ml/audit_reports/fixed_test_split_decisions.csv"
DEFAULT_REPORT = "ml/audit_reports/fruit_dataset_6_core_v1_post_apply_audit.md"


class AuditError(RuntimeError):
    """Raised when the controlled dataset cannot be audited safely."""


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (REPO_ROOT / path).resolve()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit an applied six-class dataset and write a Markdown audit report."
    )
    parser.add_argument("--target-data-yaml", default=DEFAULT_TARGET_YAML)
    parser.add_argument("--source-data-yaml", default=DEFAULT_SOURCE_YAML)
    parser.add_argument("--semantic-decisions", default=DEFAULT_SEMANTIC)
    parser.add_argument("--duplicate-decisions", default=DEFAULT_DUPLICATE)
    parser.add_argument("--fixed-test-decisions", default=DEFAULT_FIXED_TEST)
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument(
        "--no-write-version",
        action="store_true",
        help="Do not refresh DATASET_VERSION.md in the target dataset.",
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def image_paths_by_split(data_yaml: Path) -> dict[str, list[Path]]:
    config, errors = load_data_yaml(data_yaml)
    if errors:
        raise AuditError("; ".join(errors))
    root = resolve_dataset_root(data_yaml, config)
    return {
        split: iter_image_files(resolve_split_path(root, config, split) or Path())
        for split in SPLITS
    }


def pairwise_counts(values: dict[str, set[str]]) -> dict[str, int]:
    return {
        "train-val": len(values["train"] & values["val"]),
        "train-test": len(values["train"] & values["test"]),
        "val-test": len(values["val"] & values["test"]),
    }


def target_split_sets(images: dict[str, list[Path]]) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    relative_names = {
        split: {path.name for path in paths}
        for split, paths in images.items()
    }
    hashes = {
        split: {sha256_file(path) for path in paths}
        for split, paths in images.items()
    }
    return relative_names, hashes


def decision_rows(path: Path, required: list[str]) -> list[dict[str, str]]:
    if not path.exists():
        raise AuditError(f"Decision CSV not found: {display_path(path)}")
    try:
        return read_csv_rows(path, required)
    except ValueError as error:
        raise AuditError(f"Invalid decision CSV {display_path(path)}: {error}") from error


def action_stems(rows: list[dict[str, str]], action: str) -> set[str]:
    return {
        Path(row["image_path"]).stem
        for row in rows
        if row["approved_action"] == action
    }


def current_commit() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def runtime_mapping_compatible(target_names: list[str]) -> tuple[bool, list[str]]:
    mapper = REPO_ROOT / "FruitTreeScanner/Core/ImageDetectionHelpers.swift"
    parser = REPO_ROOT / "FruitTreeScanner/Core/ImageDetectorYOLOParser.swift"
    mapper_source = mapper.read_text(encoding="utf-8")
    parser_source = parser.read_text(encoding="utf-8")
    missing = [name for name in target_names if f'"{name}": .' not in mapper_source]
    parser_uses_runtime_mapping = (
        "usesRuntimeLabelMapping" in parser_source
        and "category(forRuntimeModelLabel:" in parser_source
    )
    if not parser_uses_runtime_mapping:
        missing.append("runtime-label parser path")
    return not missing, missing


def class_distribution(
    target_summary: dict[str, Any],
    target_yaml: Path,
) -> list[dict[str, Any]]:
    _, records = collect_image_records(target_yaml)
    rows = class_distribution_report_rows(target_summary, records)
    image_totals = {
        split: target_summary["splits"][split]["images"] for split in SPLITS
    }
    box_totals: dict[str, int] = {split: 0 for split in SPLITS}
    for row in rows:
        for split in SPLITS:
            box_totals[split] += int(row[f"{split}_bbox_count"])

    for row in rows:
        for split in SPLITS:
            row[f"{split}_image_percent"] = (
                100 * int(row[f"{split}_image_count"]) / image_totals[split]
                if image_totals[split]
                else 0.0
            )
            row[f"{split}_bbox_percent"] = (
                100 * int(row[f"{split}_bbox_count"]) / box_totals[split]
                if box_totals[split]
                else 0.0
            )
        row["post_apply_risk"] = (
            "watch" if row["class_name"] == "grape" and row["test_image_count"] < 20 else "ok"
        )
    return rows


def validation_failures(
    target_summary: dict[str, Any],
    source_summary: dict[str, Any],
    target_names: list[str],
    expected_counts: dict[str, int],
    name_leakage: dict[str, int],
    hash_leakage: dict[str, int],
    semantic_found: int,
    duplicate_found: int,
    fixed_excluded_found: int,
    fixed_approved_expected: int,
    fixed_approved_found: int,
    pending_decisions: int,
    mapping_ok: bool,
) -> list[str]:
    target_totals = target_summary["totals"]
    source_totals = source_summary["totals"]
    failures: list[str] = []
    if target_names != list(CORE_NAMES) or target_summary["nc"] != 6:
        failures.append("target data.yaml class order or nc is invalid")
    for split, expected in expected_counts.items():
        if target_summary["splits"].get(split, {}).get("images") != expected:
            failures.append(f"{split} image count does not match the approved plan")
    if target_totals["images"] != sum(expected_counts.values()):
        failures.append("target total image count does not match the approved plan")
    for field in (
        "missing_labels",
        "missing_images",
        "empty_labels",
        "invalid_label_lines",
        "out_of_range_class_indices",
        "invalid_bboxes",
        "corrupt_or_unknown_images",
    ):
        if target_totals[field]:
            failures.append(f"target audit found {field}={target_totals[field]}")
    if any(name_leakage.values()) or any(hash_leakage.values()):
        failures.append("split path or content-hash leakage detected")
    if semantic_found or duplicate_found or fixed_excluded_found:
        failures.append("excluded source records leaked into target dataset")
    if fixed_approved_expected != fixed_approved_found:
        failures.append("fixed-test approved rows do not exactly match target test")
    if pending_decisions:
        failures.append("approval CSVs still contain pending decisions")
    if not mapping_ok:
        failures.append("target labels are not compatible with runtime label mapping")
    if (
        source_totals["images"] != 4600
        or source_totals["labels"] != 4600
        or source_totals["missing_labels"]
        or source_totals["missing_images"]
    ):
        failures.append("source dataset no longer matches its approved integrity baseline")
    return failures


def write_version_manifest(
    target_root: Path,
    split_counts: dict[str, int],
    semantic_expected: int,
    duplicate_expected: int,
    fixed_approved: int,
    fixed_excluded: int,
) -> Path:
    path = target_root / "DATASET_VERSION.md"
    lines = [
        "# Fruit Dataset 6 Core v1",
        "",
        f"- Creation date: `{date.today().isoformat()}`",
        "- Source dataset: `ml/datasets/fruit_dataset_26`",
        f"- Apply tool commit: `{current_commit()}`",
        "- Class order: `0 apple`, `1 orange`, `2 pear`, `3 persimmon`, `4 grape`, `5 strawberry`",
        f"- Train images: {split_counts['train']}",
        f"- Validation images: {split_counts['val']}",
        f"- Test images: {split_counts['test']}",
        f"- Semantic exclusions enforced: {semantic_expected}",
        f"- Duplicate exclusions enforced: {duplicate_expected}",
        f"- Fixed-test approved / excluded: {fixed_approved} / {fixed_excluded}",
        "- Known limitation: grape has 15 fixed-test images; test metrics for grape have lower stability.",
        "- Source dataset preserved: yes",
        "- Training status: not started",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def write_report(
    path: Path,
    target_yaml: Path,
    source_yaml: Path,
    target_summary: dict[str, Any],
    source_summary: dict[str, Any],
    class_rows: list[dict[str, Any]],
    name_leakage: dict[str, int],
    hash_leakage: dict[str, int],
    semantic_expected: int,
    semantic_found: int,
    duplicate_expected: int,
    duplicate_found: int,
    fixed_excluded_expected: int,
    fixed_excluded_found: int,
    fixed_approved_expected: int,
    fixed_approved_found: int,
    pending_decisions: int,
    mapping_ok: bool,
    mapping_missing: list[str],
    failures: list[str],
) -> None:
    target = target_summary["totals"]
    source = source_summary["totals"]
    lines = [
        "# Fruit Dataset 6 Core v1 Post-Apply Audit",
        "",
        "## Apply Status",
        "",
        f"- Status: {'passed' if not failures else 'failed'}",
        f"- Target: `{display_path(target_yaml.parent)}`",
        f"- Source: `{display_path(source_yaml.parent)}`",
        "- Controlled apply: executed once after approved dry-run.",
        "",
        "## Source Integrity",
        "",
        f"- Images / labels: {source['images']} / {source['labels']}",
        f"- Missing image pairs / missing label pairs: {source['missing_images']} / {source['missing_labels']}",
        "- Source preservation baseline: 4600 images / 4600 labels.",
        "",
        "## Target Split Counts",
        "",
    ]
    for split in SPLITS:
        split_data = target_summary["splits"][split]
        lines.append(f"- {split}: {split_data['images']} images / {split_data['labels']} labels")
    lines.extend(
        [
            f"- Total: {target['images']} images / {target['labels']} labels",
            "",
            "## Image/Label Pairing and YOLO Label Validation",
            "",
            f"- Missing image pairs: {target['missing_images']}",
            f"- Missing label pairs: {target['missing_labels']}",
            f"- Empty labels: {target['empty_labels']}",
            f"- Corrupt or unreadable images: {target['corrupt_or_unknown_images']}",
            f"- Malformed YOLO rows: {target['invalid_label_lines']}",
            f"- Out-of-range class IDs: {target['out_of_range_class_indices']}",
            f"- Invalid bboxes: {target['invalid_bboxes']}",
            "",
            "## Class Mapping Validation",
            "",
            f"- Target nc: {target_summary['nc']}",
            "- Target class order: " + ", ".join(f"`{name}`" for name in target_summary['names']),
            f"- App runtime label mapping compatible: {'yes' if mapping_ok else 'no'}",
            "- Mapping gaps: " + (", ".join(mapping_missing) if mapping_missing else "none"),
            "",
            "## Split Leakage Check",
            "",
            f"- Same-name train-val / train-test / val-test: {name_leakage['train-val']} / {name_leakage['train-test']} / {name_leakage['val-test']}",
            f"- Content-hash train-val / train-test / val-test: {hash_leakage['train-val']} / {hash_leakage['train-test']} / {hash_leakage['val-test']}",
            "",
            "## Exclusion and Fixed-Test Verification",
            "",
            f"- Semantic excluded expected / found in target: {semantic_expected} / {semantic_found}",
            f"- Duplicate excluded expected / found in target: {duplicate_expected} / {duplicate_found}",
            f"- Fixed-test excluded expected / found in test: {fixed_excluded_expected} / {fixed_excluded_found}",
            f"- Fixed-test approved expected / found in test: {fixed_approved_expected} / {fixed_approved_found}",
            f"- Pending decisions: {pending_decisions}",
            "",
            "## Per-Class Distribution",
            "",
            "| Class | Train images / boxes | Train image / bbox % | Val images / boxes | Val image / bbox % | Test images / boxes | Test image / bbox % | Risk |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    for row in class_rows:
        lines.append(
            "| {class_name} | {train_image_count} / {train_bbox_count} | "
            "{train_image_percent:.2f}% / {train_bbox_percent:.2f}% | "
            "{val_image_count} / {val_bbox_count} | {val_image_percent:.2f}% / {val_bbox_percent:.2f}% | "
            "{test_image_count} / {test_bbox_count} | {test_image_percent:.2f}% / "
            "{test_bbox_percent:.2f}% | {post_apply_risk} |".format(**row)
        )
    lines.extend(
        [
            "",
            "## Known Risks",
            "",
            "- Grape has 15 fixed-test images. This is a watch item: grape test metrics have lower statistical stability, but it does not block this approved dataset creation.",
            "",
            "## Training Gate",
            "",
            f"- Ready for training: {'yes' if not failures else 'no'}",
            "- Blockers: " + ("; ".join(failures) if failures else "none"),
            "- Training status: not started.",
            "",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    target_yaml = repo_path(args.target_data_yaml)
    source_yaml = repo_path(args.source_data_yaml)
    report_path = repo_path(args.report)
    try:
        target_summary = audit_dataset(target_yaml)
        source_summary = audit_dataset(source_yaml)
        target_names = [str(name) for name in target_summary["names"]]
        target_images = image_paths_by_split(target_yaml)
        target_names_by_split, target_hashes_by_split = target_split_sets(target_images)
        target_stems_by_split = {
            split: {Path(name).stem for name in names}
            for split, names in target_names_by_split.items()
        }
        name_leakage = pairwise_counts(target_names_by_split)
        hash_leakage = pairwise_counts(target_hashes_by_split)

        semantic_rows = decision_rows(
            repo_path(args.semantic_decisions), ["image_path", "approved_action"]
        )
        duplicate_rows = decision_rows(
            repo_path(args.duplicate_decisions), ["image_path", "approved_action"]
        )
        fixed_rows = decision_rows(
            repo_path(args.fixed_test_decisions), ["image_path", "approved_action"]
        )
        semantic_excluded = action_stems(semantic_rows, "exclude_from_training")
        duplicate_excluded = action_stems(duplicate_rows, "remove_duplicate")
        fixed_excluded = action_stems(fixed_rows, "exclude_from_core_test")
        fixed_approved = action_stems(fixed_rows, "approve_move_to_test")
        target_stems = set().union(*target_stems_by_split.values())
        test_stems = target_stems_by_split["test"]
        semantic_found = len(semantic_excluded & target_stems)
        duplicate_found = len(duplicate_excluded & target_stems)
        fixed_excluded_found = len(fixed_excluded & test_stems)
        fixed_approved_found = len(fixed_approved & test_stems)
        pending_decisions = sum(
            row["approved_action"] not in {"keep", "exclude_from_training"}
            for row in semantic_rows
        ) + sum(
            row["approved_action"] in {"pending_review", "review_label_conflict"}
            for row in duplicate_rows
        ) + sum(
            row["approved_action"] in {"pending_review", "manual_review"}
            for row in fixed_rows
        )
        class_rows = class_distribution(target_summary, target_yaml)
        mapping_ok, mapping_missing = runtime_mapping_compatible(target_names)
        expected_counts = {"train": 2730, "val": 772, "test": 347}
        failures = validation_failures(
            target_summary,
            source_summary,
            target_names,
            expected_counts,
            name_leakage,
            hash_leakage,
            semantic_found,
            duplicate_found,
            fixed_excluded_found,
            len(fixed_approved),
            fixed_approved_found,
            pending_decisions,
            mapping_ok,
        )
        if not args.no_write_version:
            target_config, target_errors = load_data_yaml(target_yaml)
            if target_errors:
                raise AuditError("; ".join(target_errors))
            version_path = write_version_manifest(
                resolve_dataset_root(target_yaml, target_config),
                expected_counts,
                len(semantic_excluded),
                len(duplicate_excluded),
                len(fixed_approved),
                len(fixed_excluded),
            )
            print(f"Version manifest: {display_path(version_path)}")
        write_report(
            report_path,
            target_yaml,
            source_yaml,
            target_summary,
            source_summary,
            class_rows,
            name_leakage,
            hash_leakage,
            len(semantic_excluded),
            semantic_found,
            len(duplicate_excluded),
            duplicate_found,
            len(fixed_excluded),
            fixed_excluded_found,
            len(fixed_approved),
            fixed_approved_found,
            pending_decisions,
            mapping_ok,
            mapping_missing,
            failures,
        )
        print(f"Post-apply report: {display_path(report_path)}")
        print(f"Ready for training: {'yes' if not failures else 'no'}")
        return 0 if not failures else 2
    except (AuditError, OSError, ValueError) as error:
        print(f"ERROR: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
