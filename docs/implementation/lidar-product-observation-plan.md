# LiDAR Product Observation Plan

## Context

This note captures the mature LiDAR app patterns observed on the real device workflow and maps them to FruitTreeScanner's current architecture. The goal is not to copy a generic 3D scanner. The useful parts are the scanning confidence loop, post-capture decision flow, and dense scan history actions, adapted to orchard yield estimation.

## Observed Strengths

- The scan page keeps the camera/point-cloud preview primary and uses compact controls around the edge.
- Scan education is contextual: short tips explain movement speed, route planning, target size, and when to read more.
- Scan modes are explained by use case, not implementation detail.
- During capture, quality feedback is immediate and actionable, with coverage and pace hints instead of long instructions.
- Stopping capture does not force a heavy final step immediately. The app presents a rough preview, then lets the user process now or later.
- The result/detail view supports quick inspection, measurement, display toggles, sharing, and extend-scan actions.
- History is dense and operational: preview, share, duplicate/export/delete, metadata, and status are close to each record.

## FruitTreeScanner Mapping

- "LiDAR mode" maps to FruitTreeScanner's full-tree fruit scan: trunk, canopy, visible fruit, and crown volume.
- "Point cloud mode" maps to the existing PLY preview and measurement tools.
- "Process scan" maps to export plus multi-modal yield estimation.
- "Process later" maps to keeping the raw PLY in scan history and allowing review/import/export later.
- "Extend scan" maps to scanning the same tree again or continuing with the next tree after reviewing coverage and confidence.
- Generic mesh display settings are lower priority than orchard-specific metrics: fruit count, yield, crown volume, confidence, GPS/plot/status tags.

## Implemented In This Pass

- Replaced the thin scan skip prompt with a fruit-tree LiDAR guide that teaches slow orbiting, full-tree-first capture, blind-zone fill, and pre-analysis measurement.
- Added a post-capture rough preview panel that appears after recording stops and before final estimation, showing coverage, point count, duration, and whether to finish or keep scanning.
- Reworded real-time scan hints around tree-specific actions: keep the whole tree outline, fill canopy backside, prioritize trunk and fruit-dense regions.
- Reworded coverage completion from generic sample counts to spatial/tree-canopy sampling language.
- Confirmed the real device target name is `pro中的pro`; CoreDevice currently reports it as physical but unavailable.

## Next Product Steps

1. Add a true post-scan detail screen for raw PLY files before yield estimation, with preview, measure, analyze now, analyze later, and rescan same tree.
2. Add scan-mode education for orchard workflows: full tree, canopy point cloud, trunk/detail, row sweep, and fruit close-up.
3. Add history row actions for rescan same tree, analyze pending PLY, and mark review status.
4. Add display options to the point cloud viewer: natural color, height color, density/quality, and top-down orchard view.
5. Add a safe rename/tagging flow that pre-fills the current tree ID and never starts from an empty destructive state.
6. Add a verification checklist for real-device capture on `pro中的pro`: LiDAR available, camera authorized, point count grows, coverage reaches 60% and 85%, PLY exports, yield estimate persists, history preview opens.

## Verification Notes

- `xcodebuild` could not deploy to the earlier raw device id because the destination was not visible.
- `DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer xcrun devicectl list devices` finds `pro中的pro` as a physical iPad Pro with CoreDevice identifier `C70B127E-C984-52BC-958A-35278FDA8D0C`, but its state is currently `unavailable`.
- Generic iOS build with signing disabled reaches the Metal shader phase, then fails because the Xcode beta installation is missing the Metal Toolchain. Install it with Xcode's component manager or `xcodebuild -downloadComponent MetalToolchain` before using build output as final verification.
