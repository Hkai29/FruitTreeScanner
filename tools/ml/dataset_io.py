"""Small, side-effect-free I/O helpers shared by ML dataset tooling.

The helpers deliberately use only the standard library. Importing this module
does not inspect datasets or write reports; callers opt into I/O explicitly.
"""

from __future__ import annotations

import csv
import math
from collections import Counter
from pathlib import Path
from typing import Any, Iterable, Mapping


IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".bmp", ".webp"})
SPLITS = ("train", "val", "test")


def normalize_path(path: str | Path, base: Path | None = None) -> Path:
    """Return an absolute normalized path, resolving relative paths from ``base``."""
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate.resolve()
    return ((base or Path.cwd()) / candidate).resolve()


def display_path(path: Path, base: Path | None = None) -> str:
    """Render a path relative to ``base`` when possible."""
    resolved = path.resolve()
    try:
        return str(resolved.relative_to((base or Path.cwd()).resolve()))
    except ValueError:
        return str(path)


def parse_scalar(value: str) -> Any:
    """Parse the compact scalar/list syntax used by the repository's data.yaml."""
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
    """Read the subset of YOLO data.yaml used by the dataset tooling.

    Returns parsed values plus validation errors so audit callers can report
    all configuration issues without mutating the dataset.
    """
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


def resolve_dataset_root(data_yaml: Path, config: Mapping[str, Any]) -> Path:
    """Resolve a YOLO dataset root from its data.yaml ``path`` value."""
    raw_path = config.get("path")
    if raw_path:
        return normalize_path(str(raw_path))
    return data_yaml.parent


def class_count_matches_names(config: Mapping[str, Any]) -> bool:
    """Return whether a parsed YOLO config has a matching integer ``nc`` value."""
    names = config.get("names")
    return isinstance(config.get("nc"), int) and isinstance(names, list) and config["nc"] == len(names)


def resolve_split_path(
    dataset_root: Path,
    config: Mapping[str, Any],
    split: str,
) -> Path | None:
    """Resolve the configured image directory for one split."""
    raw_path = config.get(split)
    if raw_path is None:
        return None
    return normalize_path(str(raw_path), dataset_root)


def label_dir_for_image_dir(image_dir: Path) -> Path:
    """Map an images directory to its sibling labels directory."""
    parts = list(image_dir.parts)
    for index, part in enumerate(parts):
        if part == "images":
            parts[index] = "labels"
            return Path(*parts)
    return image_dir.parent.parent / "labels" / image_dir.name


def label_path_for_image(
    image_path: Path,
    images_root: Path,
    labels_root: Path,
) -> Path:
    """Map an image path to the matching YOLO label path."""
    return (labels_root / image_path.relative_to(images_root)).with_suffix(".txt")


def iter_image_files(directory: Path, recursive: bool = False) -> list[Path]:
    """Return supported image files in deterministic path order."""
    if not directory.exists():
        return []
    candidates: Iterable[Path] = directory.rglob("*") if recursive else directory.glob("*")
    return sorted(
        path for path in candidates if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )


def read_yolo_label_file(label_path: Path) -> list[str]:
    """Read a label file with the audit tools' replacement decoding policy."""
    try:
        return label_path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return label_path.read_text(encoding="utf-8", errors="replace").splitlines()


def parse_yolo_row(row: str) -> tuple[int, float, float, float, float] | None:
    """Parse one five-column YOLO row, or return ``None`` when malformed."""
    parts = row.split()
    if len(parts) != 5:
        return None
    try:
        class_index = int(float(parts[0]))
        x_center, y_center, width, height = (float(value) for value in parts[1:])
    except (OverflowError, ValueError):
        return None
    return class_index, x_center, y_center, width, height


def validate_yolo_bbox(x_center: float, y_center: float, width: float, height: float) -> bool:
    """Return whether normalized YOLO coordinates describe a finite valid box."""
    values = (x_center, y_center, width, height)
    return (
        all(math.isfinite(value) for value in values)
        and 0 <= x_center <= 1
        and 0 <= y_center <= 1
        and 0 < width <= 1
        and 0 < height <= 1
    )


def count_classes(rows: Iterable[str], class_count: int) -> Counter[int]:
    """Count syntactically valid, in-range class IDs from YOLO rows."""
    counts: Counter[int] = Counter()
    for row in rows:
        parsed = parse_yolo_row(row)
        if parsed is None:
            continue
        class_index = parsed[0]
        if 0 <= class_index < class_count:
            counts[class_index] += 1
    return counts


def read_csv_rows(
    path: Path,
    required_fields: Iterable[str] = (),
) -> list[dict[str, str]]:
    """Read trimmed CSV rows and validate the required header fields."""
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("CSV has no header")
        missing = [field for field in required_fields if field not in reader.fieldnames]
        if missing:
            raise ValueError(f"CSV missing fields: {', '.join(missing)}")
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def write_csv_rows(
    path: Path,
    rows: Iterable[Mapping[str, Any]],
    fieldnames: list[str],
) -> None:
    """Write deterministic UTF-8 CSV output with a single LF line ending."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
