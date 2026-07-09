# Point Cloud Sampling Quality Audit

Task: Point cloud sampling quality audit

Date: 2026-07-09

Scope: This audit documents the current point-cloud sampling path after the PLY
ASCII parser memory work. It intentionally does not change scan fusion, yield
reliability rules, ImageDetector behavior, UI behavior, or point-count limits.

## Current Pipeline

### Capture and accumulation

- `Renderer` owns the active Metal point buffer and caps raw retained points with
  `maxPoints`.
- `Renderer.applyScanQualitySettings()` applies `RendererScanSettings` values to
  `maxPoints`, depth range, RGB radius, confidence threshold, depth-edge
  threshold, and `snapshotVoxelSize`.
- `RendererFrameRendering.renderFrame(...)` accumulates point-cloud particles
  only when the AR frame has usable depth data and the renderer decides the
  current frame should contribute points.
- `Shaders.metal` unprojects depth/RGB into `ParticleUniforms` and stores a
  per-particle `confidence`. Invalid depth, depth-edge discontinuities, and
  unusable samples are represented by zero confidence.

### Live snapshot path

- `RendererPointCloudAccess.updateSnapshot()` periodically creates a live
  snapshot while recording.
- The live snapshot uses `snapshotVoxelSize` and
  `Renderer.liveSnapshotInputSampleLimit` (`240_000`) before converting samples
  to `[ColoredPoint]`.
- The update interval is count-aware:
  - fewer than `150_000` points: `0.9` seconds
  - `150_000..<500_000` points: `1.5` seconds
  - `500_000` or more points: `2.5` seconds
- The live snapshot is intended for responsive display/export state, not final
  fusion reliability by itself.

### Analysis path

- `ScanCoordinator.extractColoredPoints()` calls
  `Renderer.makeAnalysisPoints()`.
- `Renderer.makeAnalysisPoints()` uses:
  - `Renderer.analysisVoxelSizeMeters` (`0.005` meters)
  - `Renderer.analysisInputSampleLimit` (`120_000`)
  - `RendererPointCloudSnapshot.makeFilteredSamples(...)`
  - `PointCloudDenoiser.statisticalOutlierRemoval(...)`
- The analysis snapshot is cached by a signature built from point count, current
  index, voxel size, scan settings, and render size.
- The returned `[ColoredPoint]` has already lost the original per-particle
  confidence value because `RendererPointCloudSnapshot.makeColoredPoints(...)`
  maps `RendererPointSample` to `ColoredPoint`.

### Filtering and sampling inside the renderer

`RendererPointCloudSnapshot.makeFilteredSamples(...)` is the central CPU sampler
used by the current analysis and live snapshot paths.

Current behavior:

1. Compute a global fixed stride:
   `ceil(currentPointCount / inputSampleLimit)` when an input limit is supplied.
2. Walk the renderer ring buffer by that stride.
3. Reject samples that fail exportability checks:
   - confidence below `confidenceThreshold`
   - non-finite position or color
   - zero position
4. Quantize accepted positions to a voxel key.
5. Keep one sample per voxel, preferring the sample with higher confidence among
   the visited samples.
6. Return `Array(bestSamplesByVoxel.values)`.

This means the path is voxel-aware and confidence-aware after the global stride
has decided which raw points are visited. It is not confidence-weighted when
choosing the stride, and it does not reserve points near fruit detections.

### Denoise, cluster, and fusion path

- `ScanFusionYieldBuilder.build(...)` receives the sampled `[ColoredPoint]`.
- `CanopyGeometryEstimator.estimate(points:)` uses those sampled points for
  canopy geometry and bounded projection work.
- `PointCloudCandidatePipeline.run(...)` optionally applies the configured color
  filter, then performs another statistical outlier removal pass before
  clustering.
- `PointCloudCluster.processInMemory(...)` receives separate position and color
  arrays, applies its own noise filter, builds KDTree-backed DBSCAN structures,
  and emits cloud-derived `FruitCandidate` values.
- `DetectionDepthCandidatePipeline.run(...)` builds ROI-depth candidates from
  saved 2D detections, their depth maps, and depth confidence maps. This path
  samples inside the detection bounding box rather than from the accumulated
  renderer point cloud.
- `CandidateCombiner.combine(...)` merges point-cloud and detection-depth
  candidates and caps retained candidate point samples through
  `FruitScanExperimentConfig.default.candidateMerge.maxPointSamples`.
- `FusionEvidencePipeline.run(...)` calls `FusionValidator.validate(...)`,
  deduplicates fused evidence, and keeps only `.fused` fruits for reliable yield
  composition.

## Current Limits

### Renderer and capture limits

- `Renderer.maxPoints`: initialized to `1_000_000`, then set from
  `RendererScanSettings.maxPoints`.
- `SettingsStore.maxPointCount`: defaults to `1_000_000` and is clamped to
  `100_000...3_000_000`.
- `SettingsStore.confidenceThreshold`: defaults to `1` and is clamped to `0...2`.
- `SettingsStore.scanPrecision`: defaults to `0.01` meters and is clamped to
  `0.001...0.05`.

### Analysis and snapshot limits

- `Renderer.analysisInputSampleLimit`: `120_000`.
  - Defined in `FruitTreeScanner/Core/Renderer.swift`.
  - Used by `Renderer.makeAnalysisPoints()`.
  - Also used by point-cloud export in `Renderer.savePointCloud(...)`.
- `Renderer.liveSnapshotInputSampleLimit`: `240_000`.
  - Defined in `FruitTreeScanner/Core/Renderer.swift`.
  - Used by `RendererPointCloudAccess.updateSnapshot()`.
- `Renderer.analysisVoxelSizeMeters`: `0.005` meters.
  - Defined in `FruitTreeScanner/Core/Renderer.swift`.
  - Used by `Renderer.makeAnalysisPoints()` and its snapshot cache signature.
- `Renderer.snapshotVoxelSize`: initialized to `0.015` meters.
  - Defined in `FruitTreeScanner/Core/Renderer.swift`.
  - Updated by `Renderer.applyScanQualitySettings()` from
    `RendererScanSettings.snapshotVoxelSize`.
  - Used by live snapshot and point-cloud export paths.

### Quality preset and voxel-size settings

- `RendererScanSettings.make(store:deviceProfile:)` derives scan settings from
  the user settings store and the device profile.
- `RendererScanSettings.exportVoxelSize(...)` converts `scanPrecision` and
  quality preset into `snapshotVoxelSize`:
  - high quality: `max(scanPrecision * 0.7, 0.001)`
  - low quality: `min(scanPrecision * 1.5, 0.06)`
  - default: clamped `scanPrecision`
- The current default user-facing quality preset is high, so the default
  `scanPrecision` of `0.01` meters becomes a `snapshotVoxelSize` of about
  `0.007` meters.

### Downstream bounded work

- `PointCloudDenoiser` builds a position array, KDTree, mean-distance array, and
  filtered output array.
- `PointCloudCluster` builds position/color arrays, `ClusterPoint` values,
  another KDTree, local-density data, DBSCAN labels, and cluster-specific arrays.
- `CanopyGeometryEstimator` further bounds nearest-neighbor sampling and
  projection-cell work after the renderer has already applied the analysis
  sample limit.
- PLY display/import behavior remains separately bounded by its own display
  limit and is not changed by this audit.

## Sampling Strategy Classification

### Voxel-aware

Yes, but after global stride sampling.

The renderer quantizes visited points to voxels and keeps one sample per voxel.
Analysis uses a fixed `0.005` meter voxel size. Live snapshot and export use the
settings-derived `snapshotVoxelSize`.

Important nuance: if the raw point count exceeds the input sample limit, the
fixed stride decides which points are visited before voxel selection. A voxel
can only retain the best-confidence point among visited samples, not among all
raw samples.

### Confidence-aware

Partly.

The current path rejects points below `confidenceThreshold`, and for multiple
visited points in the same voxel it keeps the higher-confidence sample. However,
the global stride itself is not confidence-weighted. A high-confidence point can
be skipped before the voxel/confidence comparison ever sees it.

After conversion to `ColoredPoint`, confidence is no longer carried into
downstream point-cloud denoising, clustering, or candidate scoring.

### ROI-aware

Not for the accumulated point-cloud sampling path.

The point-cloud sampler does not know about 2D detection boxes, projected fruit
ROIs, candidate neighborhoods, or tree/fruit semantic regions. It samples the
global renderer buffer.

There is ROI-aware depth work in the separate detection-depth path:
`DetectionDepthCandidatePipeline` and `FusionValidatorProjection` sample inside
2D detection boxes using saved depth maps and confidence maps. That path helps
fusion evidence, but it does not cause the renderer analysis sampler to retain
more accumulated point-cloud samples near those ROIs.

### Candidate-aware

No for pre-fusion sampling.

Candidate construction, matching, and frustum evidence happen after the global
point-cloud sample has already been produced and denoised. `FusionValidator`
uses candidate points when matching detections, but there is no earlier
candidate-aware retention strategy.

### Depth-confidence-aware

Partly.

The renderer capture and exportability checks use the AR confidence value stored
with each particle. The ROI-depth path also uses `DepthConfidenceSampler` and the
configured minimum reliable confidence when projecting detections.

The accumulated point-cloud analysis path is not depth-confidence weighted after
conversion to `[ColoredPoint]`, because `ColoredPoint` does not carry the
particle confidence forward.

### Global stride classification

The current analysis sample is best described as:

- global fixed-stride subsampling before voxel selection
- exportability filtering by confidence and validity
- voxel deduplication among visited samples
- per-voxel highest-confidence retention among visited samples
- no ROI-aware or fruit-candidate-aware quota

It is not purely random. It is not fully uniform in 3D space either, because
voxel deduplication happens only after the fixed ring-buffer stride.

## Risk Analysis

### Benefits of the 120k analysis limit

- Bounds memory before expensive CPU work.
- Keeps KDTree construction, statistical outlier removal, DBSCAN, and canopy
  analysis in a mobile-feasible range.
- Reduces the chance that dense background/canopy captures dominate CPU and
  memory during final yield estimation.
- Keeps latency more predictable for on-device workflows.
- Reduces the number of large array copies created downstream.

### Main risk of the current limit

The `120_000` limit can drop fruit-nearby evidence because it is applied as a
global fixed stride before voxel deduplication and before any detection-aware
logic.

Risk is highest when:

- fruit points are a small fraction of the total accumulated cloud
- fruit surface points appear only during a short camera pose interval
- a detection box covers a small object against dense canopy or trunk geometry
- fruit depth evidence is sparse, noisy, or partially occluded
- the scan contains many high-confidence background points and relatively few
  high-confidence fruit-surface points
- ring-buffer order and stride alias with a brief fruit-observation segment
- fruit evidence is near depth edges, where invalidation and confidence
  thresholding remove many neighboring points

In these cases, simply having a voxel-aware sampler does not guarantee local
fruit evidence survives, because the sampler may never visit enough points from
the relevant local region.

### Does the current sample prioritize high-confidence points?

Only within the visited set.

The per-voxel replacement logic prefers higher confidence among visited samples,
and the confidence threshold removes low-confidence samples. But there is no
global high-confidence reservoir, no confidence-weighted sampling probability,
and no dedicated preservation of high-confidence samples near fruit candidates.

### Does the current sample prioritize 2D detections or fruit candidates?

No.

2D detection boxes and fruit candidates affect the detection-depth and fusion
stages, not the accumulated point-cloud sampler. The sampler cannot currently
reserve points inside projected detection frustums, detection-depth local
neighborhoods, or candidate-local voxels.

### When the current limit can improve stability

The limit can improve stability when:

- scans contain excessive background/canopy density
- low-value redundant geometry would otherwise dominate KDTree and DBSCAN work
- memory pressure would cause latency spikes or app instability
- denoising and clustering would become too expensive relative to the yield task
- voxel deduplication removes redundant local samples while preserving a
  representative point per visited voxel

The current cap is therefore reasonable as a conservative mobile performance
guard. The main concern is not that the cap exists; it is that the cap is not
ROI-aware or confidence-weighted before global thinning.

### Copies and filters before fusion

The current analysis/fusion path performs these materialization steps:

1. Metal ring buffer stores raw particle positions, colors, and confidence.
2. CPU sampler visits the ring buffer by stride.
3. Exportability checks drop invalid or low-confidence samples.
4. A voxel dictionary stores one `RendererPointSample` per voxel.
5. `Array(bestSamplesByVoxel.values)` materializes renderer samples.
6. `PointCloudDenoiser` maps samples to positions, builds a KDTree, stores mean
   distances, and materializes filtered samples.
7. Renderer maps filtered samples to `[ColoredPoint]`, dropping confidence.
8. `PointCloudCandidatePipeline` may copy points through color filtering.
9. Pipeline denoising maps colored points to positions, builds another KDTree,
   stores mean distances, and materializes another filtered point array.
10. Clustering maps points to separate position and color arrays.
11. `PointCloudCluster` zips positions/colors into cluster points, applies a
    noise filter with another KDTree, then builds DBSCAN data structures.
12. Cluster analysis maps cluster points back into candidate position arrays.
13. Candidate merge caps retained candidate point samples.
14. `FusionValidator` projects candidate centers and candidate sample points
    into detection frustums for matching and fused evidence decisions.

This sequence explains why the analysis input limit is valuable: downstream
algorithms make several bounded but still significant arrays and spatial
indices.

## Recommendation

### Keep the current limits for now

The current `120_000` analysis input limit is a reasonable conservative bound
for mobile CPU and memory, especially because denoising and clustering create
multiple derived arrays. This audit should not increase the limit, remove the
limit, or weaken fusion/yield reliability rules.

### Prefer smarter retention over simply raising point count

If future real-device validation shows missed fruit evidence near detections,
the next improvement should be ROI-aware and confidence-aware sampling rather
than a simple increase to `analysisInputSampleLimit`.

Recommended future directions:

- Preserve the global cap, but split it into bounded buckets.
- Reserve a small quota for high-confidence points.
- Reserve a small quota for points near projected detection ROIs or local
  detection-depth candidate neighborhoods.
- Keep voxel deduplication in every bucket.
- Keep `.fused` as the only reliable yield source.
- Keep image-only and cloud-only evidence out of reliable yield estimation.

### Low-risk future changes

- Add sampler diagnostics: raw count, stride, visited count, confidence rejects,
  voxel count, final analysis count, and denoised count.
- Add tests for deterministic sampling invariants and per-voxel
  highest-confidence replacement.
- Preserve confidence in an internal sample type longer, without changing public
  yield semantics.
- Add optional audit-only counters for how many analysis samples project into
  saved detection boxes.

### Changes not recommended in this phase

- Increasing `analysisInputSampleLimit` without real-device evidence.
- Removing the analysis input cap.
- Making cloud-only or image-only candidates reliable.
- Relaxing low-confidence depth or confidence-map fusion rules.
- Rewriting `FusionValidator`, `ScanFusionYieldBuilder`, or yield composition as
  part of sampling work.
- Replacing the sampler and clustering stack in one large refactor.

## Next Implementation Plan

### Step 1: Add observability without behavior changes

- Add a lightweight sampler statistics structure near the renderer sampling
  path.
- Record raw count, stride, visited count, confidence rejects, voxel count,
  final count, and denoise count.
- Keep all existing point-count limits and fusion behavior unchanged.

Suggested tests:

- Sampling stats report expected counts for a small synthetic cloud.
- Stats collection does not change returned samples.
- Malformed or invalid sample data still fails safely.

### Step 2: Extract a tested sampler helper

- Move the current stride, exportability, voxel-key, and per-voxel confidence
  replacement behavior into a small internal helper.
- Keep the public renderer entry points unchanged.
- Keep the returned samples equivalent to the current implementation.

Suggested tests:

- Below-limit input visits every sample.
- Above-limit input uses the expected stride.
- Samples below confidence threshold are dropped.
- Highest-confidence sample wins within a voxel.
- Finite/nonzero validity checks are preserved.

### Step 3: Add bounded confidence-aware retention

- Keep the same global analysis budget.
- Reserve a small deterministic quota for high-confidence samples that would
  otherwise be skipped by stride sampling.
- Deduplicate the reserved samples by voxel before merging with the global set.

Suggested tests:

- High-confidence sparse samples survive in a dense low-confidence cloud.
- Total returned samples remain bounded.
- Existing baseline sample output remains stable when no reserved samples exist.

### Step 4: Add ROI-aware audit mode before production behavior

- Project sampled or raw candidate points into saved detection boxes only for
  diagnostics.
- Measure how many analysis samples fall inside each detection ROI.
- Use real-device scans to determine whether fruit ROI retention is actually a
  bottleneck.

Suggested tests:

- ROI counters handle missing depth, missing intrinsics, and empty detections.
- ROI counters do not affect fusion results.
- Stable detections with valid camera metadata produce deterministic ROI counts.

### Step 5: Add fruit-candidate local high-density retention if justified

- Keep the global cap.
- Reserve a bounded quota for points near stable detection-depth candidate
  neighborhoods or projected detection frustums.
- Keep ROI-retained points subject to confidence and voxel checks.
- Keep downstream fusion validation unchanged: retained points may help produce
  candidates, but they must not bypass `.fused` reliability rules.

Suggested tests:

- Synthetic dense background plus sparse ROI fruit points retains ROI-local
  evidence under the fixed total cap.
- ROI-retained cloud candidates still require validator fusion before reliable
  yield.
- `imageOnly` and `cloudOnly` candidates remain excluded from reliable yield.
- Low-confidence depth evidence still cannot upgrade a candidate to `.fused`.

## Conclusion

The current sampling strategy is a conservative, bounded global sampler with
voxel deduplication and limited confidence awareness. It is appropriate as a
mobile stability guard, but it is not yet optimized for preserving sparse fruit
evidence near detections. Future reliability work should keep the current caps
and reliability rules, then add measured ROI-aware and confidence-aware
retention in small, testable steps.
