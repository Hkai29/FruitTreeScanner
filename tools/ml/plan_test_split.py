#!/usr/bin/env python3
"""Plan a fixed YOLO test split without moving or editing dataset files.

The planner is intentionally read-only. It selects deterministic candidate
images from the current train split, leaves val unchanged, and writes compact
CSV reports that can be reviewed before any dataset operation happens.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
from collections import Counter
from pathlib import Path
from typing import Any

from audit_yolo_dataset import (
    collect_image_records,
    display_path,
    ratio_note,
)


DEFAULT_DATA_YAML = "ml/datasets/fruit_dataset_26/data.yaml"
DEFAULT_OUTPUT = "ml/audit_reports/test_split_plan.csv"
DEFAULT_CLASS_SUMMARY_OUTPUT = "ml/audit_reports/test_split_class_distribution.csv"
DEFAULT_TEST_RATIO = 0.10
DEFAULT_SEED = 20260709
MIN_AFTER_TRAIN_IMAGES = 5
MIN_AFTER_TRAIN_BOXES = 20
LOW_SAMPLE_IMAGE_GUARD = 12


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plan a deterministic fixed test split for a YOLO dataset without moving files."
    )
    parser.add_argument(
        "--data-yaml",
        default=DEFAULT_DATA_YAML,
        help=f"Path to YOLO data.yaml. Default: {DEFAULT_DATA_YAML}",
    )
    parser.add_argument(
        "--test-ratio",
        type=float,
        default=DEFAULT_TEST_RATIO,
        help=f"Fraction of train images to plan for test. Default: {DEFAULT_TEST_RATIO}",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"Deterministic split seed. Default: {DEFAULT_SEED}",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help=f"CSV path for selected test-split image plan. Default: {DEFAULT_OUTPUT}",
    )
    parser.add_argument(
        "--class-summary-output",
        default=DEFAULT_CLASS_SUMMARY_OUTPUT,
        help=(
            "CSV path for before/after class distribution summary. "
            f"Default: {DEFAULT_CLASS_SUMMARY_OUTPUT}"
        ),
    )
    return parser.parse_args()


def stable_key(seed: int, record: dict[str, Any]) -> str:
    return hashlib.sha256(
        f"{seed}:{display_path(record['image_path'])}".encode("utf-8")
    ).hexdigest()


def per_class_counts(records: list[dict[str, Any]], class_count: int) -> tuple[Counter[int], Counter[int]]:
    image_counts: Counter[int] = Counter()
    box_counts: Counter[int] = Counter()
    for record in records:
        for class_id in record["class_ids"]:
            image_counts[class_id] += 1
        for class_id, count in label_box_counts(record["label_path"], class_count).items():
            box_counts[class_id] += count
    return image_counts, box_counts


def label_box_counts(label_path: Path, class_count: int) -> Counter[int]:
    counts: Counter[int] = Counter()
    if not label_path.exists():
        return counts
    try:
        lines = label_path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        lines = label_path.read_text(encoding="utf-8", errors="replace").splitlines()
    for line in lines:
        parts = line.split()
        if len(parts) != 5:
            continue
        try:
            class_id = int(float(parts[0]))
        except ValueError:
            continue
        if 0 <= class_id < class_count:
            counts[class_id] += 1
    return counts


def protected_classes(
    train_image_counts: Counter[int],
    train_box_counts: Counter[int],
    val_image_counts: Counter[int],
    class_count: int,
) -> set[int]:
    protected: set[int] = set()
    for class_id in range(class_count):
        total_images = train_image_counts[class_id] + val_image_counts[class_id]
        if (
            total_images < 50
            or val_image_counts[class_id] < 5
            or train_image_counts[class_id] <= LOW_SAMPLE_IMAGE_GUARD
            or train_image_counts[class_id] <= MIN_AFTER_TRAIN_IMAGES
            or train_box_counts[class_id] <= MIN_AFTER_TRAIN_BOXES
        ):
            protected.add(class_id)
    return protected


def can_select(
    record: dict[str, Any],
    selected_image_counts: Counter[int],
    selected_box_counts: Counter[int],
    train_image_counts: Counter[int],
    train_box_counts: Counter[int],
    protected: set[int],
    class_count: int,
) -> bool:
    class_ids = set(record["class_ids"])
    if not class_ids:
        return False
    if class_ids & protected:
        return False
    record_box_counts = label_box_counts(record["label_path"], class_count)
    for class_id in class_ids:
        after_images = train_image_counts[class_id] - selected_image_counts[class_id] - 1
        after_boxes = train_box_counts[class_id] - selected_box_counts[class_id] - record_box_counts[class_id]
        if after_images < MIN_AFTER_TRAIN_IMAGES or after_boxes < MIN_AFTER_TRAIN_BOXES:
            return False
    return True


def add_selected(
    record: dict[str, Any],
    reason: str,
    selected: dict[str, tuple[dict[str, Any], str]],
    selected_image_counts: Counter[int],
    selected_box_counts: Counter[int],
    class_count: int,
) -> None:
    key = display_path(record["image_path"])
    if key in selected:
        return
    selected[key] = (record, reason)
    for class_id in record["class_ids"]:
        selected_image_counts[class_id] += 1
    for class_id, count in label_box_counts(record["label_path"], class_count).items():
        selected_box_counts[class_id] += count


def plan_split(
    records: list[dict[str, Any]],
    names: list[str],
    test_ratio: float,
    seed: int,
) -> tuple[list[tuple[dict[str, Any], str]], dict[str, Any]]:
    train_records = [record for record in records if record["split"] == "train"]
    val_records = [record for record in records if record["split"] == "val"]
    class_count = len(names)
    train_image_counts, train_box_counts = per_class_counts(train_records, class_count)
    val_image_counts, val_box_counts = per_class_counts(val_records, class_count)
    protected = protected_classes(
        train_image_counts,
        train_box_counts,
        val_image_counts,
        class_count,
    )
    selected: dict[str, tuple[dict[str, Any], str]] = {}
    selected_image_counts: Counter[int] = Counter()
    selected_box_counts: Counter[int] = Counter()
    target_count = max(0, round(len(train_records) * max(0, min(test_ratio, 0.5))))
    shuffled_records = sorted(train_records, key=lambda record: stable_key(seed, record))

    for class_id in sorted(range(class_count), key=lambda item: train_image_counts[item]):
        if class_id in protected:
            continue
        candidates = [
            record
            for record in shuffled_records
            if class_id in record["class_ids"]
            and display_path(record["image_path"]) not in selected
        ]
        for candidate in candidates:
            if can_select(
                candidate,
                selected_image_counts,
                selected_box_counts,
                train_image_counts,
                train_box_counts,
                protected,
                class_count,
            ):
                add_selected(
                    candidate,
                    f"class_coverage:{names[class_id]}",
                    selected,
                    selected_image_counts,
                    selected_box_counts,
                    class_count,
                )
                break

    for record in shuffled_records:
        if len(selected) >= target_count:
            break
        if display_path(record["image_path"]) in selected:
            continue
        if can_select(
            record,
            selected_image_counts,
            selected_box_counts,
            train_image_counts,
            train_box_counts,
            protected,
            class_count,
        ):
            add_selected(
                record,
                "target_ratio_fill",
                selected,
                selected_image_counts,
                selected_box_counts,
                class_count,
            )

    metadata = {
        "target_count": target_count,
        "train_records": len(train_records),
        "val_records": len(val_records),
        "protected_classes": protected,
        "train_image_counts": train_image_counts,
        "train_box_counts": train_box_counts,
        "val_image_counts": val_image_counts,
        "val_box_counts": val_box_counts,
        "selected_image_counts": selected_image_counts,
        "selected_box_counts": selected_box_counts,
    }
    planned = sorted(selected.values(), key=lambda item: display_path(item[0]["image_path"]))
    return planned, metadata


def write_plan(
    planned: list[tuple[dict[str, Any], str]],
    names: list[str],
    output: Path,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "image_path",
                "label_path",
                "current_split",
                "planned_split",
                "class_ids",
                "class_names",
                "bbox_count",
                "reason",
            ],
            lineterminator="\n",
        )
        writer.writeheader()
        for record, reason in planned:
            class_ids = [int(item) for item in record["class_ids"]]
            writer.writerow(
                {
                    "image_path": display_path(record["image_path"]),
                    "label_path": display_path(record["label_path"]),
                    "current_split": record["split"],
                    "planned_split": "test",
                    "class_ids": "|".join(str(item) for item in class_ids),
                    "class_names": "|".join(names[item] for item in class_ids),
                    "bbox_count": record["bbox_count"],
                    "reason": reason,
                }
            )


def write_class_summary(
    names: list[str],
    metadata: dict[str, Any],
    output: Path,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
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
            ],
            lineterminator="\n",
        )
        writer.writeheader()
        protected = metadata["protected_classes"]
        train_image_counts = metadata["train_image_counts"]
        train_box_counts = metadata["train_box_counts"]
        val_image_counts = metadata["val_image_counts"]
        val_box_counts = metadata["val_box_counts"]
        selected_image_counts = metadata["selected_image_counts"]
        selected_box_counts = metadata["selected_box_counts"]
        for class_id, class_name in enumerate(names):
            after_train_images = train_image_counts[class_id] - selected_image_counts[class_id]
            after_train_boxes = train_box_counts[class_id] - selected_box_counts[class_id]
            writer.writerow(
                {
                    "class_id": class_id,
                    "class_name": class_name,
                    "before_train_images": train_image_counts[class_id],
                    "before_train_boxes": train_box_counts[class_id],
                    "before_val_images": val_image_counts[class_id],
                    "before_val_boxes": val_box_counts[class_id],
                    "planned_test_images": selected_image_counts[class_id],
                    "planned_test_boxes": selected_box_counts[class_id],
                    "after_train_images": after_train_images,
                    "after_train_boxes": after_train_boxes,
                    "risk_note": risk_note(
                        class_id,
                        protected,
                        selected_image_counts[class_id],
                        train_image_counts[class_id],
                        val_image_counts[class_id],
                    ),
                }
            )


def risk_note(
    class_id: int,
    protected: set[int],
    planned_test_images: int,
    train_images: int,
    val_images: int,
) -> str:
    if class_id in protected:
        return "protected_low_sample_not_sampled"
    if planned_test_images == 0:
        return "no_test_sample_selected_review_manually"
    return f"planned_test_selected_{ratio_note(train_images, val_images)}"


def main() -> int:
    args = parse_args()
    config, records = collect_image_records(Path(args.data_yaml))
    names = config["names"]
    planned, metadata = plan_split(records, names, args.test_ratio, args.seed)
    write_plan(planned, names, Path(args.output))
    write_class_summary(names, metadata, Path(args.class_summary_output))
    print(f"Dataset: {display_path(Path(args.data_yaml))}")
    print(f"Train images: {metadata['train_records']}  Val images: {metadata['val_records']}")
    print(f"Requested test ratio: {args.test_ratio:.3f}  Seed: {args.seed}")
    print(f"Planned test images: {len(planned)} / target {metadata['target_count']}")
    print(f"Plan written: {args.output}")
    print(f"Class summary written: {args.class_summary_output}")
    if len(planned) < metadata["target_count"]:
        print("NOTE: planned fewer images than target because low-sample class guards blocked candidates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
