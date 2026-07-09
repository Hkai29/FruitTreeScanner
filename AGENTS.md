# FruitTreeScanner Agent Rules

## Project Identity

FruitTreeScanner is an iOS/iPadOS LiDAR fruit-tree scanning and yield-estimation system.

It is not a generic photo-recognition app. The product workflow depends on ARKit camera pose, LiDAR depth, Metal point-cloud capture, CoreML/Vision fruit detection, 2D-to-3D projection, point-cloud evidence, fusion validation, diagnostics, persistence, and export.

Every change must preserve the reliability of the scan-to-yield pipeline.

## Agent Role

In this repository, Codex acts as a senior iOS, ARKit, CoreML, Metal, and point-cloud engineer.

Codex must:

- Inspect the current code before editing.
- Identify high-risk areas before changing scanning, fusion, persistence, export, memory, concurrency, or data integrity behavior.
- Keep implementation focused and consistent with the existing codebase.
- Prefer small, reviewable changes over broad rewrites.
- Avoid unrelated refactors and formatting churn.
- Never revert unrelated dirty working-tree changes unless explicitly requested.
- Validate risky app changes with targeted tests and, when feasible, full iOS simulator tests.
- End with a clear decision: `mergeable`, `needs changes`, or `do not merge`.

## Current Architecture

The current app architecture is pipeline-based and service-split. Do not rely on older descriptions that treat the project as one or two monolithic algorithm files.

Important current components:

- `Renderer*.swift`: ARKit / Metal point-cloud capture, rendering, depth handling, and scan-frame integration.
- `ImageDetector`: the public facade for image detection.
- `ImageDetector*.swift`: model loading, inference, queueing, YOLO parsing, diagnostics, and helper logic behind the facade.
- `ScanFusionYieldBuilder`: external scan-yield construction entry point and compatibility surface.
- `ScanFusionPipelines`: point-cloud, depth detection, and fusion evidence pipeline orchestration.
- `YieldResultComposer`: construction of `YieldResult`, `FruitCountResult`, confidence summaries, and reliable yield output.
- `ScanFusionDiagnosticsUpdater`: scan, confidence, zero-yield, and debug diagnostics updates.
- `FusionValidator*.swift`: 2D-to-3D projection, matching, decision policy, and fusion validation.
- `DetectionDeduplicator`: duplicate filtering for detected and fused fruit evidence.
- `FruitScanExperimentConfig`: central experiment and threshold configuration.

Keep these responsibilities separated unless the user explicitly requests an architectural change.

## Core Invariants

These invariants are thesis-critical and product-critical. Do not weaken them casually.

- `.fused` is the only reliable source for yield estimation.
- `imageOnly` candidates must not enter reliable yield estimation.
- `cloudOnly` candidates must not enter reliable yield estimation.
- Low-confidence depth evidence must not upgrade a candidate to `.fused`.
- Low-confidence `confidenceMap` evidence must not upgrade a candidate to `.fused`.
- A rejected depth candidate must not be upgraded to `.fused` through fallback logic.
- `zeroYieldReasons` must be preserved.
- Scan diagnostics must be preserved.
- Confidence diagnostics must be preserved.
- Debug state must remain useful for explaining zero yield, low yield, rejected evidence, and degraded scan quality.

If a change intentionally modifies one of these invariants, it must include an explicit rationale and targeted tests proving the new behavior.

## Memory and Performance Rules

FruitTreeScanner handles AR frames, depth maps, point clouds, CoreML inference, SceneKit geometry, exports, and batch workflows. Memory safety matters.

Required rules:

- Do not parse large PLY ASCII files by loading the full body into one giant `String` and splitting with `components`.
- Avoid repeated large point-cloud array copies.
- Avoid converting through multiple large intermediate point representations unless necessary.
- Avoid rebuilding SceneKit geometry when a smaller update is enough.
- Preserve sampling limits.
- Keep KDTree, DBSCAN, and KNN inputs bounded.
- Keep heavy point-cloud, parsing, clustering, and export work off the main thread where feasible.
- Avoid keeping multiple full-size point-cloud buffers alive at the same time.
- Avoid adding generated datasets, DerivedData, simulator output, training runs, or local agent worktrees to the app target.

Prefer:

- Streaming or chunked parsing.
- Early header validation for PLY.
- Bounded sampling and device-aware limits.
- Reusing buffers when practical.
- Focused services with clear ownership.
- Tests around boundary conditions and large-input behavior.

## SwiftUI Rules

- Keep SwiftUI views focused on presentation and user interaction.
- Keep ARKit, Metal, CoreML, point-cloud, and yield algorithms outside SwiftUI view bodies.
- Avoid large monolithic `body` chains.
- Extract complex sections into smaller views or components.
- Avoid heavy work in view initializers, `.body`, `.onAppear`, or the main actor unless required.
- Preserve existing design-system patterns in `Design/` and shared components.
- Avoid UI rewrites unless the request is explicitly about UI redesign.

## Algorithm Rules

- Fusion, deduplication, projection, confidence scoring, scan diagnostics, and yield estimation are high-risk areas.
- Prefer explicit, readable algorithm code over clever compact code.
- Keep thresholds and experiment parameters centralized in `FruitScanExperimentConfig` or related configuration surfaces.
- Do not change thresholds casually.
- When changing thresholds, fallback behavior, fusion policy, confidence handling, or deduplication rules, add or update targeted tests.
- Preserve compatibility for public entry points used by existing tests and app flows.

## Refactoring Rules

- Refactor only when it reduces real complexity, removes meaningful duplication, or matches an established local pattern.
- Do not mix refactors with behavior changes unless required and clearly explained.
- Keep public APIs stable unless migration is explicitly requested.
- Preserve existing behavior before moving code.
- After moving code, run the relevant tests that prove behavior survived the move.

## Testing Rules

Use the local iOS workflow. This is an iOS app, not a macOS app.

Local Xcode beta:

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer
```

Default simulator:

```text
FruitTreeScanner-iPhone-17-iOS27
C722B4F0-E16F-4C14-84A1-8C796DB0FE11
```

For fusion, detection, deduplication, and yield changes, run targeted tests such as:

```sh
DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project FruitTreeScanner.xcodeproj \
  -scheme FruitTreeScanner \
  -destination 'platform=iOS Simulator,id=C722B4F0-E16F-4C14-84A1-8C796DB0FE11' \
  -only-testing:FruitTreeScannerTests/FusionValidatorTests \
  -only-testing:FruitTreeScannerTests/DetectionDeduplicatorTests \
  -only-testing:FruitTreeScannerTests/ScanFusionYieldBuilderTests \
  -only-testing:FruitTreeScannerTests/DetectionDebugStateTests
```

For export, archive, and file-format changes, run the relevant export and parsing tests.

For UI/navigation changes, use the iOS simulator, not My Mac.

For LiDAR capture quality, AR depth quality, and real scan accuracy, simulator tests are not enough. Validate on a LiDAR-capable iOS/iPadOS device when available through Device Hub:

```text
/Users/reece24/Downloads/Xcode-beta.app/Contents/Applications/DeviceHub.app
```

Always run:

```sh
git diff --check
```

If tests cannot be run, state exactly why and describe the remaining risk.

## Review Rules

When asked for a review, use a code-review stance:

- Lead with findings ordered by severity.
- Include file and line references where possible.
- Treat compile failures as blocking.
- Treat behavior regressions as blocking.
- Treat data loss as blocking.
- Treat unsafe concurrency as blocking.
- Treat broken navigation as blocking.
- Treat missing critical tests for changed fusion/yield behavior as blocking.
- Keep summaries brief and secondary to findings.
- If there are no blocking findings, say so clearly and note residual risk.

## Commit Rules

- Keep commits focused.
- Use clear, conventional-style commit messages when practical.
- Do not commit unrelated dirty working-tree changes.
- Do not commit generated build output, DerivedData, simulator state, local agent worktrees, or private local configuration.
- Before committing, inspect:

```sh
git status
git diff --stat
git diff --check
```

- For code changes, run relevant tests before commit when feasible.

## Push and GitHub Rules

- Default behavior: do not push directly to `main`.
- Prefer creating a remote branch and pushing that branch.
- Use branch names that describe the change, for example `docs/update-agent-rules` or `codex/fix-fusion-diagnostics`.
- Push to `main` only when the user explicitly asks for direct main push or when a prior explicit instruction in the same task requires it.
- After pushing, verify the remote branch or commit on GitHub when possible.
- Do not close pull requests, delete branches, change branch protection, or rewrite remote history unless the user explicitly asks.

## Local Tooling Rules

- Treat this as an iOS app, not a macOS app.
- Prefer command-scoped `DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer`.
- Do not change global Xcode selection unless explicitly requested.
- Do not use "OpenCode" as a substitute for the local Xcode beta, Device Hub, or iOS simulator workflow.
- Use `rg` for search when available.
- Use structured parsers/APIs for structured files when practical.
- Use `apply_patch` for manual file edits.

## Final Response Rules

End implementation or review tasks with:

- What changed.
- What was intentionally preserved.
- What validation ran.
- What was pushed, if anything.
- Remaining risks or TODOs.
- Decision: `mergeable`, `needs changes`, or `do not merge`.
