// ImageDetectorQueue.swift
// Frame sampling and queue management for ImageDetector.

import Foundation
@preconcurrency import CoreVideo
import simd

/// One immutable, same-frame RGB/depth/pose packet. Its copied pixel buffers
/// are owned by the inference queue and are reduced to Observation values
/// before detections leave that queue.
struct FramePacket: @unchecked Sendable {
    let frameID: FrameID
    let pixelBuffer: CVPixelBuffer
    let depthMap: CVPixelBuffer?
    let depthConfidenceMap: CVPixelBuffer?
    let depthConfidenceProvenance: DepthConfidenceProvenance
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4
    let cameraIntrinsics: simd_float3x3
    let imageSize: CGSize
    let depthConfiguration: DepthExperimentConfig

    init(
        frameID: FrameID = FrameID(),
        pixelBuffer: CVPixelBuffer,
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer?,
        depthConfidenceProvenance: DepthConfidenceProvenance,
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize,
        depthConfiguration: DepthExperimentConfig = .default
    ) {
        self.frameID = frameID
        self.pixelBuffer = pixelBuffer
        self.depthMap = depthMap
        self.depthConfidenceMap = depthConfidenceMap
        self.depthConfidenceProvenance = depthConfidenceProvenance
        self.timestamp = timestamp
        self.cameraTransform = cameraTransform
        self.cameraIntrinsics = cameraIntrinsics
        self.imageSize = imageSize
        self.depthConfiguration = depthConfiguration
    }
}

enum ImageDetectorQueue {
    /// All mutable state is protected by the owning ImageDetector.lock.
    final class DrainWaiter: @unchecked Sendable {
        var isCancelled = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private static let queueGenerationAttachmentKey =
        "com.fruittreescanner.image-detector.queue-generation" as CFString

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
        pixelBufferCopier: (CVPixelBuffer) -> CVPixelBuffer? = { duplicatePixelBuffer(input: $0) },
        depthConfiguration: DepthExperimentConfig = .default
    ) -> FrameCopyResult {
        // ARKit 会复用帧缓冲区，必须先复制再交给异步推理队列。
        guard let copiedPixelBuffer = pixelBufferCopier(pixelBuffer) else {
            return FrameCopyResult(
                queuedFrame: nil,
                failedToCopyPixelBuffer: true,
                droppedDepthMap: false,
                droppedDepthConfidenceMap: false
            )
        }

        // 深度复制失败时允许图像诊断继续，但不会形成对齐深度证据。
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
            frameID: FrameID(),
            pixelBuffer: copiedPixelBuffer,
            depthMap: copiedDepthMap,
            depthConfidenceMap: copiedDepthConfidenceMap,
            depthConfidenceProvenance: depthConfidenceProvenance,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            depthConfiguration: depthConfiguration
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
        observations(from: fruits, with: frame).map(DetectedFruit.init(observation:))
    }

    static func observations(
        from fruits: [DetectedFruit],
        with frame: ImageDetector.QueuedFrame
    ) -> [Observation] {
        // 所有检测结果都绑定产生它的帧上下文，禁止使用当前帧补配旧检测。
        fruits.map { fruit in
            Observation.capture(
                id: fruit.id,
                frameID: frame.frameID,
                category: fruit.category,
                boundingBox: fruit.boundingBox,
                confidence: fruit.confidence,
                timestamp: fruit.timestamp,
                cameraTransform: frame.cameraTransform,
                cameraIntrinsics: frame.cameraIntrinsics,
                imageSize: frame.imageSize,
                depthMap: frame.depthMap,
                depthConfidenceMap: frame.depthConfidenceMap,
                depthConfidenceProvenance: frame.depthConfidenceProvenance,
                depthConfiguration: frame.depthConfiguration
            )
        }
    }

    static func attachQueueGeneration(_ generation: Int, to pixelBuffer: CVPixelBuffer) {
        CVBufferSetAttachment(
            pixelBuffer,
            queueGenerationAttachmentKey,
            NSNumber(value: generation),
            .shouldNotPropagate
        )
    }

    static func attachedQueueGeneration(to pixelBuffer: CVPixelBuffer) -> Int? {
        guard let value = CVBufferCopyAttachment(
            pixelBuffer,
            queueGenerationAttachmentKey,
            nil
        ) as? NSNumber else {
            return nil
        }
        return value.intValue
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

        // 同时按帧间隔和时间间隔限流，给 Metal 点云采集保留资源。
        let detectionInterval = max(config.imageDetectionInterval, 1)
        if frameCounter % detectionInterval != 0 {
            lock.unlock()
            return
        }

        if timestamp - lastQueuedTimestamp < minimumQueueInterval {
            lock.unlock()
            return
        }

        // 队列只保留一个待处理帧，避免高帧率下堆积大尺寸缓冲区。
        if !pendingFrames.isEmpty || preparingFrameGeneration != nil {
            lock.unlock()
            return
        }

        lastQueuedTimestamp = timestamp
        let generation = queueGeneration
        let capturedDepthConfiguration = depthConfiguration
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
            depthConfidenceMap: depthConfidenceMap,
            depthConfiguration: capturedDepthConfiguration
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
        // 推进队列代次，使正在复制的旧帧无法重新进入已清空的队列。
        queueGeneration &+= 1
        preparingFrameGeneration = nil
        diagnosticsRecorder.reset(modelStatus: modelStatus)
        applyModelLabelDiagnosticsToDiagnosticsLocked()
        let continuations = takeDrainContinuationsLocked()
        lock.unlock()
        continuations.forEach { $0.resume() }
    }

    func queueGenerationSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return queueGeneration
    }

    func isQueueGenerationCurrent(_ expectedQueueGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return queueGeneration == expectedQueueGeneration
    }

    @discardableResult
    func recordCoreMLDetection(
        observationCount: Int,
        confidenceFilteredCount: Int,
        unmappedObservationCount: Int,
        mappedFruitCount: Int,
        rawDetectedLabels: [String],
        mappedCategories: [String],
        unmappedLabels: [String],
        failureReason: String? = nil,
        expectedQueueGeneration: Int
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard queueGeneration == expectedQueueGeneration else { return false }
        diagnosticsRecorder.recordCoreMLDetection(
            observationCount: observationCount,
            confidenceFilteredCount: confidenceFilteredCount,
            unmappedObservationCount: unmappedObservationCount,
            mappedFruitCount: mappedFruitCount,
            rawDetectedLabels: rawDetectedLabels,
            mappedCategories: mappedCategories,
            unmappedLabels: unmappedLabels,
            failureReason: failureReason
        )
        return true
    }

    @discardableResult
    func recordDetectionFailure(
        _ reason: String,
        expectedQueueGeneration: Int
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard queueGeneration == expectedQueueGeneration else { return false }
        diagnosticsRecorder.recordDetectionFailure(reason)
        return true
    }

    @discardableResult
    func recordFallbackFrame(
        reason: String,
        expectedQueueGeneration: Int
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard queueGeneration == expectedQueueGeneration else { return false }
        diagnosticsRecorder.recordFallbackFrame(reason: reason)
        return true
    }

    func finishPreparingFrame(_ queuedFrame: QueuedFrame, generation: Int) {
        lock.lock()
        if preparingFrameGeneration == generation {
            preparingFrameGeneration = nil
        }
        guard generation == queueGeneration else {
            lock.unlock()
            return
        }
        if pendingFrames.isEmpty { pendingFrames.append(queuedFrame) }
        let continuations = takeDrainContinuationsLocked()
        lock.unlock()
        continuations.forEach { $0.resume() }
    }

    func cancelPreparingFrame(generation: Int) {
        lock.lock()
        if preparingFrameGeneration == generation {
            preparingFrameGeneration = nil
            let continuations = takeDrainContinuationsLocked()
            lock.unlock()
            continuations.forEach { $0.resume() }
            return
        }
        lock.unlock()
    }

    func drainPendingFrames() async -> [QueuedFrame] {
        let generation = queueGenerationSnapshot()
        let waiter = ImageDetectorQueue.DrainWaiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerDrainWaiter(waiter, generation: generation, continuation: continuation)
            }
            // Waking never transfers frame ownership. A cancelled consumer must
            // leave any newly prepared frame available to a valid consumer.
            guard !Task.isCancelled else { return [] }
            return drainPendingFramesIfReady(expectedGeneration: generation, waiter: waiter).frames
        } onCancel: {
            self.cancelDrainWaiter(waiter)
        }
    }

    private func registerDrainWaiter(
        _ waiter: ImageDetectorQueue.DrainWaiter,
        generation: Int,
        continuation: CheckedContinuation<Void, Never>
    ) {
        lock.lock()
        // Readiness and registration are atomic with copy completion/clear.
        // Cancellation may have run before this continuation was installed.
        if waiter.isCancelled || generation != queueGeneration ||
            preparingFrameGeneration == nil || !pendingFrames.isEmpty {
            lock.unlock()
            continuation.resume()
            return
        }
        waiter.continuation = continuation
        drainWaiters[ObjectIdentifier(waiter)] = waiter
        lock.unlock()
    }

    private func cancelDrainWaiter(_ waiter: ImageDetectorQueue.DrainWaiter) {
        lock.lock()
        waiter.isCancelled = true
        drainWaiters.removeValue(forKey: ObjectIdentifier(waiter))
        let continuation = waiter.continuation
        waiter.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    /// Caller holds lock; continuations must be resumed after unlocking.
    private func takeDrainContinuationsLocked() -> [CheckedContinuation<Void, Never>] {
        let continuations = drainWaiters.values.compactMap { waiter in
            defer { waiter.continuation = nil }
            return waiter.continuation
        }
        drainWaiters.removeAll()
        return continuations
    }

    func drainPendingFramesIfReady(
        expectedGeneration: Int? = nil,
        waiter: ImageDetectorQueue.DrainWaiter? = nil
    ) -> (frames: [QueuedFrame], isPreparing: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if let expectedGeneration, expectedGeneration != queueGeneration { return ([], false) }
        if waiter?.isCancelled == true { return ([], false) }

        guard !pendingFrames.isEmpty else {
            return ([], preparingFrameGeneration != nil)
        }

        let framesToProcess = pendingFrames
        pendingFrames.removeAll()
        for frame in framesToProcess {
            ImageDetectorQueue.attachQueueGeneration(
                queueGeneration,
                to: frame.pixelBuffer
            )
        }
        return (framesToProcess, preparingFrameGeneration != nil)
    }
}
