# Core-Class Manual Review Gate Summary

## Scope

This report is a read-only narrowing of the 200-row semantic manual-review decision queue for `fruit_dataset_6_core_v1`. It does not approve any row or alter the source dataset.

## Counts

- Total decision rows: 200
- Rows blocking six-class apply: 159
- High-risk blocking rows: 143
- Rows safe to defer for 26-class cleanup: 41
- Rows already recommended for exclusion: 60
- Rows needing actual human visual review: 159

## Gate Decision

- The semantic manual-review gate can be narrowed to the blocking rows: yes.
- Can six-class apply proceed now: no; blocking rows remain `pending_review`.
- Can six-class apply proceed after only those blocking rows are approved: not by this gate alone; the separate fixed-test approval gate still has 376 `pending_review` rows.

## Deferral Boundary

Rows marked safe to defer contain only non-core labels and are naturally excluded from the six-class copy. They remain unresolved for any future 26-class training claim and must not be treated as approved 26-class data.
