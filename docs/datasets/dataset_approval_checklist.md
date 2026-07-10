# Recognition Dataset Approval Checklist

This checklist is for human review only. It does not authorize deletion,
movement, relabeling, training, or an apply operation.

## Decision 1: Duplicate Review

Review `ml/audit_reports/duplicate_visual_review.html` and the corresponding
rows in `ml/audit_reports/duplicate_cleanup_decisions.csv`.

For each duplicate group, confirm that the two displayed images really are the
same capture and that their label paths match the displayed metadata.

- To keep both copies, set both `approved_action` values to `keep`.
- To remove one copy only from a future new dataset copy, set exactly one row
  to `remove_duplicate` and its paired row to `keep`.
- If the visual content, provenance, or labels are uncertain, use
  `review_label_conflict` and leave the group for manual follow-up.
- If a path contains unrelated, unsafe, or otherwise unexpected content, do
  not embed it in a review page or approve cleanup from metadata alone. Keep
  the row under manual review and record the mismatch for dataset curation.

Why this cannot be automated: an equal hash and label fingerprint prove that
the file bytes and current labels match, but they do not establish which path
is the canonical record, whether the source has provenance constraints, or
whether keeping both is intentional for a documented experiment.

## Decision 2: Fixed Core-Test Review

Review `ml/audit_reports/test_split_review_summary.md` and update only the
`approved_action` field in `ml/audit_reports/fixed_test_split_decisions.csv`.

- Use `approve_move_to_test` for a reviewed core candidate that should become
  part of a future copied core-test split.
- Use `keep_in_train` when the candidate should not leave target train.
- Use `exclude_from_core_test` when it should remain outside the core test.
- Use `manual_review` for uncertain rows.

The current recommendation is a six-class test only: apple, orange, pear,
persimmon, grape, and strawberry. The CSV still contains `pending_review` for
all rows until a human explicitly decides otherwise.

## Why Six-Class Testing Does Not Represent a 26-Class Model

The current fixed-test plan deliberately protects weak or unsupported classes.
Fifteen classes have no planned test images, and several of the remaining
non-core classes have only 2 to 9 planned examples. A six-class score can
measure the selected core experiment; it cannot prove recognition quality for
all 26 current App categories.

## Completion Gate

- [ ] Every duplicate row has a final `approved_action`.
- [ ] Every fixed split row has a final `approved_action`.
- [ ] The six-class scope is recorded as an experiment limitation.
- [ ] No source image, label, or `data.yaml` has been edited during review.
- [ ] A separate explicit approval is obtained before any apply task.
