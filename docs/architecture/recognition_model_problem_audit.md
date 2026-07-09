# Recognition Model Problem Audit

## 1. Current Model Used by App

The app loads `FruitsDetector` through `ImageDetector.loadCoreMLModel()`.
`ImageDetectorModelLoader` searches the app bundle in this order:
`FruitsDetector.mlmodelc`, `FruitsDetector.mlmodel`, then
`FruitsDetector.mlpackage`.

The production model file present in the repository is:

- `FruitTreeScanner/Core/FruitsDetector.mlpackage`
- Size: about 5.9 MB
- Xcode target status: included in the app resources as
  `FruitsDetector.mlpackage in Resources`
- Generated class name in CoreML metadata: `FruitsDetector`
- Model type: ML Program
- Input: RGB image, 320 x 320
- Output: MultiArray `Float32 1 x 30 x 2100`
- CoreML metadata short description:
  `Ultralytics best model trained on fruit_dataset_26/data.yaml`

The repository also contains `ml/models/yolov8s.mlpackage`. That package is
not the app-loaded model. Its metadata says it was trained on `coco.yaml`,
uses a 640 x 640 input, and outputs `Float32 1 x 84 x 8400`. It should be
treated as an experiment or reference artifact, not the production detector.

## 2. Model Labels and Runtime Support

The production `FruitsDetector.mlpackage` metadata contains a
`userDefinedMetadata.names` entry with 26 fruit labels:

0. apple
1. orange
2. mandarin
3. pomelo
4. pear
5. peach
6. cherry
7. grape
8. persimmon
9. mango
10. kiwi
11. plum
12. pomegranate
13. loquat
14. lychee
15. longan
16. bayberry
17. jujube
18. hawthorn
19. fig
20. papaya
21. chestnut
22. mulberry
23. blueberry
24. strawberry
25. coconut

This metadata matches `ml/datasets/fruit_dataset_26/data.yaml`,
`ml/fruit_mapping.json`, `FruitCategory.allCases`, and `CustomFruitID`.

However, the app currently reads supported classes from
`MLModel.modelDescription.classLabels`. This was not statically confirmed from
the repository contents. `coremlcompiler metadata` exposes
`userDefinedMetadata.names`, but this audit did not prove whether
`modelDescription.classLabels` returns the same list at runtime for this
YOLO MultiArray model. If runtime debug UI shows an empty supported class list,
that is probably because the labels are only stored in user-defined metadata.

Runtime confirmation needed:

- Launch the app or a small XCTest that loads `FruitsDetector.mlpackage`.
- Inspect `MLModel.modelDescription.classLabels`.
- Inspect `MLModel.modelDescription.metadata[.creatorDefinedKey]` for `names`.
- Confirm the actual output shape is still `[1, 30, 2100]`.

Training assets:

- `ml/datasets/fruit_dataset_26` contains 3,757 train images and 845 val images.
- The label files cover class IDs 0-25.
- Class counts are very imbalanced. Examples from YOLO label rows:
  - pear: 47,111 boxes
  - apple: 13,922 boxes
  - orange: 10,230 boxes
  - pomegranate: 73 boxes
  - longan: 61 boxes
  - jujube: 46 boxes
- Training run folders exist under `ml/training-runs/yolo/detect/runs/`.
  `fruit_26_v2/results.csv` ends near precision 0.38, recall 0.16,
  mAP50 0.13, and mAP50-95 0.07. `fruit_26_nano/results.csv` is similar.

These training artifacts are useful for traceability, but they do not support a
strong claim that the current detector is accurate across all 26 categories.

## 3. ImageDetector Pipeline

Current flow:

1. `ImageDetector` initializes with `FruitScanConfig.default`.
2. It loads `FruitsDetector` from the app bundle through
   `ImageDetectorModelLoader`.
3. Frames are queued on `ImageDetector.detectionQueue`.
4. RGB, depth, and depth-confidence buffers are copied before queueing.
5. `ImageDetectorInference.performDetection()` snapshots config and model.
6. If a CoreML model is available, it runs a `VNCoreMLRequest`.
7. If the model returns `VNRecognizedObjectObservation`, labels are read from
   Vision object observations.
8. If the model returns a `VNCoreMLFeatureValueObservation` MultiArray, the
   YOLO parser decodes it.
9. If no model is available, fallback records diagnostics and returns no boxes.
10. Detected fruits are enriched with AR frame, depth, intrinsics, and image
    size before entering scan fusion.

Fallback behavior:

- Fallback does not synthesize bounding boxes.
- Fallback records `fallbackFrameCount`, model failure reason, and debug
  failure samples.
- Fallback returns an empty detection list, so it cannot directly enter fusion.

YOLO MultiArray behavior:

- The parser expects a 3D MultiArray.
- The current production shape `[1, 30, 2100]` implies 4 box channels plus
  26 class channels.
- It selects the highest class score per anchor.
- Scores in `[0, 1]` are used directly; other finite scores are sigmoid-normalized.
- Candidates below `lowConfidenceFloor` 0.05 are ignored before diagnostics.
- Candidates below `config.minConfidence` are counted as confidence-filtered.
- Class indices are mapped by `FruitCategory.fromCustomModel`.
- NMS is category-aware and uses an IoU threshold of 0.45.

Vision object observation behavior:

- The top Vision label is taken from `observation.labels.first`.
- The raw label string is mapped through `FruitCategoryMapper.standard`.
- Detections below `config.minConfidence` are dropped.
- Unmapped labels do not produce `DetectedFruit`.

## 4. Label Mapping and FruitCategory Compatibility

There are two mapping paths:

- YOLO MultiArray path:
  `classIndex -> FruitCategory.fromCustomModel(classIndex)`.
- Vision object observation path:
  `topLabel.identifier -> FruitCategoryMapper.category(for:)`.

The custom model class order is centralized in `CustomFruitID`, and it matches
the dataset YAML order and production model metadata. The string mapper includes
the same 26 fruit names plus a few synonyms.

Important issues:

- `FruitCategoryMapper.category(for:)` lowercases labels but does not normalize
  spaces, underscores, or hyphens.
- Labels such as `kiwi fruit`, `mandarin orange`, `bay-berry`, or
  `pomegranate fruit` are not reliably mapped unless explicitly listed.
- The mapper maps `"banana"` to `.pear`, which may have been useful for COCO
  fallback experiments but is risky for a fruit-specific detector audit.
- `FruitCategoryMapper` has an integer custom mapping and a COCO mapping, but
  because custom integer mapping is checked first, a raw Vision label `"52"`
  would not reach the COCO banana mapping. This is probably harmless for the
  current production YOLO MultiArray path, but it is confusing.
- YOLO debug labels are generated from the app's custom mapping, not directly
  from model metadata. If the model class order changes, debug labels could look
  plausible while actually being wrong.

Raw label preservation:

- Raw Vision labels are stored in `DetectionPredictionDebug.label`.
- YOLO debug labels are stored as display names or `"class N"`, not the raw
  model metadata label string.
- `DetectedFruit` stores only the mapped `FruitCategory`, not the original raw
  model label.

## 5. Selected Fruit Type Filtering

The selected fruit type enters scan estimation from `settings.fruitType`.
`ScanCoordinatorWorkflows` converts it to `FruitCategory(rawValue:)`, then
passes it into `ScanFusionYieldBuilder.Input`.

Filtering before fusion:

- `ScanFusionCategoryFilter.detections()` keeps only detections whose
  `DetectedFruit.category` equals the target category.
- `ScanFusionCategoryFilter.candidates()` keeps cloud/depth candidates with no
  source category, or candidates whose `sourceCategory` matches the target.
- `FusionValidatorMatching` also checks candidate validity against the
  detection category.

Classification:

- The fusion-stage selected fruit filter is strict.
- A detection mapped to the wrong `FruitCategory` will be dropped if it does not
  match the selected category.
- The dropped count is not separately recorded as
  `filteredBySelectedFruitTypeCount`.
- A wrong mapping that happens to equal the selected fruit type could still
  enter fusion. This is a model/mapping correctness problem, not a selected type
  filter problem.

## 6. Detection Diagnostics

Currently recorded:

- `modelStatus`
- `modelName`
- `modelFailureReason`
- `queuedFrameCount`
- `processedFrameCount`
- `observationCount`
- `confidenceFilteredCount`
- `unmappedObservationCount`
- `mappedFruitCount`
- `fallbackFrameCount`
- `lastDetectionError`
- debug raw predictions
- debug filtered predictions
- debug top predictions
- failure samples in debug builds

Gaps:

- No structured `rawDetectedLabels` summary in scan diagnostics.
- No structured `mappedCategories` summary in scan diagnostics.
- No structured `unmappedLabels` list or count by label.
- No `filteredBySelectedFruitTypeCount`.
- No per-label confidence histogram.
- No explicit record of labels that passed confidence but failed mapping.
- No export field for recognition label distribution beyond the aggregate image
  diagnostic counts already exported.
- `DetectionFailureExportPayload` only includes a compact debug state snapshot;
  it does not include full raw/filtered prediction arrays from the final state.

The current diagnostics can explain broad failure classes: model missing,
fallback, no raw detections, confidence threshold too high, or labels unmapped.
They are not yet strong enough to explain exactly which labels were seen and
which labels were filtered by category selection.

## 7. Current Tests

Existing useful coverage:

- `DetectionDebugStateTests` covers threshold clamping, debug hints, failure
  sample Codable round trip, queue/depth copy behavior, and export payloads.
- `DetectionDeduplicatorTests` covers YOLO MultiArray parsing for a valid apple
  prediction and confidence-filtered candidates.
- `ScanDiagnosticsBuilderTests` covers zero-yield reason distinctions between
  confidence filtering and unmapped labels.
- Fusion and yield tests cover conservative handling of image-only/cloud-only
  sources and reliable fused yield behavior.

Missing or thin coverage:

- No dedicated `FruitCategoryMapperTests`.
- No tests for normalization of spaces, underscores, or hyphens.
- No tests for unknown labels preserving diagnostic detail.
- No tests asserting production model metadata names match `CustomFruitID`.
- No tests for selected fruit type filtering counts.
- No tests proving wrong-category detections are excluded before fusion with a
  diagnostic counter.
- No runtime model-loading test that checks `supportedClasses` from
  `MLModel.modelDescription` or user-defined metadata.

## 8. Problems Found

### A. Model Problems

- The production model supports 26 labels in metadata, but runtime class labels
  still require confirmation.
- Training run metrics are low for a thesis-grade recognition claim.
- Dataset class distribution is very imbalanced.
- Some categories have too few labeled boxes to expect reliable recognition.
- The repository contains both the production 26-class model and a COCO
  `yolov8s.mlpackage`, creating model-version confusion.
- The production model output is a raw YOLO MultiArray with app-side parsing and
  NMS. Output format changes would need parser tests.
- The default 0.5 confidence threshold is not justified by the current training
  metrics or a validation calibration document.
- Real orchard weaknesses remain unvalidated: small fruit, occlusion, backlight,
  motion blur, leaf-like color, dense clusters, and cultivar variation.

### B. Code Mapping Problems

- Mapping logic is split between `FruitCategoryMapper` and
  `FruitCategory.fromCustomModel`.
- String label normalization only lowercases; it does not normalize whitespace,
  underscores, hyphens, punctuation, or known dataset label phrases.
- `"banana" -> .pear` is surprising and should be revisited before relying on
  recognition categories.
- Unmapped labels are counted but their raw values are not retained in scan
  diagnostics.
- YOLO debug labels use app mapping, not model metadata, so model order drift
  could be hard to notice.
- Selected fruit filtering is strict at fusion time, but the filter does not
  emit its own count or label breakdown.

### C. Diagnostics Problems

- Recognition failure diagnostics are aggregate-heavy and label-light.
- It is hard to tell whether a zero-yield scan failed because the model saw the
  wrong class, saw an unknown class, was below threshold, or was filtered by the
  selected fruit type.
- Raw prediction details live in debug state but are not promoted into
  `ScanYieldDiagnostics`.
- Batch/single scan research exports currently expose image diagnostic counts,
  but not raw label distributions or selected-type filtered counts.
- Runtime model class support is not exported or persisted with scan results.

### D. Test Coverage Problems

- Mapper behavior lacks focused tests.
- Unknown label behavior lacks focused tests.
- Selected fruit type filtering lacks focused diagnostic tests.
- Model metadata versus app mapping compatibility lacks tests.
- Confidence threshold behavior has unit coverage for debug state, but not a
  validation-driven calibration test for current detector outputs.

## 9. Recommended Fix Order

Priority 1:

- Problem: Runtime model labels are not reliably surfaced, and model metadata
  can drift from `CustomFruitID`.
- Proposed code change: Add a small model metadata reader that falls back from
  `modelDescription.classLabels` to user-defined `names`, and add a test that
  validates the production label order against `CustomFruitID`.
- Files likely affected:
  - `FruitTreeScanner/Core/ImageDetectorModelLoading.swift`
  - `FruitTreeScanner/Core/FruitModelMappings.swift`
  - a new or existing recognition/model-loading test file
- Tests needed:
  - production model metadata names are readable
  - metadata label order matches `FruitCategory.allCases`
  - empty/missing metadata fails safely
- Risk: Low to medium. This is diagnostic and compatibility validation, but it
  touches model loading diagnostics.

Priority 2:

- Problem: String label mapping is under-normalized and surprising aliases are
  embedded without tests.
- Proposed code change: Centralize label normalization in `FruitCategoryMapper`
  and add explicit aliases for known dataset phrases. Revisit or document
  `"banana" -> .pear`.
- Files likely affected:
  - `FruitTreeScanner/Core/ImageDetectionHelpers.swift`
  - `FruitTreeScanner/Core/FruitModelMappings.swift` if mapping ownership is
    consolidated
  - new mapper tests
- Tests needed:
  - case-insensitive labels
  - labels with spaces, underscores, and hyphens
  - known aliases like `kiwi fruit` and `mandarin orange`
  - unknown labels return nil
  - banana behavior is intentional and documented or removed
- Risk: Medium. Mapping changes can alter which detections enter fusion.

Priority 3:

- Problem: Diagnostics count unmapped/filtered detections but do not preserve
  enough label detail.
- Proposed code change: Add bounded label summaries:
  `rawDetectedLabels`, `mappedCategories`, `unmappedLabels`,
  `filteredBySelectedFruitTypeCount`, and optional top confidence summaries.
- Files likely affected:
  - `FruitTreeScanner/Core/ImageDetectionHelpers.swift`
  - `FruitTreeScanner/Core/ImageDetectorInference.swift`
  - `FruitTreeScanner/Core/ImageDetectorYOLOParser.swift`
  - `FruitTreeScanner/Core/ScanFusionPipelines.swift`
  - `FruitTreeScanner/Core/YieldEstimateModels.swift`
  - `FruitTreeScanner/Core/ScanResultExportService.swift`
  - `FruitTreeScanner/Core/BatchExportJSONWriter.swift`
- Tests needed:
  - low confidence labels counted
  - unknown labels listed without crashing
  - selected-type filtered detections counted
  - export includes new diagnostic fields without removing old fields
- Risk: Medium. Mostly diagnostic/export changes, but care is needed to avoid
  large retained arrays.

Priority 4:

- Problem: The default confidence threshold is not validated against current
  model quality.
- Proposed code change: Do not change the threshold yet. First add an offline
  validation protocol and a small script/report that computes precision/recall
  by threshold on held-out images.
- Files likely affected:
  - `docs/validation/`
  - `tools/ml/`
  - optional recognition validation tests with mock outputs
- Tests needed:
  - threshold report parser
  - no app behavior change
- Risk: Low if documentation/script-only; high if threshold is changed without
  orchard validation.

Priority 5:

- Problem: Model quality is not yet strong enough for multi-class accuracy
  claims.
- Proposed code change: Plan a dataset/model improvement task, not an app-code
  change. Balance classes, add orchard-specific images, measure per-class AP,
  and archive the exact model used by the app.
- Files likely affected:
  - `ml/datasets/`
  - `ml/training-runs/`
  - `docs/validation/`
  - production model only after review
- Tests needed:
  - model metadata compatibility
  - smoke inference on representative images
  - no regression in parser output shape
- Risk: High. Model replacement can change all recognition behavior.

## 10. Do Not Change Yet

- Do not change `.fused` reliable yield rules.
- Do not let `imageOnly` or `cloudOnly` enter reliable yield estimation.
- Do not change fusion reliability policy.
- Do not change default confidence threshold until validation evidence exists.
- Do not replace `FruitsDetector.mlpackage` without a model card, metadata
  check, and parser compatibility tests.
- Do not remove selected fruit type filtering.
- Do not broaden UI fruit choices based only on repository metadata.
- Do not claim multi-class recognition accuracy from the current artifacts
  without per-class validation.

## 11. Implemented Status

Implemented in `feat/recognition-metadata-diagnostics`:

- Runtime model label diagnostics now read `MLModel.modelDescription.classLabels`
  when available and fall back to CoreML user-defined `names` metadata.
- Runtime labels are compared with the expected `CustomFruitID` /
  `FruitCategory` order and surfaced as compatible, mismatch, or unavailable.
- Model label diagnostics are stored in image detection diagnostics and debug
  state without changing model loading success or failure behavior.
- `FruitCategoryMapper` now normalizes case, surrounding whitespace,
  underscores, hyphens, and repeated whitespace before string label lookup.
- Mapper tests cover known labels, normalized labels, unknown labels, and
  `FruitCategory.fromCustomModel` order compatibility.
- Image detection diagnostics now keep bounded summaries for raw detected
  labels, mapped categories, and unmapped labels.
- Selected fruit type filtering now exposes a filtered count in scan
  diagnostics while keeping the existing strict filtering behavior.

Implemented in `feat/export-recognition-diagnostics`:

- Single-scan research JSON now appends a top-level `recognitionDiagnostics`
  object with model-label compatibility status, bounded label summaries,
  selected fruit type filtered count, confidence-filtered count, unmapped count,
  and mapped fruit count.
- Batch research JSON now appends per-record `recognitionDiagnostics`, reusing
  the single-scan sidecar when available and marking metadata unavailable when
  the sidecar is missing.
- Full raw/filtered prediction arrays, bounding boxes, frame data, depth maps,
  and complete runtime label arrays remain intentionally excluded from research
  JSON.

Remaining gaps:

- Confidence threshold calibration still needs validation data.
- Per-class recognition accuracy still needs real or held-out orchard-style
  evaluation.
- Future export work may add more aggregate recognition metrics if thesis
  analysis needs them, but it should keep arrays bounded.
