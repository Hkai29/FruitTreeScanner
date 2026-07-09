#!/usr/bin/env python3
"""Inspect CoreML model metadata relevant to FruitTreeScanner recognition.

This is a metadata/spec checker, not an inference parity test. It reads the
CoreML spec with coremltools when available and validates class-label metadata,
input image size, output feature names/shapes, and expected label order.
"""

from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
from typing import Any


EXPECTED_FRUIT_LABELS = [
    "apple",
    "orange",
    "mandarin",
    "pomelo",
    "pear",
    "peach",
    "cherry",
    "grape",
    "persimmon",
    "mango",
    "kiwi",
    "plum",
    "pomegranate",
    "loquat",
    "lychee",
    "longan",
    "bayberry",
    "jujube",
    "hawthorn",
    "fig",
    "papaya",
    "chestnut",
    "mulberry",
    "blueberry",
    "strawberry",
    "coconut",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check class labels and I/O metadata for a CoreML model or mlpackage."
    )
    parser.add_argument(
        "model",
        nargs="?",
        default="FruitTreeScanner/Core/FruitsDetector.mlpackage",
        help="Path to .mlpackage, .mlmodel, or model.mlmodel. Default: %(default)s",
    )
    parser.add_argument(
        "--expected-labels",
        default=None,
        help="Optional text file containing one expected label per line.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print full JSON report instead of a concise human summary.",
    )
    return parser.parse_args()


def resolve_model_file(path: Path) -> Path:
    if path.is_dir() and path.suffix == ".mlpackage":
        model_file = path / "Data" / "com.apple.CoreML" / "model.mlmodel"
        if model_file.exists():
            return model_file
    return path


def expected_labels(path: str | None) -> list[str]:
    if path is None:
        return EXPECTED_FRUIT_LABELS
    return [
        line.strip()
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def labels_from_names_metadata(value: str) -> list[str]:
    try:
        parsed = ast.literal_eval(value)
    except (SyntaxError, ValueError):
        return []
    if isinstance(parsed, dict):
        return [str(parsed[index]) for index in sorted(parsed)]
    if isinstance(parsed, list):
        return [str(item) for item in parsed]
    return []


def feature_type_summary(feature: Any) -> dict[str, Any]:
    type_name = feature.type.WhichOneof("Type")
    summary: dict[str, Any] = {"name": feature.name, "type": type_name}
    if type_name == "imageType":
        image_type = feature.type.imageType
        summary.update(
            {
                "width": image_type.width,
                "height": image_type.height,
                "color_space": image_type.colorSpace,
            }
        )
    elif type_name == "multiArrayType":
        summary["shape"] = list(feature.type.multiArrayType.shape)
        summary["data_type"] = feature.type.multiArrayType.dataType
    elif type_name == "dictionaryType":
        summary["dictionary_type"] = feature.type.dictionaryType.WhichOneof("KeyType")
    return summary


def load_spec_report(model_path: Path, expected: list[str]) -> dict[str, Any]:
    try:
        import coremltools as ct
    except ImportError as error:
        return {
            "model": str(model_path),
            "ok": False,
            "error": f"coremltools is required to inspect model.mlmodel: {error}",
        }

    model_file = resolve_model_file(model_path)
    if not model_file.exists():
        return {"model": str(model_path), "ok": False, "error": "model file not found"}

    spec = ct.utils.load_spec(str(model_file))
    description = spec.description
    metadata = dict(description.metadata.userDefined)
    labels = labels_from_names_metadata(metadata.get("names", ""))

    warnings: list[str] = []
    if not labels:
        warnings.append("No parseable class labels found in user-defined metadata key 'names'.")
    elif labels != expected:
        warnings.append("Class label order does not match expected FruitCategory order.")
    if description.predictedFeatureName or description.predictedProbabilitiesName:
        warnings.append("Model exposes classifier-style predicted feature metadata.")

    outputs = [feature_type_summary(feature) for feature in description.output]
    if not any(output.get("type") == "multiArrayType" for output in outputs):
        warnings.append("No MultiArray output found; App YOLO parser may not be compatible.")

    return {
        "model": str(model_path),
        "model_file": str(model_file),
        "ok": not warnings,
        "model_type": spec.WhichOneof("Type"),
        "inputs": [feature_type_summary(feature) for feature in description.input],
        "outputs": outputs,
        "predicted_feature_name": description.predictedFeatureName,
        "predicted_probabilities_name": description.predictedProbabilitiesName,
        "metadata": metadata,
        "labels": labels,
        "expected_labels": expected,
        "labels_match_expected": labels == expected,
        "warnings": warnings,
    }


def print_summary(report: dict[str, Any]) -> None:
    print(f"Model: {report.get('model')}")
    if report.get("error"):
        print(f"ERROR: {report['error']}")
        return
    print(f"Model type: {report.get('model_type')}")
    print(f"Inputs: {report.get('inputs')}")
    print(f"Outputs: {report.get('outputs')}")
    print(f"Labels: {len(report.get('labels', []))}")
    print(f"Labels match expected: {report.get('labels_match_expected')}")
    warnings = report.get("warnings", [])
    if warnings:
        print("Warnings:")
        for warning in warnings:
            print(f"- {warning}")


def main() -> int:
    args = parse_args()
    report = load_spec_report(Path(args.model), expected_labels(args.expected_labels))
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print_summary(report)
    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
