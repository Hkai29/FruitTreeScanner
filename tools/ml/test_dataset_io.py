#!/usr/bin/env python3
"""Lightweight standard-library checks for shared ML dataset I/O helpers."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from dataset_io import (
    class_count_matches_names,
    count_classes,
    iter_image_files,
    label_path_for_image,
    load_data_yaml,
    parse_yolo_row,
    read_csv_rows,
    validate_yolo_bbox,
    write_csv_rows,
)


class DatasetIOTests(unittest.TestCase):
    def test_load_data_yaml_and_matching_class_count(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "data.yaml"
            path.write_text("nc: 2\nnames:\n  0: apple\n  1: pear\n", encoding="utf-8")

            config, errors = load_data_yaml(path)

        self.assertEqual(errors, [])
        self.assertEqual(config["names"], ["apple", "pear"])
        self.assertTrue(class_count_matches_names(config))

    def test_parse_and_validate_yolo_row(self) -> None:
        parsed = parse_yolo_row("1 0.5 0.25 0.2 0.4")

        self.assertEqual(parsed, (1, 0.5, 0.25, 0.2, 0.4))
        self.assertTrue(validate_yolo_bbox(*parsed[1:]))
        self.assertFalse(validate_yolo_bbox(0.5, 0.5, 1.1, 0.2))
        self.assertIsNone(parse_yolo_row("not-a-yolo-row"))
        self.assertEqual(count_classes(["1 0.5 0.25 0.2 0.4", "7 0 0 1 1"], 2), {1: 1})

    def test_image_to_label_mapping_and_missing_label(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            images_root = root / "images" / "train"
            labels_root = root / "labels" / "train"
            image_path = images_root / "nested" / "fruit.jpg"
            image_path.parent.mkdir(parents=True)
            image_path.write_bytes(b"image")

            label_path = label_path_for_image(image_path, images_root, labels_root)

            self.assertEqual(label_path, labels_root / "nested" / "fruit.txt")
            self.assertFalse(label_path.exists())
            self.assertEqual(iter_image_files(images_root, recursive=True), [image_path])

    def test_csv_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "reports" / "rows.csv"
            write_csv_rows(path, [{"class": "apple", "count": 2}], ["class", "count"])

            rows = read_csv_rows(path, ["class", "count"])

        self.assertEqual(rows, [{"class": "apple", "count": "2"}])


if __name__ == "__main__":
    unittest.main()
