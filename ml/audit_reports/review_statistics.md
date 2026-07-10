# Semantic Manual Review Statistics

## Scope

This report prioritizes existing `manual_review` rows only. It does not make dataset changes or confirm that an image is invalid. Apple Vision is a triage signal and requires human verification.

- Full manual-review population: 750 images
- Semantic sidecar matches: 750/750 images
- First-pass queue target: 200 images
- Recommended first-pass review: 200 images
- Deferred after first pass: 550 images

The first pass retains every high-risk entry, then fills remaining places with the highest-priority medium-risk entries. Deferred rows remain in the source audit CSV and are not approved for training by this report.

## Risk Distribution

| Risk level | Images | Share of manual-review population |
| --- | ---: | ---: |
| high | 180 | 24.0% |
| medium | 570 | 76.0% |
| low | 0 | 0.0% |

## Priority Categories

| Priority | Rule | Images |
| --- | --- | ---: |
| 1 | Fruit-class disagreement | 8 |
| 2 | Strong non-fruit signal (score >= 0.85) | 60 |
| 3 | Object-dominant non-fruit signal (score >= 0.70) | 112 |
| 4 | People without fruit signal | 501 |
| 5 | Weak non-fruit signal | 69 |
| Later | Weak or unavailable signal | 0 |

## Manual Review by Current Class

Multi-label images are counted once for each listed current class, so this table can sum to more than the number of image rows.

| Current class | Manual-review images | High | Medium | Low | High-risk share |
| --- | ---: | ---: | ---: | ---: | ---: |
| pear | 263 | 56 | 207 | 0 | 21.3% |
| apple | 208 | 59 | 149 | 0 | 28.4% |
| orange | 78 | 21 | 57 | 0 | 26.9% |
| persimmon | 64 | 11 | 53 | 0 | 17.2% |
| strawberry | 41 | 5 | 36 | 0 | 12.2% |
| grape | 32 | 9 | 23 | 0 | 28.1% |
| mango | 24 | 9 | 15 | 0 | 37.5% |
| cherry | 18 | 5 | 13 | 0 | 27.8% |
| longan | 16 | 1 | 15 | 0 | 6.2% |
| lychee | 13 | 4 | 9 | 0 | 30.8% |
| bayberry | 12 | 7 | 5 | 0 | 58.3% |
| plum | 11 | 0 | 11 | 0 | 0.0% |
| chestnut | 8 | 5 | 3 | 0 | 62.5% |
| blueberry | 7 | 2 | 5 | 0 | 28.6% |
| pomegranate | 7 | 6 | 1 | 0 | 85.7% |
| loquat | 5 | 0 | 5 | 0 | 0.0% |
| coconut | 4 | 0 | 4 | 0 | 0.0% |
| peach | 4 | 3 | 1 | 0 | 75.0% |
| pomelo | 3 | 0 | 3 | 0 | 0.0% |
| hawthorn | 2 | 0 | 2 | 0 | 0.0% |
| kiwi | 2 | 2 | 0 | 0 | 100.0% |
| mulberry | 2 | 1 | 1 | 0 | 50.0% |
| papaya | 2 | 0 | 2 | 0 | 0.0% |
| mandarin | 1 | 1 | 0 | 0 | 100.0% |

## Recommended Review Order

Review the 180 high-risk images first. The bounded first-pass queue then includes 20 medium-risk images to reach 200 total items. Resolve class disagreements and likely non-fruit/object-dominant frames before reviewing people-only and weak signals. Do not delete, move, relabel, or train on any item solely from this automated triage.

## Review Assistant Artifacts

- HTML review page generated for the 200 first-pass rows.
- `manual_review_decisions.csv` was generated with every approval set to `pending_review`.
- These materials support human approval only; they do not alter images, labels, or dataset membership.
- Dataset status remains: not approved for training.
- Resolve all 180 first-pass high-risk samples before considering training approval.
