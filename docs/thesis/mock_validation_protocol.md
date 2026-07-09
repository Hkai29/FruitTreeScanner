# Mock Validation Protocol

Task: Mock research export validation

Date: 2026-07-09

Purpose: validate the research export path when no real orchard data or LiDAR
device validation is available. This protocol exercises export structure,
schema stability, diagnostic traceability, and downstream error-calculation
readiness with synthetic data only.

## Goals

- Prove single-scan CSV and JSON can be produced from a synthetic `YieldResult`.
- Prove per-fruit research CSV can be produced from synthetic
  `FruitMassEstimate` values.
- Prove batch CSV/Excel can be produced from synthetic `ScanFileRecord` values.
- Prove fused, image-only, and cloud-only source labels can be represented in
  research JSON without changing reliable yield rules.
- Prove exported identifiers support later joining with manual ground truth.

## Constructing a Mock Scan Result

Use a synthetic `ScanResultExportService.ExportRequest`:

- `treeID`: stable tree identifier such as `T-001`
- `fruitType`: crop label such as `apple`
- `scanDate`: fixed timestamp for deterministic tests
- `gpsLat`, `gpsLon`: valid coordinates or invalid values for sanitization tests
- `sourceFilename`: safe PLY filename, for example
  `mock_tree_T-001_rep1.ply`
- `result`: synthetic `YieldResult`

Populate `YieldResult` with:

- `nLidar`: reliable exported count
- `yieldFinalKg`: final exported yield in kg
- `confidence`, `methodUsed`, `note`
- `clusterEps`, `clusterMinPoints`, `colorFilterDesc`, `occlusionK`
- `pointCloudSize`
- canopy fields such as `treeHeightM` and `crownVolM3`
- `diagnostics` for scan quality and failure traceability
- `fruitMassEstimates` for per-fruit mass research
- `validatedFruits` for source-label export verification

## Constructing Fused, Image-Only, and Cloud-Only Mock Entries

Production reliable yield still depends on `.fused` evidence. Do not alter
`FusionValidator`, `FusionEvidencePipeline`, or `.fused` filtering rules.

For export-schema tests only, construct synthetic `ValidatedFruitData` values:

- `.fused`: confirms reliable fused-source rows are exported.
- `.imageOnly`: confirms image-only source labels remain distinguishable in
  research metadata.
- `.cloudOnly`: confirms cloud-only source labels remain distinguishable in
  research metadata.

These synthetic entries validate export representation, not production yield
eligibility.

## Constructing Fruit Mass Estimates

Create one or more `FruitMassEstimate` values with deterministic IDs and dates.
Recommended fields:

- `fruitCategory`
- `lengthCm`, `widthCm`, `heightCm`
- `equivalentDiameterCm`
- `sphereVolumeCm3`, `ellipsoidVolumeCm3`, `selectedVolumeCm3`
- `densityGPerCm3`
- `estimatedWeightG`
- `confidenceScore`
- `pointCount`
- `highConfidenceRatio`
- `validDepthRatio`
- `shapeModelUsed`
- `warningFlags`
- `createdAt`

Use `ResearchCSVExporter.makeCSV(estimates:groundTruthByID:)` to verify
per-fruit export. Provide `FruitMassEstimateGroundTruth` only when a manual
per-fruit label exists.

## Ground Truth Join Table

When real field data becomes available, keep a separate ground-truth table. At
minimum:

- `tree_id`
- `scan_id`
- `replicate_id`
- `fruit_type`
- `scan_timestamp`
- `manual_fruit_count`
- `actual_yield_kg`
- `operator_id`
- `plot_id`
- `row_id`
- `tree_position`
- `notes`

For per-fruit validation, add:

- `fruit_instance_id`
- `scan_id`
- `manual_weight_g`
- `manual_volume_cm3`
- `matching_confidence`
- `labeler_id`

Join scan-level ground truth to exports by `tree_id`, `scan_id`, `fruit_type`,
and timestamp window. Join per-fruit ground truth by `fruit_instance_id` when
available; otherwise use a manually reviewed mapping table.

## Error Metrics

For each scan with valid ground truth:

- count error = `predicted_count - manual_fruit_count`
- count absolute error = `abs(count error)`
- count percentage error = `abs(count error) / manual_fruit_count * 100`
- yield error = `predicted_yield_kg - actual_yield_kg`
- yield absolute error = `abs(yield error)`
- yield percentage error = `abs(yield error) / actual_yield_kg * 100`

Aggregate:

- count MAE = mean count absolute error
- count MAPE = mean count percentage error
- yield MAE = mean yield absolute error
- yield MAPE = mean yield percentage error

Skip MAPE rows where the ground-truth denominator is missing, non-finite, or
less than or equal to zero.

## Repeated Scan Stability

For each `tree_id` and `fruit_type`, group repeated scans by experiment date or
replicate batch.

Recommended statistics:

- predicted count mean
- predicted count standard deviation
- predicted count coefficient of variation
- predicted yield mean
- predicted yield standard deviation
- predicted yield coefficient of variation
- per-source diagnostic counts, especially fused count and zero-yield reasons

Repeated scan stability should be reported separately from accuracy against
manual ground truth.

## Mock Test Coverage

The current mock validation should verify:

- single-scan CSV exists and escapes spreadsheet formula prefixes
- single-scan JSON contains `scanID`, `sourceFilename`, `treeID`, `fruitType`,
  timestamp, GPS, count, yield, diagnostics, `fruitMassEstimates`, and
  `validatedFruits`
- diagnostics include validation-source counts, image diagnostics, canopy
  diagnostics, depth availability, conservative mode, and zero-yield reasons
- `fruitMassEstimates` include geometry, confidence, warning flags, and model
  choice
- per-fruit research CSV includes optional `trueWeightG` and `trueVolumeCm3`
- batch CSV/Excel include scan-level grouping fields and totals

## Real Experiment Field Checklist

Record these fields per tree during real experiments:

- orchard/site ID
- plot/block ID
- row ID
- tree ID
- fruit type/cultivar
- scan ID
- replicate ID
- scan timestamp
- operator/device ID
- weather and lighting notes
- manual fruit count
- harvested yield kg
- calibration records used, if any
- notes for occlusion, missing views, unusual canopy shape, or failed scans

## Current Limitations

- This protocol validates export wiring, not LiDAR scan accuracy.
- It does not prove ARKit depth quality, fruit detection recall, or fusion
  correctness on real trees.
- Current batch export has CSV and Excel XML, but no dedicated batch JSON.
- Per-detection boxes and raw depth-confidence maps are not exported.
- Manual ground-truth alignment remains an external data-management step.
