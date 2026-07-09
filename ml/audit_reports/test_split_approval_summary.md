# Fixed Test Split Approval Summary

## Plan Identity

- Source plan: `ml/audit_reports/test_split_plan.csv`
- Per-class summary: `ml/audit_reports/test_split_class_distribution.csv`
- Source split: current `train` only; current `val` remains unchanged
- Planned unique test images: 376
- Requested test ratio: 10%
- Planning seed: `20260709`
- Target calculation: `round(3,757 train images * 0.10) = 376`
- Actual dataset state: no `test` split exists yet; this report does not move
  any image or label.

The class-level image counts below can sum to more than 376 because a planned
image may contain more than one class. Planned boxes are the boxes for that
class in the selected images.

## Per-Class Planned Coverage

| ID | Class | Planned test images | Planned test boxes | After-plan train images | Review status |
| --- | --- | ---: | ---: | ---: | --- |
| 0 | apple | 102 | 1,358 | 712 | usable core coverage |
| 1 | orange | 66 | 1,119 | 451 | usable core coverage |
| 2 | mandarin | 0 | 0 | 18 | protected low sample |
| 3 | pomelo | 0 | 0 | 52 | protected; no validation coverage |
| 4 | pear | 156 | 4,467 | 1,239 | usable core coverage |
| 5 | peach | 6 | 52 | 41 | limited test coverage |
| 6 | cherry | 0 | 0 | 73 | protected; validation has only 3 images |
| 7 | grape | 18 | 522 | 136 | usable core coverage |
| 8 | persimmon | 93 | 888 | 723 | usable core coverage |
| 9 | mango | 4 | 13 | 46 | test coverage too small for a reliable claim |
| 10 | kiwi | 9 | 104 | 44 | limited test coverage |
| 11 | plum | 0 | 0 | 44 | protected; no validation coverage |
| 12 | pomegranate | 0 | 0 | 22 | protected low sample |
| 13 | loquat | 0 | 0 | 59 | protected; no validation coverage |
| 14 | lychee | 0 | 0 | 59 | protected; no validation coverage |
| 15 | longan | 0 | 0 | 22 | protected low sample |
| 16 | bayberry | 0 | 0 | 34 | protected low sample |
| 17 | jujube | 0 | 0 | 2 | protected low sample |
| 18 | hawthorn | 0 | 0 | 45 | protected; no validation coverage |
| 19 | fig | 0 | 0 | 2 | protected low sample |
| 20 | papaya | 0 | 0 | 7 | protected low sample |
| 21 | chestnut | 0 | 0 | 42 | protected; no validation coverage |
| 22 | mulberry | 2 | 9 | 62 | test coverage too small for a reliable claim |
| 23 | blueberry | 3 | 82 | 70 | test coverage too small for a reliable claim |
| 24 | strawberry | 25 | 339 | 206 | usable core coverage |
| 25 | coconut | 0 | 0 | 20 | protected; validation has only 3 images |

## Classes With Insufficient Test Evidence

The following planned classes have fewer than 10 test images: `peach` (6),
`mango` (4), `kiwi` (9), `mulberry` (2), and `blueberry` (3). Their planned
examples can expose obvious failures but are not sufficient for a robust
per-class quality claim.

Fifteen classes are deliberately not sampled into test: `mandarin`, `pomelo`,
`cherry`, `plum`, `pomegranate`, `loquat`, `lychee`, `longan`, `bayberry`,
`jujube`, `hawthorn`, `fig`, `papaya`, `chestnut`, and `coconut`. The guard is
appropriate: it avoids taking the last meaningful training support from a
class that is already low-sample, lacks validation coverage, or has too few
validation images. It also means the resulting test split cannot substantiate
a 26-class performance claim.

## Effect on Training Support

The planner retains at least its configured post-split support for every
selected class and leaves every protected class unchanged. It therefore does
not make the weakest classes weaker by removing examples from them. It does
reduce train images for selected marginal classes, for example `kiwi` from 53
to 44 and `peach` from 47 to 41, but those remain above the planner guards.

The material risk is not train depletion. It is incomplete test coverage:
classes with zero or only a few test images must remain unsupported for
per-class test reporting until independent data is collected.

## Approval Recommendation

Recommendation: **conditionally approve** the current plan as the fixed test
candidate set for an initial core-class model. Do **not** approve it as a
complete 26-class evaluation set.

Approval conditions:

1. Complete the duplicate decisions in `duplicate_review_pack.md` before any
   split operation, so a duplicate cannot later be retained in train and
   test.
2. Freeze the plan path list and seed exactly as recorded above.
3. Use fixed-test metrics only for classes with meaningful planned coverage;
   do not report unsupported or protected classes as tested.
4. Keep the current validation split unchanged and record the actual file
   operation in the dataset version note when a future approved cleanup task
   performs it.

If a full 26-class release is the goal, revise the plan only after collecting
independent train/validation/test examples for protected classes. Increasing
the test ratio now would further reduce marginal train support without solving
the lack of class diversity.

Human approval:

- [ ] Approve as fixed core-class test plan
- [ ] Request a revised plan after additional data collection
- [ ] Reject the plan
