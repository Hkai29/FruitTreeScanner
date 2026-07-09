#!/usr/bin/env python3
"""Audit a YOLO-format detection dataset for FruitTreeScanner retraining.

The checker intentionally uses only the Python standard library so it can run
before ML dependencies are installed. It validates dataset structure, image and
label pairing, class index bounds, basic bbox validity, split leakage, and class
distribution. Reports are compact summaries with capped examples.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import struct
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLITS = ("train", "val", "test")
EXAMPLE_LIMIT = 50


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(Path.cwd()))
    except ValueError:
        return str(path)


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


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if value == "":
        return ""
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [item.strip().strip("'\"") for item in body.split(",")]
    try:
        return int(value)
    except ValueError:
        return value.strip("'\"")


def load_data_yaml(path: Path) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    config: dict[str, Any] = {}
    names: dict[int, str] = {}
    in_names = False

    if not path.exists():
        return {}, [f"data.yaml not found: {path}"]

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue

        if line.startswith((" ", "\t")) and in_names:
            item = line.strip()
            if ":" not in item:
                errors.append(f"Invalid names entry: {raw_line}")
                continue
            key, value = item.split(":", 1)
            try:
                names[int(key.strip())] = str(parse_scalar(value))
            except ValueError:
                errors.append(f"Invalid names index: {raw_line}")
            continue

        in_names = False
        if ":" not in line:
            errors.append(f"Invalid yaml line: {raw_line}")
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key == "names" and not value.strip():
            in_names = True
            continue
        parsed = parse_scalar(value)
        if key == "names" and isinstance(parsed, list):
            names = {index: name for index, name in enumerate(parsed)}
        else:
            config[key] = parsed

    if names:
        max_index = max(names)
        config["names"] = [names.get(index, "") for index in range(max_index + 1)]
    else:
        config["names"] = []
        errors.append("data.yaml has no parseable names entries")

    return config, errors


def dataset_root(data_yaml: Path, config: dict[str, Any]) -> Path:
    raw_path = config.get("path")
    if raw_path:
        path = Path(str(raw_path))
        return path if path.is_absolute() else Path.cwd() / path
    return data_yaml.parent


def split_image_dir(root: Path, config: dict[str, Any], split: str) -> Path | None:
    raw = config.get(split)
    if raw is None:
        return None
    path = Path(str(raw))
    return path if path.is_absolute() else root / path


def label_dir_for_image_dir(image_dir: Path) -> Path:
    parts = list(image_dir.parts)
    for index, part in enumerate(parts):
        if part == "images":
            parts[index] = "labels"
            return Path(*parts)
    return image_dir.parent.parent / "labels" / image_dir.name


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
    yaml_nc_matches_names = isinstance(nc, int) and nc == len(names)

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
        images = sorted(
            path for path in image_dir.glob("*") if path.suffix.lower() in IMAGE_EXTENSIONS
        ) if image_dir.exists() else []
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

            try:
                raw_lines = label_path.read_text(encoding="utf-8").splitlines()
            except UnicodeDecodeError:
                raw_lines = label_path.read_text(encoding="utf-8", errors="replace").splitlines()
            nonempty = [line for line in raw_lines if line.strip()]
            if not nonempty:
                split_summary["empty_labels"] += 1
                add_example(summary["examples"]["empty_labels"], label_path)
                continue

            classes_in_image: set[int] = set()
            for line_number, line in enumerate(nonempty, start=1):
                parts = line.split()
                if len(parts) != 5:
                    split_summary["invalid_label_lines"] += 1
                    add_example(
                        summary["examples"]["invalid_label_lines"],
                        f"{display_path(label_path)}:{line_number}",
                    )
                    continue
                try:
                    class_index = int(float(parts[0]))
                    x_center, y_center, width, height = map(float, parts[1:])
                except ValueError:
                    split_summary["invalid_label_lines"] += 1
                    add_example(
                        summary["examples"]["invalid_label_lines"],
                        f"{display_path(label_path)}:{line_number}",
                    )
                    continue
                if class_index < 0 or class_index >= len(names):
                    split_summary["out_of_range_class_indices"] += 1
                    add_example(
                        summary["examples"]["out_of_range_class_indices"],
                        f"{display_path(label_path)}:{line_number}:{class_index}",
                    )
                    continue
                if (
                    not 0 <= x_center <= 1
                    or not 0 <= y_center <= 1
                    or not 0 < width <= 1
                    or not 0 < height <= 1
                ):
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
    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    with distribution_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["class_index", "class_name", "bbox_count", "image_count"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(class_rows(summary))


def main() -> int:
    args = parse_args()
    summary = audit_dataset(Path(args.data_yaml), hash_duplicates=args.hash_duplicates)
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
