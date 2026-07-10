# Six-Class Semantic Exclusion Impact Summary

## Overall

- Excluded image count: 158
- Kept image count: 1
- Pending count: 0
- Excluded core-class bbox count: 1237
- Affected core classes: apple, orange, pear, persimmon, grape, strawberry

## Per-Class Impact

Remaining train estimates start from the approved fixed-test split plan's `after_train` baseline, remove exclusions that would otherwise stay in train, and keep fixed-test-overlap exclusions out of the train subtraction. Validation estimates remove every excluded validation image.

| Class | Excluded images | Excluded boxes | Remaining train images estimate | Remaining train boxes estimate | Remaining val images estimate | Remaining val boxes estimate | Planned test images affected | Planned test boxes affected | Risk after exclusion |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| apple | 59 | 206 | 671 | 8962 | 198 | 3418 | 7 | 22 | low |
| orange | 23 | 215 | 434 | 6571 | 145 | 2454 | 3 | 129 | low |
| pear | 63 | 491 | 1195 | 31939 | 350 | 10387 | 8 | 173 | low |
| persimmon | 13 | 141 | 714 | 7503 | 177 | 2068 | 1 | 6 | low |
| grape | 12 | 152 | 129 | 4093 | 37 | 853 | 3 | 22 | low |
| strawberry | 6 | 32 | 203 | 2024 | 52 | 1128 | 1 | 12 | low |

## Fixed-Test Interaction

- Excluded rows also in fixed test plan: 21
- By-class fixed-test image memberships: apple=7, orange=3, pear=8, persimmon=1, grape=3, strawberry=1
- By-class fixed-test boxes affected: apple=22, orange=129, pear=173, persimmon=6, grape=22, strawberry=12
- Fixed-test plan must be regenerated or revised: yes; excluded rows must not enter target test.

## Recommendation

- Can six-class semantic review gate be considered cleared? yes
- Can dataset apply proceed now? no
- Remaining blockers:
  - duplicate approval: blocked by 2 unresolved row(s)
  - fixed-test approval: blocked by 376 pending row(s)
  - class distribution risk: none after the approved exclusions

This report is a planning estimate only. It does not alter source images, labels, decisions, test splits, or dataset membership, and it does not authorize apply.
