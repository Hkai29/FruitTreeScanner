#!/usr/bin/env python3
"""Create a conservative review queue for unsafe or low-quality YOLO images.

The tool is read-only with respect to the dataset. It decodes one image at a
time, hashes files for exact duplicate detection, and writes only the review
CSV. Semantic content is never inferred from a filename or a YOLO class; known
human-review decisions are the only automatic content exclusions.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from PIL import Image, ImageStat, UnidentifiedImageError

from audit_yolo_dataset import IMAGE_EXTENSIONS, load_data_yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_YAML = "ml/datasets/fruit_dataset_26/data.yaml"
DEFAULT_OUTPUT = "ml/audit_reports/dataset_invalid_image_review.csv"
DEFAULT_DUPLICATE_DECISIONS = "ml/audit_reports/duplicate_cleanup_decisions.csv"
DEFAULT_SEMANTIC_REVIEW = "ml/audit_reports/dataset_semantic_image_review.csv"
CSV_FIELDS = [
    "image_path",
    "current_class",
    "issue_type",
    "confidence",
    "recommended_action",
    "notes",
]
ACTION_PRIORITY = {
    "exclude_from_training": 0,
    "manual_review": 1,
    "keep": 2,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Read a YOLO image dataset and write conservative invalid-image "
            "review candidates without changing images or labels."
        )
    )
    parser.add_argument(
        "--data-yaml",
        default=DEFAULT_DATA_YAML,
        help=f"YOLO data.yaml path. Default: {DEFAULT_DATA_YAML}",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help=f"Review CSV output path. Default: {DEFAULT_OUTPUT}",
    )
    parser.add_argument(
        "--duplicate-decisions",
        default=DEFAULT_DUPLICATE_DECISIONS,
        help=(
            "Existing human duplicate decisions used as high-confidence review "
            f"evidence. Default: {DEFAULT_DUPLICATE_DECISIONS}"
        ),
    )
    parser.add_argument(
        "--semantic-review",
        default=DEFAULT_SEMANTIC_REVIEW,
        help=(
            "Optional Apple Vision semantic review CSV merged as manual-review "
            f"evidence. Default: {DEFAULT_SEMANTIC_REVIEW}"
        ),
    )
    parser.add_argument(
        "--thumbnail-size",
        type=int,
        default=128,
        help="Maximum decoded thumbnail dimension for quality metrics. Default: 128",
    )
    return parser.parse_args()


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (REPO_ROOT / path).resolve()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def read_csv(path: Path, required_fields: list[str]) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no header: {display_path(path)}")
        missing = [field for field in required_fields if field not in reader.fieldnames]
        if missing:
            raise ValueError(
                f"CSV missing fields ({', '.join(missing)}): {display_path(path)}"
            )
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def load_dataset(data_yaml: Path) -> tuple[Path, dict[str, Any], list[str]]:
    config, errors = load_data_yaml(data_yaml)
    if errors:
        raise ValueError("; ".join(errors))
    names = [str(name).strip() for name in config.get("names", [])]
    nc = config.get("nc")
    if not isinstance(nc, int) or nc != len(names):
        raise ValueError(f"Invalid data.yaml class count: nc={nc!r}, names={len(names)}")
    dataset_value = Path(str(config.get("path", data_yaml.parent)))
    dataset_root = dataset_value.resolve() if dataset_value.is_absolute() else repo_path(dataset_value)
    if not dataset_root.exists():
        raise ValueError(f"Dataset root not found: {display_path(dataset_root)}")
    return dataset_root, config, names


def image_and_label_directories(
    dataset_root: Path, config: dict[str, Any]
) -> list[tuple[str, Path, Path]]:
    directories: list[tuple[str, Path, Path]] = []
    for split in ("train", "val", "test"):
        configured = config.get(split)
        if configured is None:
            continue
        image_dir_value = Path(str(configured))
        image_dir = (
            image_dir_value.resolve()
            if image_dir_value.is_absolute()
            else (dataset_root / image_dir_value).resolve()
        )
        if not image_dir.exists():
            raise ValueError(f"Image directory not found: {display_path(image_dir)}")
        relative = image_dir.relative_to(dataset_root)
        parts = list(relative.parts)
        if "images" not in parts:
            raise ValueError(f"Image directory is not under images/: {display_path(image_dir)}")
        parts[parts.index("images")] = "labels"
        label_dir = dataset_root.joinpath(*parts)
        if not label_dir.exists():
            raise ValueError(f"Label directory not found: {display_path(label_dir)}")
        directories.append((split, image_dir, label_dir))
    return directories


def parse_current_classes(label_path: Path, names: list[str]) -> str:
    try:
        lines = label_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return "unknown"
    class_ids: set[int] = set()
    for line in lines:
        fields = line.split()
        if not fields:
            continue
        try:
            class_id = int(float(fields[0]))
        except ValueError:
            continue
        if 0 <= class_id < len(names):
            class_ids.add(class_id)
    return "|".join(names[class_id] for class_id in sorted(class_ids)) or "unknown"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def image_quality(path: Path, thumbnail_size: int) -> dict[str, float | int]:
    try:
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            width, height = image.size
            preview = image.convert("RGB")
            preview.thumbnail((thumbnail_size, thumbnail_size))
            stats = ImageStat.Stat(preview)
            mean = sum(stats.mean) / len(stats.mean)
            variance = sum(stats.var) / len(stats.var)
    except (OSError, UnidentifiedImageError, ValueError, SyntaxError) as error:
        raise ValueError(str(error)) from error
    return {
        "width": width,
        "height": height,
        "mean": mean,
        "stddev": math.sqrt(max(variance, 0.0)),
    }


def human_duplicate_decisions(path: Path) -> dict[Path, dict[str, str]]:
    rows = read_csv(
        path,
        ["image_path", "approved_action", "duplicate_group_id", "notes"],
    )
    decisions: dict[Path, dict[str, str]] = {}
    for row in rows:
        image_path = repo_path(row["image_path"])
        if image_path in decisions:
            raise ValueError(f"Duplicate decision path repeated: {display_path(image_path)}")
        decisions[image_path] = row
    return decisions


def semantic_review_rows(path: Path) -> list[dict[str, str]]:
    return read_csv(path, CSV_FIELDS)


def merge_candidate(
    candidates: dict[Path, dict[str, str]],
    image_path: Path,
    candidate: dict[str, str],
) -> None:
    current = candidates.get(image_path)
    if current is None:
        candidates[image_path] = candidate
        return
    if current["recommended_action"] == "exclude_from_training":
        return
    if candidate["recommended_action"] == "exclude_from_training":
        candidates[image_path] = candidate
        return
    if current["recommended_action"] == "keep" and candidate["recommended_action"] == "manual_review":
        candidates[image_path] = candidate


def candidate_from_decision(
    image_path: Path,
    current_class: str,
    decision: dict[str, str],
) -> dict[str, str] | None:
    action = decision["approved_action"]
    group = decision["duplicate_group_id"]
    if action == "remove_duplicate":
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "duplicate_image",
            "confidence": "high_human_approved",
            "recommended_action": "exclude_from_training",
            "notes": (
                f"Duplicate group {group}; human-approved duplicate candidate. "
                "Exclude only from a future training copy; preserve the source file."
            ),
        }
    if action == "keep":
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "duplicate_image",
            "confidence": "high_human_approved",
            "recommended_action": "keep",
            "notes": f"Duplicate group {group}; human-approved canonical retained copy.",
        }
    if action == "review_label_conflict":
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "inappropriate_or_label_mismatch",
            "confidence": "high_human_review",
            "recommended_action": "exclude_from_training",
            "notes": (
                f"Duplicate group {group}; human review reported unexpected content. "
                "Exclude from training pending content, provenance, and label curation; "
                "preserve the source file."
            ),
        }
    if action == "pending_review":
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "duplicate_image",
            "confidence": "high_exact_hash",
            "recommended_action": "manual_review",
            "notes": f"Duplicate group {group}; approval remains pending_review.",
        }
    raise ValueError(f"Unsupported duplicate approved_action: {action}")


def quality_candidate(
    image_path: Path,
    current_class: str,
    metrics: dict[str, float | int] | None,
    error: Exception | None,
) -> dict[str, str] | None:
    if error is not None:
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "corrupt_or_unreadable_image",
            "confidence": "high_decode_failure",
            "recommended_action": "exclude_from_training",
            "notes": f"Pillow could not fully decode the image: {error}",
        }
    assert metrics is not None
    width = int(metrics["width"])
    height = int(metrics["height"])
    mean = float(metrics["mean"])
    stddev = float(metrics["stddev"])
    pixels = width * height
    aspect_ratio = max(width, height) / max(1, min(width, height))
    if mean <= 8.0 and stddev <= 3.0:
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "near_black_image",
            "confidence": "high_pixel_metric",
            "recommended_action": "exclude_from_training",
            "notes": f"mean={mean:.1f}, stddev={stddev:.1f}, size={width}x{height}",
        }
    if min(width, height) < 64 or pixels < 16_384:
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "extremely_low_resolution",
            "confidence": "medium_pixel_metric",
            "recommended_action": "manual_review",
            "notes": f"size={width}x{height}, pixels={pixels}",
        }
    if aspect_ratio > 5.0:
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "extreme_aspect_ratio",
            "confidence": "medium_pixel_metric",
            "recommended_action": "manual_review",
            "notes": f"size={width}x{height}, aspect_ratio={aspect_ratio:.2f}",
        }
    if 8.0 < mean < 247.0 and stddev <= 3.0:
        return {
            "image_path": display_path(image_path),
            "current_class": current_class,
            "issue_type": "very_low_contrast",
            "confidence": "low_pixel_metric",
            "recommended_action": "manual_review",
            "notes": f"mean={mean:.1f}, stddev={stddev:.1f}, size={width}x{height}",
        }
    return None


def write_report(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ordered = sorted(
        rows,
        key=lambda row: (
            ACTION_PRIORITY.get(row["recommended_action"], 99),
            row["issue_type"],
            row["image_path"],
        ),
    )
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(ordered)


def main() -> int:
    args = parse_args()
    data_yaml = repo_path(args.data_yaml)
    output = repo_path(args.output)
    decisions_path = repo_path(args.duplicate_decisions)
    semantic_path = repo_path(args.semantic_review)
    dataset_root, config, names = load_dataset(data_yaml)
    decisions = human_duplicate_decisions(decisions_path)
    candidates: dict[Path, dict[str, str]] = {}
    image_hashes: dict[str, list[Path]] = defaultdict(list)
    scanned = 0

    for _, image_dir, label_dir in image_and_label_directories(dataset_root, config):
        images = sorted(
            path
            for path in image_dir.rglob("*")
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
        )
        for image_path in images:
            scanned += 1
            relative = image_path.relative_to(image_dir)
            label_path = (label_dir / relative).with_suffix(".txt")
            current_class = parse_current_classes(label_path, names)
            resolved_path = image_path.resolve()
            digest = sha256(resolved_path)
            image_hashes[digest].append(resolved_path)

            decision = decisions.get(resolved_path)
            if decision is not None:
                candidate = candidate_from_decision(resolved_path, current_class, decision)
                if candidate is not None:
                    merge_candidate(candidates, resolved_path, candidate)

            try:
                metrics = image_quality(resolved_path, args.thumbnail_size)
                quality_error: Exception | None = None
            except ValueError as error:
                metrics = None
                quality_error = error
            candidate = quality_candidate(resolved_path, current_class, metrics, quality_error)
            if candidate is not None and resolved_path not in candidates:
                merge_candidate(candidates, resolved_path, candidate)

    for digest, paths in image_hashes.items():
        if len(paths) < 2:
            continue
        for image_path in paths:
            if image_path in candidates:
                continue
            merge_candidate(candidates, image_path, {
                "image_path": display_path(image_path),
                "current_class": "unknown",
                "issue_type": "duplicate_image",
                "confidence": "high_exact_hash",
                "recommended_action": "manual_review",
                "notes": (
                    f"Exact SHA-256 duplicate group ({digest[:12]}...). "
                    "No human duplicate decision was found."
                ),
            })

    semantic_rows = semantic_review_rows(semantic_path)
    for row in semantic_rows:
        image_path = repo_path(row["image_path"])
        if not image_path.exists():
            raise ValueError(
                f"Semantic review references a missing image: {display_path(image_path)}"
            )
        merge_candidate(candidates, image_path, row)

    rows = list(candidates.values())
    write_report(output, rows)
    action_counts = Counter(row["recommended_action"] for row in rows)
    issue_counts = Counter(row["issue_type"] for row in rows)
    print(f"Scanned images: {scanned}")
    print(f"Review rows: {len(rows)}")
    print(f"Merged semantic review rows: {len(semantic_rows)}")
    print("Actions: " + ", ".join(f"{key}={action_counts[key]}" for key in sorted(action_counts)))
    print("Issues: " + ", ".join(f"{key}={issue_counts[key]}" for key in sorted(issue_counts)))
    print(f"Report written: {display_path(output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
