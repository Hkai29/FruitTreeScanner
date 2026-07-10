# Dataset Cleanup Dry-Run Summary

- Mode: apply-preflight
- Source dataset: `ml/datasets/fruit_dataset_26`
- Planned output dataset: `ml/datasets/fruit_dataset_6_core_v1`
- Fixed split seed: `20260709`
- Core classes: `apple`, `orange`, `pear`, `persimmon`, `grape`, `strawberry`
- Apply currently blocked: no

## Approval State

- Pending duplicate decisions: 0
- Duplicate label-conflict reviews: 0
- Pending split decisions: 0
- Split manual reviews: 0
- Pending semantic decisions: 0

## Enforced Exclusion Gates

- semantic_excluded_images: 158
- duplicate_excluded_images: 4
- fixed_test_excluded_images: 29
- fixed_test_approved_images: 347
- planned_train_images: 2730
- planned_val_images: 772
- planned_test_images: 347
- blocked_pending_decisions: 0

## Planned Duplicate Actions

- Keep: 4
- Remove from the new dataset copy: 4
- Pending review: 0
- Label-conflict review: 0

## Planned Fixed Test-Split Actions

- Approve move to test: 347
- Keep in train: 0
- Exclude from core test (retained in core train when applicable): 29
- Pending review: 0
- Manual review: 0

## Files That Would Be Copied

No source file is copied in dry-run mode. The resolved projection below shows only records whose destination is currently explicit; pending decision rows are withheld until approved.

| Target split | Resolved core image records |
| --- | ---: |
| train | 2730 |
| val | 772 |
| test | 347 |
| pending decision | 0 |

Examples of resolved copy candidates (capped at eight per split):
- train: `ml/datasets/fruit_dataset_26/images/train/000000000142.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000000196.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000000584.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000000902.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001036.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001261.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001401.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001667.jpg`
- val: `ml/datasets/fruit_dataset_26/images/val/000000000984.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000001386.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000001888.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000002624.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000004642.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000005472.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000006151.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000007179.jpg`
- test: `ml/datasets/fruit_dataset_26/images/train/000000000969.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000002279.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000002886.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000003464.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000004376.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000011527.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000012428.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000013145.jpg`
- pending: none

## Files Excluded From the Core Copy

- Non-core-only source records: 589
- Non-core classes excluded from the target labels: `mandarin`, `pomelo`, `peach`, `cherry`, `mango`, `kiwi`, `plum`, `pomegranate`, `loquat`, `lychee`, `longan`, `bayberry`, `jujube`, `hawthorn`, `fig`, `papaya`, `chestnut`, `mulberry`, `blueberry`, `coconut`
- Approved duplicate source exclusions: 4
- The original 26-class dataset is preserved in all cases.

## Target Dataset Rules

- Core annotations would be remapped to the six-class order: `apple`, `orange`, `pear`, `persimmon`, `grape`, `strawberry`.
- Non-core annotations would not be copied into the new core-only labels.
- `exclude_from_core_test` keeps an otherwise eligible image in target train; semantic exclusions take precedence and prevent any target placement.
- Apply mode creates a new output root only and refuses to overwrite an existing one.

## Apply Readiness

- All decisions are final. Apply mode may create the new dataset copy.
