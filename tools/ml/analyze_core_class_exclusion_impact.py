#!/usr/bin/env python3
"""Estimate six-class dataset impact from approved semantic exclusions.

This tool is read-only with respect to source data and decision CSVs. It
generates a Markdown report only and never invokes dataset apply or training.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path

from dataset_io import (
    class_count_matches_names,
    load_data_yaml,
    parse_yolo_row,
    read_csv_rows,
    read_yolo_label_file,
)


CORE_CLASS_NAMES = (
    "apple",
    "orange",
    "pear",
    "persimmon",
    "grape",
    "strawberry",
)
DECISION_FIELDS = [
    "image_path",
    "label_path",
    "class_names",
    "risk_level",
    "issue_type",
    "recommended_action",
    "approved_action",
    "notes",
]
GATE_FIELDS = [
    "image_path",
    "label_path",
    "class_names",
    "contains_core_class",
    "contains_only_non_core_classes",
    "appears_in_fixed_test_plan",
    "risk_level",
    "issue_type",
    "recommended_action",
    "current_approved_action",
    "blocks_six_class_apply",
    "block_reason",
]
FIXED_TEST_FIELDS = [
    "image_path",
    "label_path",
    "current_split",
    "planned_split",
    "class_names",
    "bbox_count",
    "recommended_action",
    "approved_action",
    "notes",
]
SPLIT_DISTRIBUTION_FIELDS = [
    "class_id",
    "class_name",
    "before_train_images",
    "before_train_boxes",
    "before_val_images",
    "before_val_boxes",
    "planned_test_images",
    "planned_test_boxes",
    "after_train_images",
    "after_train_boxes",
    "risk_note",
]
CLASS_DISTRIBUTION_FIELDS = [
    "class_id",
    "class_name",
    "train_image_count",
    "train_bbox_count",
    "val_image_count",
    "val_bbox_count",
    "test_image_count",
    "test_bbox_count",
    "total_image_count",
    "total_bbox_count",
    "train_val_ratio_note",
    "risk_level",
    "recommended_action",
]
DUPLICATE_FIELDS = [
    "duplicate_group_id",
    "image_path",
    "label_path",
    "class_names",
    "bbox_count",
    "label_fingerprint",
    "recommended_action",
    "approved_action",
    "human_review_required",
    "notes",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a read-only six-class semantic-exclusion impact summary."
    )
    parser.add_argument(
        "--decisions",
        default="ml/audit_reports/core_class_manual_review_decisions.csv",
        help="Six-class manual decision CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--gate",
        default="ml/audit_reports/core_class_review_gate.csv",
        help="Six-class gate CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--gate-summary",
        default="ml/audit_reports/core_class_review_gate_summary.md",
        help="Six-class gate summary. Default: %(default)s",
    )
    parser.add_argument(
        "--fixed-test-decisions",
        default="ml/audit_reports/fixed_test_split_decisions.csv",
        help="Fixed test decision CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--test-split-distribution",
        default="ml/audit_reports/test_split_class_distribution.csv",
        help="Test-split distribution CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--class-distribution",
        default="ml/audit_reports/class_distribution_report.csv",
        help="Source class-distribution CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--duplicate-decisions",
        default="ml/audit_reports/duplicate_cleanup_decisions.csv",
        help="Duplicate decision CSV read for remaining blockers. Default: %(default)s",
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Source YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--output",
        default="ml/audit_reports/core_class_exclusion_impact_summary.md",
        help="Markdown output. Default: %(default)s",
    )
    return parser.parse_args()


def image_split(image_path: str) -> str:
    marker = "/images/"
    if marker not in image_path:
        raise ValueError(f"Image path is not under images/: {image_path}")
    split = image_path.split(marker, maxsplit=1)[1].split("/", maxsplit=1)[0]
    if split not in {"train", "val", "test"}:
        raise ValueError(f"Unsupported source split {split!r}: {image_path}")
    return split


def label_core_counts(label_path: Path, class_names: list[str]) -> Counter[str]:
    if not label_path.exists():
        raise ValueError(f"Missing label file: {label_path}")
    class_ids = {class_names.index(name): name for name in CORE_CLASS_NAMES}
    counts: Counter[str] = Counter()
    for line_number, row in enumerate(read_yolo_label_file(label_path), start=1):
        if not row.strip():
            continue
        parsed = parse_yolo_row(row)
        if parsed is None:
            raise ValueError(f"Invalid YOLO row at {label_path}:{line_number}")
        class_id = parsed[0]
        if class_id in class_ids:
            counts[class_ids[class_id]] += 1
    return counts


def as_int(row: dict[str, str], field: str) -> int:
    try:
        return int(row[field])
    except ValueError as error:
        raise ValueError(f"Invalid integer {field}={row[field]!r}") from error


def post_exclusion_risk(train_images: int, train_boxes: int, val_images: int, val_boxes: int) -> str:
    if train_images < 5 or train_boxes < 20 or val_images < 5 or val_boxes < 20:
        return "critical"
    if train_images < 12 or val_images < 12:
        return "watch"
    return "low"


def main() -> int:
    args = parse_args()
    config, yaml_errors = load_data_yaml(Path(args.data_yaml))
    if yaml_errors or not class_count_matches_names(config):
        raise ValueError("data.yaml could not be validated")
    names = [str(name) for name in config["names"]]
    if not set(CORE_CLASS_NAMES).issubset(names):
        raise ValueError("data.yaml is missing one or more core classes")

    decisions = read_csv_rows(Path(args.decisions), DECISION_FIELDS)
    gate_rows = read_csv_rows(Path(args.gate), GATE_FIELDS)
    fixed_rows = read_csv_rows(Path(args.fixed_test_decisions), FIXED_TEST_FIELDS)
    split_rows = read_csv_rows(Path(args.test_split_distribution), SPLIT_DISTRIBUTION_FIELDS)
    source_rows = read_csv_rows(Path(args.class_distribution), CLASS_DISTRIBUTION_FIELDS)
    duplicate_rows = read_csv_rows(Path(args.duplicate_decisions), DUPLICATE_FIELDS)
    gate_summary = Path(args.gate_summary)
    if not gate_summary.exists() or "Rows blocking six-class apply" not in gate_summary.read_text(encoding="utf-8"):
        raise ValueError("Six-class gate summary is missing or invalid")

    gate_by_path = {row["image_path"]: row for row in gate_rows}
    decision_paths = {row["image_path"] for row in decisions}
    blocking_paths = {
        row["image_path"]
        for row in gate_rows
        if row["blocks_six_class_apply"] == "yes"
    }
    if decision_paths != blocking_paths:
        raise ValueError("Six-class decisions do not match the blocking gate rows")

    fixed_by_path = {
        row["image_path"]
        for row in fixed_rows
        if row["planned_split"] == "test"
    }
    split_by_name = {row["class_name"]: row for row in split_rows}
    source_by_name = {row["class_name"]: row for row in source_rows}
    if any(name not in split_by_name or name not in source_by_name for name in CORE_CLASS_NAMES):
        raise ValueError("Distribution reports are missing a core class")

    actions = Counter(row["approved_action"] for row in decisions)
    excluded = [row for row in decisions if row["approved_action"] == "exclude_from_training"]
    pending = actions["pending_review"] + actions["manual_review"]
    excluded_images: dict[str, Counter[str]] = defaultdict(Counter)
    excluded_boxes: dict[str, Counter[str]] = defaultdict(Counter)
    planned_test_images: Counter[str] = Counter()
    planned_test_boxes: Counter[str] = Counter()
    fixed_test_overlap_rows = 0

    for row in excluded:
        split = image_split(row["image_path"])
        core_counts = label_core_counts(Path(row["label_path"]), names)
        if not core_counts:
            raise ValueError(f"Excluded six-class row lacks a core bbox: {row['image_path']}")
        in_fixed_test = row["image_path"] in fixed_by_path
        if in_fixed_test:
            fixed_test_overlap_rows += 1
        for class_name, box_count in core_counts.items():
            excluded_images[split][class_name] += 1
            excluded_boxes[split][class_name] += box_count
            if in_fixed_test:
                planned_test_images[class_name] += 1
                planned_test_boxes[class_name] += box_count

    rows: list[str] = []
    affected_classes: list[str] = []
    class_risks: dict[str, str] = {}
    for class_name in CORE_CLASS_NAMES:
        baseline = split_by_name[class_name]
        source = source_by_name[class_name]
        if (
            as_int(baseline, "before_train_images") != as_int(source, "train_image_count")
            or as_int(baseline, "before_val_images") != as_int(source, "val_image_count")
        ):
            raise ValueError(f"Distribution baseline mismatch for {class_name}")
        excluded_train_images = excluded_images["train"][class_name]
        excluded_train_boxes = excluded_boxes["train"][class_name]
        excluded_val_images = excluded_images["val"][class_name]
        excluded_val_boxes = excluded_boxes["val"][class_name]
        remaining_train_images = (
            as_int(baseline, "after_train_images")
            - excluded_train_images
            + planned_test_images[class_name]
        )
        remaining_train_boxes = (
            as_int(baseline, "after_train_boxes")
            - excluded_train_boxes
            + planned_test_boxes[class_name]
        )
        remaining_val_images = as_int(baseline, "before_val_images") - excluded_val_images
        remaining_val_boxes = as_int(baseline, "before_val_boxes") - excluded_val_boxes
        risk = post_exclusion_risk(
            remaining_train_images,
            remaining_train_boxes,
            remaining_val_images,
            remaining_val_boxes,
        )
        class_risks[class_name] = risk
        if excluded_train_images or excluded_val_images:
            affected_classes.append(class_name)
        rows.append(
            "| "
            + " | ".join(
                [
                    class_name,
                    str(excluded_train_images + excluded_val_images),
                    str(excluded_train_boxes + excluded_val_boxes),
                    str(remaining_train_images),
                    str(remaining_train_boxes),
                    str(remaining_val_images),
                    str(remaining_val_boxes),
                    str(planned_test_images[class_name]),
                    str(planned_test_boxes[class_name]),
                    risk,
                ]
            )
            + " |"
        )

    fixed_pending = sum(row["approved_action"] == "pending_review" for row in fixed_rows)
    unresolved_duplicates = sum(
        row["approved_action"] in {"pending_review", "review_label_conflict"}
        for row in duplicate_rows
    )
    semantic_cleared = pending == 0
    distribution_risks = [name for name, risk in class_risks.items() if risk != "low"]
    apply_ready = semantic_cleared and fixed_pending == 0 and unresolved_duplicates == 0 and not distribution_risks
    excluded_bbox_total = sum(sum(counts.values()) for counts in excluded_boxes.values())
    lines = [
        "# Six-Class Semantic Exclusion Impact Summary",
        "",
        "## Overall",
        "",
        f"- Excluded image count: {len(excluded)}",
        f"- Kept image count: {actions['keep']}",
        f"- Pending count: {pending}",
        f"- Excluded core-class bbox count: {excluded_bbox_total}",
        f"- Affected core classes: {', '.join(affected_classes)}",
        "",
        "## Per-Class Impact",
        "",
        "Remaining train estimates start from the approved fixed-test split plan's "
        "`after_train` baseline, remove exclusions that would otherwise stay in train, "
        "and keep fixed-test-overlap exclusions out of the train subtraction. Validation "
        "estimates remove every excluded validation image.",
        "",
        "| Class | Excluded images | Excluded boxes | Remaining train images estimate | Remaining train boxes estimate | Remaining val images estimate | Remaining val boxes estimate | Planned test images affected | Planned test boxes affected | Risk after exclusion |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        *rows,
        "",
        "## Fixed-Test Interaction",
        "",
        f"- Excluded rows also in fixed test plan: {fixed_test_overlap_rows}",
        "- By-class fixed-test image memberships: "
        + ", ".join(f"{name}={planned_test_images[name]}" for name in CORE_CLASS_NAMES),
        "- By-class fixed-test boxes affected: "
        + ", ".join(f"{name}={planned_test_boxes[name]}" for name in CORE_CLASS_NAMES),
        "- Fixed-test plan must be regenerated or revised: "
        + ("yes; excluded rows must not enter target test." if fixed_test_overlap_rows else "no."),
        "",
        "## Recommendation",
        "",
        f"- Can six-class semantic review gate be considered cleared? {'yes' if semantic_cleared else 'no'}",
        f"- Can dataset apply proceed now? {'yes' if apply_ready else 'no'}",
        "- Remaining blockers:",
        f"  - duplicate approval: {'blocked by ' + str(unresolved_duplicates) + ' unresolved row(s)' if unresolved_duplicates else 'cleared'}",
        f"  - fixed-test approval: {'blocked by ' + str(fixed_pending) + ' pending row(s)' if fixed_pending else 'cleared'}",
        f"  - class distribution risk: {', '.join(distribution_risks) if distribution_risks else 'none after the approved exclusions'}",
        "",
        "This report is a planning estimate only. It does not alter source images, labels, "
        "decisions, test splits, or dataset membership, and it does not authorize apply.",
        "",
    ]
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Excluded images: {len(excluded)}")
    print(f"Fixed-test rows affected: {fixed_test_overlap_rows}")
    print(f"Semantic review cleared: {'yes' if semantic_cleared else 'no'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
