// ImageDetector.swift
// 图像水果检测组件 - 使用 CoreML 模型

import Foundation
import os
import Vision
@preconcurrency import CoreVideo
import simd

// MARK: - ImageDetector

final class ImageDetector: @unchecked Sendable {

    // pixelBuffer is synchronously copied (duplicatePixelBuffer) inside enqueueFrame
    // before QueuedFrame is created, so cross-detectionQueue transfer is safe.
    struct QueuedFrame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let imageSize: CGSize
    }

    struct SendablePixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    // MARK: - Properties

    var config: FruitScanConfig

    let detectionQueue = DispatchQueue(label: "com.fruittreescanner.imagedetector", qos: .userInitiated)
    var pendingFrames: [QueuedFrame] = []
    var frameCounter: Int = 0
    var lastQueuedTimestamp: TimeInterval = 0
    var queueGeneration: Int = 0
    var preparingFrameGeneration: Int?
    let minimumQueueInterval: TimeInterval = 0.45
    let lock = NSLock()

    // CoreML 模型 (由初始化时注入)
    var coreMLModel: VNCoreMLModel?
    private(set) var modelStatus: ImageDetectorModelStatus = .fallback(reason: "模型尚未加载")
    var diagnosticsRecorder = ImageDetectionDiagnosticsRecorder()
    var detectionDebugState = DetectionDebugState()
    var detectionFailureSamples: [DetectionFailureSample] = []
    let maxDetectionFailureSamples = 20
    let categoryMapper = FruitCategoryMapper.standard

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
        self.detectionDebugState = DetectionDebugState(currentThreshold: config.minConfidence)
        loadCoreMLModel()
    }

    func updateConfig(_ newConfig: FruitScanConfig) {
        lock.lock()
        defer { lock.unlock() }
        self.config = newConfig
        detectionDebugState.currentThreshold = newConfig.minConfidence
        detectionDebugState.lastUpdatedAt = Date()
    }

    func configSnapshot() -> FruitScanConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    /// 加载 CoreML 模型
    /// - Important: 调用此方法前需要先将 .mlmodel 文件添加到项目
    private func loadCoreMLModel() {
        // 尝试加载用户训练的模型
        // 如果模型不存在，使用 Vision 内置分类器作为 fallback
        do {
            let loadedModel = try ImageDetectorModelLoader.loadModel(named: "FruitsDetector")
            coreMLModel = loadedModel.model
            modelStatus = .coreML(
                resourceName: loadedModel.resourceName,
                bundleExtension: loadedModel.bundleExtension
            )
            Log.detection.info("CoreML model loaded: \(loadedModel.displayName), supportedClasses=\(loadedModel.supportedClasses.joined(separator: ","))")
            updateModelDiagnostics()
            updateModelDebugStateLoaded(loadedModel)
        } catch {
            let modelResource = ImageDetectorModelLoader.modelURL(named: "FruitsDetector")
            let modelName = modelResource.map { "FruitsDetector.\($0.bundleExtension)" } ?? "FruitsDetector"
            coreMLModel = nil
            modelStatus = .fallback(reason: error.localizedDescription)
            Log.detection.error("CoreML model not available, using fallback: \(error.localizedDescription)")
            updateModelDiagnostics()
            updateModelDebugStateFailure(
                modelName: modelName,
                modelURLFound: modelResource != nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    func diagnosticsSnapshot() -> ImageDetectionDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return diagnosticsRecorder.snapshot
    }

    private func updateModelDiagnostics() {
        lock.lock()
        defer { lock.unlock() }
        applyModelStatusToDiagnosticsLocked()
    }

    private func applyModelStatusToDiagnosticsLocked() {
        diagnosticsRecorder.apply(modelStatus: modelStatus)
    }

    private func updateModelDebugStateLoaded(_ loadedModel: ImageDetectorLoadedModel) {
        lock.lock()
        detectionDebugState.markModelLoaded(
            modelName: loadedModel.displayName,
            modelURLFound: true,
            supportedClasses: loadedModel.supportedClasses
        )
        lock.unlock()
    }

    private func updateModelDebugStateFailure(
        modelName: String,
        modelURLFound: Bool,
        errorMessage: String
    ) {
        lock.lock()
        detectionDebugState.markModelLoadFailure(
            modelName: modelName,
            modelURLFound: modelURLFound,
            errorMessage: errorMessage
        )
        lock.unlock()
    }

    // MARK: - Public Methods

    /// Process the queued frames and return detected fruits.
    /// This method performs detection on a background thread.
    func processQueue() async -> [DetectedFruit] {
        let framesToProcess = await drainPendingFrames()
        guard !framesToProcess.isEmpty else { return [] }

        var allDetectedFruits: [DetectedFruit] = []

        for frame in framesToProcess {
            let fruits = await performDetection(
                pixelBuffer: frame.pixelBuffer,
                timestamp: frame.timestamp,
                imageSize: frame.imageSize
            )
            let enriched = fruits.map { fruit in
                DetectedFruit(
                    category: fruit.category,
                    boundingBox: fruit.boundingBox,
                    confidence: fruit.confidence,
                    timestamp: fruit.timestamp,
                    cameraTransform: frame.cameraTransform,
                    cameraIntrinsics: frame.cameraIntrinsics,
                    imageSize: frame.imageSize
                )
            }
            allDetectedFruits.append(contentsOf: enriched)
        }

        return allDetectedFruits
    }

    func recordCoreMLDetection(
        observationCount: Int,
        confidenceFilteredCount: Int,
        unmappedObservationCount: Int,
        mappedFruitCount: Int
    ) {
        lock.lock()
        diagnosticsRecorder.recordCoreMLDetection(
            observationCount: observationCount,
            confidenceFilteredCount: confidenceFilteredCount,
            unmappedObservationCount: unmappedObservationCount,
            mappedFruitCount: mappedFruitCount
        )
        lock.unlock()
    }

    func recordDetectionFailure(_ reason: String) {
        lock.lock()
        diagnosticsRecorder.recordDetectionFailure(reason)
        lock.unlock()
    }

    func recordFallbackFrame(reason: String) {
        lock.lock()
        diagnosticsRecorder.recordFallbackFrame(reason: reason)
        lock.unlock()
    }

    func detectionDebugSnapshot() -> DetectionDebugState {
        lock.lock()
        defer { lock.unlock() }
        return detectionDebugState
    }

    func detectionFailureSamplesSnapshot() -> [DetectionFailureSample] {
        lock.lock()
        defer { lock.unlock() }
        return detectionFailureSamples
    }

    func recordDebugInferenceStarted(
        frameSize: CGSize,
        pixelBufferSize: CGSize,
        threshold: Float
    ) {
        lock.lock()
        detectionDebugState.markInferenceStarted(
            frameSize: frameSize,
            pixelBufferSize: pixelBufferSize,
            threshold: threshold
        )
        lock.unlock()
    }

    func recordDebugInferenceCompleted(
        elapsedMs: Double,
        rawObservationCount: Int,
        filteredObservationCount: Int,
        rawPredictions: [DetectionPredictionDebug],
        filteredPredictions: [DetectionPredictionDebug],
        threshold: Float,
        errorMessage: String? = nil
    ) {
        lock.lock()
        detectionDebugState.markInferenceCompleted(
            elapsedMs: elapsedMs,
            rawObservationCount: rawObservationCount,
            filteredObservationCount: filteredObservationCount,
            rawPredictions: rawPredictions,
            filteredPredictions: filteredPredictions,
            threshold: threshold,
            errorMessage: errorMessage
        )
        lock.unlock()
    }

    func captureDetectionFailureSample(
        note: String? = nil,
        fruitCategoryExpected: String? = nil
    ) {
        lock.lock()
        let sample = DetectionFailureSample(
            timestamp: Date(),
            modelName: detectionDebugState.modelName,
            threshold: detectionDebugState.currentThreshold,
            topPredictions: detectionDebugState.topPredictions,
            rawObservationCount: detectionDebugState.rawObservationCount,
            filteredObservationCount: detectionDebugState.filteredObservationCount,
            note: note,
            fruitCategoryExpected: fruitCategoryExpected
        )
        detectionFailureSamples.append(sample)
        if detectionFailureSamples.count > maxDetectionFailureSamples {
            detectionFailureSamples.removeFirst(detectionFailureSamples.count - maxDetectionFailureSamples)
        }
        lock.unlock()

        Log.detection.info("Detection failure sample captured: model=\(sample.modelName), raw=\(sample.rawObservationCount), filtered=\(sample.filteredObservationCount), threshold=\(sample.threshold)")
    }
}
