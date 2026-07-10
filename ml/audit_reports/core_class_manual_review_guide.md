# Six-Class Manual Review Guide

This guide supports human decisions in `core_class_manual_review_decisions.csv`.
It does not authorize image deletion, relabeling, dataset copying, or apply.

## When to use `keep`

- The image clearly contains a core fruit.
- People, hands, or background do not obscure the fruit subject.
- Fruit bounding boxes and category are broadly correct.
- A real orchard scene is suitable for retention.

## When to use `exclude_from_training`

- Pornographic or otherwise unsuitable content is present.
- A computer, animal, document, clothing, bedding, or another clearly non-fruit subject dominates the image.
- The image does not contain the target fruit.
- The label category is clearly wrong and no label correction is planned now.
- Fruit is too small or cannot be identified reliably.

## When to use `manual_review`

- It is uncertain whether the subject is the target fruit.
- The category may be wrong but needs a human label correction decision.
- Fruit is present but annotations may be materially incomplete.
- Multiple categories are mixed and the correct action is uncertain.
