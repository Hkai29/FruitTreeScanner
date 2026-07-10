#!/usr/bin/env python3
"""Finalize fixed-test actions from existing six-class review decisions.

The tool does not move images, edit labels, or invoke dataset apply. It only
updates the fixed-test approval CSV with action values accepted by
``apply_dataset_cleanup.py`` and writes summary reports.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from dataset_io import (
    class_count_matches_names,
    load_data_yaml,
    parse_yolo_row,
    read_csv_rows,
    read_yolo_label_file,
    validate_yolo_bbox,
    write_csv_rows,
)


CORE_CLASS_NAMES = (
    "apple",
    "orange",
    "pear",
    "persimmon",
    "grape",
    "strawberry",
)
SPLIT_FIELDS = [
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
SEMANTIC_FIELDS = [
    "image_path",
    "label_path",
    "class_names",
    "risk_level",
    "issue_type",
    "recommended_action",
    "approved_action",
    "notes",
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
SPLIT_ACTIONS = {
    "pending_review",
    "approve_move_to_test",
    "keep_in_train",
    "exclude_from_core_test",
    "manual_review",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Finalize six-class fixed-test approval actions without applying data changes."
    )
    parser.add_argument(
        "--fixed-decisions",
        default="ml/audit_reports/fixed_test_split_decisions.csv",
        help="Fixed-test decision CSV to revise. Default: %(default)s",
    )
    parser.add_argument(
        "--semantic-decisions",
        default="ml/audit_reports/core_class_manual_review_decisions.csv",
        help="Final six-class semantic decisions. Default: %(default)s",
    )
    parser.add_argument(
        "--duplicate-decisions",
        default="ml/audit_reports/duplicate_cleanup_decisions.csv",
        help="Final duplicate decisions. Default: %(default)s",
    )
    parser.add_argument(
        "--test-split-distribution",
        default="ml/audit_reports/test_split_class_distribution.csv",
        help="Original test-split distribution. Default: %(default)s",
    )
    parser.add_argument(
        "--class-distribution",
        default="ml/audit_reports/class_distribution_report.csv",
        help="Current source class distribution. Default: %(default)s",
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Source YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--summary-output",
        default="ml/audit_reports/fixed_test_revision_summary.md",
        help="Revision summary output. Default: %(default)s",
    )
    parser.add_argument(
        "--distribution-output",
        default="ml/audit_reports/fixed_test_class_distribution_after_revision.csv",
        help="Revised class distribution output. Default: %(default)s",
    )
    return parser.parse_args()


def parse_label(label_path: Path, names: list[str]) -> Counter[str]:
    if not label_path.exists():
        raise FileNotFoundError(str(label_path))
    counts: Counter[str] = Counter()
    for line_number, row in enumerate(read_yolo_label_file(label_path), start=1):
        if not row.strip():
            continue
        parsed = parse_yolo_row(row)
        if parsed is None:
            raise ValueError(f"invalid_yolo_row:{label_path}:{line_number}")
        class_id, x_center, y_center, width, height = parsed
        if not 0 <= class_id < len(names):
            raise ValueError(f"class_index_out_of_range:{label_path}:{line_number}")
        if not validate_yolo_bbox(x_center, y_center, width, height):
            raise ValueError(f"invalid_yolo_bbox:{label_path}:{line_number}")
        counts[names[class_id]] += 1
    if not counts:
        raise ValueError(f"empty_label_file:{label_path}")
    return counts


def existing_note(notes: str) -> str:
    return notes.split("; six_class_fixed_test:", maxsplit=1)[0].strip()


def note_with_reason(notes: str, reason: str) -> str:
    prefix = existing_note(notes)
    return f"{prefix}; six_class_fixed_test:{reason}" if prefix else f"six_class_fixed_test:{reason}"


def exclusion_reason(
    row: dict[str, str],
    semantic_actions: dict[str, str],
    duplicate_exclusions: set[str],
    names: list[str],
) -> tuple[str | None, Counter[str] | None]:
    image_path = Path(row["image_path"])
    label_path = Path(row["label_path"])
    if semantic_actions.get(row["image_path"]) == "exclude_from_training":
        return "excluded_by_semantic_review", None
    if row["image_path"] in duplicate_exclusions:
        return "excluded_by_duplicate_cleanup", None
    if not image_path.exists() or not label_path.exists():
        return "missing_after_dataset_cleanup", None
    try:
        label_counts = parse_label(label_path, names)
    except ValueError:
        return "invalid_label_after_dataset_cleanup", None
    core_counts = Counter(
        {name: count for name, count in label_counts.items() if name in CORE_CLASS_NAMES}
    )
    if not core_counts:
        return "non_core_class", label_counts
    return None, core_counts


def risk_level(approved_images: int) -> tuple[str, str]:
    if approved_images < 5:
        return "critical", "fewer than 5 approved test images"
    if approved_images < 20:
        return "watch", "fewer than 20 approved test images"
    return "low", "approved volume remains at or above 20 images"


def main() -> int:
    args = parse_args()
    config, yaml_errors = load_data_yaml(Path(args.data_yaml))
    if yaml_errors or not class_count_matches_names(config):
        raise ValueError("data.yaml could not be validated")
    names = [str(name) for name in config["names"]]
    if not set(CORE_CLASS_NAMES).issubset(names):
        raise ValueError("data.yaml is missing one or more core classes")

    fixed_rows = read_csv_rows(Path(args.fixed_decisions), SPLIT_FIELDS)
    semantic_rows = read_csv_rows(Path(args.semantic_decisions), SEMANTIC_FIELDS)
    duplicate_rows = read_csv_rows(Path(args.duplicate_decisions), DUPLICATE_FIELDS)
    split_distribution = read_csv_rows(
        Path(args.test_split_distribution), SPLIT_DISTRIBUTION_FIELDS
    )
    source_distribution = read_csv_rows(
        Path(args.class_distribution), CLASS_DISTRIBUTION_FIELDS
    )
    if not fixed_rows:
        raise ValueError("fixed-test decisions CSV is empty")
    if any(row["approved_action"] not in SPLIT_ACTIONS for row in fixed_rows):
        raise ValueError("fixed-test decisions contain an unsupported action")

    semantic_actions = {row["image_path"]: row["approved_action"] for row in semantic_rows}
    if any(action in {"pending_review", "manual_review"} for action in semantic_actions.values()):
        raise ValueError("semantic review has unresolved rows")
    duplicate_exclusions = {
        row["image_path"]
        for row in duplicate_rows
        if row["approved_action"] == "remove_duplicate"
    }
    baseline_by_name = {row["class_name"]: row for row in split_distribution}
    source_by_name = {row["class_name"]: row for row in source_distribution}
    if any(name not in baseline_by_name or name not in source_by_name for name in CORE_CLASS_NAMES):
        raise ValueError("distribution reports are missing a core class")

    original_count = len(fixed_rows)
    counts_by_reason: Counter[str] = Counter()
    approved_images: Counter[str] = Counter()
    approved_boxes: Counter[str] = Counter()
    excluded_images: Counter[str] = Counter()
    excluded_boxes: Counter[str] = Counter()
    revised_rows: list[dict[str, str]] = []
    for row in fixed_rows:
        reason, core_counts = exclusion_reason(
            row,
            semantic_actions,
            duplicate_exclusions,
            names,
        )
        revised = dict(row)
        if reason is None:
            assert core_counts is not None
            revised["approved_action"] = "approve_move_to_test"
            revised["notes"] = note_with_reason(
                row["notes"], "approved_for_six_class_fixed_test"
            )
            for class_name, bbox_count in core_counts.items():
                approved_images[class_name] += 1
                approved_boxes[class_name] += bbox_count
        else:
            revised["approved_action"] = "exclude_from_core_test"
            revised["notes"] = note_with_reason(row["notes"], reason)
            counts_by_reason[reason] += 1
            if core_counts is None and Path(row["label_path"]).exists():
                try:
                    parsed_counts = parse_label(Path(row["label_path"]), names)
                    core_counts = Counter(
                        {
                            name: count
                            for name, count in parsed_counts.items()
                            if name in CORE_CLASS_NAMES
                        }
                    )
                except ValueError:
                    core_counts = Counter()
            for class_name, bbox_count in (core_counts or Counter()).items():
                excluded_images[class_name] += 1
                excluded_boxes[class_name] += bbox_count
        revised_rows.append(revised)

    write_csv_rows(Path(args.fixed_decisions), revised_rows, SPLIT_FIELDS)
    action_counts = Counter(row["approved_action"] for row in revised_rows)
    pending_count = action_counts["pending_review"] + action_counts["manual_review"]
    fixed_gate_cleared = pending_count == 0
    distribution_rows: list[dict[str, str]] = []
    class_risks: list[str] = []
    for class_name in CORE_CLASS_NAMES:
        baseline = baseline_by_name[class_name]
        source = source_by_name[class_name]
        if baseline["before_train_images"] != source["train_image_count"]:
            raise ValueError(f"source distribution mismatch for {class_name}")
        level, note = risk_level(approved_images[class_name])
        if level != "low":
            class_risks.append(class_name)
        distribution_rows.append(
            {
                "class_name": class_name,
                "approved_test_images": str(approved_images[class_name]),
                "approved_test_boxes": str(approved_boxes[class_name]),
                "excluded_test_images": str(excluded_images[class_name]),
                "excluded_test_boxes": str(excluded_boxes[class_name]),
                "risk_level": level,
                "notes": note,
            }
        )
    write_csv_rows(
        Path(args.distribution_output),
        distribution_rows,
        [
            "class_name",
            "approved_test_images",
            "approved_test_boxes",
            "excluded_test_images",
            "excluded_test_boxes",
            "risk_level",
            "notes",
        ],
    )

    semantic_excluded = counts_by_reason["excluded_by_semantic_review"]
    missing_rows = counts_by_reason["missing_after_dataset_cleanup"]
    non_core_rows = counts_by_reason["non_core_class"]
    duplicate_rows_excluded = counts_by_reason["excluded_by_duplicate_cleanup"]
    apply_ready = False
    summary_lines = [
        "# Fixed-Test Revision Summary",
        "",
        f"- Original fixed-test rows: {original_count}",
        f"- Approved fixed-test rows: {action_counts['approve_move_to_test']}",
        f"- Excluded fixed-test rows: {action_counts['exclude_from_core_test']}",
        f"- Pending rows: {pending_count}",
        f"- Rows excluded because of semantic review: {semantic_excluded}",
        f"- Rows excluded because file missing: {missing_rows}",
        f"- Rows excluded because non-core class: {non_core_rows}",
        f"- Rows excluded because duplicate cleanup: {duplicate_rows_excluded}",
        "",
        "## Per-Class Approved Test Coverage",
        "",
        *[
            f"- {row['class_name']}: {row['approved_test_images']} images, "
            f"{row['approved_test_boxes']} boxes; excluded "
            f"{row['excluded_test_images']} images / {row['excluded_test_boxes']} boxes; "
            f"risk={row['risk_level']}"
            for row in distribution_rows
        ],
        "",
        "## Gate Status",
        "",
        f"- Fixed-test gate cleared: {'yes' if fixed_gate_cleared else 'no'}",
        "- Dataset apply can proceed: no.",
        "- Remaining blockers:",
        "  - semantic review: decisions are final, but the current apply tool does not read "
        "`core_class_manual_review_decisions.csv`; semantic exclusions would otherwise remain in target train.",
        "  - duplicate cleanup: cleared for the current duplicate decisions.",
        "  - fixed-test approval: cleared for this CSV revision.",
        "  - class distribution: "
        + (", ".join(class_risks) + " need low-volume review." if class_risks else "no critical post-revision risk."),
        "",
        "The actions use the existing apply schema: `approve_move_to_test` and "
        "`exclude_from_core_test`. The latter prevents test placement only; it is not a "
        "whole-dataset semantic exclusion action.",
        "",
    ]
    output = Path(args.summary_output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(summary_lines), encoding="utf-8")
    print(f"Original fixed-test rows: {original_count}")
    print(f"Approved rows: {action_counts['approve_move_to_test']}")
    print(f"Excluded rows: {action_counts['exclude_from_core_test']}")
    print(f"Pending rows: {pending_count}")
    print(f"Fixed-test gate cleared: {'yes' if fixed_gate_cleared else 'no'}")
    print(f"Dataset apply ready: {'yes' if apply_ready else 'no'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
