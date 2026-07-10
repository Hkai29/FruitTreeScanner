#!/usr/bin/env python3
"""Audit a YOLO-format detection dataset for FruitTreeScanner retraining.

The checker intentionally uses only the Python standard library so it can run
before ML dependencies are installed. It validates dataset structure, image and
label pairing, class index bounds, basic bbox validity, split leakage, and class
distribution. Reports are compact summaries with capped examples.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from dataset_io import (
    IMAGE_EXTENSIONS,
    SPLITS,
    class_count_matches_names,
    count_classes,
    display_path,
    iter_image_files,
    label_dir_for_image_dir,
    label_path_for_image,
    load_data_yaml,
    parse_yolo_row,
    read_yolo_label_file,
    resolve_dataset_root,
    resolve_split_path,
    validate_yolo_bbox,
    write_csv_rows,
)

EXAMPLE_LIMIT = 50


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit a YOLO dataset and write compact JSON/CSV summaries."
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Path to YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--output-dir",
        default="ml/audit_reports",
        help="Directory for dataset_audit_summary.json and dataset_class_distribution.csv.",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="Print summary only; do not write report files.",
    )
    parser.add_argument(
        "--hash-duplicates",
        action="store_true",
        help="Hash image contents to detect duplicate images. Slower but still bounded.",
    )
    return parser.parse_args()


def dataset_root(data_yaml: Path, config: dict[str, Any]) -> Path:
    return resolve_dataset_root(data_yaml, config)


def split_image_dir(root: Path, config: dict[str, Any], split: str) -> Path | None:
    return resolve_split_path(root, config, split)


def image_signature(path: Path) -> str | None:
    try:
        with path.open("rb") as handle:
            header = handle.read(32)
            if header.startswith(b"\xff\xd8\xff"):
                handle.seek(-2, 2)
                return "jpeg" if handle.read(2) == b"\xff\xd9" else None
            if header.startswith(b"\x89PNG\r\n\x1a\n"):
                return "png"
            if header.startswith(b"BM"):
                return "bmp"
            if header[:4] == b"RIFF" and header[8:12] == b"WEBP":
                return "webp"
    except OSError:
        return None
    return None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_label_file(label_path: Path, class_count: int) -> tuple[list[int], int, str]:
    raw_lines = read_yolo_label_file(label_path)
    normalized_lines = [line.strip() for line in raw_lines if line.strip()]
    class_ids = sorted(count_classes(normalized_lines, class_count))
    fingerprint = hashlib.sha256(
        "\n".join(sorted(normalized_lines)).encode("utf-8")
    ).hexdigest()
    return sorted(set(class_ids)), len(normalized_lines), fingerprint


def collect_image_records(data_yaml: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    config, yaml_errors = load_data_yaml(data_yaml)
    if yaml_errors:
        raise ValueError("; ".join(yaml_errors))
    root = dataset_root(data_yaml, config)
    names = config.get("names", [])
    records: list[dict[str, Any]] = []

    for split in SPLITS:
        image_dir = split_image_dir(root, config, split)
        if image_dir is None:
            continue
        label_dir = label_dir_for_image_dir(image_dir)
        images = iter_image_files(image_dir)
        for image_path in images:
            label_path = label_path_for_image(image_path, image_dir, label_dir)
            class_ids: list[int] = []
            bbox_count = 0
            label_fingerprint = ""
            if label_path.exists():
                class_ids, bbox_count, label_fingerprint = parse_label_file(
                    label_path,
                    len(names),
                )
            records.append(
                {
                    "image_path": image_path,
                    "label_path": label_path,
                    "split": split,
                    "class_ids": class_ids,
                    "bbox_count": bbox_count,
                    "label_fingerprint": label_fingerprint,
                }
            )
    return config, records


def class_distribution_report_rows(
    summary: dict[str, Any],
    records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    names = summary["names"]
    image_counts: dict[str, Counter[int]] = {
        split: Counter() for split in SPLITS
    }
    bbox_counts: dict[str, Counter[int]] = {
        split: Counter() for split in SPLITS
    }

    for record in records:
        split = str(record["split"])
        label_path = record["label_path"]
        class_ids = set(record["class_ids"])
        for class_id in class_ids:
            image_counts[split][class_id] += 1
        if label_path.exists():
            bbox_counts[split].update(
                count_classes(read_yolo_label_file(label_path), len(names))
            )

    rows: list[dict[str, Any]] = []
    for class_id, class_name in enumerate(names):
        train_image_count = image_counts["train"][class_id]
        val_image_count = image_counts["val"][class_id]
        test_image_count = image_counts["test"][class_id]
        train_bbox_count = bbox_counts["train"][class_id]
        val_bbox_count = bbox_counts["val"][class_id]
        test_bbox_count = bbox_counts["test"][class_id]
        total_image_count = train_image_count + val_image_count + test_image_count
        total_bbox_count = train_bbox_count + val_bbox_count + test_bbox_count
        train_val_ratio_note = ratio_note(train_image_count, val_image_count)
        risk_level, recommended_action = class_risk(
            train_image_count,
            val_image_count,
            total_image_count,
            train_val_ratio_note,
        )
        rows.append(
            {
                "class_id": class_id,
                "class_name": class_name,
                "train_image_count": train_image_count,
                "train_bbox_count": train_bbox_count,
                "val_image_count": val_image_count,
                "val_bbox_count": val_bbox_count,
                "test_image_count": test_image_count,
                "test_bbox_count": test_bbox_count,
                "total_image_count": total_image_count,
                "total_bbox_count": total_bbox_count,
                "train_val_ratio_note": train_val_ratio_note,
                "risk_level": risk_level,
                "recommended_action": recommended_action,
            }
        )
    return rows


def ratio_note(train_images: int, val_images: int) -> str:
    if train_images == 0 and val_images == 0:
        return "missing_from_dataset"
    if val_images == 0:
        return "missing_from_val"
    ratio = train_images / max(val_images, 1)
    if ratio > 12:
        return f"train_heavy_{ratio:.1f}:1"
    if ratio < 2:
        return f"val_heavy_{ratio:.1f}:1"
    return f"ok_{ratio:.1f}:1"


def class_risk(
    train_images: int,
    val_images: int,
    total_images: int,
    train_val_ratio_note: str,
) -> tuple[str, str]:
    if total_images == 0:
        return "review", "manual_review"
    if total_images < 10 or train_images < 5:
        return "low_sample", "merge_or_drop_candidate"
    if val_images == 0:
        return "missing_from_val", "do_not_sample_into_test_yet"
    if val_images < 5:
        return "val_too_small", "collect_more_data"
    if train_val_ratio_note.startswith(("train_heavy", "val_heavy")):
        return "train_val_imbalanced", "manual_review"
    if total_images < 50:
        return "low_sample", "collect_more_data"
    return "ok", "keep"


def duplicate_report_rows(
    records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    hashes: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        image_path = record["image_path"]
        try:
            hashes[sha256_file(image_path)].append(record)
        except OSError:
            continue

    rows: list[dict[str, Any]] = []
    duplicate_groups = [
        (digest, group)
        for digest, group in sorted(hashes.items())
        if len(group) > 1
    ]
    for group_index, (digest, group) in enumerate(duplicate_groups, start=1):
        fingerprints = {str(record["label_fingerprint"]) for record in group}
        same_group_labels = len(fingerprints) == 1
        recommended_action = (
            "remove_duplicate_candidate"
            if same_group_labels
            else "review_label_conflict"
        )
        reference_fingerprint = str(group[0]["label_fingerprint"])
        for record in group:
            same_label_as_group = str(record["label_fingerprint"]) == reference_fingerprint
            rows.append(
                {
                    "hash": digest,
                    "image_path": display_path(record["image_path"]),
                    "split": record["split"],
                    "label_path": display_path(record["label_path"]),
                    "class_ids": "|".join(str(item) for item in record["class_ids"]),
                    "bbox_count": record["bbox_count"],
                    "label_fingerprint": record["label_fingerprint"],
                    "duplicate_group_id": f"dup_{group_index:03d}",
                    "same_label_as_group": str(same_label_as_group).lower(),
                    "recommended_action": recommended_action,
                    "notes": (
                        "identical image bytes and matching label fingerprint"
                        if same_group_labels
                        else "identical image bytes but label fingerprints differ"
                    ),
                }
            )
    return rows


def add_example(items: list[Any], value: Any) -> None:
    if len(items) < EXAMPLE_LIMIT:
        if isinstance(value, Path):
            items.append(display_path(value))
        else:
            items.append(value)


def audit_dataset(data_yaml: Path, hash_duplicates: bool = False) -> dict[str, Any]:
    config, yaml_errors = load_data_yaml(data_yaml)
    root = dataset_root(data_yaml, config) if config else data_yaml.parent
    names = config.get("names", [])
    nc = config.get("nc")
    yaml_nc_matches_names = class_count_matches_names(config)

    summary: dict[str, Any] = {
        "data_yaml": display_path(data_yaml),
        "dataset_root": display_path(root),
        "nc": nc,
        "names": names,
        "yaml_errors": yaml_errors,
        "yaml_nc_matches_names": yaml_nc_matches_names,
        "splits": {},
        "totals": {
            "images": 0,
            "labels": 0,
            "missing_labels": 0,
            "missing_images": 0,
            "empty_labels": 0,
            "invalid_label_lines": 0,
            "out_of_range_class_indices": 0,
            "invalid_bboxes": 0,
            "corrupt_or_unknown_images": 0,
            "duplicate_stems_across_splits": 0,
            "duplicate_image_hashes": 0,
        },
        "examples": defaultdict(list),
        "class_bbox_counts": {str(index): 0 for index in range(len(names))},
        "class_image_counts": {str(index): 0 for index in range(len(names))},
    }

    stems_by_split: dict[str, set[str]] = {}
    image_hashes: dict[str, list[str]] = defaultdict(list)

    for split in SPLITS:
        image_dir = split_image_dir(root, config, split)
        if image_dir is None:
            continue
        label_dir = label_dir_for_image_dir(image_dir)
        images = iter_image_files(image_dir)
        labels = sorted(label_dir.glob("*.txt")) if label_dir.exists() else []
        image_by_stem = {path.stem: path for path in images}
        label_by_stem = {path.stem: path for path in labels}
        stems_by_split[split] = set(image_by_stem)

        split_summary = {
            "image_dir": display_path(image_dir),
            "label_dir": display_path(label_dir),
            "images": len(images),
            "labels": len(labels),
            "missing_labels": 0,
            "missing_images": 0,
            "empty_labels": 0,
            "invalid_label_lines": 0,
            "out_of_range_class_indices": 0,
            "invalid_bboxes": 0,
            "corrupt_or_unknown_images": 0,
        }

        for image_path in images:
            signature = image_signature(image_path)
            if signature is None:
                split_summary["corrupt_or_unknown_images"] += 1
                add_example(summary["examples"]["corrupt_or_unknown_images"], image_path)
            if image_path.stem not in label_by_stem:
                split_summary["missing_labels"] += 1
                add_example(summary["examples"]["missing_labels"], image_path)
            if hash_duplicates:
                try:
                    image_hashes[sha256_file(image_path)].append(display_path(image_path))
                except OSError:
                    add_example(summary["examples"]["unreadable_images"], image_path)

        for label_path in labels:
            if label_path.stem not in image_by_stem:
                split_summary["missing_images"] += 1
                add_example(summary["examples"]["missing_images"], label_path)
                continue

            raw_lines = read_yolo_label_file(label_path)
            nonempty = [line for line in raw_lines if line.strip()]
            if not nonempty:
                split_summary["empty_labels"] += 1
                add_example(summary["examples"]["empty_labels"], label_path)
                continue

            classes_in_image: set[int] = set()
            for line_number, line in enumerate(nonempty, start=1):
                parsed = parse_yolo_row(line)
                if parsed is None:
                    split_summary["invalid_label_lines"] += 1
                    add_example(
                        summary["examples"]["invalid_label_lines"],
                        f"{display_path(label_path)}:{line_number}",
                    )
                    continue
                class_index, x_center, y_center, width, height = parsed
                if class_index < 0 or class_index >= len(names):
                    split_summary["out_of_range_class_indices"] += 1
                    add_example(
                        summary["examples"]["out_of_range_class_indices"],
                        f"{display_path(label_path)}:{line_number}:{class_index}",
                    )
                    continue
                if not validate_yolo_bbox(x_center, y_center, width, height):
                    split_summary["invalid_bboxes"] += 1
                    add_example(
                        summary["examples"]["invalid_bboxes"],
                        f"{display_path(label_path)}:{line_number}",
                    )
                    continue
                summary["class_bbox_counts"][str(class_index)] += 1
                classes_in_image.add(class_index)

            for class_index in classes_in_image:
                summary["class_image_counts"][str(class_index)] += 1

        for key, value in split_summary.items():
            if isinstance(value, int) and key in summary["totals"]:
                summary["totals"][key] += value
        summary["splits"][split] = split_summary

    duplicate_stems: dict[str, list[str]] = {}
    all_stems: dict[str, list[str]] = defaultdict(list)
    for split, stems in stems_by_split.items():
        for stem in stems:
            all_stems[stem].append(split)
    for stem, splits in all_stems.items():
        if len(splits) > 1:
            duplicate_stems[stem] = splits
            add_example(summary["examples"]["duplicate_stems_across_splits"], f"{stem}: {splits}")
    summary["totals"]["duplicate_stems_across_splits"] = len(duplicate_stems)

    if hash_duplicates:
        duplicate_hashes = {digest: paths for digest, paths in image_hashes.items() if len(paths) > 1}
        summary["totals"]["duplicate_image_hashes"] = len(duplicate_hashes)
        for paths in duplicate_hashes.values():
            add_example(summary["examples"]["duplicate_image_hashes"], paths)

    summary["examples"] = dict(summary["examples"])
    return summary


def class_rows(summary: dict[str, Any]) -> list[dict[str, Any]]:
    names = summary["names"]
    bbox_counts = summary["class_bbox_counts"]
    image_counts = summary["class_image_counts"]
    rows = []
    for index, name in enumerate(names):
        rows.append(
            {
                "class_index": index,
                "class_name": name,
                "bbox_count": bbox_counts.get(str(index), 0),
                "image_count": image_counts.get(str(index), 0),
            }
        )
    return rows


def write_reports(summary: dict[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    summary_path = output_dir / "dataset_audit_summary.json"
    distribution_path = output_dir / "dataset_class_distribution.csv"
    class_distribution_report_path = output_dir / "class_distribution_report.csv"
    duplicate_report_path = output_dir / "duplicate_images_report.csv"
    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    write_csv_rows(
        distribution_path,
        class_rows(summary),
        ["class_index", "class_name", "bbox_count", "image_count"],
    )
    if "class_distribution_report_rows" in summary:
        write_csv_rows(
            class_distribution_report_path,
            summary["class_distribution_report_rows"],
            [
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
            ],
        )
    if "duplicate_image_report_rows" in summary:
        write_csv_rows(
            duplicate_report_path,
            summary["duplicate_image_report_rows"],
            [
                "hash",
                "image_path",
                "split",
                "label_path",
                "class_ids",
                "bbox_count",
                "label_fingerprint",
                "duplicate_group_id",
                "same_label_as_group",
                "recommended_action",
                "notes",
            ],
        )


def main() -> int:
    args = parse_args()
    data_yaml = Path(args.data_yaml)
    summary = audit_dataset(data_yaml, hash_duplicates=args.hash_duplicates)
    try:
        _, records = collect_image_records(data_yaml)
        summary["class_distribution_report_rows"] = class_distribution_report_rows(
            summary,
            records,
        )
        if args.hash_duplicates:
            summary["duplicate_image_report_rows"] = duplicate_report_rows(records)
    except ValueError as error:
        summary["examples"].setdefault("report_generation_errors", []).append(str(error))
    if not args.no_write:
        write_reports(summary, Path(args.output_dir))

    totals = summary["totals"]
    print(f"Dataset: {summary['data_yaml']}")
    print(f"Images: {totals['images']}  Labels: {totals['labels']}")
    print(f"YAML nc matches names: {summary['yaml_nc_matches_names']}")
    print(
        "Issues: "
        f"missing_labels={totals['missing_labels']}, "
        f"missing_images={totals['missing_images']}, "
        f"empty_labels={totals['empty_labels']}, "
        f"out_of_range={totals['out_of_range_class_indices']}, "
        f"invalid_bboxes={totals['invalid_bboxes']}, "
        f"split_stem_duplicates={totals['duplicate_stems_across_splits']}"
    )
    if not args.no_write:
        print(f"Reports written to: {args.output_dir}")
    return 1 if summary["yaml_errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
