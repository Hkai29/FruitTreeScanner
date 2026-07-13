import ARKit
import UIKit

// MARK: - ARSessionDelegate
extension ScanCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let lifecycleState = lifecycleSnapshot().state
        guard acceptsReliableEvidence() || lifecycleState == .idle else { return }
        publishDepthStatusIfNeeded(frame)
        enqueueDetectionFrameIfRecording(frame)
        publishCameraResolutionIfNeeded(frame)
        publishQualitySampleIfNeeded(frame)
        updateCameraSpeedAndGuidance(frame)
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

    private func publishCameraResolutionIfNeeded(_ frame: ARFrame) {
        guard !hasPublishedCameraResolution else { return }
        hasPublishedCameraResolution = true
        let res = frame.camera.imageResolution
        let display = "\(Int(res.width))x\(Int(res.height))"
        DispatchQueue.main.async {
            self.settings.currentCameraResolutionDisplay = display
        }
    }

    private func publishQualitySampleIfNeeded(_ frame: ARFrame) {
        guard acceptsReliableEvidence() else { return }
        let now = CACurrentMediaTime()
        guard now - lastQualitySampleTime >= qualitySampleInterval else { return }
        lastQualitySampleTime = now
        onQualitySampleUpdate?(ScanQualitySampler.makeSample(from: frame))
    }

    private func updateCameraSpeedAndGuidance(_ frame: ARFrame) {
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
            guard let self, !self.isTornDown else { return }
            self.hudState?.update(
                cameraSpeed: self.smoothedCameraSpeed,
                medianDepth: medianDepth,
                guidanceHint: hint
            )
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        invalidateReliableEvidenceImmediately()
        Task { @MainActor [weak self] in
            self?.handleSystemInterruption(.arSessionInterrupted)
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.handleSessionInterruptionEnded()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        invalidateReliableEvidenceImmediately()
        Task { @MainActor [weak self] in
            self?.handleSessionFailure(error)
        }
    }
}
