# Exported Research Fields

Task: Mock research export validation

Date: 2026-07-09

Scope: research export fields that can be validated without a real orchard scan.
This document describes current app exports plus low-risk fields appended for
research validation. It does not change fusion, yield reliability, ImageDetector,
Renderer, point-cloud sampling, or PLY parser behavior.

## Export Surfaces

- Single-scan CSV: `ScanResultExportService.makeCSVContent(for:)`
- Single-scan JSON metadata: `ScanResultExportService.writeMetadata(for:baseName:scansDir:)`
- Per-fruit research CSV: `ResearchCSVExporter.makeCSV(estimates:groundTruthByID:)`
- Batch CSV: `BatchExportCSVWriter.write(records:options:to:)`
- Batch Excel XML: `BatchExportExcelWriter.write(records:options:to:)`
- Batch research JSON: `BatchExportJSONWriter.write(records:options:to:)`
- Scan history records: `ScanFileRecord`

Batch research JSON is intended for thesis analysis scripts. CSV and Excel are
kept for spreadsheet workflows and compatibility with existing app behavior.

## Field Matrix

| Field | Meaning | Unit | Source module | Exported | Error metric use | Failure diagnosis use | Needs manual ground truth |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `scanID` | Stable scan-level identifier derived from source filename | text | `ScanResultExportService` / `ScanFileRecord.fileURL` | Single JSON, batch JSON | repeated scan grouping | trace exported files | no |
| `sourceFilename` | Original PLY filename used for export | text | `ScanResultExportService.ExportRequest` / `ScanFileRecord.fileURL` | Single JSON, batch JSON | traceability | trace file provenance | no |
| `treeID` / `树编号` / `果树编号` | Tree identifier | text | export request / `ScanFileRecord` | Single CSV, single JSON, batch CSV/XML, batch JSON | grouping by tree | trace repeated scans | yes, for ground truth join |
| `treeName` | Human tree name if available | text | not currently modeled | Batch JSON as null | grouping if manually added later | traceability | yes |
| `orchardName` | Orchard/site name if available | text | not currently modeled | Batch JSON as null | site grouping | traceability | yes |
| `fruitType` / `水果类型` | Fruit type or category label | text | export request / result / `ScanFileRecord` | Single CSV, single JSON, batch CSV/XML, batch JSON, per-fruit CSV | grouping by crop | category mismatch diagnosis | yes, if ground truth is typed |
| `timestamp` / `扫描日期` | Scan timestamp | ISO-8601 or formatted date | export request / `ScanFileRecord` | Single CSV, single JSON, batch CSV/XML, batch JSON | repeated scan stability | temporal trace | yes, if matching field notes |
| `gpsLat`, `gpsLon` / `GPS纬度`, `GPS经度` / `纬度`, `经度` | Scan GPS coordinate | degrees | export request / `ScanFileRecord` | Single CSV, single JSON, batch CSV/XML, batch JSON | orchard block grouping | location mismatch | optional |
| `fruitCount` / `estimatedCount` / `果实数量` | Reliable exported fruit count | count | `YieldResult.nLidar` / `ScanFileRecord` | Single CSV, single JSON, batch CSV/XML, batch JSON | count MAE/MAPE | zero or low yield review | yes |
| `yieldKg` / `estimatedYield` / `estimatedYieldKg` / `产量(kg)` | Final exported yield | kg | `YieldResult.yieldFinalKg` / `ScanFileRecord` | Single CSV, single JSON, batch CSV/XML, batch JSON | yield MAE/MAPE | yield plausibility | yes |
| `confidence` / `置信度` | Summary confidence label | text | `YieldResult.confidence` | Single CSV, single JSON, scan history defaults | stratified error analysis | low confidence triage | no |
| `methodUsed` / `方法` | Yield method summary | text | `YieldResult.methodUsed` | Single CSV, single JSON | stratified analysis | method path trace | no |
| `note` / `备注` | Human-readable scan note | text | `YieldResult.note` | Single CSV, single JSON | no | failure/review trace | no |
| `clusterEps` / `聚类Eps` | DBSCAN epsilon used for point-cloud clustering | meters | `YieldResult.clusterEps` | Single CSV, single JSON | no | clustering diagnosis | no |
| `clusterMinPoints` / `聚类MinPoints` | DBSCAN min points | count | `YieldResult.clusterMinPoints` | Single CSV, single JSON | no | clustering diagnosis | no |
| `colorFilterDesc` / `颜色过滤` | Color filter description | text | `YieldResult.colorFilterDesc` | Single CSV, single JSON | no | category/color filtering review | no |
| `occlusionK` / `遮挡系数K` | Occlusion correction factor | multiplier | `YieldResult.occlusionK` | Single CSV, single JSON | sensitivity analysis | overcorrection review | no |
| `pointCloudSize` / `点云大小` | Analysis point-cloud size | points | `YieldResult.pointCloudSize` | Single CSV, single JSON | no | scan density diagnosis | no |
| `treeHeightM` | Canopy/tree height | meters | `YieldResult` / canopy estimator | Single JSON | covariate | scan geometry diagnosis | optional |
| `crownVolM3` | Effective crown volume | cubic meters | `YieldResult` / canopy estimator | Single JSON | covariate | canopy quality diagnosis | optional |
| `meanDiameterCm` | Mean estimated fruit diameter | cm | `YieldResult` | Single JSON | fruit-size analysis | geometry plausibility | optional |
| `meanVolumeCm3` | Mean estimated fruit volume | cm3 | `YieldResult` | Single JSON | fruit-size analysis | geometry plausibility | optional |
| `correctionK` | Count/yield correction factor used in result | multiplier | `YieldResult` | Single JSON | sensitivity analysis | overcorrection review | no |
| `yieldBVisibleKg` | Visible-fruit yield before occlusion correction | kg | `YieldResult` | Single JSON | method comparison | occlusion diagnosis | optional |
| `yieldBCorrectedKg` | Corrected yield after occlusion/calibration | kg | `YieldResult` | Single JSON | yield MAE/MAPE variant | correction diagnosis | yes |
| `fruitMassEstimates` | Per-fruit mass estimate array | mixed | `YieldResult.fruitMassEstimates` | Single JSON, batch JSON when sidecar exists | per-fruit mass error | mass/shape diagnosis | yes, for per-fruit validation |
| `validatedFruits` | Per-fruit validation source, category, position, confidence | mixed | `YieldResult.validatedFruits` | Single JSON, batch JSON when sidecar exists | source-stratified error | fusion evidence trace | optional |
| `sourceCounts` | Summary counts by validation source | counts | `ScanYieldDiagnostics` | Batch JSON when sidecar exists | stratified error analysis | fusion evidence trace | no |
| `diagnostics.*Count` | Point-cloud, image, depth, fused, and candidate counts | counts | `ScanYieldDiagnostics` | Single JSON, batch JSON when sidecar exists | stratified error analysis | scan failure diagnosis | no |
| `diagnostics.zeroYieldReasons` / `zeroYieldReasons` | Structured reasons for zero-yield output | text array | `ScanYieldDiagnostics` | Single JSON, batch JSON when sidecar exists | no | zero-yield diagnosis | no |
| `diagnostics.imageModelStatus` | Image model status | text | `ScanYieldDiagnostics` | Single JSON, batch JSON when sidecar exists | no | model readiness diagnosis | no |
| `diagnostics.imageModelName` | Image model name | text | `ScanYieldDiagnostics` | Single JSON, batch JSON when sidecar exists | no | model provenance | no |
| `diagnostics.imageFailureReason` | Image detection failure reason | text | `ScanYieldDiagnostics` | Single JSON, batch JSON when sidecar exists | no | detection failure diagnosis | no |
| `recognitionDiagnostics` | Bounded runtime recognition diagnostics: model-label compatibility, label summaries, selected-type filter count, confidence/unmapped/mapped counts | mixed | `ScanYieldDiagnostics` / `ScanResultExportService` | Single JSON, batch JSON | no | recognition failure, category mismatch, unmapped-label diagnosis | no |
| `trueWeightG` | Manual per-fruit mass | grams | `FruitMassEstimateGroundTruth` | Per-fruit research CSV | per-fruit mass MAE/MAPE | no | yes |
| `trueVolumeCm3` | Manual per-fruit volume | cm3 | `FruitMassEstimateGroundTruth` | Per-fruit research CSV | per-fruit volume error | no | yes |

## Already Exported

- Single-scan CSV covers tree ID, fruit type, scan date, fruit count, yield,
  GPS, clustering settings, color filter, occlusion factor, point-cloud size,
  confidence, method, and note.
- Single-scan JSON covers the same high-level result fields plus canopy metrics,
  mass estimates, validation-source diagnostics, scan diagnostics, image
  diagnostics, recognition diagnostics, zero-yield reasons, `scanID`,
  `sourceFilename`, and per-fruit `validatedFruits`.
- Per-fruit research CSV covers fruit mass geometry, model choice, warning
  flags, confidence, point/depth quality, and optional manual per-fruit ground
  truth.
- Batch CSV/Excel covers scan-history summaries: tree ID, fruit count, yield,
  GPS, date, fruit type, optional grouping, and totals.
- Batch research JSON covers export metadata, scan-level summary fields, and
  detailed per-scan research fields when the matching single-scan `_result.json`
  sidecar is available.

## Batch JSON Compared With CSV and Excel

- CSV and Excel are spreadsheet-friendly summaries and keep their existing
  headers for compatibility.
- Batch JSON is structured for scripts and notebooks. It includes
  `exportMetadata`, a `records` array, sidecar availability flags, source
  counts, diagnostics, `validatedFruits`, and `fruitMassEstimates`.
- Batch JSON does not replace single-scan JSON. It reuses single-scan JSON
  sidecars when available and falls back to `ScanFileRecord` summary fields when
  they are not available.
- Ground truth alignment should use `treeID`, `scanID`, `sourceFilename`,
  `fruitType`, `timestamp`, and GPS/location fields where reliable.
- MAE/MAPE calculations should use `estimatedCount` with manual fruit count and
  `estimatedYieldKg` with harvested yield kg.
- Scan failure diagnosis should use `diagnostics`, `zeroYieldReasons`,
  `sourceCounts`, `imageDiagnostics`, `recognitionDiagnostics`, and
  `singleScanMetadataAvailable`.

## Internal but Not Exported

- Raw `DetectedFruit` bounding boxes, per-detection confidence, image timestamp,
  camera intrinsics, camera transform, depth map, and depth confidence map are
  internal and not exported in research files.
- Full raw/filtered prediction arrays are internal debug data and are not
  exported. Research JSON only includes bounded label summaries in
  `recognitionDiagnostics`.
- `FruitCandidate` point samples, sphericity, average color, source category,
  and depth support ratio are internal and not exported per candidate.
- Full point-cloud samples and renderer confidence values are internal and are
  not exported through research CSV/JSON.
- `FruitCountResult` has a Codable validated-fruit list, but the single-scan
  export path uses `YieldResult`; `YieldResult.validatedFruits` is the appended
  research export bridge.

## Missing or Manual-Only Fields

- Manual ground-truth columns are not stored in scan exports. They should be
  joined externally by `treeID`, `scanID`, timestamp, and fruit type.
- Repeated-scan labels such as replicate number, operator ID, plot/block ID, row
  number, and tree position are not part of single-scan or batch JSON unless
  encoded in `treeID`, `sourceFilename`, or external ground-truth sheets.
- Per-fruit matching from exported mass estimates to hand-labeled fruits still
  requires external labeling or a manual ID map.

## Compatibility Notes

- Existing export field names were not deleted or renamed.
- New JSON fields are appended only.
- CSV headers are unchanged in this validation pass.
- `.fused` remains the reliable yield source. Mock JSON can contain
  `image_only` or `cloud_only` entries only when synthetic test data explicitly
  puts them in `YieldResult.validatedFruits`; the production fusion pipeline
  still filters reliable yield output to fused evidence.
