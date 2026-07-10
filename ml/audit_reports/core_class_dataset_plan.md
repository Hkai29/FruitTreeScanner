# Core-Class Dataset Application Plan

## Target Dataset

- Target dataset name: `fruit_dataset_6_core_v1`
- Target path: `ml/datasets/fruit_dataset_6_core_v1/`
- Source dataset: `ml/datasets/fruit_dataset_26/`
- Source preservation: mandatory. The target can only be created by copying
  approved source files; it must never move, delete, or rewrite the 26-class
  source dataset.

## Core Classes and Target Label Order

| Target class ID | Target class | Source class ID |
| --- | --- | ---: |
| 0 | apple | 0 |
| 1 | orange | 1 |
| 2 | pear | 4 |
| 3 | persimmon | 8 |
| 4 | grape | 7 |
| 5 | strawberry | 24 |

The planned core dataset should have a new six-class `data.yaml` with the
target order above. It is a new training dataset, not an edit to
`fruit_dataset_26/data.yaml`.

## Split and Cleanup Rules

- Use the approved fixed-test decisions derived from the 376-image, seed
  `20260709` plan.
- `approve_move_to_test` copies an eligible core image into target `test`.
- `keep_in_train` and `exclude_from_core_test` keep an eligible image in target
  `train`; neither action deletes the source.
- `val` remains target `val`.
- Images without a core annotation are excluded from the six-class copy, while
  remaining untouched in the 26-class source.
- Mixed-class labels are copied only with their core annotations, remapped to
  the six target IDs.
- An approved `remove_duplicate` can omit one duplicate image only from the
  new dataset copy. It cannot remove a source file.

## Unsupported Classes

The other 20 source classes remain in the original dataset and are outside the
first six-class training claim. This is an experimental-scope decision, not a
taxonomy deletion. Weak classes must be collected, evaluated, or separately
approved before a later model claims support for them.

## App Mapping Risk

The current App's custom YOLO mapping expects the 26-label order in
`FruitCategory.customModelLabelOrder`. A six-class CoreML model would have a
different label space and must not be copied into the App under the existing
mapping.

Before any production six-class model change, choose and validate one path:

1. Support model-label metadata driven mapping in the App.
2. Add a dedicated six-class mapping with diagnostics for unsupported selected
   fruit types.
3. Keep the current 26-output label space and improve only the six core
   classes, while retaining a compatible 26-label model contract.

None of these App changes are part of the controlled cleanup task. They need a
separate design, mapping, diagnostics, and real-device validation task.

## Why the Original Dataset Must Remain Intact

- It preserves the current 26-class research record and App compatibility
  baseline.
- It allows repeatable comparison of the core experiment against future
  full-class data collection.
- It prevents an irreversible cleanup decision from masquerading as improved
  model quality.
- It keeps weak and unsupported classes available for later annotation review
  or independent split design.
