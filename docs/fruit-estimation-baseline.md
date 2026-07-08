# Fruit Estimation Baseline

This document describes the current professional baseline for per-fruit mass estimation. It is intentionally simple and local: no new detection model, point-cloud completion, alpha shape, NeRF, or third-party dependency is introduced.

## Pipeline

1. The existing scanner produces LiDAR point-cloud candidates and optional RGB/Vision detections.
2. When a candidate contains its clustered 3D points, `SimpleFruitGeometryEstimator` filters unusable points and measures the x/y/z bounding extents.
3. The estimator computes both a sphere baseline and an ellipsoid baseline:
   - Sphere volume: `4/3 * pi * r^3`, using the equivalent diameter from the three axes.
   - Ellipsoid volume: `4/3 * pi * a * b * c`, using half-lengths for the three axes.
4. A category heuristic selects the displayed baseline:
   - Round fruit such as apple, orange, mandarin, citrus, or tomato use sphere only when the three axes are close.
   - Pear, mango, peach, pomelo, grapefruit, pomegranate, and persimmon prefer ellipsoid.
   - Small fruit categories are flagged as lower reliability on iOS LiDAR.
5. `FruitEstimationQualityScorer` adds `confidenceScore` and `warningFlags` from point count, depth quality ratios, dimensions, and fruit category.
6. Existing whole-tree yield estimation still applies its visible-count and occlusion correction at the tree level. A single-fruit `FruitMassEstimate` does not apply whole-tree `occlusionK`.

## Baseline Limitations

This baseline is not a full fruit reconstruction method. It uses axis-aligned min/max bounds, so partial scans, occlusion, leaves, sparse LiDAR returns, or mixed fruit clusters can overestimate or underestimate dimensions.

Large fruit are generally more suitable for iOS LiDAR because their diameter is large relative to LiDAR depth noise and point spacing. Small fruit such as grape, cherry, blueberry, strawberry, and mulberry have lower reliability and are flagged with `smallFruitLowLiDARReliability`.

The sphere model is retained as a compatibility baseline, especially when only a candidate diameter is available. The ellipsoid model gives a better first-order estimate for elongated or asymmetric fruit, but it still depends on complete enough surface coverage.

## Calibration Needs

Production-quality mass estimation requires real calibration data:

- Actual fruit weight from a scale.
- Actual fruit volume from water displacement or a validated measuring workflow.
- Multiple varieties, growth stages, distances, lighting conditions, and scan angles.
- Error analysis grouped by fruit category, size, depth confidence, and point count.

The current density values come from the app's fruit parameters. They should be calibrated per variety and orchard when possible.

## Research CSV

`ResearchCSVExporter` exports one row per fruit with:

- Dimensions and equivalent diameter.
- Sphere, ellipsoid, and selected volume.
- Density, estimated weight, confidence score, point count, depth ratios, shape model, and warning flags.
- Optional `trueWeightG` and `trueVolumeCm3` columns for ground-truth labels.

The CSV is designed for Excel, Numbers, and pandas. Use it to compute absolute error, percentage error, bias by category, and reliability curves versus `confidenceScore` and `warningFlags`.
