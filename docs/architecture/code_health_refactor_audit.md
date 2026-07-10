# Code Health and Refactor Hotspot Audit

## Legacy YieldEstimator Boundary

### Current production yield path

The production scan flow is:

1. `ScanView` finishes a scan and calls `ScanCoordinator.runMultiModalYieldEstimate`.
2. `ScanCoordinator` flushes pending image detections and captures an immutable `ScanFusionYieldBuilder.Input` snapshot.
3. `ScanFusionYieldBuilder.build(from:)` runs the point-cloud, depth-detection, category-filter, and fusion-evidence pipelines.
4. `YieldResultComposer` creates the final result and diagnostics.

`FusionEvidencePipeline` and `YieldResultComposer` preserve the core reliability rule: only `.fused` evidence contributes to reliable yield. `imageOnly` and `cloudOnly` evidence remain diagnostic/supporting evidence and do not become reliable yield through this path.

### Legacy estimator status

`YieldEstimator` is not on a production App path. The current source audit found references only in `FruitTreeScannerTests/YieldEstimatorTests.swift`; production scan code enters through `ScanFusionYieldBuilder`.

The legacy estimator remains in Core because it provides a historical Route A / Route B baseline and keeps its existing regression tests available for offline comparison. Its independent correction and fusion behavior is not interchangeable with the current scan-fusion pipeline, which carries scan diagnostics, depth evidence, category filtering, and `.fused` reliability semantics.

`YieldEstimator` is therefore deprecated for production use. New scan, export, or result presentation code must not instantiate it; use `ScanFusionYieldBuilder` through `ScanCoordinator.runMultiModalYieldEstimate` instead.

### Removal or migration checklist

Before removing `YieldEstimator`:

1. Re-run a production-reference search and confirm it is still test/offline-only.
2. Decide whether its historical Route A / Route B tests remain required as a baseline; migrate required cases to a dedicated baseline fixture or archive them with documented expected outputs.
3. Confirm that no experiment, export, or offline analysis tool depends on its result fields or method labels.
4. Preserve the current `ScanFusionYieldBuilder` fusion and reliable-yield tests, including `.fused`-only yield rules.
5. Remove the type and obsolete tests only in a dedicated behavior-preserving change with full simulator validation and any required offline baseline comparison.

Until that checklist is complete, the file remains intentionally available but marked deprecated to prevent accidental production reuse.
