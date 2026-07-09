# Recognition Retraining Class Strategy

This strategy compares training directions using
`class_distribution_report.csv`. It is a decision record, not a new
`data.yaml`, training configuration, or App behavior change.

## Option A: Continue 26-Class Retraining

### Advantages

- Preserves the existing 26-class taxonomy and current App model-label order.
- Avoids an immediate unsupported-category product decision.
- Retains future coverage potential for all recorded fruit types.

### Risks

- Historical 26-class runs have low aggregate metrics and multiple classes
  lack usable validation or test support.
- `jujube` (2 total images), `fig` (3), and `papaya` (7) cannot support
  credible per-class training or evaluation.
- Nine classes have no validation images: `pomelo`, `plum`, `pomegranate`,
  `loquat`, `lychee`, `longan`, `bayberry`, `hawthorn`, and `chestnut`.
- `cherry` and `coconut` have only three validation images each.
- The planned fixed test split intentionally protects 15 weak classes, so it
  cannot validate a 26-class release.

### Conditions Required

1. Resolve the five duplicate groups and record the result.
2. Add independent train, validation, and test examples for every class that
   is expected to be supported.
3. Freeze an evaluation protocol with meaningful per-class test coverage.
4. Require per-class precision, recall, mAP, error examples, CoreML metadata
   compatibility, and real-device validation before release.

### Current Recommendation

Not recommended as the next training run. It is appropriate only after the
weak classes have data support and a full-class fixed test strategy exists.

## Option B: Train a Smaller High-Quality Core Model

### Suggested Initial Core Classes

`apple`, `orange`, `pear`, `persimmon`, `grape`, and `strawberry`.

These six classes have the strongest current combination of train images,
validation images, bounding-box volume, and planned test coverage:

| Class | Total images | Validation images | Planned test images |
| --- | ---: | ---: | ---: |
| apple | 1,023 | 209 | 102 |
| orange | 665 | 148 | 66 |
| pear | 1,756 | 361 | 156 |
| persimmon | 996 | 180 | 93 |
| grape | 193 | 39 | 18 |
| strawberry | 285 | 54 | 25 |

`peach`, `mango`, `kiwi`, `mulberry`, and `blueberry` are possible later
expansion candidates, but their planned test counts range from 2 to 9 and are
not yet strong enough for an initial quality claim.

### Temporarily Excluded From the Initial Core Experiment

All other classes should remain out of the first high-quality training claim.
This is an experiment-scope decision, not a request to delete their images or
change their labels. In particular, classes with no validation coverage or
very low total image counts need data collection before they can be claimed as
reliably supported.

### App Compatibility Consideration

No App change is part of this decision pack. If a future core-only model is
considered for the App, it must declare its supported labels explicitly,
preserve label-order compatibility for those labels, and leave unsupported
selected fruit types visible as unsupported rather than silently mapping them
to a different category. Any production model change requires its own App
compatibility, diagnostics, export, and real-device validation task.

### Current Recommendation

Recommended as the next training direction, after duplicate and split
approval. It provides a smaller, measurable release candidate instead of
using aggregate metrics to mask weak classes.

## Option C: Merge or Temporarily Remove Weak Classes

### Merge or Drop Candidates

`jujube`, `fig`, and `papaya` are the clearest temporary drop or re-scope
candidates because they have 2, 3, and 7 total images respectively. The audit
also flags `pomelo`, `pomegranate`, `longan`, `bayberry`, `hawthorn`, and
`chestnut` as having limited support with no validation coverage.

`loquat` and `lychee` have no validation coverage and also contain the current
same-split duplicates. Cleanup would improve data quality but would not make
them evaluation-ready.

### Required Human Confirmation

- Whether a class is botanically and product-wise valid to merge. No automatic
  merge is justified by this audit.
- Whether each unsupported class is outside the immediate thesis experiment,
  rather than merely under-collected.
- Whether a temporary removal changes a promised App fruit category or a
  downstream experiment label.
- The exact future mapping and migration plan before any `data.yaml` or App
  category change.

### Risks

Merging semantically different fruit classes hides errors and breaks the
meaning of current labels. Removing a class from a training experiment is
lower risk than relabeling it, but a future App model with fewer classes must
not silently claim support for the excluded fruit types.

### Current Recommendation

Use this option only as a documented scope control around Option B. Do not
merge labels automatically, and do not change the current taxonomy in this
task.

## Decision

**Recommended next training strategy: Option B**

Train the six-class high-quality core model only after the duplicate review and
the conditional fixed-test approval are signed off. Keep the 26-class dataset
unchanged while collecting independent data for weak classes. Revisit Option A
only when each included class has usable train, validation, and fixed-test
coverage.
