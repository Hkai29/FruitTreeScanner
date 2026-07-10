#!/usr/bin/env python3
"""Build a six-class manual-review gate without changing source dataset files.

The report narrows the semantic review queue to images that can enter the
planned six-class dataset. It does not approve decisions, copy data, or invoke
the cleanup apply tool.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from dataset_io import (
    class_count_matches_names,
    load_data_yaml,
    parse_yolo_row,
    read_csv_rows,
    read_yolo_label_file,
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
DECISION_FIELDS = [
    "image_path",
    "class_name",
    "issue_type",
    "risk_level",
    "vision_signal",
    "recommended_action",
    "approved_action",
    "notes",
]
PRIORITY_FIELDS = [
    "image_path",
    "class_name",
    "issue_type",
    "vision_signal",
    "risk_level",
    "recommended_action",
    "review_reason",
]
INVALID_REVIEW_FIELDS = [
    "image_path",
    "current_class",
    "issue_type",
    "confidence",
    "recommended_action",
    "notes",
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
NARROWED_FIELDS = [
    "image_path",
    "label_path",
    "class_names",
    "risk_level",
    "issue_type",
    "recommended_action",
    "approved_action",
    "notes",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build read-only six-class manual-review gate reports."
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Source YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--manual-decisions",
        default="ml/audit_reports/manual_review_decisions.csv",
        help="Authoritative manual decision CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--priority-queue",
        default="ml/audit_reports/manual_review_priority_queue.csv",
        help="Generated semantic priority queue. Default: %(default)s",
    )
    parser.add_argument(
        "--invalid-review",
        default="ml/audit_reports/dataset_invalid_image_review.csv",
        help="Merged invalid-image review CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--fixed-test-decisions",
        default="ml/audit_reports/fixed_test_split_decisions.csv",
        help="Fixed test-split decision CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--gate-output",
        default="ml/audit_reports/core_class_review_gate.csv",
        help="Output CSV for every manual-review decision. Default: %(default)s",
    )
    parser.add_argument(
        "--summary-output",
        default="ml/audit_reports/core_class_review_gate_summary.md",
        help="Output Markdown summary. Default: %(default)s",
    )
    parser.add_argument(
        "--narrowed-decisions-output",
        default="ml/audit_reports/core_class_manual_review_decisions.csv",
        help="Output six-class-only approval CSV. Default: %(default)s",
    )
    return parser.parse_args()


def label_path_for_image(image_path: Path) -> Path:
    parts = list(image_path.parts)
    if "images" not in parts:
        raise ValueError(f"Image path is not under images/: {image_path}")
    parts[parts.index("images")] = "labels"
    return Path(*parts).with_suffix(".txt")


def class_names_from_label(
    label_path: Path,
    names: list[str],
) -> tuple[list[str], list[str]]:
    if not label_path.exists():
        return [], ["missing_label_file"]

    class_ids: set[int] = set()
    errors: list[str] = []
    for line_number, row in enumerate(read_yolo_label_file(label_path), start=1):
        if not row.strip():
            continue
        parsed = parse_yolo_row(row)
        if parsed is None:
            errors.append(f"invalid_yolo_row:{line_number}")
            continue
        class_id = parsed[0]
        if not 0 <= class_id < len(names):
            errors.append(f"class_index_out_of_range:{line_number}")
            continue
        class_ids.add(class_id)
    if not class_ids and not errors:
        errors.append("empty_label_file")
    return [names[class_id] for class_id in sorted(class_ids)], errors


def yes_no(value: bool) -> str:
    return "yes" if value else "no"


def build_gate_rows(
    decisions: list[dict[str, str]],
    names: list[str],
    fixed_test_paths: set[str],
) -> list[dict[str, str]]:
    core_names = set(CORE_CLASS_NAMES)
    rows: list[dict[str, str]] = []
    for decision in decisions:
        image_path = Path(decision["image_path"])
        label_path = label_path_for_image(image_path)
        label_classes, label_errors = class_names_from_label(label_path, names)
        contains_core = bool(set(label_classes).intersection(core_names))
        only_non_core = bool(label_classes) and not contains_core and not label_errors
        in_fixed_test_plan = decision["image_path"] in fixed_test_paths
        blocks = contains_core or bool(label_errors)

        if label_errors:
            reason = "fail_closed_label_validation:" + "|".join(label_errors)
        elif contains_core and in_fixed_test_plan:
            reason = "core_label_enters_six_class_copy_and_fixed_test_plan"
        elif contains_core:
            reason = "source_label_contains_core_class"
        elif in_fixed_test_plan:
            reason = "only_non_core_labels_are_excluded_from_six_class_copy"
        else:
            reason = "only_non_core_labels_are_excluded_from_six_class_copy"

        rows.append(
            {
                "image_path": decision["image_path"],
                "label_path": str(label_path),
                "class_names": "|".join(label_classes),
                "contains_core_class": yes_no(contains_core),
                "contains_only_non_core_classes": yes_no(only_non_core),
                "appears_in_fixed_test_plan": yes_no(in_fixed_test_plan),
                "risk_level": decision["risk_level"],
                "issue_type": decision["issue_type"],
                "recommended_action": decision["recommended_action"],
                "current_approved_action": decision["approved_action"],
                "blocks_six_class_apply": yes_no(blocks),
                "block_reason": reason,
            }
        )
    return rows


def write_summary(
    path: Path,
    gate_rows: list[dict[str, str]],
    fixed_test_rows: list[dict[str, str]],
) -> None:
    blocking_rows = [row for row in gate_rows if row["blocks_six_class_apply"] == "yes"]
    defer_rows = [row for row in gate_rows if row["blocks_six_class_apply"] == "no"]
    high_risk_blocking = sum(row["risk_level"] == "high" for row in blocking_rows)
    exclude_candidates = sum(
        row["recommended_action"].startswith("exclude_from_training")
        for row in gate_rows
    )
    pending_blocking = sum(
        row["current_approved_action"] == "pending_review" for row in blocking_rows
    )
    fixed_test_pending = sum(
        row["approved_action"] == "pending_review" for row in fixed_test_rows
    )
    lines = [
        "# Core-Class Manual Review Gate Summary",
        "",
        "## Scope",
        "",
        "This report is a read-only narrowing of the 200-row semantic manual-review "
        "decision queue for `fruit_dataset_6_core_v1`. It does not approve any row "
        "or alter the source dataset.",
        "",
        "## Counts",
        "",
        f"- Total decision rows: {len(gate_rows)}",
        f"- Rows blocking six-class apply: {len(blocking_rows)}",
        f"- High-risk blocking rows: {high_risk_blocking}",
        f"- Rows safe to defer for 26-class cleanup: {len(defer_rows)}",
        f"- Rows already recommended for exclusion: {exclude_candidates}",
        f"- Rows needing actual human visual review: {pending_blocking}",
        "",
        "## Gate Decision",
        "",
        "- The semantic manual-review gate can be narrowed to the blocking rows: yes.",
        "- Can six-class apply proceed now: no; blocking rows remain `pending_review`.",
        "- Can six-class apply proceed after only those blocking rows are approved: "
        "not by this gate alone; the separate fixed-test approval gate still has "
        f"{fixed_test_pending} `pending_review` rows.",
        "",
        "## Deferral Boundary",
        "",
        "Rows marked safe to defer contain only non-core labels and are naturally "
        "excluded from the six-class copy. They remain unresolved for any future "
        "26-class training claim and must not be treated as approved 26-class data.",
        "",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    data_yaml = Path(args.data_yaml)
    config, yaml_errors = load_data_yaml(data_yaml)
    if yaml_errors:
        raise ValueError("; ".join(yaml_errors))
    if not class_count_matches_names(config):
        raise ValueError("data.yaml nc does not match names count")
    names = [str(name) for name in config["names"]]
    if not set(CORE_CLASS_NAMES).issubset(names):
        raise ValueError("data.yaml does not contain every required core class")

    decisions = read_csv_rows(Path(args.manual_decisions), DECISION_FIELDS)
    priority_rows = read_csv_rows(Path(args.priority_queue), PRIORITY_FIELDS)
    invalid_rows = read_csv_rows(Path(args.invalid_review), INVALID_REVIEW_FIELDS)
    fixed_test_rows = read_csv_rows(Path(args.fixed_test_decisions), FIXED_TEST_FIELDS)

    decision_paths = {row["image_path"] for row in decisions}
    priority_paths = {row["image_path"] for row in priority_rows}
    invalid_paths = {row["image_path"] for row in invalid_rows}
    if decision_paths != priority_paths:
        raise ValueError("manual decisions and priority queue do not cover the same images")
    if not decision_paths.issubset(invalid_paths):
        raise ValueError("manual decisions are missing from the invalid-image review")

    fixed_test_paths = {
        row["image_path"]
        for row in fixed_test_rows
        if row["planned_split"] == "test"
    }
    gate_rows = build_gate_rows(decisions, names, fixed_test_paths)
    narrowed_rows = [
        {
            "image_path": row["image_path"],
            "label_path": row["label_path"],
            "class_names": row["class_names"],
            "risk_level": row["risk_level"],
            "issue_type": row["issue_type"],
            "recommended_action": row["recommended_action"],
            "approved_action": "pending_review",
            "notes": "",
        }
        for row in gate_rows
        if row["blocks_six_class_apply"] == "yes"
    ]
    write_csv_rows(Path(args.gate_output), gate_rows, GATE_FIELDS)
    write_csv_rows(Path(args.narrowed_decisions_output), narrowed_rows, NARROWED_FIELDS)
    write_summary(Path(args.summary_output), gate_rows, fixed_test_rows)

    blocking_count = sum(row["blocks_six_class_apply"] == "yes" for row in gate_rows)
    high_risk_count = sum(
        row["blocks_six_class_apply"] == "yes" and row["risk_level"] == "high"
        for row in gate_rows
    )
    print(f"Decision rows: {len(gate_rows)}")
    print(f"Six-class blocking rows: {blocking_count}")
    print(f"High-risk blocking rows: {high_risk_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
