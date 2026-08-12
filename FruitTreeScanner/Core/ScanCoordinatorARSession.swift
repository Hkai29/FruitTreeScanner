import ARKit
import UIKit

// MARK: - ARSessionDelegate
extension ScanCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard acceptsDelegateCallback(from: session) else { return }
        // Read tracking quality before any evidence path. This also covers a
        // missed state-change callback by reconciling every delivered frame.
        handleCameraTrackingState(
            frame.camera.trackingState,
            originatingFrom: session
        )
        // 非采集状态只允许空闲页更新设备状态，禁止继续形成可靠证据。
        let lifecycleState = lifecycleSnapshot().state
        if lifecycleState == .recording {
            // Keep tracking-quality diagnostics alive while point and image
            // evidence are temporarily suspended.
            publishQualitySampleIfNeeded(frame)
            publishTrackingGuidanceIfSuspended(frame, session: session)
        }
        guard acceptsReliableEvidence() || lifecycleState == .idle else { return }
        publishDepthStatusIfNeeded(frame)
        enqueueDetectionFrameIfRecording(frame)
        publishCameraResolutionIfNeeded(frame, session: session)
        updateCameraSpeedAndGuidance(frame, session: session)
    }

    private func publishDepthStatusIfNeeded(_ frame: ARFrame) {
        guard requestedSceneDepth else { return }
        let hasDepthFrame = frame.smoothedSceneDepth != nil || frame.sceneDepth != nil
        publishDepthRuntimeStatus(hasDepthFrame ? .activeDepth : .waitingForDepth)
    }

    private func enqueueDetectionFrameIfRecording(_ frame: ARFrame) {
        guard renderer?.isRecording == true, acceptsReliableEvidence() else { return }
        let imageSize = CGSize(
            width: CGFloat(frame.camera.imageResolution.width),
            height: CGFloat(frame.camera.imageResolution.height)
        )
        // RGB、位姿和同帧深度必须一起入队，保证后续 2D→3D 投影对齐。
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        imageDetector.enqueueFrame(
            frame.capturedImage,
            timestamp: frame.timestamp,
            cameraTransform: frame.camera.transform,
            cameraIntrinsics: frame.camera.intrinsics,
            imageSize: imageSize,
            depthMap: depthData?.depthMap,
            depthConfidenceMap: depthData?.confidenceMap
        )
    }

    private func publishCameraResolutionIfNeeded(
        _ frame: ARFrame,
        session: ARSession
    ) {
        guard !hasPublishedCameraResolution else { return }
        hasPublishedCameraResolution = true
        let res = frame.camera.imageResolution
        let display = "\(Int(res.width))x\(Int(res.height))"
        DispatchQueue.main.async { [weak self] in
            guard let self, self.acceptsDelegateCallback(from: session) else { return }
            self.settings.currentCameraResolutionDisplay = display
        }
    }

    private func publishQualitySampleIfNeeded(_ frame: ARFrame) {
        // 质量诊断限频发布，避免 ARSession 回调把主线程更新压满。
        let now = CACurrentMediaTime()
        guard now - lastQualitySampleTime >= qualitySampleInterval else { return }
        lastQualitySampleTime = now
        onQualitySampleUpdate?(ScanQualitySampler.makeSample(from: frame))
    }

    private func publishTrackingGuidanceIfSuspended(
        _ frame: ARFrame,
        session: ARSession
    ) {
        guard !acceptsReliableEvidence() else { return }
        let hint = ScanGuidanceHelper.trackingHint(
            for: frame.camera.trackingState,
            lightIntensity: frame.lightEstimate?.ambientIntensity
        ) ?? .none
        DispatchQueue.main.async { [weak self] in
            guard let self, self.acceptsDelegateCallback(from: session) else { return }
            self.hudState?.update(guidanceHint: hint)
        }
    }

    private func updateCameraSpeedAndGuidance(
        _ frame: ARFrame,
        session: ARSession
    ) {
        guard renderer?.isRecording == true, acceptsReliableEvidence() else {
            lastCameraPosition = nil
            return
        }
        let now = CACurrentMediaTime()
        let pos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )

        // 指数平滑抑制单帧位姿抖动，提示使用稳定速度绕树采集。
        if let lastPos = lastCameraPosition, now - lastCameraSpeedTime > 0.05 {
            let dt = Float(now - lastCameraSpeedTime)
            let instantSpeed = simd_distance(pos, lastPos) / dt
            smoothedCameraSpeed = smoothedCameraSpeed * 0.7 + instantSpeed * 0.3
            lastCameraPosition = pos
            lastCameraSpeedTime = now
        } else if lastCameraPosition == nil {
            lastCameraPosition = pos
            lastCameraSpeedTime = now
        }

        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        let medianDepth: Float = depthData.flatMap { ScanGuidanceHelper.sampleMedianDepth($0.depthMap) } ?? 0

        let hint = ScanGuidanceHelper.evaluate(
            speed: smoothedCameraSpeed,
            medianDepth: medianDepth,
            trackingState: frame.camera.trackingState,
            lightIntensity: frame.lightEstimate?.ambientIntensity,
            captureDepthQuality: renderer?.captureDiagnosticsPublic.latestDepthQuality
        )

        DispatchQueue.main.async { [weak self] in
            guard let self, self.acceptsDelegateCallback(from: session) else { return }
            self.hudState?.update(
                cameraSpeed: self.smoothedCameraSpeed,
                medianDepth: medianDepth,
                guidanceHint: hint
            )
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard acceptsDelegateCallback(from: session) else { return }
        handleCameraTrackingState(
            camera.trackingState,
            originatingFrom: session
        )
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard acceptsDelegateCallback(from: session) else { return }
        // 先同步关闭证据门，再异步更新界面状态，避免中断竞态。
        invalidateReliableEvidenceImmediately()
        clearCameraTrackingSuspension()
        Task { @MainActor [weak self] in
            guard let self, self.acceptsDelegateCallback(from: session) else { return }
            self.handleSystemInterruption(.arSessionInterrupted)
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard acceptsDelegateCallback(from: session) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.acceptsDelegateCallback(from: session) else { return }
            self.handleSessionInterruptionEnded()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard acceptsDelegateCallback(from: session) else { return }
        invalidateReliableEvidenceImmediately()
        clearCameraTrackingSuspension()
        Task { @MainActor [weak self] in
            guard let self, self.acceptsDelegateCallback(from: session) else { return }
            self.handleSessionFailure(error)
        }
    }
}
