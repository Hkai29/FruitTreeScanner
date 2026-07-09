#!/usr/bin/env python3
"""Check YOLO data.yaml label order against the App custom model mapping.

This guard intentionally uses only the Python standard library. It parses the
YOLO `data.yaml` names and the Swift `CustomFruitID` enum, then fails when the
class count, raw label order, or normalized label order diverges.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify data.yaml names match FruitTreeScanner CustomFruitID order."
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Path to YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--swift-file",
        default="FruitTreeScanner/Core/FruitModelMappings.swift",
        help="Swift file containing CustomFruitID. Default: %(default)s",
    )
    return parser.parse_args()


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [item.strip().strip("'\"") for item in body.split(",")]
    try:
        return int(value)
    except ValueError:
        return value.strip("'\"")


def load_data_yaml(path: Path) -> tuple[int | None, list[str]]:
    if not path.exists():
        raise FileNotFoundError(f"data.yaml not found: {path}")

    nc: int | None = None
    indexed_names: dict[int, str] = {}
    list_names: list[str] | None = None
    in_names = False

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue

        if line.startswith((" ", "\t")) and in_names:
            item = line.strip()
            if ":" not in item:
                raise ValueError(f"Invalid names entry in data.yaml: {raw_line}")
            key, value = item.split(":", 1)
            indexed_names[int(key.strip())] = str(parse_scalar(value))
            continue

        in_names = False
        if ":" not in line:
            raise ValueError(f"Invalid line in data.yaml: {raw_line}")
        key, value = line.split(":", 1)
        key = key.strip()
        if key == "nc":
            parsed = parse_scalar(value)
            if not isinstance(parsed, int):
                raise ValueError(f"Invalid nc value in data.yaml: {value.strip()}")
            nc = parsed
        elif key == "names":
            if value.strip():
                parsed = parse_scalar(value)
                if not isinstance(parsed, list):
                    raise ValueError("Inline names must be a YAML-style list")
                list_names = [str(item) for item in parsed]
            else:
                in_names = True

    if list_names is not None:
        return nc, list_names
    if indexed_names:
        return nc, [indexed_names.get(index, "") for index in range(max(indexed_names) + 1)]
    raise ValueError("data.yaml has no parseable names")


def extract_enum_body(source: str, enum_name: str) -> str:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\b[^\{{]*\{{", source)
    if not match:
        raise ValueError(f"{enum_name} enum not found")

    depth = 1
    index = match.end()
    while index < len(source):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[match.end():index]
        index += 1
    raise ValueError(f"{enum_name} enum is not closed")


def load_custom_fruit_order(swift_file: Path) -> list[str]:
    if not swift_file.exists():
        raise FileNotFoundError(f"Swift mapping file not found: {swift_file}")

    body = extract_enum_body(swift_file.read_text(encoding="utf-8"), "CustomFruitID")
    cases: list[tuple[int, str]] = []
    next_raw_value = 0
    for raw_line in body.splitlines():
        line = raw_line.split("//", 1)[0].strip()
        if not line.startswith("case "):
            continue
        case_body = line.removeprefix("case ").strip()
        for part in case_body.split(","):
            item = part.strip()
            if not item:
                continue
            match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*(-?\d+))?", item)
            if not match:
                raise ValueError(f"Could not parse CustomFruitID case: {raw_line}")
            name = match.group(1)
            if match.group(2) is not None:
                next_raw_value = int(match.group(2))
            cases.append((next_raw_value, name))
            next_raw_value += 1

    if not cases:
        raise ValueError("CustomFruitID has no parseable cases")
    return [name for _, name in sorted(cases)]


def normalize_label(label: str) -> str:
    return " ".join(
        label.strip()
        .lower()
        .replace("_", " ")
        .replace("-", " ")
        .split()
    )


def first_mismatch(left: list[str], right: list[str]) -> int | None:
    for index, (left_value, right_value) in enumerate(zip(left, right)):
        if left_value != right_value:
            return index
    if len(left) != len(right):
        return min(len(left), len(right))
    return None


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main() -> int:
    args = parse_args()
    try:
        nc, data_names = load_data_yaml(Path(args.data_yaml))
        app_order = load_custom_fruit_order(Path(args.swift_file))
    except (FileNotFoundError, ValueError) as error:
        return fail(str(error))

    if nc != len(data_names):
        return fail(
            f"data.yaml nc ({nc}) does not equal names count ({len(data_names)})."
        )
    if len(data_names) != len(app_order):
        return fail(
            "data.yaml class count "
            f"({len(data_names)}) does not equal App CustomFruitID count ({len(app_order)})."
        )

    raw_mismatch = first_mismatch(data_names, app_order)
    if raw_mismatch is not None:
        return fail(
            "data.yaml label order does not match CustomFruitID. "
            f"First mismatch index {raw_mismatch}: "
            f"data.yaml={data_names[raw_mismatch]!r}, app={app_order[raw_mismatch]!r}."
        )

    normalized_data = [normalize_label(label) for label in data_names]
    normalized_app = [normalize_label(label) for label in app_order]
    normalized_mismatch = first_mismatch(normalized_data, normalized_app)
    if normalized_mismatch is not None:
        return fail(
            "Normalized data.yaml label order does not match CustomFruitID. "
            f"First mismatch index {normalized_mismatch}: "
            f"data.yaml={normalized_data[normalized_mismatch]!r}, "
            f"app={normalized_app[normalized_mismatch]!r}."
        )

    print("OK: data.yaml labels match FruitCategory.customModelLabelOrder")
    print(f"Classes: {len(data_names)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
