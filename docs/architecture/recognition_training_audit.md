# Recognition Training and Model Quality Audit

This audit covers the current recognition model, YOLO dataset, training records, CoreML export path, and App-side category compatibility. It does not change the CoreML model, scan fusion, reliable yield rules, Renderer, PLY, point-cloud sampling, or App estimation behavior.

## 1. Current App Model

The App loads `FruitsDetector` from the main bundle through `ImageDetectorModelLoader.loadModelState(named: "FruitsDetector")`. Lookup order is `FruitsDetector.mlmodelc`, `FruitsDetector.mlmodel`, then `FruitsDetector.mlpackage`.

The production model present in the App target is:

- `FruitTreeScanner/Core/FruitsDetector.mlpackage`
- Xcode file reference: `FruitsDetector.mlpackage`
- Xcode build phase: listed under `PBXResourcesBuildPhase` as `FruitsDetector.mlpackage in Resources`

The CoreML spec for `FruitTreeScanner/Core/FruitsDetector.mlpackage` reports:

- Model type: `mlProgram`
- Input: `image`, image type, `320x320`
- Output: `var_910`, `multiArrayType`, shape `[1, 30, 2100]`
- Metadata `task`: `detect`
- Metadata `imgsz`: `[320, 320]`
- Metadata `args`: `nms=False`
- Metadata `names`: 26 fruit labels in the expected order

This output is a YOLO MultiArray export, not a Vision recognized-object output. The App path is compatible with that format because `ImageDetectorInference` falls back from `VNRecognizedObjectObservation` to `VNCoreMLFeatureValueObservation` and parses the first `MLMultiArray` with `ImageDetector.parseYOLOMultiArray`.

The repository also contains `ml/models/yolov8s.mlpackage`. That package is not loaded by the App. It is a COCO model with 80 labels, `640x640` input, output shape `[1, 84, 8400]`, and label order that does not match `FruitCategory`.

## 2. Dataset Structure

Current dataset:

- `ml/datasets/fruit_dataset_26/data.yaml`
- YOLO-format images and labels
- `images/train`: 3,757 images
- `images/val`: 845 images
- `labels/train`: 3,757 labels
- `labels/val`: 845 labels
- No `test` split is declared in `data.yaml`
- `nc: 26`
- `names` order matches `FruitCategory.customModelLabelOrder` and `CustomFruitID`

The audit utility added in this change writes compact reports:

- `ml/audit_reports/dataset_audit_summary.json`
- `ml/audit_reports/dataset_class_distribution.csv`

The mapping guard added after the initial audit is:

- `tools/ml/check_data_yaml_app_mapping.py`
- Default data source: `ml/datasets/fruit_dataset_26/data.yaml`
- Default App mapping source: `FruitTreeScanner/Core/FruitModelMappings.swift`
- It fails when `data.yaml` is missing, `nc` differs from `names.count`, class count differs from `CustomFruitID`, raw label order differs, or normalized label order differs.
- Current result: `OK: data.yaml labels match FruitCategory.customModelLabelOrder`

## 3. Dataset Problems Found

Structural checks passed on the current dataset:

- `data.yaml` exists
- `nc` equals number of `names`
- Image/label files are paired
- No missing labels
- No missing images
- No empty label files
- No out-of-range class indices
- No invalid YOLO bbox values found
- No corrupt or unknown image headers found
- No same-stem train/val/test leakage found
- Five duplicate image hashes found when running with `--hash-duplicates`; examples are within the training split, not train/val leakage

The largest issue is severe class imbalance:

- `pear`: 1,756 images, 47,111 boxes
- `apple`: 1,023 images, 13,922 boxes
- `persimmon`: 996 images, 10,594 boxes
- `jujube`: 2 images, 46 boxes
- `fig`: 3 images, 144 boxes
- `papaya`: 7 images, 107 boxes
- `pomegranate`: 22 images, 73 boxes
- `longan`: 22 images, 61 boxes
- `coconut`: 23 images, 262 boxes
- `mandarin`: 26 images, 377 boxes

This imbalance makes the current 26-class setup fragile. Several classes have too few source images for reliable validation, per-class threshold calibration, or real orchard generalization. The current audit cannot determine small-target, occlusion, and long-distance coverage from labels alone; those need visual review and held-out orchard data.

## 4. Training Configuration

Training records exist under `ml/training-runs/yolo/detect/runs/`.

Observed runs:

- `fruit_26`: `yolov8s.pt`, 80 epochs, image size 640, batch 16, CPU, pretrained, val enabled, plots enabled, no `results.csv` present in this run folder
- `fruit_26_nano`: `yolov8n.pt`, 30 epochs, image size 320, batch 32, CPU, cache enabled, pretrained, val enabled, `best.pt`, `last.pt`, `results.csv`, confusion matrices, PR/P/R/F1 curves, exported `best.mlpackage`
- `fruit_26_v2`: `yolov8n.pt`, 30 epochs, image size 320, batch 32, CPU, cache enabled, pretrained, val enabled, `best.pt`, `last.pt`, `results.csv`, confusion matrices, PR/P/R/F1 curves, exported `best.mlpackage`

Final metrics in the recorded 30-epoch runs are low:

- `fruit_26_nano`: precision 0.322, recall 0.146, mAP50 0.116, mAP50-95 0.066
- `fruit_26_v2`: precision 0.382, recall 0.162, mAP50 0.127, mAP50-95 0.073

These look like exploratory or low-quality baseline runs, not a model ready for reliable yield estimation. There is validation output, but no fixed test set and no checked-in per-class metrics table. The imbalance and missing test split create overfitting and false-confidence risk, especially for classes with fewer than 50 images.

## 5. CoreML Export Compatibility

The current production model metadata is internally consistent:

- `names` metadata is present
- Label order matches App expectation
- Input size is `320x320`
- Output is YOLO MultiArray
- `nms=False`, so the App-side parser performs post-processing and NMS

App thresholds:

- Detection confidence threshold comes from `FruitScanConfig.minConfidence`, sourced from `FruitScanExperimentConfig.default.detector.minConfidence`
- YOLO parser low-confidence debug floor is `0.05`
- YOLO App-side NMS threshold defaults to `0.45`
- Training/validation args use Ultralytics validation `iou: 0.7`

Missing export validation:

- No script currently proves that PyTorch YOLO and exported CoreML return the same label order and comparable outputs on a fixed image set
- No completed model-card style record ties the App-bundled `FruitsDetector.mlpackage` to the exact `best.pt`, dataset hash, script version, and metrics

The added `tools/ml/check_model_metadata.py` is a metadata/spec checker. It is not an inference parity checker.

The production export guard in `tools/ml/export_coreml.py` now refuses COCO fallback. Before export, it requires:

- A readable `data.yaml`
- `nc` equal to `names.count`
- `names` matching the 26-class FruitTreeScanner label order
- A custom-trained `best.pt` from `--weights` or known training-run candidates

If custom weights are missing, it fails with `missing custom weights` and `refusing COCO fallback for FruitTreeScanner production model`. `--dry-run` validates these checks without importing Ultralytics or exporting CoreML.

## 6. App Category Mapping Compatibility

The current label order is compatible across:

- `ml/datasets/fruit_dataset_26/data.yaml`
- `CustomFruitID`
- `FruitCategory.customModelLabelOrder`
- `FruitCategory.fromCustomModel`

For YOLO MultiArray outputs, the App maps `classIndex -> FruitCategory.fromCustomModel(classIndex)`. For Vision recognized-object outputs, the App maps string labels through `FruitCategoryMapper.standard`, which normalizes case, whitespace, underscores, and hyphens.

Diagnostics/export coverage is already present:

- Runtime model labels
- Label compatibility status and warnings
- Raw detected labels
- Mapped detected categories
- Unmapped detected labels
- Confidence-filtered count
- Unmapped-observation count
- Selected fruit type filter count

Single-scan JSON and batch JSON both preserve recognition diagnostics. The selected fruit type filter is applied later in `ScanFusionPipelines.detectionFilterResult`: if a scan is configured for one fruit type, detections of other categories are filtered before fusion. This is expected behavior, but it means renamed or remapped model labels can look like detection failure during yield estimation.

## 7. Model Quality Risks

P0 risks:

- Legacy notebooks or manual workflows can still create COCO exports if used outside the guarded production export script. The production `tools/ml/export_coreml.py` path now refuses COCO fallback.
- There is no fixed test split, so validation quality can be overstated and cannot measure held-out orchard generalization.
- No export parity gate currently proves CoreML labels and outputs match the PyTorch model selected for release.

P1 risks:

- Severe class imbalance makes 26-class training unstable.
- Several classes have too few source images for useful per-class validation.
- Historical remapping in `train_and_export.py` merges unrelated or weak proxy classes into fruit labels, for example `banana -> pear`, `tomato -> persimmon`, and synthetic COCO-like IDs into fruit classes.
- `fruit_26_nano` and `fruit_26_v2` metrics are far below a production recognition threshold for a yield-estimation pipeline.
- Small fruit, occluded fruit, distant fruit, and orchard background coverage are not proven by current metadata.

P2 risks:

- Confidence threshold and NMS threshold are global, not per class.
- UI and operator diagnostics can say a model loaded successfully even if a newly exported model is low quality.
- Current metadata does not include dataset version, training run ID, git commit, or per-class metrics.

## 8. Required Fixes Before Retraining

P0:

- Use `tools/ml/export_coreml.py`; it now disables COCO fallback for production export and requires custom `best.pt`.
- Add a fixed `test` split or external held-out orchard test set before declaring quality.
- Keep `data.yaml`, `CustomFruitID`, and `FruitCategory.customModelLabelOrder` locked together with `tools/ml/check_data_yaml_app_mapping.py`.
- Require model metadata labels to match App label order before replacing `FruitsDetector.mlpackage`.
- Record exact dataset path/hash, training args, source weights, metrics, and export args for every release candidate.

P1:

- Clean or rebalance classes with fewer than 50 images before full 26-class training.
- Consider a smaller high-quality class set first, such as apple/orange/pear/persimmon/grape/strawberry, before forcing 26 classes.
- Remove weak proxy mappings unless they are explicitly justified with visual review.
- Add per-class metrics to each training report.
- Add class-focused visual QA for small, occluded, clustered, and distant fruit.

P2:

- Calibrate confidence thresholds after CoreML export.
- Consider per-class thresholds only after per-class validation data exists.
- Surface unsupported model classes in UI diagnostics if a future model uses fewer classes.
- Add real-orchard held-out validation with LiDAR-capable device captures.

## 9. Recommended Retraining Plan

1. Freeze label order and supported class set before training.
2. Run `tools/ml/audit_yolo_dataset.py --hash-duplicates` on the candidate dataset.
3. Run `tools/ml/check_data_yaml_app_mapping.py` and fix any class order mismatch.
4. Create a fixed test split that is never used for training or early stopping.
5. Decide whether to train all 26 classes or a smaller high-quality subset.
6. Remove weak remaps and ambiguous labels from the training source.
7. Train with documented Ultralytics version, source weights, image size, epochs, batch, augmentations, and seed.
8. Fill out `docs/templates/recognition_model_card.md` for the candidate run.
9. Save per-class metrics, confusion matrix, PR curves, sample predictions, and failure cases.
10. Export CoreML through `tools/ml/export_coreml.py --weights <best.pt> --data-yaml <data.yaml>` with class labels preserved and `nms=False` unless the App parser is intentionally changed.
11. Run metadata checks and inference parity checks before copying any model into `FruitTreeScanner/Core/`.
12. Validate the release candidate on a LiDAR-capable iOS/iPadOS device before claiming scan-to-yield reliability.

## 10. Post-training Validation Checklist

- `data.yaml` labels match App label order.
- `tools/ml/check_data_yaml_app_mapping.py` passes.
- No missing labels/images, empty labels, bbox errors, out-of-range class IDs, split leakage, or duplicate images.
- Fixed test set metrics are recorded.
- Per-class precision, recall, mAP50, and mAP50-95 are recorded.
- Confusion matrix is reviewed for similar-fruit collapse.
- CoreML metadata `names` exactly matches expected labels.
- CoreML input size and output shape match App parser assumptions.
- CoreML export uses expected NMS behavior.
- `tools/ml/export_coreml.py --dry-run --weights <best.pt> --data-yaml <data.yaml>` passes before export.
- `docs/templates/recognition_model_card.md` is completed for the candidate model.
- PyTorch/CoreML inference parity is checked on representative images.
- Single-scan JSON and batch JSON include recognition diagnostics.
- Simulator tests pass for detection diagnostics and mapping.
- Real-device LiDAR validation is performed before thesis/product claims.

## 11. Next Code Tasks

Task 1: dataset audit script

- Goal: Keep YOLO dataset integrity checks repeatable.
- Files: `tools/ml/audit_yolo_dataset.py`, `ml/audit_reports/*`
- App changes: No
- Model changes: No
- Test: `python3 -m py_compile tools/ml/audit_yolo_dataset.py`; `python3 tools/ml/audit_yolo_dataset.py --help`; run on candidate dataset.
- Risk: Low; read-only checker.

Task 2: model metadata checker

- Goal: Block model replacement when labels, input size, or output format do not match App assumptions.
- Files: `tools/ml/check_model_metadata.py`
- App changes: No
- Model changes: No
- Test: `python3 -m py_compile tools/ml/check_model_metadata.py`; `python3 tools/ml/check_model_metadata.py --help`; run on candidate `.mlpackage`.
- Risk: Low; depends on `coremltools` for spec inspection.

Task 3: data.yaml to FruitCategory consistency test

- Goal: Keep `data.yaml` order locked to `FruitCategory.customModelLabelOrder`.
- Files: `tools/ml/check_data_yaml_app_mapping.py`
- App changes: No production behavior change
- Model changes: No
- Test: `python3 tools/ml/check_data_yaml_app_mapping.py`
- Risk: Low.

Task 4: CoreML export verification doc

- Goal: Document a release gate for `best.pt -> .mlpackage -> App`.
- Files: `docs/architecture/*`, `tools/ml/export_coreml.py`, `docs/templates/recognition_model_card.md`
- App changes: No
- Model changes: No
- Test: `python3 tools/ml/export_coreml.py --dry-run`; metadata checker and a future inference parity script.
- Risk: Low.

Task 5: training run report template

- Goal: Make every candidate model traceable to dataset, run args, metrics, export args, and App compatibility.
- Files: `docs/templates/recognition_model_card.md`, then copy per run as `ml/training-runs/*/MODEL_CARD.md`
- App changes: No
- Model changes: No
- Test: review checklist completion.
- Risk: Low.
