#!/usr/bin/env python3
"""Focused safety tests for the controlled six-class apply plan."""

from __future__ import annotations

import unittest
from pathlib import Path

import apply_dataset_cleanup as cleanup


NAMES = [*cleanup.CORE_CLASS_NAMES, "lychee"]


def source_record(name: str, split: str, class_ids: list[int]) -> dict[str, object]:
    image_path = (Path("/tmp/apply-plan-tests") / f"{name}.jpg").resolve()
    return {
        "split": split,
        "image_path": image_path,
        "label_path": image_path.with_suffix(".txt"),
        "relative_path": Path(f"{name}.jpg"),
        "entries": [(class_id, ["0.5", "0.5", "0.2", "0.2"]) for class_id in class_ids],
        "class_ids": class_ids,
        "bbox_count": len(class_ids),
        "label_fingerprint": "test",
    }


def plan_for(
    records: list[dict[str, object]],
    *,
    split_rows: list[dict[str, str]] | None = None,
    semantic_exclusions: set[Path] | None = None,
    pending_semantic: set[Path] | None = None,
) -> dict[str, object]:
    return cleanup.target_plan(
        records,
        NAMES,
        [],
        split_rows or [],
        semantic_exclusions or set(),
        pending_semantic or set(),
    )


class ApplyDatasetCleanupTests(unittest.TestCase):
    def assert_not_planned(self, plan: dict[str, object], image_path: Path) -> None:
        targets = plan["targets"]
        for split in ("train", "val", "test"):
            self.assertNotIn(
                image_path,
                [record["image_path"] for record in targets[split]],
            )

    def test_semantic_exclusion_never_enters_any_split(self) -> None:
        for split in ("train", "val", "test"):
            with self.subTest(source_split=split):
                record = source_record(f"semantic-{split}", split, [0])
                plan = plan_for([record], semantic_exclusions={record["image_path"]})
                self.assert_not_planned(plan, record["image_path"])
                self.assertEqual([record], plan["excluded_semantic"])

    def test_semantic_exclusion_overrides_fixed_test_approval(self) -> None:
        record = source_record("semantic-overrides-test", "train", [0])
        plan = plan_for(
            [record],
            split_rows=[
                {
                    "image_path": str(record["image_path"]),
                    "approved_action": "approve_move_to_test",
                }
            ],
            semantic_exclusions={record["image_path"]},
        )
        self.assert_not_planned(plan, record["image_path"])

    def test_fixed_test_approval_moves_candidate_to_test(self) -> None:
        record = source_record("approved-from-val", "val", [1])
        plan = plan_for(
            [record],
            split_rows=[
                {
                    "image_path": str(record["image_path"]),
                    "approved_action": "approve_move_to_test",
                }
            ],
        )
        self.assertEqual([], plan["targets"]["train"])
        self.assertEqual([], plan["targets"]["val"])
        self.assertEqual([record["image_path"]], [item["image_path"] for item in plan["targets"]["test"]])

    def test_fixed_test_exclusion_never_enters_test(self) -> None:
        record = source_record("excluded-from-test", "train", [2])
        plan = plan_for(
            [record],
            split_rows=[
                {
                    "image_path": str(record["image_path"]),
                    "approved_action": "exclude_from_core_test",
                }
            ],
        )
        self.assertEqual([], plan["targets"]["test"])
        self.assertEqual([record["image_path"]], [item["image_path"] for item in plan["targets"]["train"]])

    def test_duplicate_exclusion_never_enters_any_split(self) -> None:
        record = source_record("duplicate", "train", [3])
        plan = cleanup.target_plan(
            [record],
            NAMES,
            [
                {
                    "image_path": str(record["image_path"]),
                    "approved_action": "remove_duplicate",
                }
            ],
            [],
            set(),
            set(),
        )
        self.assert_not_planned(plan, record["image_path"])
        self.assertEqual([record], plan["excluded_duplicate"])

    def test_pending_semantic_decision_is_a_blocker_and_is_withheld(self) -> None:
        record = source_record("semantic-pending", "train", [0])
        counts = cleanup.unresolved_counts([], [], [{"approved_action": "pending_review"}])
        self.assertEqual(1, counts["pending_semantic"])
        self.assertTrue(any(counts.values()))
        plan = plan_for([record], pending_semantic={record["image_path"]})
        self.assert_not_planned(plan, record["image_path"])
        self.assertEqual([record], plan["pending_semantic"])

    def test_non_core_record_never_enters_six_class_dataset(self) -> None:
        record = source_record("non-core", "train", [6])
        plan = plan_for([record])
        self.assert_not_planned(plan, record["image_path"])
        self.assertEqual([record], plan["excluded_non_core"])


if __name__ == "__main__":
    unittest.main()
