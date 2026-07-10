# ScanYieldEstimationController Production Integration Audit

## Verified Production Path

The production yield path is wired as follows:

`ScanView → ScanCoordinator.runMultiModalYieldEstimate → ScanYieldEstimationController.start → ScanFusionYieldBuilder.build → fusion pipelines → YieldResultComposer`

`ScanCoordinator` instantiates `ScanYieldEstimationController` as `yieldEstimationController` and delegates the estimation request to it. The coordinator supplies only the scan-owned callbacks required at the boundary:

- flush pending detections;
- build a snapshot from current scan state;
- submit the accepted result to HUD state and the UI completion.

## Ownership Audit

`ScanYieldEstimationController` owns request generation, cancellation, stale-result rejection, the detached builder task, calibration lookup, and the `ScanFusionYieldBuilder` invocation.

`ScanCoordinatorWorkflows` no longer contains a separate estimation task, request gate, `Task.detached` builder path, or direct `ScanFusionYieldBuilder.build` call. It retains AR/Renderer-owned state access needed to construct the immutable snapshot and keeps HUD/result submission on the coordinator boundary.

## Test Coverage

`YieldEstimationRequestGateTests` directly exercises the request gate and controller stale-request/cancellation behavior. `ScanFusionYieldBuilderTests` and `FusionValidatorTests` cover the downstream yield and fusion semantics.

There is intentionally no duplicate end-to-end Coordinator integration harness: constructing the production coordinator path requires AR/Renderer lifecycle state that simulator unit tests cannot faithfully provide. The source-level production wiring above is verified by the direct delegation and Xcode target references.

## Guardrails Preserved

This verification made no algorithm changes. `ScanFusionYieldBuilder` remains the production builder, and the existing `.fused`-only reliable-yield rule remains unchanged; `imageOnly` and `cloudOnly` do not become reliable yield through this path.
