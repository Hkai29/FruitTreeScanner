# Duplicate Image Review Pack

This is a human-decision aid generated from `duplicate_images_report.csv`. It
does not remove, move, or rename any dataset file. Every group below contains
identical image bytes within the current training split and matching label
fingerprints. The recommended action remains a candidate until a reviewer
records a decision.

## Review Rules

- Compare the listed images visually before removing either copy.
- Confirm the image and label paths still belong to the intended dataset
  version.
- If a group is approved for cleanup, record the retained path and the
  removed-candidate path in the dataset version record before any file action.
- Do not use this report as authorization to modify the dataset.

## Duplicate Group `dup_001`

Images:

- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_38.jpg`
- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_4.jpg`

Labels:

- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_38.txt`
- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_4.txt`

Class names: `13` / `loquat`.

Bounding boxes: 22 in each label file. Label status: same labels. Both files
have fingerprint `dc15cedd01302fd7558f9840fcd14476bcf01899c098538e92606e432a9e08c1`.

Recommended action: `remove_duplicate_candidate` after visual confirmation.

Risk note: the duplicate does not cross a split, but retaining both copies
overweights the same loquat scene. Do not remove a file until the retained
canonical path is recorded.

Human decision:

- [ ] Keep all
- [ ] Remove one duplicate candidate
- [ ] Review labels manually

## Duplicate Group `dup_002`

Images:

- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_1.jpg`
- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_44.jpg`

Labels:

- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_1.txt`
- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_44.txt`

Class names: `13` / `loquat`.

Bounding boxes: 11 in each label file. Label status: same labels. Both files
have fingerprint `144105af218fdbd7f34e8bbd5d333bbc81ca700a369cf28b317e4386ad8ea38a`.

Recommended action: `remove_duplicate_candidate` after visual confirmation.

Risk note: this is a same-split duplicate, so it is not split leakage today;
keeping it still gives a single scene extra training weight.

Human decision:

- [ ] Keep all
- [ ] Remove one duplicate candidate
- [ ] Review labels manually

## Duplicate Group `dup_003`

Images:

- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_3.jpg`
- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_37.jpg`

Labels:

- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_3.txt`
- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_37.txt`

Class names: `13` / `loquat`.

Bounding boxes: 37 in each label file. Label status: same labels. Both files
have fingerprint `902fefec9b35501f24162a6a2ae8a02640b1c695b2ad9226708f1cd732715e0c`.

Recommended action: `remove_duplicate_candidate` after visual confirmation.

Risk note: the high box count can disproportionately repeat one dense scene
during training, even though the labels agree.

Human decision:

- [ ] Keep all
- [ ] Remove one duplicate candidate
- [ ] Review labels manually

## Duplicate Group `dup_004`

Images:

- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_2.jpg`
- `ml/datasets/fruit_dataset_26/images/train/loquat_Image_45.jpg`

Labels:

- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_2.txt`
- `ml/datasets/fruit_dataset_26/labels/train/loquat_Image_45.txt`

Class names: `13` / `loquat`.

Bounding boxes: 18 in each label file. Label status: same labels. Both files
have fingerprint `eb63f53b08115331a178e61c588e0cdaa5bf28510b302d145dfaf0e2c9519e04`.

Recommended action: `remove_duplicate_candidate` after visual confirmation.

Risk note: this duplicate is not current train/validation leakage, but it
reduces the effective diversity of the loquat training examples.

Human decision:

- [ ] Keep all
- [ ] Remove one duplicate candidate
- [ ] Review labels manually

## Duplicate Group `dup_005`

Images:

- `ml/datasets/fruit_dataset_26/images/train/lychee_Image_1.jpg`
- `ml/datasets/fruit_dataset_26/images/train/lychee_Image_2.jpg`

Labels:

- `ml/datasets/fruit_dataset_26/labels/train/lychee_Image_1.txt`
- `ml/datasets/fruit_dataset_26/labels/train/lychee_Image_2.txt`

Class names: `14` / `lychee`.

Bounding boxes: 2 in each label file. Label status: same labels. Both files
have fingerprint `ba9b1bb6de90bc9cae6f2c730822766eb44a063170784b659775d66a45704d06`.

Recommended action: `review_label_conflict`.

Risk note: human visual review found unexpected content inconsistent with the
claimed lychee class. Matching image hashes and label fingerprints only prove
that the two files duplicate each other; they do not validate the semantic
label. Do not approve cleanup or use either file for training until content,
provenance, and labels are curated.

Human decision:

- [ ] Keep all
- [ ] Remove one duplicate candidate
- [x] Review labels manually

## Decision Summary

- Duplicate groups: 5
- Label conflicts: 0
- Current action state: four loquat groups have approved future-copy duplicate
  decisions; `dup_005` is held for label-conflict curation. No dataset action
  has been taken.
- Required before cleanup: a completed checkbox decision for each group and a
  dataset-version entry that identifies any retained and removed-candidate
  paths.
