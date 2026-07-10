# Fruit Dataset 26 Pretraining Review

**Status: pretraining review, not approved for training yet**

This is a prefilled version record based on the current read-only audit. It
does not claim that the dataset has been cleaned, split, or approved.

## Dataset Identity

- Version name: `fruit_dataset_26_pretraining_review`
- Creation date: 2026-07-10
- Owner: pending human assignment
- Source dataset path: `ml/datasets/fruit_dataset_26`
- `data.yaml` path: `ml/datasets/fruit_dataset_26/data.yaml`
- Planned split seed: `20260709`
- Planned test split ratio: 10%
- App mapping check: passed; `data.yaml` labels match
  `FruitCategory.customModelLabelOrder`

## Class Order

| Class ID | Class name | App mapping check |
| --- | --- | --- |
| 0 | apple | pass |
| 1 | orange | pass |
| 2 | mandarin | pass |
| 3 | pomelo | pass |
| 4 | pear | pass |
| 5 | peach | pass |
| 6 | cherry | pass |
| 7 | grape | pass |
| 8 | persimmon | pass |
| 9 | mango | pass |
| 10 | kiwi | pass |
| 11 | plum | pass |
| 12 | pomegranate | pass |
| 13 | loquat | pass |
| 14 | lychee | pass |
| 15 | longan | pass |
| 16 | bayberry | pass |
| 17 | jujube | pass |
| 18 | hawthorn | pass |
| 19 | fig | pass |
| 20 | papaya | pass |
| 21 | chestnut | pass |
| 22 | mulberry | pass |
| 23 | blueberry | pass |
| 24 | strawberry | pass |
| 25 | coconut | pass |

## Current Split Summary

| Split | Unique images | Bounding boxes | Status |
| --- | ---: | ---: | --- |
| train | 3,757 | 80,058 | current |
| val | 845 | 21,955 | current |
| test | 0 | 0 | not declared in `data.yaml` |
| total | 4,602 | 102,013 | current audit |

The read-only plan proposes 376 unique train images (8,953 boxes) for a future
fixed test split. The plan is not an applied split; `data.yaml` still has only
`train` and `val`.

## Duplicate Review Status

- Duplicate hash groups: 5
- Affected classes: `loquat` (4 groups) and `lychee` (1 group)
- Label conflicts: none found; every group has matching label fingerprints
- Current recommendation: review visually, then decide whether one copy in
  each group is a removal candidate
- Decision record: `ml/audit_reports/duplicate_review_pack.md`
- Cleanup state: no image deleted, moved, renamed, or relabeled

## Fixed Test Split Status

- Plan: `ml/audit_reports/test_split_plan.csv`
- Class summary: `ml/audit_reports/test_split_class_distribution.csv`
- Approval summary: `ml/audit_reports/test_split_approval_summary.md`
- Recommendation: conditionally approve for a core-class evaluation only;
  insufficient to support a 26-class quality claim
- Actual file operation: none

## Weak Classes and Coverage Gaps

- Very low total image count: `mandarin`, `jujube`, `fig`, `papaya`
- No validation images: `pomelo`, `plum`, `pomegranate`, `loquat`, `lychee`,
  `longan`, `bayberry`, `hawthorn`, `chestnut`
- Validation too small: `cherry`, `coconut`
- Initial core-model recommendation: `apple`, `orange`, `pear`, `persimmon`,
  `grape`, `strawberry`
- Strategy record: `ml/audit_reports/retraining_class_strategy.md`

## Pending Human Decisions

- [ ] Decide the disposition of every duplicate group.
- [ ] Approve, revise, or reject the fixed test-split plan.
- [ ] Confirm whether the first experiment is six-class core-only or requires
  additional data before training.
- [ ] Confirm which weak classes are data-collection targets, temporarily
  unsupported, or candidates for a separately approved taxonomy decision.
- [ ] Record any future cleanup or split operation before it occurs.

## Controlled Cleanup Preparation

- Duplicate decision template:
  `ml/audit_reports/duplicate_cleanup_decisions.csv`
- Fixed split decision template:
  `ml/audit_reports/fixed_test_split_decisions.csv`
- Apply tool: `tools/ml/apply_dataset_cleanup.py`
- Dry-run summary: `ml/audit_reports/dataset_cleanup_dry_run_summary.md`
- Current state: blocked until every `approved_action` is changed from
  `pending_review` to an explicit final decision.
- Source protection: the tool cannot modify this dataset in place. Any future
  approved operation can only create a separate target such as
  `ml/datasets/fruit_dataset_6_core_v1/`.

## Known Limitations

- This record does not include visual QA of small, occluded, distant, or
  low-light fruit examples.
- Current audits do not establish orchard-domain generalization.
- Existing historical 26-class runs have insufficient metrics for a reliable
  yield-estimation claim.
