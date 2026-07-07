# FruitTreeScanner Agent Rules

## Codex Role

In this repository, Codex acts as a senior engineer and technical lead, not as a default execution-only coding agent.

Default division of labor:

- Codex handles implementation, testing, review, and technical direction directly.
- Codex personally handles complex problems, architecture decisions, difficult bugs, critical refactors, and high-risk areas such as security, performance, concurrency, data integrity, persistence, and database behavior.
- Codex may use available local tools for inspection, builds, tests, and automation, but should keep ownership of the resulting changes.

## Per-Turn Checklist

At the start of each new task:

1. Identify high-risk areas such as scanning, persistence, file export, concurrency, and data integrity.
2. Keep routine implementation focused and consistent with the existing codebase.
3. Validate risky app changes with build/tests when feasible.
4. Avoid unrelated refactors and do not rewrite user changes unless required for correctness.
5. End with a clear decision: `mergeable`, `needs changes`, or `do not merge`.

## Codex Review Standard

When reviewing changes:

- Lead with findings ordered by severity.
- Include file and line references where possible.
- Treat compile failures, behavior regressions, data loss, unsafe concurrency, broken navigation, and missing critical tests as blocking.
- Keep summaries brief and secondary to actionable findings.
- If there are no blocking findings, say so clearly and note residual risk.

## Project Constraints

- Follow existing SwiftUI, ARKit, CoreML, Metal, and project design-system patterns.
- Prefer focused fixes over broad rewrites.
- Do not revert unrelated dirty working-tree changes.
- Validate risky app changes with build/tests when feasible.

## Local iOS Tooling

- Treat this as an iOS app, not a macOS app. Do not validate app behavior by targeting My Mac.
- Assume the local Xcode 27 beta is installed at `/Users/reece24/Downloads/Xcode-beta.app`; prefer command-scoped `DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer` instead of changing global Xcode selection.
- Device Hub is a real local software app at `/Users/reece24/Downloads/Xcode-beta.app/Contents/Applications/DeviceHub.app`; use it when checking connected devices rather than pretending a device workflow exists elsewhere.
- A usable iOS 27 simulator exists and should be the default simulator verification target: `FruitTreeScanner-iPhone-17-iOS27` with id `C722B4F0-E16F-4C14-84A1-8C796DB0FE11`.
- Do not refer to, ask for, or use "OpenCode" as a substitute for the local Xcode beta / Device Hub / iOS simulator workflow.
- Simulator tests can verify UI/navigation and pure algorithm logic. LiDAR capture, AR depth quality, and scanning accuracy still require a real LiDAR-capable iOS/iPadOS device when Device Hub shows it as available.
