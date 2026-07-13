// RendererStateAccess.swift
// Recording state and lightweight public accessors for Renderer.

import ARKit
import Foundation
import UIKit

extension Renderer {
    public func resumeRecordingPreservingPointCloud() {
        shouldResetPointCloudOnRecordingStart = false
        isRecording = true
    }

    func resetPointCloudCapture() {
        scannedRegions.removeAll()
        captureDiagnosticsLock.lock()
        captureDiagnostics = RendererCaptureDiagnostics()
        captureDiagnosticsLock.unlock()
        do {
            pointBufferLock.lock()
            defer { pointBufferLock.unlock() }
            currentPointIndex = 0
            currentPointCount = 0
        }
        coverageVoxels.removeAll()
        scanProgress.reset()
    }

    func drawRectResized(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
        updateOrientation()
        rgbUniforms.viewRatio = Float(size.width / max(size.height, 1))
    }

    // MARK: - 当前点数（供 UI 显示）
    var currentPointCountPublic: Int {
        pointBufferSnapshot().count
    }

    var captureDiagnosticsPublic: RendererCaptureDiagnostics {
        captureDiagnosticsLock.lock()
        defer { captureDiagnosticsLock.unlock() }
        return captureDiagnostics
    }

    func recordCaptureDecision(_ decision: RendererCaptureFrameDecision) {
        captureDiagnosticsLock.lock()
        captureDiagnostics.record(decision)
        captureDiagnosticsLock.unlock()
    }

    func pointBufferSnapshot() -> (count: Int, index: Int) {
        pointBufferLock.lock()
        defer { pointBufferLock.unlock() }
        return (currentPointCount, currentPointIndex)
    }

    /// Wait until every submitted render command buffer has completed. Call
    /// after recording is stopped and before CPU-side export reads the shared
    /// particle buffer, otherwise the last in-flight GPU write can race the
    /// snapshot.
    @discardableResult
    func waitForPointCloudWritesToComplete(timeout: TimeInterval = 5) -> Bool {
        let deadline = DispatchTime.now() + .milliseconds(Int(timeout * 1_000))
        var acquiredPermits = 0

        for _ in 0..<maxInFlightBuffers {
            guard inFlightSemaphore.wait(timeout: deadline) == .success else {
                for _ in 0..<acquiredPermits {
                    inFlightSemaphore.signal()
                }
                return false
            }
            acquiredPermits += 1
        }

        for _ in 0..<acquiredPermits {
            inFlightSemaphore.signal()
        }
        return true
    }

    var scannedRegionCountPublic: Int { scannedRegions.count }
    var coverageVoxelCount: Int { coverageVoxels.count }
    var coverageAngleRatioPublic: Float {
        RendererDepthCoverage.estimateHorizontalAngleCoverage(from: coverageVoxels)
    }
    var coverageAngleUniformityPublic: Float {
        RendererDepthCoverage.estimateHorizontalAngleUniformity(from: coverageVoxels)
    }
    var coverageOppositeSideRatioPublic: Float {
        RendererDepthCoverage.estimateOppositeSideCoverage(from: scannedRegions)
    }
    var coverageVerticalRatioPublic: Float {
        RendererDepthCoverage.estimateVerticalCoverage(from: coverageVoxels)
    }
    var voxelDiscoveryTrendPublic: VoxelDiscoveryTrend { scanProgress.voxelDiscoveryTrend }
    var voxelDiscoveryRatePublic: Float { scanProgress.voxelDiscoveryRate }

    struct CameraMatrices {
        let projectionMatrix: simd_float4x4
        let viewMatrix: simd_float4x4
        let viewportSize: CGSize
    }

    func getCameraMatrices() -> CameraMatrices? {
        guard let frame = session.currentFrame else { return nil }
        updateOrientation()
        let projMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        return CameraMatrices(projectionMatrix: projMatrix, viewMatrix: viewMatrix, viewportSize: viewportSize)
    }
}
