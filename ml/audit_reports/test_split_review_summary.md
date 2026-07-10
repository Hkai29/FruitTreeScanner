# Core-Class Fixed Test Split Review Summary

This review summarizes the current `fixed_test_split_decisions.csv` without
changing it. All 376 rows remain `pending_review`; the counts below are planned
test candidates, not an applied test split.

## Core-Class Coverage

The initial core-model scope is `apple`, `orange`, `pear`, `persimmon`,
`grape`, and `strawberry`.

- Unique planned images containing at least one core class: 368
- Core class-image memberships in those planned rows: 460
- Non-core-only planned rows: 8
- Actual test files moved: 0

Class-image memberships can exceed the number of unique images because a
single image can contain more than one fruit class.

| Class | Current train images | Planned test candidates | Train:test ratio | Review recommendation |
| --- | ---: | ---: | ---: | --- |
| apple | 814 | 102 | 8.0:1 | approve for core test after human review |
| orange | 517 | 66 | 7.8:1 | approve for core test after human review |
| pear | 1,395 | 156 | 8.9:1 | approve for core test after human review |
| persimmon | 816 | 93 | 8.8:1 | approve for core test after human review |
| grape | 154 | 18 | 8.6:1 | approve, but report its smaller test set separately |
| strawberry | 231 | 25 | 9.2:1 | approve, but report its smaller test set separately |

## Risk Review

- `grape` has 18 planned test images and `strawberry` 25. They are useful for
  the core experiment but have less test breadth than apple, orange, pear, and
  persimmon.
- Some planned core images also carry non-core annotations. A future approved
  core-only dataset copy must retain only the six approved label IDs; this
  review does not perform that filtering.
- `peach` (6), `mango` (4), `kiwi` (9), `mulberry` (2), and `blueberry` (3)
  have planned rows but are not part of the core-class test claim.
- The other 15 weak/protected classes have no planned test candidates. They
  remain outside the core test and cannot be used to report 26-class quality.

## Approval Recommendation

Conditionally approve the fixed test plan for the six-class core experiment
after the duplicate visual review is completed. Keep every non-core category
marked as **not part of core-class test**. Do not present this split as a
26-class evaluation, and do not run an apply operation until every
`approved_action` is an explicit final decision.
