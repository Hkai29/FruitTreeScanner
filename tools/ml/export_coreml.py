#!/usr/bin/env python3
"""Export a custom FruitTreeScanner YOLO model to CoreML.

This production export guard refuses to fall back to COCO pretrained weights.
Use a custom-trained checkpoint with the 26-class FruitTreeScanner label order.
"""

import argparse
import shutil
from pathlib import Path

from check_data_yaml_app_mapping import load_data_yaml, normalize_label

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_YAML = REPO_ROOT / "ml" / "datasets" / "fruit_dataset_26" / "data.yaml"
DEFAULT_OUTPUT = REPO_ROOT / "FruitsDetector.mlmodel"
CUSTOM_MODEL_CANDIDATES = [
    REPO_ROOT / "ml" / "training-runs" / "yolo" / "detect" / "runs" / "fruit_26_nano" / "weights" / "best.pt",
    REPO_ROOT / "ml" / "training-runs" / "yolo" / "detect" / "runs" / "fruit_26_v2" / "weights" / "best.pt",
    REPO_ROOT / "ml" / "training-runs" / "yolo" / "fruit_detector_26" / "train" / "weights" / "best.pt",
]
COCO_REFUSAL = "refusing COCO fallback for FruitTreeScanner production model"

FRUIT_CLASSES_26 = [
    "apple",       # 0
    "orange",      # 1
    "mandarin",    # 2
    "pomelo",      # 3
    "pear",        # 4
    "peach",       # 5
    "cherry",      # 6
    "grape",       # 7
    "persimmon",   # 8
    "mango",       # 9
    "kiwi",        # 10
    "plum",        # 11
    "pomegranate", # 12
    "loquat",      # 13
    "lychee",      # 14
    "longan",      # 15
    "bayberry",    # 16
    "jujube",      # 17
    "hawthorn",    # 18
    "fig",         # 19
    "papaya",      # 20
    "chestnut",    # 21
    "mulberry",    # 22
    "blueberry",   # 23
    "strawberry",  # 24
    "coconut",     # 25
]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Export a custom 26-class FruitTreeScanner YOLO checkpoint to CoreML."
    )
    parser.add_argument(
        "--weights",
        default=None,
        help="Path to custom-trained best.pt. Defaults to known training-run candidates.",
    )
    parser.add_argument(
        "--data-yaml",
        default=str(DEFAULT_DATA_YAML),
        help="Path to the 26-class data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT),
        help="Output copy path for the exported CoreML artifact. Default: %(default)s",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate weights and data.yaml without importing Ultralytics or exporting.",
    )
    return parser.parse_args()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def find_custom_weights(explicit_weights: str | None) -> Path:
    if explicit_weights:
        path = Path(explicit_weights)
        if not path.is_absolute():
            path = REPO_ROOT / path
        if not path.exists():
            raise FileNotFoundError(
                f"missing custom weights: {path}; {COCO_REFUSAL}"
            )
        return path

    for candidate in CUSTOM_MODEL_CANDIDATES:
        if candidate.exists():
            return candidate

    candidates = ", ".join(display_path(path) for path in CUSTOM_MODEL_CANDIDATES)
    raise FileNotFoundError(
        f"missing custom weights: none of [{candidates}] exists; {COCO_REFUSAL}"
    )


def validate_data_yaml(path: Path) -> list[str]:
    if not path.exists():
        raise FileNotFoundError(f"missing data.yaml: {path}")
    nc, names = load_data_yaml(path)
    normalized_names = [normalize_label(name) for name in names]
    normalized_expected = [normalize_label(name) for name in FRUIT_CLASSES_26]
    if nc != len(names):
        raise ValueError(f"data.yaml nc ({nc}) does not match names count ({len(names)})")
    if names != FRUIT_CLASSES_26 or normalized_names != normalized_expected:
        raise ValueError(
            "data.yaml names do not match the 26-class FruitTreeScanner label order"
        )
    return names


def artifact_size_mb(path: Path) -> float:
    if path.is_dir():
        total = sum(file.stat().st_size for file in path.rglob("*") if file.is_file())
    else:
        total = path.stat().st_size
    return total / (1024 * 1024)


def copy_artifact(source: Path, destination: Path) -> None:
    if destination.exists():
        if destination.is_dir():
            shutil.rmtree(destination)
        else:
            destination.unlink()
    if source.is_dir():
        shutil.copytree(source, destination)
    else:
        shutil.copy2(source, destination)


def main():
    args = parse_args()
    print("=" * 60)
    print("FruitTreeScanner - custom YOLO CoreML export guard")
    print("=" * 60)

    data_yaml = Path(args.data_yaml)
    if not data_yaml.is_absolute():
        data_yaml = REPO_ROOT / data_yaml
    labels = validate_data_yaml(data_yaml)
    weights = find_custom_weights(args.weights)
    output = Path(args.output)
    if not output.is_absolute():
        output = REPO_ROOT / output

    print(f"Custom weights: {display_path(weights)}")
    print(f"data.yaml: {display_path(data_yaml)}")
    print(f"Classes: {len(labels)}")
    print(f"Output: {display_path(output)}")

    if args.dry_run:
        print("OK: dry run passed; no CoreML export performed")
        return

    try:
        from ultralytics import YOLO
    except ImportError as error:
        raise SystemExit(f"ultralytics not installed: {error}") from error

    model = YOLO(str(weights))
    print("Exporting to CoreML format...")
    coreml_path = Path(model.export(format="coreml"))
    print(f"Export complete: {coreml_path}")
    print(f"Size: {artifact_size_mb(coreml_path):.2f} MB")

    copy_artifact(coreml_path, output)
    print(f"Copied exported artifact to: {output}")
    print("Next: run check_model_metadata.py before replacing any production model.")

if __name__ == '__main__':
    main()
