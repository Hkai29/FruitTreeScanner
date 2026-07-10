#!/usr/bin/env python3
"""Prepare or apply an approved core-class dataset copy without touching source data.

The default path is a dry run. Apply mode is deliberately guarded: every
decision must be final, source files must validate, and the result is copied
to a new dataset root. The original 26-class dataset is never moved, deleted,
or rewritten by this tool.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import shutil
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

from audit_yolo_dataset import IMAGE_EXTENSIONS, load_data_yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET_ROOT = "ml/datasets/fruit_dataset_26"
DEFAULT_DUPLICATE_DECISIONS = "ml/audit_reports/duplicate_cleanup_decisions.csv"
DEFAULT_SPLIT_DECISIONS = "ml/audit_reports/fixed_test_split_decisions.csv"
DEFAULT_OUTPUT_ROOT = "ml/datasets/fruit_dataset_6_core_v1"
DEFAULT_SUMMARY = "ml/audit_reports/dataset_cleanup_dry_run_summary.md"
DEFAULT_DUPLICATE_REPORT = "ml/audit_reports/duplicate_images_report.csv"
DEFAULT_SPLIT_PLAN = "ml/audit_reports/test_split_plan.csv"
DEFAULT_SEED = 20260709
CORE_CLASS_NAMES = ("apple", "orange", "pear", "persimmon", "grape", "strawberry")
DUPLICATE_ACTIONS = {
    "pending_review",
    "keep",
    "remove_duplicate",
    "review_label_conflict",
}
SPLIT_ACTIONS = {
    "pending_review",
    "approve_move_to_test",
    "keep_in_train",
    "exclude_from_core_test",
    "manual_review",
}
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


class CleanupError(RuntimeError):
    """Raised when a dataset operation is unsafe or incomplete."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare or apply approved duplicate cleanup and a core-class fixed "
            "test split without changing the source dataset."
        )
    )
    parser.add_argument(
        "--dataset-root",
        default=DEFAULT_DATASET_ROOT,
        help=f"Source dataset root. Default: {DEFAULT_DATASET_ROOT}",
    )
    parser.add_argument(
        "--duplicate-decisions",
        default=DEFAULT_DUPLICATE_DECISIONS,
        help=f"Duplicate approval CSV. Default: {DEFAULT_DUPLICATE_DECISIONS}",
    )
    parser.add_argument(
        "--split-decisions",
        default=DEFAULT_SPLIT_DECISIONS,
        help=f"Fixed test-split approval CSV. Default: {DEFAULT_SPLIT_DECISIONS}",
    )
    parser.add_argument(
        "--output-root",
        default=DEFAULT_OUTPUT_ROOT,
        help=(
            "New dataset root used only by approved apply mode. "
            f"Default: {DEFAULT_OUTPUT_ROOT}"
        ),
    )
    parser.add_argument(
        "--mode",
        choices=("dry-run", "apply"),
        default="dry-run",
        help="Execution mode. Default: dry-run",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Force dry-run behavior even when --mode apply is supplied.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"Recorded fixed-split seed. Default: {DEFAULT_SEED}",
    )
    parser.add_argument(
        "--write-decision-templates",
        action="store_true",
        help=(
            "Create approval CSV templates from the existing audit reports. "
            "Refuses to overwrite existing approval files."
        ),
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
        raise CleanupError(f"CSV not found: {display_path(path)}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise CleanupError(f"CSV has no header: {display_path(path)}")
        missing = [field for field in required_fields if field not in reader.fieldnames]
        if missing:
            raise CleanupError(
                f"CSV missing fields ({', '.join(missing)}): {display_path(path)}"
            )
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def load_source_dataset(dataset_root: Path) -> tuple[dict[str, Any], list[str]]:
    data_yaml = dataset_root / "data.yaml"
    config, errors = load_data_yaml(data_yaml)
    if errors:
        raise CleanupError("; ".join(errors))
    names = [str(name).strip() for name in config.get("names", [])]
    nc = config.get("nc")
    if not isinstance(nc, int) or nc != len(names):
        raise CleanupError(
            f"data.yaml class count is invalid: nc={nc!r}, names={len(names)}"
        )
    if not names or any(not name for name in names):
        raise CleanupError("data.yaml contains empty or missing class names")
    if len(set(names)) != len(names):
        raise CleanupError("data.yaml contains duplicate class names")
    return config, names


def split_directories(dataset_root: Path, config: dict[str, Any]) -> dict[str, Path]:
    directories: dict[str, Path] = {}
    for split in ("train", "val", "test"):
        raw_path = config.get(split)
        if raw_path is None:
            continue
        candidate = Path(str(raw_path))
        image_dir = candidate.resolve() if candidate.is_absolute() else (dataset_root / candidate).resolve()
        try:
            image_dir.relative_to(dataset_root)
        except ValueError as error:
            raise CleanupError(
                f"{split} image directory escapes dataset root: {image_dir}"
            ) from error
        directories[split] = image_dir
    if "train" not in directories or "val" not in directories:
        raise CleanupError("data.yaml must declare both train and val image directories")
    return directories


def label_directory(dataset_root: Path, image_dir: Path) -> Path:
    relative = image_dir.relative_to(dataset_root)
    parts = list(relative.parts)
    if "images" not in parts:
        raise CleanupError(f"Image directory is not under images/: {display_path(image_dir)}")
    parts[parts.index("images")] = "labels"
    return dataset_root.joinpath(*parts)


def parse_yolo_label(label_path: Path, class_count: int) -> tuple[list[tuple[int, list[str]]], str]:
    if not label_path.exists():
        raise CleanupError(f"Missing label file: {display_path(label_path)}")
    try:
        raw_lines = label_path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise CleanupError(f"Label file is not UTF-8: {display_path(label_path)}") from error

    normalized = [line.strip() for line in raw_lines if line.strip()]
    if not normalized:
        raise CleanupError(f"Empty label file: {display_path(label_path)}")

    parsed: list[tuple[int, list[str]]] = []
    for line_number, line in enumerate(normalized, start=1):
        parts = line.split()
        if len(parts) != 5:
            raise CleanupError(
                f"Invalid YOLO label field count at {display_path(label_path)}:{line_number}"
            )
        try:
            raw_class = float(parts[0])
        except ValueError as error:
            raise CleanupError(
                f"Invalid YOLO class index at {display_path(label_path)}:{line_number}"
            ) from error
        if not math.isfinite(raw_class) or not raw_class.is_integer():
            raise CleanupError(
                f"Non-integer YOLO class index at {display_path(label_path)}:{line_number}"
            )
        class_id = int(raw_class)
        if not 0 <= class_id < class_count:
            raise CleanupError(
                f"YOLO class index out of range at {display_path(label_path)}:{line_number}"
            )
        try:
            coordinates = [float(value) for value in parts[1:]]
        except ValueError as error:
            raise CleanupError(
                f"Invalid YOLO coordinates at {display_path(label_path)}:{line_number}"
            ) from error
        x_center, y_center, width, height = coordinates
        if (
            not all(math.isfinite(value) for value in coordinates)
            or not 0 <= x_center <= 1
            or not 0 <= y_center <= 1
            or not 0 < width <= 1
            or not 0 < height <= 1
        ):
            raise CleanupError(
                f"YOLO coordinates out of range at {display_path(label_path)}:{line_number}"
            )
        parsed.append((class_id, parts[1:]))

    fingerprint = hashlib.sha256(
        "\n".join(sorted(normalized)).encode("utf-8")
    ).hexdigest()
    return parsed, fingerprint


def collect_source_records(
    dataset_root: Path,
    config: dict[str, Any],
    class_count: int,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for split, image_dir in split_directories(dataset_root, config).items():
        if not image_dir.exists():
            raise CleanupError(f"Missing {split} image directory: {display_path(image_dir)}")
        labels_dir = label_directory(dataset_root, image_dir)
        if not labels_dir.exists():
            raise CleanupError(f"Missing {split} label directory: {display_path(labels_dir)}")

        images = sorted(
            path
            for path in image_dir.rglob("*")
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
        )
        if not images:
            raise CleanupError(f"No images found in {display_path(image_dir)}")

        expected_labels: set[Path] = set()
        for image_path in images:
            relative = image_path.relative_to(image_dir)
            label_path = (labels_dir / relative).with_suffix(".txt")
            entries, fingerprint = parse_yolo_label(label_path, class_count)
            expected_labels.add(label_path.resolve())
            records.append(
                {
                    "split": split,
                    "image_path": image_path.resolve(),
                    "label_path": label_path.resolve(),
                    "relative_path": relative,
                    "entries": entries,
                    "class_ids": sorted({class_id for class_id, _ in entries}),
                    "bbox_count": len(entries),
                    "label_fingerprint": fingerprint,
                }
            )

        actual_labels = {
            path.resolve() for path in labels_dir.rglob("*.txt") if path.is_file()
        }
        orphan_labels = actual_labels - expected_labels
        if orphan_labels:
            example = display_path(sorted(orphan_labels)[0])
            raise CleanupError(f"Label file has no matching image: {example}")
    return records


def class_names_for_ids(class_ids: str, names: list[str]) -> str:
    ids = [int(value) for value in class_ids.split("|") if value]
    if any(not 0 <= class_id < len(names) for class_id in ids):
        raise CleanupError(f"Class ID is out of range in audit report: {class_ids}")
    return "|".join(names[class_id] for class_id in ids)


def core_recommended_action(class_names: str) -> str:
    labels = {name for name in class_names.split("|") if name}
    return (
        "candidate_for_core_test"
        if labels.intersection(CORE_CLASS_NAMES)
        else "review_or_exclude_from_core_test"
    )


def expected_duplicate_rows(names: list[str]) -> list[dict[str, str]]:
    rows = read_csv(
        repo_path(DEFAULT_DUPLICATE_REPORT),
        [
            "image_path",
            "label_path",
            "class_ids",
            "bbox_count",
            "label_fingerprint",
            "duplicate_group_id",
            "recommended_action",
            "notes",
        ],
    )
    return [
        {
            "duplicate_group_id": row["duplicate_group_id"],
            "image_path": row["image_path"],
            "label_path": row["label_path"],
            "class_names": class_names_for_ids(row["class_ids"], names),
            "bbox_count": row["bbox_count"],
            "label_fingerprint": row["label_fingerprint"],
            "recommended_action": row["recommended_action"],
            "approved_action": "pending_review",
            "human_review_required": "yes",
            "notes": f"{row['notes']}; visual review required before any copy cleanup",
        }
        for row in rows
    ]


def expected_split_rows(names: list[str]) -> list[dict[str, str]]:
    rows = read_csv(
        repo_path(DEFAULT_SPLIT_PLAN),
        [
            "image_path",
            "label_path",
            "current_split",
            "planned_split",
            "class_ids",
            "bbox_count",
            "reason",
        ],
    )
    prepared: list[dict[str, str]] = []
    for row in rows:
        class_names = class_names_for_ids(row["class_ids"], names)
        prepared.append(
            {
                "image_path": row["image_path"],
                "label_path": row["label_path"],
                "current_split": row["current_split"],
                "planned_split": row["planned_split"],
                "class_names": class_names,
                "bbox_count": row["bbox_count"],
                "recommended_action": core_recommended_action(class_names),
                "approved_action": "pending_review",
                "notes": f"source plan reason: {row['reason']}; explicit approval required",
            }
        )
    return prepared


def write_decision_templates(
    duplicate_path: Path,
    split_path: Path,
    names: list[str],
) -> None:
    if duplicate_path.exists() or split_path.exists():
        existing = [
            display_path(path)
            for path in (duplicate_path, split_path)
            if path.exists()
        ]
        raise CleanupError(
            "Refusing to overwrite existing approval CSVs: " + ", ".join(existing)
        )
    write_csv(duplicate_path, DUPLICATE_FIELDS, expected_duplicate_rows(names))
    write_csv(split_path, SPLIT_FIELDS, expected_split_rows(names))


def record_map(records: list[dict[str, Any]]) -> dict[Path, dict[str, Any]]:
    return {record["image_path"]: record for record in records}


def validate_duplicate_decisions(
    path: Path,
    expected_rows: list[dict[str, str]],
    source_records: dict[Path, dict[str, Any]],
    names: list[str],
) -> list[dict[str, str]]:
    rows = read_csv(path, DUPLICATE_FIELDS)
    expected_by_key = {
        (row["duplicate_group_id"], row["image_path"], row["label_path"]): row
        for row in expected_rows
    }
    received_by_key: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in rows:
        key = (row["duplicate_group_id"], row["image_path"], row["label_path"])
        if key in received_by_key:
            raise CleanupError(f"Duplicate approval row repeated: {key[0]} / {key[1]}")
        if row["approved_action"] not in DUPLICATE_ACTIONS:
            raise CleanupError(f"Unsupported duplicate approved_action: {row['approved_action']}")
        received_by_key[key] = row

    if set(received_by_key) != set(expected_by_key):
        raise CleanupError("Duplicate decision rows do not exactly match the audit report")

    removals_by_group: Counter[str] = Counter()
    for key, expected in expected_by_key.items():
        row = received_by_key[key]
        for field in (
            "class_names",
            "bbox_count",
            "label_fingerprint",
            "recommended_action",
            "human_review_required",
        ):
            if row[field] != expected[field]:
                raise CleanupError(f"Duplicate decision changed protected field {field}: {key[1]}")
        image_path = repo_path(row["image_path"])
        label_path = repo_path(row["label_path"])
        record = source_records.get(image_path)
        if record is None or record["label_path"] != label_path:
            raise CleanupError(f"Duplicate decision source is missing or mismatched: {key[1]}")
        actual_names = "|".join(names[class_id] for class_id in record["class_ids"])
        if row["class_names"] != actual_names:
            raise CleanupError(f"Duplicate decision class names no longer match source: {key[1]}")
        if row["bbox_count"] != str(record["bbox_count"]):
            raise CleanupError(f"Duplicate decision bbox count no longer matches source: {key[1]}")
        if row["label_fingerprint"] != record["label_fingerprint"]:
            raise CleanupError(f"Duplicate decision label fingerprint no longer matches source: {key[1]}")
        if row["approved_action"] == "remove_duplicate":
            removals_by_group[row["duplicate_group_id"]] += 1

    over_removed = [group for group, count in removals_by_group.items() if count > 1]
    if over_removed:
        raise CleanupError(
            "At most one duplicate copy may be removed per group: " + ", ".join(over_removed)
        )
    return rows


def validate_split_decisions(
    path: Path,
    expected_rows: list[dict[str, str]],
    source_records: dict[Path, dict[str, Any]],
    names: list[str],
) -> list[dict[str, str]]:
    rows = read_csv(path, SPLIT_FIELDS)
    expected_by_key = {(row["image_path"], row["label_path"]): row for row in expected_rows}
    received_by_key: dict[tuple[str, str], dict[str, str]] = {}
    for row in rows:
        key = (row["image_path"], row["label_path"])
        if key in received_by_key:
            raise CleanupError(f"Split approval row repeated: {key[0]}")
        if row["approved_action"] not in SPLIT_ACTIONS:
            raise CleanupError(f"Unsupported split approved_action: {row['approved_action']}")
        received_by_key[key] = row

    if set(received_by_key) != set(expected_by_key):
        raise CleanupError("Split decision rows do not exactly match the fixed test plan")

    for key, expected in expected_by_key.items():
        row = received_by_key[key]
        for field in (
            "current_split",
            "planned_split",
            "class_names",
            "bbox_count",
            "recommended_action",
        ):
            if row[field] != expected[field]:
                raise CleanupError(f"Split decision changed protected field {field}: {key[0]}")
        image_path = repo_path(row["image_path"])
        label_path = repo_path(row["label_path"])
        record = source_records.get(image_path)
        if record is None or record["label_path"] != label_path:
            raise CleanupError(f"Split decision source is missing or mismatched: {key[0]}")
        actual_names = "|".join(names[class_id] for class_id in record["class_ids"])
        if row["class_names"] != actual_names:
            raise CleanupError(f"Split decision class names no longer match source: {key[0]}")
        if row["bbox_count"] != str(record["bbox_count"]):
            raise CleanupError(f"Split decision bbox count no longer matches source: {key[0]}")
    return rows


def unresolved_counts(
    duplicate_rows: list[dict[str, str]], split_rows: list[dict[str, str]]
) -> dict[str, int]:
    return {
        "pending_duplicate": sum(
            row["approved_action"] == "pending_review" for row in duplicate_rows
        ),
        "manual_duplicate": sum(
            row["approved_action"] == "review_label_conflict" for row in duplicate_rows
        ),
        "pending_split": sum(
            row["approved_action"] == "pending_review" for row in split_rows
        ),
        "manual_split": sum(
            row["approved_action"] == "manual_review" for row in split_rows
        ),
    }


def target_plan(
    records: list[dict[str, Any]],
    names: list[str],
    duplicate_rows: list[dict[str, str]],
    split_rows: list[dict[str, str]],
) -> dict[str, Any]:
    source_ids = {name: names.index(name) for name in CORE_CLASS_NAMES}
    remap = {source_ids[name]: target_id for target_id, name in enumerate(CORE_CLASS_NAMES)}
    removed_images = {
        repo_path(row["image_path"])
        for row in duplicate_rows
        if row["approved_action"] == "remove_duplicate"
    }
    split_actions = {repo_path(row["image_path"]): row["approved_action"] for row in split_rows}
    targets: dict[str, list[dict[str, Any]]] = {"train": [], "val": [], "test": []}
    pending_records: list[dict[str, Any]] = []
    excluded_non_core: list[dict[str, Any]] = []
    excluded_duplicate: list[dict[str, Any]] = []

    for record in records:
        core_entries = [entry for entry in record["entries"] if entry[0] in remap]
        if not core_entries:
            excluded_non_core.append(record)
            continue
        if record["image_path"] in removed_images:
            excluded_duplicate.append(record)
            continue

        destination = record["split"]
        action = split_actions.get(record["image_path"])
        if record["split"] == "train" and action is not None:
            if action == "approve_move_to_test":
                destination = "test"
            elif action in {"keep_in_train", "exclude_from_core_test"}:
                destination = "train"
            elif action in {"pending_review", "manual_review"}:
                pending_records.append(record)
                continue
        if destination not in targets:
            raise CleanupError(
                f"Unsupported source split for core dataset: {record['split']}"
            )
        target_record = dict(record)
        target_record["core_entries"] = [(remap[class_id], values) for class_id, values in core_entries]
        targets[destination].append(target_record)

    return {
        "targets": targets,
        "pending_records": pending_records,
        "excluded_non_core": excluded_non_core,
        "excluded_duplicate": excluded_duplicate,
        "remap": remap,
    }


def sample_paths(records: list[dict[str, Any]], limit: int = 8) -> list[str]:
    return [display_path(record["image_path"]) for record in records[:limit]]


def write_dry_run_summary(
    path: Path,
    dataset_root: Path,
    output_root: Path,
    seed: int,
    names: list[str],
    duplicate_rows: list[dict[str, str]],
    split_rows: list[dict[str, str]],
    plan: dict[str, Any],
    counts: dict[str, int],
    is_dry_run: bool,
) -> None:
    duplicate_actions = Counter(row["approved_action"] for row in duplicate_rows)
    split_actions = Counter(row["approved_action"] for row in split_rows)
    blocked_reasons: list[str] = []
    if counts["pending_duplicate"]:
        blocked_reasons.append(f"{counts['pending_duplicate']} duplicate decisions are pending_review")
    if counts["manual_duplicate"]:
        blocked_reasons.append(f"{counts['manual_duplicate']} duplicate decisions require label-conflict review")
    if counts["pending_split"]:
        blocked_reasons.append(f"{counts['pending_split']} split decisions are pending_review")
    if counts["manual_split"]:
        blocked_reasons.append(f"{counts['manual_split']} split decisions require manual review")
    blocked = bool(blocked_reasons)
    targets = plan["targets"]
    non_core_names = [name for name in names if name not in CORE_CLASS_NAMES]
    lines = [
        "# Dataset Cleanup Dry-Run Summary",
        "",
        f"- Mode: {'dry-run' if is_dry_run else 'apply-preflight'}",
        f"- Source dataset: `{display_path(dataset_root)}`",
        f"- Planned output dataset: `{display_path(output_root)}`",
        f"- Fixed split seed: `{seed}`",
        f"- Core classes: {', '.join(f'`{name}`' for name in CORE_CLASS_NAMES)}",
        f"- Apply currently blocked: {'yes' if blocked else 'no'}",
        "",
        "## Approval State",
        "",
        f"- Pending duplicate decisions: {counts['pending_duplicate']}",
        f"- Duplicate label-conflict reviews: {counts['manual_duplicate']}",
        f"- Pending split decisions: {counts['pending_split']}",
        f"- Split manual reviews: {counts['manual_split']}",
        "",
        "## Planned Duplicate Actions",
        "",
        f"- Keep: {duplicate_actions['keep']}",
        f"- Remove from the new dataset copy: {duplicate_actions['remove_duplicate']}",
        f"- Pending review: {duplicate_actions['pending_review']}",
        f"- Label-conflict review: {duplicate_actions['review_label_conflict']}",
        "",
        "## Planned Fixed Test-Split Actions",
        "",
        f"- Approve move to test: {split_actions['approve_move_to_test']}",
        f"- Keep in train: {split_actions['keep_in_train']}",
        f"- Exclude from core test (retained in core train when applicable): {split_actions['exclude_from_core_test']}",
        f"- Pending review: {split_actions['pending_review']}",
        f"- Manual review: {split_actions['manual_review']}",
        "",
        "## Files That Would Be Copied",
        "",
        "No source file is copied in dry-run mode. The resolved projection below "
        "shows only records whose destination is currently explicit; pending split "
        "rows are withheld until approved.",
        "",
        "| Target split | Resolved core image records |",
        "| --- | ---: |",
        f"| train | {len(targets['train'])} |",
        f"| val | {len(targets['val'])} |",
        f"| test | {len(targets['test'])} |",
        f"| pending split decision | {len(plan['pending_records'])} |",
        "",
        "Examples of resolved copy candidates (capped at eight per split):",
    ]
    for split in ("train", "val", "test"):
        examples = sample_paths(targets[split])
        lines.append(f"- {split}: {', '.join(f'`{item}`' for item in examples) or 'none'}")
    pending_examples = sample_paths(plan["pending_records"])
    lines.append(
        "- pending: "
        + (", ".join(f"`{item}`" for item in pending_examples) if pending_examples else "none")
    )
    lines.extend(
        [
            "",
            "## Files Excluded From the Core Copy",
            "",
            f"- Non-core-only source records: {len(plan['excluded_non_core'])}",
            "- Non-core classes excluded from the target labels: "
            + ", ".join(f"`{name}`" for name in non_core_names),
            f"- Approved duplicate removals that would affect the new copy: {len(plan['excluded_duplicate'])}",
            "- The original 26-class dataset is preserved in all cases.",
            "",
            "## Target Dataset Rules",
            "",
            "- Core annotations would be remapped to the six-class order: `apple`, "
            "`orange`, `pear`, `persimmon`, `grape`, `strawberry`.",
            "- Non-core annotations would not be copied into the new core-only labels.",
            "- `exclude_from_core_test` keeps an otherwise eligible image in target train; "
            "it does not delete the source image.",
            "- Apply mode creates a new output root only and refuses to overwrite an existing one.",
            "",
            "## Blocked Reasons" if blocked else "## Apply Readiness",
            "",
        ]
    )
    if blocked:
        lines.extend(f"- {reason}" for reason in blocked_reasons)
        lines.append("- Change approved_action to an explicit final decision before apply mode.")
    else:
        lines.append("- All decisions are final. Apply mode may create the new dataset copy.")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_target_dataset(
    output_root: Path,
    source_root: Path,
    plan: dict[str, Any],
    seed: int,
) -> None:
    if output_root.exists():
        raise CleanupError(f"Output root already exists: {display_path(output_root)}")
    if output_root.resolve() == source_root.resolve():
        raise CleanupError("Output root must not be the source dataset root")
    try:
        output_root.resolve().relative_to(source_root.resolve())
    except ValueError:
        pass
    else:
        raise CleanupError("Output root must not be inside the source dataset root")
    output_root.parent.mkdir(parents=True, exist_ok=True)
    staging_root = Path(
        tempfile.mkdtemp(prefix=f".{output_root.name}.staging-", dir=output_root.parent)
    )
    try:
        copied_counts: Counter[str] = Counter()
        for split, records in plan["targets"].items():
            for record in records:
                image_destination = staging_root / "images" / split / record["relative_path"]
                label_destination = (staging_root / "labels" / split / record["relative_path"]).with_suffix(".txt")
                image_destination.parent.mkdir(parents=True, exist_ok=True)
                label_destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(record["image_path"], image_destination)
                label_lines = [
                    " ".join([str(class_id), *coordinates])
                    for class_id, coordinates in record["core_entries"]
                ]
                label_destination.write_text("\n".join(label_lines) + "\n", encoding="utf-8")
                copied_counts[split] += 1

        output_path = display_path(output_root)
        names_lines = "\n".join(
            f"  {index}: {name}" for index, name in enumerate(CORE_CLASS_NAMES)
        )
        (staging_root / "data.yaml").write_text(
            "\n".join(
                [
                    f"path: {output_path}",
                    "train: images/train",
                    "val: images/val",
                    "test: images/test",
                    "",
                    "nc: 6",
                    "names:",
                    names_lines,
                    "",
                ]
            ),
            encoding="utf-8",
        )
        (staging_root / "DATASET_VERSION.md").write_text(
            "\n".join(
                [
                    "# Fruit Dataset 6 Core v1",
                    "",
                    "- Source dataset: `ml/datasets/fruit_dataset_26`",
                    f"- Fixed split seed: `{seed}`",
                    "- Core order: " + ", ".join(f"`{name}`" for name in CORE_CLASS_NAMES),
                    f"- Train images: {copied_counts['train']}",
                    f"- Validation images: {copied_counts['val']}",
                    f"- Test images: {copied_counts['test']}",
                    "- Original 26-class dataset: preserved and unchanged",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        staging_root.replace(output_root)
    except Exception:
        shutil.rmtree(staging_root, ignore_errors=True)
        raise


def main() -> int:
    args = parse_args()
    is_dry_run = args.dry_run or args.mode == "dry-run"
    dataset_root = repo_path(args.dataset_root)
    duplicate_path = repo_path(args.duplicate_decisions)
    split_path = repo_path(args.split_decisions)
    output_root = repo_path(args.output_root)
    summary_path = repo_path(DEFAULT_SUMMARY)

    try:
        config, names = load_source_dataset(dataset_root)
        if any(name not in names for name in CORE_CLASS_NAMES):
            raise CleanupError("Source data.yaml is missing one or more required core classes")
        records = collect_source_records(dataset_root, config, len(names))
        source_records = record_map(records)
        if args.write_decision_templates:
            write_decision_templates(duplicate_path, split_path, names)
            print(f"Decision templates written: {display_path(duplicate_path)}, {display_path(split_path)}")

        duplicate_rows = validate_duplicate_decisions(
            duplicate_path,
            expected_duplicate_rows(names),
            source_records,
            names,
        )
        split_rows = validate_split_decisions(
            split_path,
            expected_split_rows(names),
            source_records,
            names,
        )
        counts = unresolved_counts(duplicate_rows, split_rows)
        plan = target_plan(records, names, duplicate_rows, split_rows)
        write_dry_run_summary(
            summary_path,
            dataset_root,
            output_root,
            args.seed,
            names,
            duplicate_rows,
            split_rows,
            plan,
            counts,
            is_dry_run,
        )
        blocked = any(counts.values())

        print(f"Source dataset: {display_path(dataset_root)}")
        print(f"Decision templates: {display_path(duplicate_path)}, {display_path(split_path)}")
        print(f"Dry-run summary: {display_path(summary_path)}")
        print(
            "Pending decisions: "
            f"duplicates={counts['pending_duplicate']}, splits={counts['pending_split']}"
        )
        print(f"Apply blocked: {'yes' if blocked else 'no'}")

        if is_dry_run:
            return 0
        if blocked:
            raise CleanupError("Apply blocked until every approval CSV decision is final")
        write_target_dataset(output_root, dataset_root, plan, args.seed)
        print(f"Created approved dataset copy: {display_path(output_root)}")
        return 0
    except (CleanupError, OSError, ValueError) as error:
        print(f"ERROR: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
