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
persimmon, grape, and strawberry. The fixed-test revision now records 347
`approve_move_to_test` rows and 29 `exclude_from_core_test` rows: 21 semantic
exclusions and eight non-core candidates were removed from the target test.
The fixed-test approval gate is cleared.

## Decision 3: Six-Class Semantic Review Boundary

`ml/audit_reports/core_class_review_gate.csv` distinguishes the semantic
manual-review rows that can enter `fruit_dataset_6_core_v1` from rows that
contain only non-core labels and are naturally excluded from that copied
dataset. Review the blocking subset through
`ml/audit_reports/core_class_manual_review_decisions.csv`; its
`approved_action` values must be set through documented human review before a
six-class apply task is considered.

This is a scope boundary, not an approval for the 26-class dataset. Non-core
semantic exceptions may be deferred only for the six-class experiment; they
remain unresolved and must not be used to justify 26-class model training.
The narrowed semantic review does not replace the duplicate or fixed-test
approval gates above.

## Current Six-Class Gate Status

- Semantic review: cleared (one `keep`, 158 `exclude_from_training`, no
  pending rows).
- Duplicate conflict: cleared; the rejected lychee duplicate pair was removed
  with its labels and the dataset audit was rerun without pairing errors.
- Fixed test: cleared; `fixed_test_revision_summary.md` records the final
  actions and the 21 semantic-excluded candidates removed from target test.
- Apply planning: cleared. `apply_dataset_cleanup.py` consumes
  `core_class_manual_review_decisions.csv` and excludes every
  `exclude_from_training` source record from train, validation, and test;
  `core_dataset_apply_readiness.md` records the dry-run projection. A separate
  explicit approval is still required before an apply operation creates a
  dataset copy.

## Why Six-Class Testing Does Not Represent a 26-Class Model

The current fixed-test plan deliberately protects weak or unsupported classes.
Fifteen classes have no planned test images, and several of the remaining
non-core classes have only 2 to 9 planned examples. A six-class score can
measure the selected core experiment; it cannot prove recognition quality for
all 26 current App categories.

## Completion Gate

- [x] Every duplicate row has a final `approved_action`.
- [x] Every fixed split row has a final `approved_action`.
- [x] Every blocking row in `core_class_manual_review_decisions.csv` has a
  documented final approval.
- [x] The six-class scope is recorded as an experiment limitation.
- [x] The rejected lychee duplicate pair and corresponding labels were removed
  intentionally; the post-removal audit confirms no missing image/label pairs.
- [x] Semantic exclusions are enforced by the controlled apply plan.
- [ ] A separate explicit approval is obtained before any apply task.
