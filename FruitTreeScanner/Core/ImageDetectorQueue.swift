// ImageDetectorQueue.swift
// Frame sampling and queue management for ImageDetector.

import Foundation
@preconcurrency import CoreVideo
import simd

extension ImageDetector {
    func enqueueFrame(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize,
        depthMap: CVPixelBuffer?
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

        guard let copiedPixelBuffer = duplicatePixelBuffer(input: pixelBuffer) else {
            Log.detection.error("Dropping image detection frame: failed to copy RGB pixel buffer")
            cancelPreparingFrame(generation: generation)
            return
        }
        // ARKit recycles scene-depth buffers. Keep the exact depth image that
        // accompanied this RGB frame so fusion never projects through a later
        // frame's depth map.
        let copiedDepthMap = depthMap.flatMap { duplicatePixelBuffer(input: $0) }
        if depthMap != nil, copiedDepthMap == nil {
            Log.detection.warning("Continuing image detection without aligned depth: failed to copy depth pixel buffer")
        }
        let queuedFrame = QueuedFrame(
            pixelBuffer: copiedPixelBuffer,
            depthMap: copiedDepthMap,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize
        )
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
