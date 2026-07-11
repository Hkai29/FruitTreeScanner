// ImageDetectorQueue.swift
// Frame sampling and queue management for ImageDetector.

import Foundation
@preconcurrency import CoreVideo
import simd

enum ImageDetectorQueue {
    struct FrameCopyResult {
        let queuedFrame: ImageDetector.QueuedFrame?
        let failedToCopyPixelBuffer: Bool
        let droppedDepthMap: Bool
        let droppedDepthConfidenceMap: Bool
    }

    static func makeQueuedFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize,
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer?,
        pixelBufferCopier: (CVPixelBuffer) -> CVPixelBuffer? = { duplicatePixelBuffer(input: $0) }
    ) -> FrameCopyResult {
        guard let copiedPixelBuffer = pixelBufferCopier(pixelBuffer) else {
            return FrameCopyResult(
                queuedFrame: nil,
                failedToCopyPixelBuffer: true,
                droppedDepthMap: false,
                droppedDepthConfidenceMap: false
            )
        }

        let copiedDepthMap = depthMap.flatMap(pixelBufferCopier)
        let copiedDepthConfidenceMap = depthConfidenceMap.flatMap(pixelBufferCopier)
        let depthConfidenceProvenance: DepthConfidenceProvenance
        if depthConfidenceMap == nil {
            depthConfidenceProvenance = .unavailable
        } else if copiedDepthConfidenceMap == nil {
            depthConfidenceProvenance = .copyFailed
        } else {
            depthConfidenceProvenance = .available
        }
        let queuedFrame = ImageDetector.QueuedFrame(
            pixelBuffer: copiedPixelBuffer,
            depthMap: copiedDepthMap,
            depthConfidenceMap: copiedDepthConfidenceMap,
            depthConfidenceProvenance: depthConfidenceProvenance,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize
        )

        return FrameCopyResult(
            queuedFrame: queuedFrame,
            failedToCopyPixelBuffer: false,
            droppedDepthMap: depthMap != nil && copiedDepthMap == nil,
            droppedDepthConfidenceMap: depthConfidenceMap != nil && copiedDepthConfidenceMap == nil
        )
    }

    static func enrich(
        _ fruits: [DetectedFruit],
        with frame: ImageDetector.QueuedFrame
    ) -> [DetectedFruit] {
        fruits.map { fruit in
            DetectedFruit(
                category: fruit.category,
                boundingBox: fruit.boundingBox,
                confidence: fruit.confidence,
                timestamp: fruit.timestamp,
                cameraTransform: frame.cameraTransform,
                cameraIntrinsics: frame.cameraIntrinsics,
                imageSize: frame.imageSize,
                depthMap: frame.depthMap,
                depthConfidenceMap: frame.depthConfidenceMap,
                depthConfidenceProvenance: frame.depthConfidenceProvenance
            )
        }
    }
}

extension ImageDetector {
    func enqueueFrame(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize,
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer? = nil
    ) {
        let pixelBufferSize = CGSize(
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )

        lock.lock()
        detectionDebugState.markFrameReceived(
            frameSize: imageSize,
            pixelBufferSize: pixelBufferSize,
            threshold: config.minConfidence
        )
        frameCounter += 1

        let detectionInterval = max(config.imageDetectionInterval, 1)
        if frameCounter % detectionInterval != 0 {
            lock.unlock()
            return
        }

        if timestamp - lastQueuedTimestamp < minimumQueueInterval {
            lock.unlock()
            return
        }

        if !pendingFrames.isEmpty || preparingFrameGeneration != nil {
            lock.unlock()
            return
        }

        lastQueuedTimestamp = timestamp
        let generation = queueGeneration
        preparingFrameGeneration = generation
        diagnosticsRecorder.recordQueuedFrame()
        lock.unlock()

        let frameCopy = ImageDetectorQueue.makeQueuedFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            depthMap: depthMap,
            depthConfidenceMap: depthConfidenceMap
        )
        guard let queuedFrame = frameCopy.queuedFrame else {
            Log.detection.error("Dropping image detection frame: failed to copy RGB pixel buffer")
            cancelPreparingFrame(generation: generation)
            return
        }
        if frameCopy.droppedDepthMap {
            Log.detection.warning("Continuing image detection without aligned depth: failed to copy depth pixel buffer")
        }
        if frameCopy.droppedDepthConfidenceMap {
            Log.detection.warning("Continuing image detection without depth confidence: failed to copy confidence pixel buffer")
        }
        detectionQueue.async { [weak self, queuedFrame, generation] in
            self?.finishPreparingFrame(queuedFrame, generation: generation)
        }
    }

    func clearQueue() {
        lock.lock()
        pendingFrames.removeAll()
        frameCounter = 0
        lastQueuedTimestamp = 0
        queueGeneration &+= 1
        preparingFrameGeneration = nil
        diagnosticsRecorder.reset(modelStatus: modelStatus)
        applyModelLabelDiagnosticsToDiagnosticsLocked()
        lock.unlock()
    }

    func finishPreparingFrame(_ queuedFrame: QueuedFrame, generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        if preparingFrameGeneration == generation {
            preparingFrameGeneration = nil
        }
        guard generation == queueGeneration else { return }
        guard pendingFrames.isEmpty else { return }
        pendingFrames.append(queuedFrame)
    }

    func cancelPreparingFrame(generation: Int) {
        lock.lock()
        if preparingFrameGeneration == generation {
            preparingFrameGeneration = nil
        }
        lock.unlock()
    }

    func drainPendingFrames() async -> [QueuedFrame] {
        let maxAttempts = 6
        for _ in 0..<maxAttempts {
            let drainResult = drainPendingFramesIfReady()
            if !drainResult.frames.isEmpty || !drainResult.isPreparing {
                return drainResult.frames
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        return drainPendingFramesIfReady().frames
    }

    func drainPendingFramesIfReady() -> (frames: [QueuedFrame], isPreparing: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard !pendingFrames.isEmpty else {
            return ([], preparingFrameGeneration != nil)
        }

        let framesToProcess = pendingFrames
        pendingFrames.removeAll()
        return (framesToProcess, preparingFrameGeneration != nil)
    }
}
