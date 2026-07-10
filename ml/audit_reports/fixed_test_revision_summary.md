# Fixed-Test Revision Summary

- Original fixed-test rows: 376
- Approved fixed-test rows: 347
- Excluded fixed-test rows: 29
- Pending rows: 0
- Rows excluded because of semantic review: 21
- Rows excluded because file missing: 0
- Rows excluded because non-core class: 8
- Rows excluded because duplicate cleanup: 0

## Per-Class Approved Test Coverage

- apple: 95 images, 1336 boxes; excluded 7 images / 22 boxes; risk=low
- orange: 63 images, 990 boxes; excluded 3 images / 129 boxes; risk=low
- pear: 148 images, 4294 boxes; excluded 8 images / 173 boxes; risk=low
- persimmon: 92 images, 882 boxes; excluded 1 images / 6 boxes; risk=low
- grape: 15 images, 500 boxes; excluded 3 images / 22 boxes; risk=watch
- strawberry: 24 images, 327 boxes; excluded 1 images / 12 boxes; risk=low

## Gate Status

- Fixed-test gate cleared: yes
- Dataset apply can proceed: no.
- Remaining blockers:
  - semantic review: decisions are final, but the current apply tool does not read `core_class_manual_review_decisions.csv`; semantic exclusions would otherwise remain in target train.
  - duplicate cleanup: cleared for the current duplicate decisions.
  - fixed-test approval: cleared for this CSV revision.
  - class distribution: grape need low-volume review.

The actions use the existing apply schema: `approve_move_to_test` and `exclude_from_core_test`. The latter prevents test placement only; it is not a whole-dataset semantic exclusion action.
