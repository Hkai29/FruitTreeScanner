# Fruit Dataset 6 Core v1 Post-Apply Audit

## Apply Status

- Status: passed
- Target: `ml/datasets/fruit_dataset_6_core_v1`
- Source: `ml/datasets/fruit_dataset_26`
- Controlled apply: executed once after approved dry-run.

## Source Integrity

- Images / labels: 4600 / 4600
- Missing image pairs / missing label pairs: 0 / 0
- Source preservation baseline: 4600 images / 4600 labels.

## Target Split Counts

- train: 2730 images / 2730 labels
- val: 772 images / 772 labels
- test: 347 images / 347 labels
- Total: 3849 images / 3849 labels

## Image/Label Pairing and YOLO Label Validation

- Missing image pairs: 0
- Missing label pairs: 0
- Empty labels: 0
- Corrupt or unreadable images: 0
- Malformed YOLO rows: 0
- Out-of-range class IDs: 0
- Invalid bboxes: 0

## Class Mapping Validation

- Target nc: 6
- Target class order: `apple`, `orange`, `pear`, `persimmon`, `grape`, `strawberry`
- App runtime label mapping compatible: yes
- Mapping gaps: none

## Split Leakage Check

- Same-name train-val / train-test / val-test: 0 / 0 / 0
- Content-hash train-val / train-test / val-test: 0 / 0 / 0

## Exclusion and Fixed-Test Verification

- Semantic excluded expected / found in target: 158 / 0
- Duplicate excluded expected / found in target: 4 / 0
- Fixed-test excluded expected / found in test: 29 / 0
- Fixed-test approved expected / found in test: 347 / 347
- Pending decisions: 0

## Per-Class Distribution

| Class | Train images / boxes | Train image / bbox % | Val images / boxes | Val image / bbox % | Test images / boxes | Test image / bbox % | Risk |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| apple | 671 / 8962 | 24.58% / 14.67% | 198 / 3418 | 25.65% / 16.83% | 95 / 1336 | 27.38% / 16.04% | ok |
| orange | 434 / 6571 | 15.90% / 10.76% | 145 / 2454 | 18.78% / 12.08% | 63 / 990 | 18.16% / 11.89% | ok |
| pear | 1195 / 31939 | 43.77% / 52.28% | 350 / 10387 | 45.34% / 51.15% | 148 / 4294 | 42.65% / 51.55% | ok |
| persimmon | 714 / 7503 | 26.15% / 12.28% | 177 / 2068 | 22.93% / 10.18% | 92 / 882 | 26.51% / 10.59% | ok |
| grape | 129 / 4093 | 4.73% / 6.70% | 37 / 853 | 4.79% / 4.20% | 15 / 500 | 4.32% / 6.00% | watch |
| strawberry | 203 / 2024 | 7.44% / 3.31% | 52 / 1128 | 6.74% / 5.55% | 24 / 327 | 6.92% / 3.93% | ok |

## Known Risks

- Grape has 15 fixed-test images. This is a watch item: grape test metrics have lower statistical stability, but it does not block this approved dataset creation.

## Training Gate

- Ready for training: yes
- Blockers: none
- Training status: not started.
