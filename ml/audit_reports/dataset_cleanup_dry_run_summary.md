# Dataset Cleanup Dry-Run Summary

- Mode: dry-run
- Source dataset: `ml/datasets/fruit_dataset_26`
- Planned output dataset: `ml/datasets/fruit_dataset_6_core_v1`
- Fixed split seed: `20260709`
- Core classes: `apple`, `orange`, `pear`, `persimmon`, `grape`, `strawberry`
- Apply currently blocked: yes

## Approval State

- Pending duplicate decisions: 10
- Duplicate label-conflict reviews: 0
- Pending split decisions: 376
- Split manual reviews: 0

## Planned Duplicate Actions

- Keep: 0
- Remove from the new dataset copy: 0
- Pending review: 10
- Label-conflict review: 0

## Planned Fixed Test-Split Actions

- Approve move to test: 0
- Keep in train: 0
- Exclude from core test (retained in core train when applicable): 0
- Pending review: 376
- Manual review: 0

## Files That Would Be Copied

No source file is copied in dry-run mode. The resolved projection below shows only records whose destination is currently explicit; pending split rows are withheld until approved.

| Target split | Resolved core image records |
| --- | ---: |
| train | 2839 |
| val | 800 |
| test | 0 |
| pending split decision | 368 |

Examples of resolved copy candidates (capped at eight per split):
- train: `ml/datasets/fruit_dataset_26/images/train/000000000142.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000000196.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000000584.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000000902.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001036.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001261.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001401.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000001667.jpg`
- val: `ml/datasets/fruit_dataset_26/images/val/000000000984.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000001386.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000001888.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000002624.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000004642.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000005472.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000006151.jpg`, `ml/datasets/fruit_dataset_26/images/val/000000007179.jpg`
- test: none
- pending: `ml/datasets/fruit_dataset_26/images/train/000000000969.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000002279.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000002886.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000003464.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000004376.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000011527.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000012428.jpg`, `ml/datasets/fruit_dataset_26/images/train/000000013145.jpg`

## Files Excluded From the Core Copy

- Non-core-only source records: 595
- Non-core classes excluded from the target labels: `mandarin`, `pomelo`, `peach`, `cherry`, `mango`, `kiwi`, `plum`, `pomegranate`, `loquat`, `lychee`, `longan`, `bayberry`, `jujube`, `hawthorn`, `fig`, `papaya`, `chestnut`, `mulberry`, `blueberry`, `coconut`
- Approved duplicate removals that would affect the new copy: 0
- The original 26-class dataset is preserved in all cases.

## Target Dataset Rules

- Core annotations would be remapped to the six-class order: `apple`, `orange`, `pear`, `persimmon`, `grape`, `strawberry`.
- Non-core annotations would not be copied into the new core-only labels.
- `exclude_from_core_test` keeps an otherwise eligible image in target train; it does not delete the source image.
- Apply mode creates a new output root only and refuses to overwrite an existing one.

## Blocked Reasons

- 10 duplicate decisions are pending_review
- 376 split decisions are pending_review
- Change approved_action to an explicit final decision before apply mode.
